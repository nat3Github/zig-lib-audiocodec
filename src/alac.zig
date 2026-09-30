//! Zig port of Apple's ALACDecoder.cpp / ALACEncoder.cpp on top of the ALAC C DSP core
//! (vendor/alac, bound in zig-c-headers/alac.zig). The bitstream produced/consumed is identical to
//! the C++ reference. Differences from the C++:
//! - untrusted input is bounds-checked (frame sizes from the bitstream, caller buffer sizes);
//! - errors are Zig errors instead of int32 status codes;
//! - the cookie's channel layout tag is written big-endian, as ALACMagicCookieDescription.txt specifies
//!   (the C++ wrote it host-endian);
//! - dropped: Finish() and GetSourceFormat() (no-ops), the VERBOSE_DEBUG filler, printf diagnostics.

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("zig-c-headers/alac.zig");

pub const Error = error{
    /// kALAC_ParamError: bad config, malformed bitstream or too-small buffer.
    InvalidParameter,
};

pub const AudioFormatDescription = c.AudioFormatDescription;
pub const SpecificConfig = c.ALACSpecificConfig;
pub const default_frame_size = c.kALACDefaultFrameSize;
const BitBuffer = c.BitBuffer;

const max_channels = c.kALACMaxChannels;
/// unpc_block/pc_block touch samples [0, numActive] (numActive <= 30) whatever the sample count.
const min_buffer_len = 32;
/// The C BitBuffer peeks 2 bytes ahead and dyn_decomp up to 5; a header runs < 140 bytes before
/// decode() checks the position again. Packets are copied into a buffer with this much slack.
const packet_padding = 256;

fn bytesPerSample(bit_depth: u32) u32 {
    return switch (bit_depth) {
        16 => 2,
        20, 24 => 3,
        32 => 4,
        else => unreachable,
    };
}

fn signed(value: anytype) u32 {
    return @bitCast(@as(i32, value));
}

fn i32Ptr(bytes: [*]u8) [*]i32 {
    return @ptrCast(@alignCast(bytes));
}

fn i16Ptr(bytes: [*]u8) [*]i16 {
    return @ptrCast(@alignCast(bytes));
}

pub const Decoder = struct {
    /// Host-endian copy of the stream's ALACSpecificConfig.
    config: SpecificConfig,
    active_elements: u16 = 0,
    mix_buffer_u: []i32,
    mix_buffer_v: []i32,
    /// The "shift off" buffer shares this memory (viewed as u16), as in the C++.
    predictor: []i32,
    /// Copy of the packet being decoded, plus packet_padding zeros.
    packet: []u8,

    /// Older encoders wrap the config in 'frma' and 'alac' atoms; skips them if present.
    pub fn unwrap(magic_cookie: []const u8) []const u8 {
        var cookie = magic_cookie;
        if (cookie.len >= 12 and std.mem.eql(u8, cookie[4..8], "frma")) cookie = cookie[12..];
        if (cookie.len >= 12 and std.mem.eql(u8, cookie[4..8], "alac")) cookie = cookie[12..];
        return cookie;
    }

    pub fn init(gpa: Allocator, magic_cookie: []const u8) (Allocator.Error || Error)!Decoder {
        const cookie = unwrap(magic_cookie);
        if (cookie.len < @sizeOf(SpecificConfig)) return error.InvalidParameter;

        const config: SpecificConfig = .{
            .frameLength = std.mem.readInt(u32, cookie[0..4], .big),
            .compatibleVersion = cookie[4],
            .bitDepth = cookie[5],
            .pb = cookie[6],
            .mb = cookie[7],
            .kb = cookie[8],
            .numChannels = cookie[9],
            .maxRun = std.mem.readInt(u16, cookie[10..12], .big),
            .maxFrameBytes = std.mem.readInt(u32, cookie[12..16], .big),
            .avgBitRate = std.mem.readInt(u32, cookie[16..20], .big),
            .sampleRate = std.mem.readInt(u32, cookie[20..24], .big),
        };
        if (config.compatibleVersion > c.kALACVersion) return error.InvalidParameter;
        switch (config.bitDepth) {
            16, 20, 24, 32 => {},
            else => return error.InvalidParameter,
        }

        const len = @max(config.frameLength, min_buffer_len);
        const mix_buffer_u = try gpa.alloc(i32, len);
        errdefer gpa.free(mix_buffer_u);
        const mix_buffer_v = try gpa.alloc(i32, len);
        errdefer gpa.free(mix_buffer_v);
        const predictor = try gpa.alloc(i32, len);
        errdefer gpa.free(predictor);
        // the largest packet: every sample escaped at 4 bytes, plus element headers
        const packet = try gpa.alloc(u8, @as(usize, config.frameLength) * @max(config.numChannels, 1) * 4 + 64 + packet_padding);
        @memset(mix_buffer_u, 0);
        @memset(mix_buffer_v, 0);
        @memset(predictor, 0);
        @memset(packet, 0);

        return .{
            .config = config,
            .mix_buffer_u = mix_buffer_u,
            .mix_buffer_v = mix_buffer_v,
            .predictor = predictor,
            .packet = packet,
        };
    }

    pub fn deinit(self: *Decoder, gpa: Allocator) void {
        gpa.free(self.mix_buffer_u);
        gpa.free(self.mix_buffer_v);
        gpa.free(self.predictor);
        gpa.free(self.packet);
        self.* = undefined;
    }

    fn shiftBuffer(self: *Decoder) [*]u16 {
        return @ptrCast(self.predictor.ptr);
    }

    /// Decodes one packet into `sample_buffer`, interleaved in bitstream order, `bitDepth` bits per
    /// sample (20/24-bit packed as 3 bytes). Returns the number of samples per channel decoded.
    pub fn decode(self: *Decoder, packet: []const u8, sample_buffer: []u8, requested_samples: u32, num_channels: u32) Error!u32 {
        if (num_channels == 0) return error.InvalidParameter;
        const bit_depth: u32 = self.config.bitDepth;
        const sample_bytes = bytesPerSample(bit_depth);
        if (requested_samples > self.config.frameLength or
            @as(u64, requested_samples) * num_channels * sample_bytes > sample_buffer.len) return error.InvalidParameter;
        if (packet.len > self.packet.len - packet_padding) return error.InvalidParameter;
        // ponytail: one memcpy per packet buys the read-ahead slack the C bit reader needs
        @memcpy(self.packet[0..packet.len], packet);

        var bit_buffer: BitBuffer = undefined;
        c.BitBufferInit(&bit_buffer, self.packet.ptr, @intCast(packet.len));
        const bits = &bit_buffer;

        const out = sample_buffer.ptr;
        var num_samples = requested_samples;
        var out_num_samples = num_samples;
        var channel_index: u32 = 0;
        var coefs_u: [32]i16 = undefined;
        var coefs_v: [32]i16 = undefined;

        self.active_elements = 0;

        while (channel_index < num_channels) {
            if (@intFromPtr(bits.cur) >= @intFromPtr(bits.end)) return error.InvalidParameter;

            const pb: u32 = self.config.pb;
            const tag = c.BitBufferReadSmall(bits, 3);
            switch (tag) {
                c.ID_SCE, c.ID_LFE, c.ID_CPE => {
                    const stereo = tag == c.ID_CPE;
                    // if decoding this pair would take us over the max channels limit, bail
                    if (stereo and channel_index + 2 > num_channels) break;

                    const element_instance_tag: u4 = @truncate(c.BitBufferReadSmall(bits, 4));
                    self.active_elements |= @as(u16, 1) << element_instance_tag;

                    if (c.BitBufferRead(bits, 12) != 0) return error.InvalidParameter;

                    // 1-bit "partial frame", 2-bit "shift-off" and 1-bit "escape" flags
                    const header: u8 = @truncate(c.BitBufferRead(bits, 4));
                    const partial_frame = header >> 3;
                    var bytes_shifted: u8 = (header >> 1) & 0x3;
                    if (bytes_shifted == 3) return error.InvalidParameter;
                    const escape = header & 0x1 != 0;

                    var chan_bits: u32 = bit_depth - @as(u32, bytes_shifted) * 8 + @intFromBool(stereo);

                    if (partial_frame != 0) {
                        num_samples = c.BitBufferRead(bits, 16) << 16;
                        num_samples |= c.BitBufferRead(bits, 16);
                    }
                    const channels_here: u32 = if (stereo) 2 else 1;
                    if (num_samples > self.config.frameLength) return error.InvalidParameter;
                    if (@as(u64, num_samples) * num_channels * sample_bytes > sample_buffer.len) return error.InvalidParameter;

                    var mix_bits: i32 = 0;
                    var mix_res: i32 = 0;
                    var shift_bits: BitBuffer = undefined;

                    if (!escape) {
                        mix_bits = @as(u8, @truncate(c.BitBufferRead(bits, 8)));
                        mix_res = @as(i8, @bitCast(@as(u8, @truncate(c.BitBufferRead(bits, 8)))));

                        const u = readPredictorHeader(bits, &coefs_u);
                        const v = if (stereo) readPredictorHeader(bits, &coefs_v) else undefined;

                        // if shift active, skip the (interleaved) shifted values but remember where they start
                        if (bytes_shifted != 0) {
                            shift_bits = bits.*;
                            c.BitBufferAdvance(bits, @as(u32, bytes_shifted) * 8 * channels_here * num_samples);
                        }

                        try self.decompress(bits, pb, u, &coefs_u, self.mix_buffer_u, num_samples, chan_bits);
                        if (stereo) try self.decompress(bits, pb, v, &coefs_v, self.mix_buffer_v, num_samples, chan_bits);
                    } else {
                        // uncompressed frame, copy data into the mix buffers to use common output code
                        if (stereo) chan_bits = bit_depth;
                        if (chan_bits == 0) return error.InvalidParameter;
                        if (try bitsLeft(bits) < @as(u64, num_samples) * chan_bits * channels_here) return error.InvalidParameter;
                        const shift: u5 = @intCast(32 - chan_bits);
                        for (0..num_samples) |i| {
                            self.mix_buffer_u[i] = readEscapedSample(bits, chan_bits, shift);
                            if (stereo) self.mix_buffer_v[i] = readEscapedSample(bits, chan_bits, shift);
                        }
                        bytes_shifted = 0;
                    }

                    // now read the shifted values into the shift buffer
                    if (bytes_shifted != 0) {
                        const shift_buffer = self.shiftBuffer();
                        for (0..num_samples * channels_here) |i|
                            shift_buffer[i] = @truncate(c.BitBufferRead(&shift_bits, bytes_shifted * 8));
                    }

                    if (stereo)
                        self.unmix(out, channel_index, num_channels, num_samples, mix_bits, mix_res, bytes_shifted)
                    else
                        self.copyMono(out, channel_index, num_channels, num_samples, bytes_shifted);

                    channel_index += channels_here;
                    out_num_samples = num_samples;
                },
                // unsupported elements
                c.ID_CCE, c.ID_PCE => return error.InvalidParameter,
                c.ID_DSE => try dataStreamElement(bits),
                c.ID_FIL => try fillElement(bits),
                c.ID_END => {
                    // frame end, all done so byte align the frame
                    c.BitBufferByteAlign(bits, 0);
                    return out_num_samples;
                },
                else => unreachable,
            }
        }

        // if we haven't decoded all of the requested channels, fill the remaining channels with zeros
        // ponytail: the C++ skipped 20-bit here; 20-bit is 3 bytes like 24-bit, so it is zeroed too.
        while (channel_index < num_channels) : (channel_index += 1) {
            var index: usize = channel_index * sample_bytes;
            for (0..num_samples) |_| {
                @memset(out[index..][0..sample_bytes], 0);
                index += num_channels * sample_bytes;
            }
        }
        return out_num_samples;
    }

    /// Bits before the end of the packet; an error if a read already ran past it.
    fn bitsLeft(bits: *const BitBuffer) Error!u64 {
        const cur = @intFromPtr(bits.cur);
        const end = @intFromPtr(bits.end);
        if (cur > end or (cur == end and bits.bitIndex != 0)) return error.InvalidParameter;
        return (end - cur) * 8 - bits.bitIndex;
    }

    const PredictorHeader = struct { mode: u8, den_shift: u32, pb_factor: u32, num: u8 };

    fn readPredictorHeader(bits: *BitBuffer, coefs: *[32]i16) PredictorHeader {
        const mode_byte: u8 = @truncate(c.BitBufferRead(bits, 8));
        const filter_byte: u8 = @truncate(c.BitBufferRead(bits, 8));
        const num = filter_byte & 0x1f;
        for (coefs[0..num]) |*coef| coef.* = @bitCast(@as(u16, @truncate(c.BitBufferRead(bits, 16))));
        return .{ .mode = mode_byte >> 4, .den_shift = mode_byte & 0xf, .pb_factor = filter_byte >> 5, .num = num };
    }

    fn decompress(self: *Decoder, bits: *BitBuffer, pb: u32, h: PredictorHeader, coefs: *[32]i16, out: []i32, num_samples: u32, chan_bits: u32) Error!void {
        var ag_params: c.AGParamRec = undefined;
        var num_bits: u32 = undefined;
        const n: i32 = @intCast(num_samples);
        // dyn_decomp bounds its (cur-relative) bit position by byteSize, so make that the bytes left
        _ = try bitsLeft(bits);
        bits.byteSize = @intCast(@intFromPtr(bits.end) - @intFromPtr(bits.cur));
        c.set_ag_params(&ag_params, self.config.mb, (pb * h.pb_factor) / 4, self.config.kb, num_samples, num_samples, self.config.maxRun);
        if (c.dyn_decomp(&ag_params, bits, self.predictor.ptr, n, @intCast(chan_bits), &num_bits) != 0) return error.InvalidParameter;

        // the special "numActive == 31" mode can be done in-place
        if (h.mode != 0) c.unpc_block(self.predictor.ptr, self.predictor.ptr, n, null, 31, chan_bits, 0);
        c.unpc_block(self.predictor.ptr, out.ptr, n, coefs, h.num, chan_bits, h.den_shift);
    }

    fn readEscapedSample(bits: *BitBuffer, chan_bits: u32, shift: u5) i32 {
        // BitBufferRead() can't read more than 16 bits at a time so break up the reads
        if (chan_bits <= 16) {
            const raw = c.BitBufferRead(bits, @intCast(chan_bits));
            return @as(i32, @bitCast(raw << shift)) >> shift;
        }
        const high: i32 = @as(i32, @bitCast(c.BitBufferRead(bits, 16) << 16)) >> shift;
        return high | @as(i32, @bitCast(c.BitBufferRead(bits, @intCast(chan_bits - 16))));
    }

    fn copyMono(self: *Decoder, out: [*]u8, channel_index: u32, stride: u32, num_samples: u32, bytes_shifted: u8) void {
        const n: i32 = @intCast(num_samples);
        switch (self.config.bitDepth) {
            16 => {
                const out16 = i16Ptr(out) + channel_index;
                for (0..num_samples) |i| out16[i * stride] = @truncate(self.mix_buffer_u[i]);
            },
            20 => c.copyPredictorTo20(self.mix_buffer_u.ptr, out + channel_index * 3, stride, n),
            24 => if (bytes_shifted != 0)
                c.copyPredictorTo24Shift(self.mix_buffer_u.ptr, self.shiftBuffer(), out + channel_index * 3, stride, n, bytes_shifted)
            else
                c.copyPredictorTo24(self.mix_buffer_u.ptr, out + channel_index * 3, stride, n),
            32 => if (bytes_shifted != 0)
                c.copyPredictorTo32Shift(self.mix_buffer_u.ptr, self.shiftBuffer(), i32Ptr(out) + channel_index, stride, n, bytes_shifted)
            else
                c.copyPredictorTo32(self.mix_buffer_u.ptr, i32Ptr(out) + channel_index, stride, n),
            else => unreachable,
        }
    }

    /// mix_res == 0 means just interleave, which is what escaped frames use.
    fn unmix(self: *Decoder, out: [*]u8, channel_index: u32, stride: u32, num_samples: u32, mix_bits: i32, mix_res: i32, bytes_shifted: u8) void {
        const n: i32 = @intCast(num_samples);
        const u = self.mix_buffer_u.ptr;
        const v = self.mix_buffer_v.ptr;
        switch (self.config.bitDepth) {
            16 => c.unmix16(u, v, i16Ptr(out) + channel_index, stride, n, mix_bits, mix_res),
            20 => c.unmix20(u, v, out + channel_index * 3, stride, n, mix_bits, mix_res),
            24 => c.unmix24(u, v, out + channel_index * 3, stride, n, mix_bits, mix_res, self.shiftBuffer(), bytes_shifted),
            32 => c.unmix32(u, v, i32Ptr(out) + channel_index, stride, n, mix_bits, mix_res, self.shiftBuffer(), bytes_shifted),
            else => unreachable,
        }
    }

    fn fillElement(bits: *BitBuffer) Error!void {
        // 4-bit count or (4-bit + 8-bit count) if 4-bit count == 15, minus one
        var count: u32 = c.BitBufferReadSmall(bits, 4);
        if (count == 15) count = count + c.BitBufferReadSmall(bits, 8) - 1;
        c.BitBufferAdvance(bits, count * 8);
        if (@intFromPtr(bits.cur) > @intFromPtr(bits.end)) return error.InvalidParameter;
    }

    fn dataStreamElement(bits: *BitBuffer) Error!void {
        _ = c.BitBufferReadSmall(bits, 4); // element_instance_tag
        const byte_align = c.BitBufferReadOne(bits) != 0;
        // 8-bit count or (8-bit + 8-bit count) if 8-bit count == 255
        var count: u32 = c.BitBufferReadSmall(bits, 8);
        if (count == 255) count += c.BitBufferReadSmall(bits, 8);
        if (byte_align) c.BitBufferByteAlign(bits, 0);
        c.BitBufferAdvance(bits, count * 8);
        if (@intFromPtr(bits.cur) > @intFromPtr(bits.end)) return error.InvalidParameter;
    }
};

pub const Encoder = struct {
    const max_sample_size = 32;
    const default_mix_bits = 2;
    const default_mix_res = 0;
    const max_res = 4;
    const default_num_uv = 8;
    const min_uv = 4;
    const max_uv = 8;
    const Coefs = [max_channels][c.kALACMaxSearches][c.kALACMaxCoefs]i16;

    /// 3-bit element tag per channel index (index advances by two for channel pairs).
    const channel_maps = [max_channels]u32{
        c.ID_SCE,
        c.ID_CPE,
        (c.ID_CPE << 3) | c.ID_SCE,
        (c.ID_SCE << 9) | (c.ID_CPE << 3) | c.ID_SCE,
        (c.ID_CPE << 9) | (c.ID_CPE << 3) | c.ID_SCE,
        (c.ID_SCE << 15) | (c.ID_CPE << 9) | (c.ID_CPE << 3) | c.ID_SCE,
        (c.ID_SCE << 18) | (c.ID_SCE << 15) | (c.ID_CPE << 9) | (c.ID_CPE << 3) | c.ID_SCE,
        (c.ID_SCE << 21) | (c.ID_CPE << 15) | (c.ID_CPE << 9) | (c.ID_CPE << 3) | c.ID_SCE,
    };

    bit_depth: u32,
    fast_mode: bool,
    last_mix_res: [max_channels]i16 = @splat(default_mix_res),
    mix_buffer_u: []i32,
    mix_buffer_v: []i32,
    predictor_u: []i32,
    predictor_v: []i32,
    shift_buffer_uv: []u16,
    work_buffer: []u8,
    coefs_u: Coefs = undefined,
    coefs_v: Coefs = undefined,
    total_bytes_generated: u32 = 0,
    avg_bit_rate: u32 = 0,
    max_frame_bytes: u32 = 0,
    frame_size: u32,
    /// Required size of the output buffer passed to encode().
    max_output_bytes: u32,
    num_channels: u32,
    output_sample_rate: u32,

    /// output_format.mFormatFlags selects the bit depth: 1 = 16, 2 = 20, 3 = 24, 4 = 32.
    /// frame_size replaces SetFrameSize(); pass default_frame_size for the C++ default.
    pub fn init(gpa: Allocator, output_format: AudioFormatDescription, frame_size: u32, fast_mode: bool) (Allocator.Error || Error)!Encoder {
        const bit_depth: u32 = switch (output_format.mFormatFlags) {
            1 => 16,
            2 => 20,
            3 => 24,
            4 => 32,
            else => return error.InvalidParameter,
        };
        const num_channels = output_format.mChannelsPerFrame;
        if (num_channels == 0 or num_channels > max_channels or frame_size == 0) return error.InvalidParameter;

        // the maximum output frame size can be no bigger than (samplesPerBlock * numChannels * ((10 + sampleSize)/8) + 1)
        // plus, for small frames, the element headers (< 64 bytes each) the C++ bound left out
        const max_output_bytes = frame_size * num_channels * ((10 + max_sample_size) / 8) + 1 + max_channels * 64;

        const len = @max(frame_size, min_buffer_len);
        const mix_buffer_u = try gpa.alloc(i32, len);
        errdefer gpa.free(mix_buffer_u);
        const mix_buffer_v = try gpa.alloc(i32, len);
        errdefer gpa.free(mix_buffer_v);
        const predictor_u = try gpa.alloc(i32, len);
        errdefer gpa.free(predictor_u);
        const predictor_v = try gpa.alloc(i32, len);
        errdefer gpa.free(predictor_v);
        const shift_buffer_uv = try gpa.alloc(u16, frame_size * 2);
        errdefer gpa.free(shift_buffer_uv);
        const work_buffer = try gpa.alloc(u8, max_output_bytes);
        inline for (.{ mix_buffer_u, mix_buffer_v, predictor_u, predictor_v, shift_buffer_uv, work_buffer }) |buffer| @memset(buffer, 0);

        var self: Encoder = .{
            .bit_depth = bit_depth,
            .fast_mode = fast_mode,
            .mix_buffer_u = mix_buffer_u,
            .mix_buffer_v = mix_buffer_v,
            .predictor_u = predictor_u,
            .predictor_v = predictor_v,
            .shift_buffer_uv = shift_buffer_uv,
            .work_buffer = work_buffer,
            .frame_size = frame_size,
            .max_output_bytes = max_output_bytes,
            .num_channels = num_channels,
            .output_sample_rate = @intFromFloat(output_format.mSampleRate),
        };
        // initialize coefs once b/c retaining state across blocks actually improves the encode ratio
        for (0..num_channels) |channel| {
            for (0..c.kALACMaxSearches) |search| {
                c.init_coefs(&self.coefs_u[channel][search], c.DENSHIFT_DEFAULT, c.kALACMaxCoefs);
                c.init_coefs(&self.coefs_v[channel][search], c.DENSHIFT_DEFAULT, c.kALACMaxCoefs);
            }
        }
        return self;
    }

    pub fn deinit(self: *Encoder, gpa: Allocator) void {
        gpa.free(self.mix_buffer_u);
        gpa.free(self.mix_buffer_v);
        gpa.free(self.predictor_u);
        gpa.free(self.predictor_v);
        gpa.free(self.shift_buffer_uv);
        gpa.free(self.work_buffer);
        self.* = undefined;
    }

    /// Encodes one packet of interleaved samples (`input.len / mBytesPerPacket` frames, at most
    /// frame_size). `output` must hold max_output_bytes. Returns the number of bytes written.
    pub fn encode(self: *Encoder, input_format: AudioFormatDescription, input: []const u8, output: []u8) Error!u32 {
        const channels = input_format.mChannelsPerFrame;
        const sample_bytes = bytesPerSample(self.bit_depth);
        if (channels == 0 or channels > max_channels) return error.InvalidParameter;
        if (input_format.mBytesPerPacket < channels * sample_bytes) return error.InvalidParameter;
        if (output.len < self.max_output_bytes) return error.InvalidParameter;
        const num_frames: u32 = @intCast(input.len / input_format.mBytesPerPacket);
        if (num_frames > self.frame_size) return error.InvalidParameter;

        // the C DSP routines take non-const pointers but never write the input
        const in: [*]u8 = @constCast(input.ptr);

        var bitstream: BitBuffer = undefined;
        c.BitBufferInit(&bitstream, output.ptr, self.max_output_bytes);

        if (channels == 2) {
            // frame start tag ID_CPE = channel pair & 4-bit element instance tag = 0
            c.BitBufferWrite(&bitstream, c.ID_CPE, 3);
            c.BitBufferWrite(&bitstream, 0, 4);
            if (self.fast_mode)
                try self.encodeStereoFast(&bitstream, in, 2, 0, num_frames)
            else
                try self.encodeStereo(&bitstream, in, 2, 0, num_frames);
        } else if (channels == 1) {
            c.BitBufferWrite(&bitstream, c.ID_SCE, 3);
            c.BitBufferWrite(&bitstream, 0, 4);
            try self.encodeMono(&bitstream, in, 1, 0, num_frames);
        } else {
            var input_buffer = in;
            var stereo_element_tag: u32 = 0;
            var mono_element_tag: u32 = 0;
            var lfe_element_tag: u32 = 0;
            var channel_index: u32 = 0;
            while (channel_index < channels) {
                const tag = (channel_maps[channels - 1] >> @intCast(channel_index * 3)) & 0x7;
                c.BitBufferWrite(&bitstream, tag, 3);
                switch (tag) {
                    c.ID_SCE, c.ID_LFE => {
                        const element_tag = if (tag == c.ID_SCE) &mono_element_tag else &lfe_element_tag;
                        c.BitBufferWrite(&bitstream, element_tag.*, 4);
                        try self.encodeMono(&bitstream, input_buffer, channels, channel_index, num_frames);
                        input_buffer += sample_bytes;
                        channel_index += 1;
                        element_tag.* += 1;
                    },
                    c.ID_CPE => {
                        c.BitBufferWrite(&bitstream, stereo_element_tag, 4);
                        try self.encodeStereo(&bitstream, input_buffer, channels, channel_index, num_frames);
                        input_buffer += sample_bytes * 2;
                        channel_index += 2;
                        stereo_element_tag += 1;
                    },
                    else => unreachable,
                }
            }
        }

        // frame end tag, then byte-align the output data
        c.BitBufferWrite(&bitstream, c.ID_END, 3);
        c.BitBufferByteAlign(&bitstream, 1);

        const output_size = c.BitBufferGetPosition(&bitstream) / 8;
        self.total_bytes_generated +%= output_size;
        self.max_frame_bytes = @max(self.max_frame_bytes, output_size);
        return output_size;
    }

    /// The config with multi-byte fields big-endian, as stored in the magic cookie.
    pub fn getConfig(self: *const Encoder) SpecificConfig {
        return .{
            .frameLength = std.mem.nativeToBig(u32, self.frame_size),
            .compatibleVersion = c.kALACCompatibleVersion,
            .bitDepth = @intCast(self.bit_depth),
            .pb = c.PB0,
            .mb = c.MB0,
            .kb = c.KB0,
            .numChannels = @intCast(self.num_channels),
            .maxRun = std.mem.nativeToBig(u16, c.MAX_RUN_DEFAULT),
            .maxFrameBytes = std.mem.nativeToBig(u32, self.max_frame_bytes),
            .avgBitRate = std.mem.nativeToBig(u32, self.avg_bit_rate),
            .sampleRate = std.mem.nativeToBig(u32, self.output_sample_rate),
        };
    }

    pub fn magicCookieSize(num_channels: u32) u32 {
        if (num_channels > 2) return @sizeOf(SpecificConfig) + c.kChannelAtomSize + @sizeOf(c.ALACAudioChannelLayout);
        return @sizeOf(SpecificConfig);
    }

    /// Writes the magic cookie into `out`; returns its size, or 0 if `out` is too small.
    pub fn getMagicCookie(self: *const Encoder, out: []u8) u32 {
        const size = magicCookieSize(self.num_channels);
        if (out.len < size) return 0;

        const config = self.getConfig();
        @memcpy(out[0..@sizeOf(SpecificConfig)], std.mem.asBytes(&config));
        if (self.num_channels > 2) {
            const layout_size = @sizeOf(c.ALACAudioChannelLayout);
            const atom = out[@sizeOf(SpecificConfig)..][0..c.kChannelAtomSize];
            atom.* = .{ 0, 0, 0, c.kChannelAtomSize + layout_size, 'c', 'h', 'a', 'n', 0, 0, 0, 0 };
            const layout = out[@sizeOf(SpecificConfig) + c.kChannelAtomSize ..][0..layout_size];
            @memset(layout, 0);
            std.mem.writeInt(u32, layout[0..4], c.ALACChannelLayoutTags[self.num_channels - 1], .big);
        }
        return size;
    }

    fn bytesShiftedFor(bit_depth: u32) u8 {
        // matrix encoding adds an extra bit but 32-bit inputs cannot be matrixed b/c 33 is too many
        // so enable 16-bit "shift off" and encode in 17-bit mode; 24-bit improves with one byte shifted off
        return if (bit_depth == 32) 2 else if (bit_depth >= 24) 1 else 0;
    }

    fn mix(self: *Encoder, in: [*]u8, stride: u32, num_samples: u32, mix_bits: i32, mix_res: i32, bytes_shifted: u8) void {
        const n: i32 = @intCast(num_samples);
        const u = self.mix_buffer_u.ptr;
        const v = self.mix_buffer_v.ptr;
        switch (self.bit_depth) {
            16 => c.mix16(i16Ptr(in), stride, u, v, n, mix_bits, mix_res),
            20 => c.mix20(in, stride, u, v, n, mix_bits, mix_res),
            // 24/32 also extract the shifted-off bytes into the shift buffer
            24 => c.mix24(in, stride, u, v, n, mix_bits, mix_res, self.shift_buffer_uv.ptr, bytes_shifted),
            32 => c.mix32(i32Ptr(in), stride, u, v, n, mix_bits, mix_res, self.shift_buffer_uv.ptr, bytes_shifted),
            else => unreachable,
        }
    }

    fn agParams(num_samples: u32) c.AGParamRec {
        const pb_factor = 4;
        var params: c.AGParamRec = undefined;
        c.set_ag_params(&params, c.MB0, (pb_factor * c.PB0) / 4, c.KB0, num_samples, num_samples, c.MAX_RUN_DEFAULT);
        return params;
    }

    fn compress(pc: []i32, bitstream: *BitBuffer, num_samples: u32, chan_bits: u32) Error!u32 {
        var num_bits: u32 = undefined;
        if (compressStatus(pc, bitstream, num_samples, chan_bits, &num_bits) != 0) return error.InvalidParameter;
        return num_bits;
    }

    /// dyn_comp sets outNumBits (and advances the stream) even when it fails.
    fn compressStatus(pc: []i32, bitstream: *BitBuffer, num_samples: u32, chan_bits: u32, num_bits: *u32) i32 {
        var params = agParams(num_samples);
        return c.dyn_comp(&params, pc.ptr, bitstream, @intCast(num_samples), @intCast(chan_bits), num_bits);
    }

    /// Stereo element header after the 7-bit tag: flags, mix params, two predictor headers + coefs
    /// (mode 0, DENSHIFT_DEFAULT, pbFactor 4), then the interleaved shifted-off bytes.
    fn writeStereoHeader(self: *Encoder, bitstream: *BitBuffer, partial_frame: bool, num_samples: u32, bytes_shifted: u8, mix_bits: i32, mix_res: i32, coefs_u: []const i16, coefs_v: []const i16) void {
        const pb_factor = 4;
        c.BitBufferWrite(bitstream, 0, 12);
        c.BitBufferWrite(bitstream, (@as(u32, @intFromBool(partial_frame)) << 3) | (@as(u32, bytes_shifted) << 1), 4);
        if (partial_frame) c.BitBufferWrite(bitstream, num_samples, 32);
        c.BitBufferWrite(bitstream, signed(mix_bits), 8);
        c.BitBufferWrite(bitstream, signed(mix_res), 8);
        for ([_][]const i16{ coefs_u, coefs_v }) |coefs| {
            c.BitBufferWrite(bitstream, (0 << 4) | c.DENSHIFT_DEFAULT, 8);
            c.BitBufferWrite(bitstream, (pb_factor << 5) | @as(u32, @intCast(coefs.len)), 8);
            for (coefs) |coef| c.BitBufferWrite(bitstream, signed(coef), 16);
        }
        if (bytes_shifted != 0) {
            const bit_shift: u5 = @intCast(bytes_shifted * 8);
            var index: usize = 0;
            while (index < num_samples * 2) : (index += 2) {
                const shifted = (@as(u32, self.shift_buffer_uv[index]) << bit_shift) | self.shift_buffer_uv[index + 1];
                c.BitBufferWrite(bitstream, shifted, @as(u32, bit_shift) * 2);
            }
        }
    }

    fn encodeStereo(self: *Encoder, bitstream: *BitBuffer, in: [*]u8, stride: u32, channel_index: u32, num_samples: u32) Error!void {
        const start_bits = bitstream.*;
        // retaining coefs state across blocks (and across mixRes passes) gives better compression
        const coefs_u = &self.coefs_u[channel_index];
        const coefs_v = &self.coefs_v[channel_index];
        const bytes_shifted = bytesShiftedFor(self.bit_depth);
        const chan_bits = self.bit_depth - @as(u32, bytes_shifted) * 8 + 1;
        const partial_frame = num_samples != self.frame_size;
        const mix_bits: i32 = default_mix_bits;
        var work_bits: BitBuffer = undefined;

        // brute-force search for the best mixRes on a decimated signal
        {
            const dilate = 8;
            const n = num_samples / dilate;
            var min_bits: u32 = 1 << 31;
            var best_res: i32 = self.last_mix_res[channel_index];
            var mix_res: i32 = 0;
            while (mix_res <= max_res) : (mix_res += 1) {
                self.mix(in, stride, n, mix_bits, mix_res, bytes_shifted);
                c.BitBufferInit(&work_bits, self.work_buffer.ptr, self.max_output_bytes);
                c.pc_block(self.mix_buffer_u.ptr, self.predictor_u.ptr, @intCast(n), &coefs_u[default_num_uv - 1], default_num_uv, chan_bits, c.DENSHIFT_DEFAULT);
                c.pc_block(self.mix_buffer_v.ptr, self.predictor_v.ptr, @intCast(n), &coefs_v[default_num_uv - 1], default_num_uv, chan_bits, c.DENSHIFT_DEFAULT);
                const bits1 = try compress(self.predictor_u, &work_bits, n, chan_bits);
                const bits2 = try compress(self.predictor_v, &work_bits, n, chan_bits);
                if (bits1 + bits2 < min_bits) {
                    min_bits = bits1 + bits2;
                    best_res = mix_res;
                }
            }
            self.last_mix_res[channel_index] = @intCast(best_res);
        }

        // mix the stereo inputs with the current best mixRes
        const mix_res: i32 = self.last_mix_res[channel_index];
        self.mix(in, stride, num_samples, mix_bits, mix_res, bytes_shifted);

        // predictor coefficient search loop
        var num_u: u32 = min_uv;
        var num_v: u32 = min_uv;
        var min_bits1: u32 = 1 << 31;
        var min_bits2: u32 = 1 << 31;
        var num_uv: u32 = min_uv;
        while (num_uv <= max_uv) : (num_uv += 4) {
            c.BitBufferInit(&work_bits, self.work_buffer.ptr, self.max_output_bytes);

            // run the predictor over the same data multiple times to help it converge
            for (0..8) |_| {
                c.pc_block(self.mix_buffer_u.ptr, self.predictor_u.ptr, @intCast(num_samples / 32), &coefs_u[num_uv - 1], @intCast(num_uv), chan_bits, c.DENSHIFT_DEFAULT);
                c.pc_block(self.mix_buffer_v.ptr, self.predictor_v.ptr, @intCast(num_samples / 32), &coefs_v[num_uv - 1], @intCast(num_uv), chan_bits, c.DENSHIFT_DEFAULT);
            }

            const dilate = 8;
            // the reference ignores dyn_comp's status in this search pass
            var bits1: u32 = undefined;
            var bits2: u32 = undefined;
            _ = compressStatus(self.predictor_u, &work_bits, num_samples / dilate, chan_bits, &bits1);
            if (bits1 * dilate + 16 * num_uv < min_bits1) {
                min_bits1 = bits1 * dilate + 16 * num_uv;
                num_u = num_uv;
            }
            _ = compressStatus(self.predictor_v, &work_bits, num_samples / dilate, chan_bits, &bits2);
            if (bits2 * dilate + 16 * num_uv < min_bits2) {
                min_bits2 = bits2 * dilate + 16 * num_uv;
                num_v = num_uv;
            }
        }

        // escape hatch if the best estimated compressed size is more than the input size
        var min_bits = min_bits1 + min_bits2 + (8 * 8) + @as(u32, if (partial_frame) 32 else 0);
        if (bytes_shifted != 0) min_bits += num_samples * (@as(u32, bytes_shifted) * 8) * 2;
        const escape_bits = (num_samples * self.bit_depth * 2) + @as(u32, if (partial_frame) 32 else 0) + (2 * 8);

        if (min_bits < escape_bits) {
            self.writeStereoHeader(bitstream, partial_frame, num_samples, bytes_shifted, mix_bits, mix_res, coefs_u[num_u - 1][0..num_u], coefs_v[num_v - 1][0..num_v]);

            // run the dynamic predictor and lossless compression per channel (mode 0 only)
            c.pc_block(self.mix_buffer_u.ptr, self.predictor_u.ptr, @intCast(num_samples), &coefs_u[num_u - 1], @intCast(num_u), chan_bits, c.DENSHIFT_DEFAULT);
            _ = try compress(self.predictor_u, bitstream, num_samples, chan_bits);
            c.pc_block(self.mix_buffer_v.ptr, self.predictor_v.ptr, @intCast(num_samples), &coefs_v[num_v - 1], @intCast(num_v), chan_bits, c.DENSHIFT_DEFAULT);
            _ = try compress(self.predictor_v, bitstream, num_samples, chan_bits);

            // chuck a compressed packet that ended up bigger than an escape packet
            var mutable_start = start_bits;
            if (c.BitBufferGetPosition(bitstream) - c.BitBufferGetPosition(&mutable_start) < escape_bits) return;
            bitstream.* = start_bits;
        }
        self.encodeStereoEscape(bitstream, in, stride, num_samples);
    }

    /// Stereo without the search loop, for maximum speed.
    fn encodeStereoFast(self: *Encoder, bitstream: *BitBuffer, in: [*]u8, stride: u32, channel_index: u32, num_samples: u32) Error!void {
        var start_bits = bitstream.*;
        const coefs_u = &self.coefs_u[channel_index];
        const coefs_v = &self.coefs_v[channel_index];
        const bytes_shifted = bytesShiftedFor(self.bit_depth);
        const chan_bits = self.bit_depth - @as(u32, bytes_shifted) * 8 + 1;
        const partial_frame = num_samples != self.frame_size;
        const mix_bits: i32 = default_mix_bits;
        const mix_res: i32 = default_mix_res;
        const num_u = default_num_uv;
        const num_v = default_num_uv;

        self.mix(in, stride, num_samples, mix_bits, mix_res, bytes_shifted);

        // speculatively write the bitstream assuming the compressed version will be smaller
        self.writeStereoHeader(bitstream, partial_frame, num_samples, bytes_shifted, mix_bits, mix_res, coefs_u[num_u - 1][0..num_u], coefs_v[num_v - 1][0..num_v]);

        c.pc_block(self.mix_buffer_u.ptr, self.predictor_u.ptr, @intCast(num_samples), &coefs_u[num_u - 1], num_u, chan_bits, c.DENSHIFT_DEFAULT);
        const bits1 = try compress(self.predictor_u, bitstream, num_samples, chan_bits);
        c.pc_block(self.mix_buffer_v.ptr, self.predictor_v.ptr, @intCast(num_samples), &coefs_v[num_v - 1], num_v, chan_bits, c.DENSHIFT_DEFAULT);
        const bits2 = try compress(self.predictor_v, bitstream, num_samples, chan_bits);

        const escape_bits = (num_samples * self.bit_depth * 2) + @as(u32, if (partial_frame) 32 else 0) + (2 * 8);
        var min_bits = bits1 + num_u * 16 + bits2 + num_v * 16 + (8 * 8) + @as(u32, if (partial_frame) 32 else 0);
        if (bytes_shifted != 0) min_bits += num_samples * (@as(u32, bytes_shifted) * 8) * 2;
        if (min_bits < escape_bits and
            c.BitBufferGetPosition(bitstream) - c.BitBufferGetPosition(&start_bits) < escape_bits) return;

        // reset bitstream position since we speculatively wrote the compressed version
        bitstream.* = start_bits;
        self.encodeStereoEscape(bitstream, in, stride, num_samples);
    }

    fn encodeStereoEscape(self: *Encoder, bitstream: *BitBuffer, in: [*]u8, stride: u32, num_samples: u32) void {
        const partial_frame = num_samples != self.frame_size;
        c.BitBufferWrite(bitstream, 0, 12);
        c.BitBufferWrite(bitstream, (@as(u32, @intFromBool(partial_frame)) << 3) | 1, 4); // LSB = 1: not compressed
        if (partial_frame) c.BitBufferWrite(bitstream, num_samples, 32);

        const n: i32 = @intCast(num_samples);
        switch (self.bit_depth) {
            16 => {
                const in16 = i16Ptr(in);
                for (0..num_samples) |i| {
                    c.BitBufferWrite(bitstream, signed(in16[i * stride]), 16);
                    c.BitBufferWrite(bitstream, signed(in16[i * stride + 1]), 16);
                }
            },
            // mixN() with mixres = 0 means de-interleave
            20, 24 => {
                if (self.bit_depth == 20)
                    c.mix20(in, stride, self.mix_buffer_u.ptr, self.mix_buffer_v.ptr, n, 0, 0)
                else
                    c.mix24(in, stride, self.mix_buffer_u.ptr, self.mix_buffer_v.ptr, n, 0, 0, self.shift_buffer_uv.ptr, 0);
                for (0..num_samples) |i| {
                    c.BitBufferWrite(bitstream, signed(self.mix_buffer_u[i]), self.bit_depth);
                    c.BitBufferWrite(bitstream, signed(self.mix_buffer_v[i]), self.bit_depth);
                }
            },
            32 => {
                const in32 = i32Ptr(in);
                for (0..num_samples) |i| {
                    c.BitBufferWrite(bitstream, signed(in32[i * stride]), 32);
                    c.BitBufferWrite(bitstream, signed(in32[i * stride + 1]), 32);
                }
            },
            else => unreachable,
        }
    }

    fn encodeMono(self: *Encoder, bitstream: *BitBuffer, in: [*]u8, stride: u32, channel_index: u32, num_samples: u32) Error!void {
        var start_bits = bitstream.*;
        const coefs_u = &self.coefs_u[channel_index];
        const bytes_shifted = bytesShiftedFor(self.bit_depth);
        const shift: u5 = @intCast(bytes_shifted * 8);
        const mask: u32 = (@as(u32, 1) << shift) - 1;
        const chan_bits = self.bit_depth - @as(u32, bytes_shifted) * 8;
        const partial_frame = num_samples != self.frame_size;
        const n: i32 = @intCast(num_samples);
        const pb_factor = 4;

        // convert N-bit data to 32-bit for the predictor, extracting shifted-off bytes for 24/32-bit
        switch (self.bit_depth) {
            16 => {
                const in16 = i16Ptr(in);
                for (0..num_samples) |i| self.mix_buffer_u[i] = in16[i * stride];
            },
            20 => c.copy20ToPredictor(in, stride, self.mix_buffer_u.ptr, n),
            24 => {
                c.copy24ToPredictor(in, stride, self.mix_buffer_u.ptr, n);
                for (self.mix_buffer_u[0..num_samples], self.shift_buffer_uv[0..num_samples]) |*value, *shifted| {
                    shifted.* = @truncate(@as(u32, @bitCast(value.*)) & mask);
                    value.* >>= shift;
                }
            },
            32 => {
                const in32 = i32Ptr(in);
                for (0..num_samples) |i| {
                    const value = in32[i * stride];
                    self.shift_buffer_uv[i] = @truncate(@as(u32, @bitCast(value)) & mask);
                    self.mix_buffer_u[i] = value >> shift;
                }
            },
            else => unreachable,
        }

        // brute-force search for the best predictor order on a decimated signal
        var min_bits: u32 = 1 << 31;
        var best_u: u32 = 4;
        var num_u: u32 = 4;
        while (num_u <= 8) : (num_u += 4) {
            var work_bits: BitBuffer = undefined;
            c.BitBufferInit(&work_bits, self.work_buffer.ptr, self.max_output_bytes);
            for (0..7) |_|
                c.pc_block(self.mix_buffer_u.ptr, self.predictor_u.ptr, @intCast(num_samples / 32), &coefs_u[num_u - 1], @intCast(num_u), chan_bits, c.DENSHIFT_DEFAULT);
            const dilate = 8;
            c.pc_block(self.mix_buffer_u.ptr, self.predictor_u.ptr, @intCast(num_samples / dilate), &coefs_u[num_u - 1], @intCast(num_u), chan_bits, c.DENSHIFT_DEFAULT);
            const bits1 = try compress(self.predictor_u, &work_bits, num_samples / dilate, chan_bits);
            const num_bits = dilate * bits1 + 16 * num_u;
            if (num_bits < min_bits) {
                best_u = num_u;
                min_bits = num_bits;
            }
        }

        // escape hatch; first add bits for the header bytes mixRes/maxRes/shiftU/filterU
        min_bits += (4 * 8) + @as(u32, if (partial_frame) 32 else 0);
        if (bytes_shifted != 0) min_bits += num_samples * shift;
        const escape_bits = (num_samples * self.bit_depth) + @as(u32, if (partial_frame) 32 else 0) + (2 * 8);

        if (min_bits < escape_bits) {
            c.BitBufferWrite(bitstream, 0, 12);
            c.BitBufferWrite(bitstream, (@as(u32, @intFromBool(partial_frame)) << 3) | (@as(u32, bytes_shifted) << 1), 4);
            if (partial_frame) c.BitBufferWrite(bitstream, num_samples, 32);
            c.BitBufferWrite(bitstream, 0, 16); // mixBits = mixRes = 0

            num_u = best_u;
            c.BitBufferWrite(bitstream, (0 << 4) | c.DENSHIFT_DEFAULT, 8); // modeU = 0
            c.BitBufferWrite(bitstream, (pb_factor << 5) | num_u, 8);
            for (coefs_u[num_u - 1][0..num_u]) |coef| c.BitBufferWrite(bitstream, signed(coef), 16);

            if (bytes_shifted != 0) {
                for (self.shift_buffer_uv[0..num_samples]) |shifted| c.BitBufferWrite(bitstream, shifted, shift);
            }

            c.pc_block(self.mix_buffer_u.ptr, self.predictor_u.ptr, n, &coefs_u[num_u - 1], @intCast(num_u), chan_bits, c.DENSHIFT_DEFAULT);
            var params: c.AGParamRec = undefined;
            c.set_standard_ag_params(&params, num_samples, num_samples);
            var bits1: u32 = undefined;
            // the reference keeps this status and returns it after the packet is written
            if (c.dyn_comp(&params, self.predictor_u.ptr, bitstream, n, @intCast(chan_bits), &bits1) != 0) return error.InvalidParameter;

            if (c.BitBufferGetPosition(bitstream) - c.BitBufferGetPosition(&start_bits) < escape_bits) return;
            bitstream.* = start_bits;
        }

        // escape: header, then the raw input
        c.BitBufferWrite(bitstream, 0, 12);
        c.BitBufferWrite(bitstream, (@as(u32, @intFromBool(partial_frame)) << 3) | 1, 4); // LSB = 1: not compressed
        if (partial_frame) c.BitBufferWrite(bitstream, num_samples, 32);
        switch (self.bit_depth) {
            16 => {
                const in16 = i16Ptr(in);
                for (0..num_samples) |i| c.BitBufferWrite(bitstream, signed(in16[i * stride]), 16);
            },
            20, 24 => {
                if (self.bit_depth == 20)
                    c.copy20ToPredictor(in, stride, self.mix_buffer_u.ptr, n)
                else
                    c.copy24ToPredictor(in, stride, self.mix_buffer_u.ptr, n);
                for (self.mix_buffer_u[0..num_samples]) |value| c.BitBufferWrite(bitstream, signed(value), self.bit_depth);
            },
            32 => {
                const in32 = i32Ptr(in);
                for (0..num_samples) |i| c.BitBufferWrite(bitstream, signed(in32[i * stride]), 32);
            },
            else => unreachable,
        }
    }
};
