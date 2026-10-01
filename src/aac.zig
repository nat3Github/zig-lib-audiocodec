//! AAC through fdk-aac (Fraunhofer FDK AAC Codec Library, see README for its license terms): the
//! decoder and encoder cores shared with the m4a container (m4a.zig), and raw ADTS streams (.aac).
//!
//! Decode: one access unit per aacDecoder_Fill + aacDecoder_DecodeFrame (m4a: TT_MP4_RAW configured
//! with the AudioSpecificConfig; ADTS: TT_MP4_ADTS fed one whole frame at a time, split by us).
//! Output: fdk's INT_PCM (i16) in WAV channel order (AAC_PCM_OUTPUT_CHANNEL_MAPPING 1), no
//! downmix, no channel extension, limiter off (it would add delay and change levels), concealment
//! by noise substitution (no delay, as ffmpeg's libfdk wrapper); remapped to
//! canonical order from the channel types fdk reports. HE-AAC / HE-AACv2: rate and channels are
//! only known after a frame (implicit SBR/PS signalling), so both containers decode one at open.
//!
//! ADTS carries no gapless info: the output keeps the encoder delay in front and the padding of
//! the last frame (length = whole frames minus fdk's own decoder delay, see Format.delay). With a Seeker, open scans the frame headers once
//! (`frames`, seek points); without one `frames` is null and seek is NotSeekable.
//!
//! Encode: aacEncEncode, one frame of input at a time (i16, WAV channel order = canonical for
//! the layouts we accept), AUs handed to the container's sink; finish flushes until
//! AACENC_ENCODE_EOF. Afterburner on. VBR 1..5 from quality, or CBR at Options.bitrate.

const std = @import("std");
const skip = @import("pcm.zig").skip;
const root = @import("root.zig");
const sample = @import("sample.zig");
const c_allocator = @import("c_allocator.zig");
const fdk = @import("zig-c-headers/fdk_aac.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Seeker = root.Seeker;
const ChannelLayout = root.ChannelLayout;

/// Output frames per access unit and channel, upper bound (USAC with 4:1 SBR; HE-AAC: 2048).
pub const max_frame = 4096;
pub const max_channels = 8;

// --- output format and channel order ---

pub const Format = struct {
    rate: u32,
    channels: u16,
    /// Output frames per access unit.
    frame_size: u32,
    /// Output frames fdk delays the signal by (SBR QMF banks: 962 for HE-AAC at 2:1), on top
    /// of the encoder's priming; the containers trim it at the start.
    delay: u32,
    /// null: unspecified, fdk's order kept.
    layout: ?ChannelLayout,
    /// Canonical position of each output channel.
    order: [max_channels]u8,

    pub fn eql(a: Format, b: Format) bool {
        return a.rate == b.rate and a.channels == b.channels and a.frame_size == b.frame_size;
    }

    /// Access units decoded before a seek target. The MDCT overlap needs one; SBR envelopes are
    /// delta coded in time, so an SBR stream (delay > 0) must reach back past an SBR header,
    /// which fdk's encoder sends every 10 access units. Measured: 3 give output identical to a
    /// linear decode for LC. ponytail: encoders with a longer header period converge later.
    pub fn preroll(f: Format) u32 {
        return if (f.delay > 0) 3 + 10 else 3;
    }
};

const identity: [max_channels]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7 };

/// Speaker positions from fdk's channel types and indices. Fronts: centre first (odd count), then
/// pairs from the inside out (two pairs: FLC/FRC, FL/FR). Surround pairs: side before back; one
/// pair is SL/SR when a back centre exists (6.1), else BL/BR (5.1). Anything else (more pairs,
/// top/bottom channels): layout null, fdk's order.
fn formatOf(info: *const fdk.CStreamInfo) ?Format {
    if (info.numChannels < 1 or info.numChannels > max_channels or info.sampleRate <= 0) return null;
    if (info.frameSize <= 0 or info.frameSize > max_frame) return null;
    const n: usize = @intCast(info.numChannels);
    var f: Format = .{
        .rate = @intCast(info.sampleRate),
        .channels = @intCast(n),
        .frame_size = @intCast(info.frameSize),
        .delay = info.outputDelay,
        .layout = null,
        .order = identity,
    };
    const types = info.pChannelType orelse return f;
    const indices = info.pChannelIndices orelse return f;

    // Output channels per type, ordered by fdk's index.
    const Group = struct {
        ch: [max_channels]u8 = undefined,
        len: usize = 0,

        fn collect(g: *@This(), t: []const fdk.AUDIO_CHANNEL_TYPE, idx: []const u8, want: fdk.AUDIO_CHANNEL_TYPE) void {
            for (0..t.len) |i| if (t[i] == want) {
                g.ch[g.len] = @intCast(i);
                g.len += 1;
            };
            std.mem.sortUnstable(u8, g.ch[0..g.len], idx, struct {
                fn less(ix: []const u8, a: u8, b: u8) bool {
                    return ix[a] < ix[b];
                }
            }.less);
        }
    };
    var front: Group = .{};
    var side: Group = .{};
    var back: Group = .{};
    var lfe: Group = .{};
    front.collect(types[0..n], indices[0..n], fdk.ACT_FRONT);
    side.collect(types[0..n], indices[0..n], fdk.ACT_SIDE);
    back.collect(types[0..n], indices[0..n], fdk.ACT_BACK);
    lfe.collect(types[0..n], indices[0..n], fdk.ACT_LFE);
    if (front.len + side.len + back.len + lfe.len != n or lfe.len > 1 or side.len % 2 != 0) return f;

    var bit: [max_channels]u5 = undefined;
    const B = struct {
        const fl = 0;
        const fr = 1;
        const fc = 2;
        const lf = 3;
        const bl = 4;
        const br = 5;
        const flc = 6;
        const frc = 7;
        const bc = 8;
        const sl = 9;
        const sr = 10;
    };
    var fronts = front.ch[0..front.len];
    if (fronts.len % 2 == 1) {
        bit[fronts[0]] = B.fc;
        fronts = fronts[1..];
    }
    switch (fronts.len) {
        0 => {},
        2 => {
            bit[fronts[0]] = B.fl;
            bit[fronts[1]] = B.fr;
        },
        4 => {
            bit[fronts[0]] = B.flc;
            bit[fronts[1]] = B.frc;
            bit[fronts[2]] = B.fl;
            bit[fronts[3]] = B.fr;
        },
        else => return f,
    }
    var backs = back.ch[0..back.len];
    const back_center = backs.len % 2 == 1;
    if (back_center) {
        bit[backs[backs.len - 1]] = B.bc;
        backs = backs[0 .. backs.len - 1];
    }
    var sides = side.ch[0..side.len];
    if (sides.len == 0 and (backs.len == 4 or (backs.len == 2 and back_center))) {
        sides = backs[0..2];
        backs = backs[2..];
    }
    if (sides.len > 2 or backs.len > 2) return f;
    if (sides.len == 2) {
        bit[sides[0]] = B.sl;
        bit[sides[1]] = B.sr;
    }
    if (backs.len == 2) {
        bit[backs[0]] = B.bl;
        bit[backs[1]] = B.br;
    }
    if (lfe.len == 1) bit[lfe.ch[0]] = B.lf;

    var mask: u32 = 0;
    for (bit[0..n]) |b| mask |= @as(u32, 1) << b;
    for (bit[0..n], 0..) |b, i| f.order[i] = @intCast(@popCount(mask & ((@as(u32, 1) << b) - 1)));
    f.layout = ChannelLayout.fromMask(mask);
    return f;
}

/// Output channel order -> canonical, in place (`frames` interleaved frames).
pub fn remap(pcm: []i16, f: Format) void {
    if (f.layout == null) return;
    const n = f.channels;
    if (std.mem.eql(u8, f.order[0..n], identity[0..n])) return;
    var i: usize = 0;
    while (i < pcm.len) : (i += n) {
        const frame = pcm[i..][0..n];
        var tmp: [max_channels]i16 = undefined;
        @memcpy(tmp[0..n], frame);
        for (f.order[0..n], 0..) |dst, src| frame[dst] = tmp[src];
    }
}

// --- decoder core ---

/// One fdk decoder instance.
pub const Codec = struct {
    handle: fdk.HANDLE_AACDECODER,
    /// Set after a seek: the next access unit follows a discontinuity.
    interrupted: bool = false,

    /// `config`: the AudioSpecificConfig (m4a); null for ADTS.
    pub fn open(gpa: Allocator, config: ?[]const u8) Error!Codec {
        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        const handle = fdk.aacDecoder_Open(if (config == null) fdk.TT_MP4_ADTS else fdk.TT_MP4_RAW, 1) orelse return error.OutOfMemory;
        errdefer fdk.aacDecoder_Close(handle);
        if (c_allocator.failed) return error.OutOfMemory;
        if (config) |asc| {
            if (asc.len == 0 or asc.len > std.math.maxInt(u32)) return error.InvalidFile;
            const conf = [_][*]u8{@constCast(asc.ptr)};
            const len = [_]fdk.UINT{@intCast(asc.len)};
            const err = fdk.aacDecoder_ConfigRaw(handle, &conf, &len);
            if (c_allocator.failed or err == fdk.AAC_DEC_OUT_OF_MEMORY) return error.OutOfMemory;
            if (err != fdk.AAC_DEC_OK) return if (err >= fdk.aac_dec_init_error_start and err <= fdk.aac_dec_init_error_end and err != fdk.AAC_DEC_UNSUPPORTED_FORMAT) error.UnsupportedFormat else error.InvalidFile;
        }
        for ([_]struct { fdk.AACDEC_PARAM, fdk.INT }{
            .{ fdk.AAC_PCM_OUTPUT_CHANNEL_MAPPING, 1 },
            .{ fdk.AAC_PCM_MIN_OUTPUT_CHANNELS, -1 },
            .{ fdk.AAC_PCM_MAX_OUTPUT_CHANNELS, -1 },
            .{ fdk.AAC_PCM_LIMITER_ENABLE, 0 },
            // Noise substitution: the default (energy interpolation) delays the output by a frame.
            .{ fdk.AAC_CONCEAL_METHOD, 1 },
        }) |p| if (fdk.aacDecoder_SetParam(handle, p[0], p[1]) != fdk.AAC_DEC_OK) return error.UnsupportedFormat;
        return .{ .handle = handle };
    }

    pub fn close(d: *Codec, gpa: Allocator) void {
        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        fdk.aacDecoder_Close(d.handle);
    }

    /// Decodes one access unit (m4a) or ADTS frame into `pcm` (interleaved, canonical order).
    /// Returns the format of the output: `frame_size` frames were written.
    pub fn decode(d: *Codec, gpa: Allocator, packet: []const u8, pcm: []i16) Error!Format {
        if (packet.len == 0 or packet.len > std.math.maxInt(u32)) return error.InvalidFile;
        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        const buf = [_][*]u8{@constCast(packet.ptr)};
        const size = [_]fdk.UINT{@intCast(packet.len)};
        var valid: fdk.UINT = size[0];
        var err = fdk.aacDecoder_Fill(d.handle, &buf, &size, &valid);
        if (err != fdk.AAC_DEC_OK or valid != 0) return if (c_allocator.failed) error.OutOfMemory else error.InvalidFile;
        const flags: fdk.UINT = if (d.interrupted) fdk.AACDEC_INTR | fdk.AACDEC_CLRHIST else 0;
        err = fdk.aacDecoder_DecodeFrame(d.handle, pcm.ptr, @intCast(pcm.len), flags);
        if (c_allocator.failed or err == fdk.AAC_DEC_OUT_OF_MEMORY) return error.OutOfMemory;
        if (err != fdk.AAC_DEC_OK) {
            // A stream fdk can't decode at all (ELD downscale, unsupported AOT ...) vs. damage.
            if (err >= fdk.aac_dec_init_error_start and err <= fdk.aac_dec_init_error_end and
                err != fdk.AAC_DEC_UNSUPPORTED_FORMAT and err != fdk.AAC_DEC_OUTPUT_BUFFER_TOO_SMALL)
                return error.UnsupportedFormat;
            return error.InvalidFile;
        }
        d.interrupted = false;
        const info = fdk.aacDecoder_GetStreamInfo(d.handle) orelse return error.InvalidFile;
        const f = formatOf(info) orelse return error.UnsupportedFormat;
        remap(pcm[0 .. f.frame_size * f.channels], f);
        return f;
    }

    /// Next access unit is not the one after the last (seek): fdk resynchronizes, and CLRHIST
    /// clears its delay lines (else the first frame after a seek to the start holds stale output).
    pub fn reset(d: *Codec) void {
        _ = fdk.aacDecoder_SetParam(d.handle, fdk.AAC_TPDEC_CLEAR_BUFFER, 1);
        d.interrupted = true;
    }
};

// --- encoder core ---

pub const Profile = root.AacProfile;

/// One fdk encoder instance. `Sink` has `fn packet(sink, bytes: []const u8) Error!void`,
/// called with each access unit (raw or ADTS frame) in order.
pub const Enc = struct {
    handle: fdk.HANDLE_AACENCODER,
    gpa: Allocator,
    channels: u16,
    /// Input frames per access unit (output frames for HE: the core runs at half rate).
    frame_length: u32,
    /// Encoder delay (output frames of an ideal decoder before the first input frame): m4a's
    /// edit list. fdk's nDelayCore; its nDelay adds the decoder's SBR delay (`decoder_delay`),
    /// which our decoder (Format.delay) and Apple's trim themselves.
    delay: u32,
    decoder_delay: u32,
    /// AudioSpecificConfig (raw transport).
    config: [64]u8,
    config_len: u32,
    input: []i16,
    input_frames: u32 = 0,
    out: []u8,

    pub fn open(gpa: Allocator, options: root.Encoder.Options, adts: bool) Error!Enc {
        const channels = options.channels;
        const mode: fdk.CHANNEL_MODE = switch (channels) {
            1 => fdk.MODE_1,
            2 => fdk.MODE_2,
            3 => fdk.MODE_1_2,
            4 => fdk.MODE_1_2_1,
            5 => fdk.MODE_1_2_2,
            6 => fdk.MODE_1_2_2_1,
            7 => fdk.MODE_6_1,
            8 => fdk.MODE_7_1_BACK,
            else => return error.UnsupportedFormat,
        };
        if (options.channel_layout) |l| if (l.mask() != layouts[channels - 1].mask()) return error.UnsupportedFormat;
        const aot: fdk.AUDIO_OBJECT_TYPE = switch (options.aac_profile) {
            .lc => fdk.AOT_AAC_LC,
            .he => fdk.AOT_SBR,
            .he_v2 => fdk.AOT_PS,
        };
        if (options.aac_profile == .he_v2 and channels != 2) return error.UnsupportedFormat;
        // VBR 1 (~32 kbit/s stereo, tuned for HE-AACv2) .. 5 (~228 kbit/s).
        const vbr: fdk.UINT = if (options.quality) |q| blk: {
            if (!(q >= 0 and q <= 1)) return error.InvalidOptions;
            break :blk 1 + @as(fdk.UINT, @intFromFloat(@round(q * 4)));
        } else switch (options.aac_profile) {
            .lc => 4,
            .he => 2,
            .he_v2 => 1,
        };
        if (options.bitrate) |b| if (b == 0) return error.InvalidOptions;

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        var h: ?fdk.HANDLE_AACENCODER = null;
        if (fdk.aacEncOpen(&h, 0, channels) != fdk.AACENC_OK) return error.OutOfMemory;
        const handle = h.?;
        errdefer _ = fdk.aacEncClose(&h);
        const params = [_]struct { fdk.AACENC_PARAM, fdk.UINT }{
            .{ fdk.AACENC_AOT, @intCast(aot) },
            .{ fdk.AACENC_SAMPLERATE, options.sample_rate },
            .{ fdk.AACENC_CHANNELMODE, @intCast(mode) },
            .{ fdk.AACENC_CHANNELORDER, 1 },
            .{ fdk.AACENC_BITRATEMODE, if (options.bitrate == null) vbr else 0 },
            .{ fdk.AACENC_BITRATE, options.bitrate orelse 0 },
            .{ fdk.AACENC_TRANSMUX, @intCast(if (adts) fdk.TT_MP4_ADTS else fdk.TT_MP4_RAW) },
            // m4a: SBR/PS announced in the AudioSpecificConfig (as ffmpeg and iTunes write it).
            .{ fdk.AACENC_SIGNALING_MODE, if (adts or aot == fdk.AOT_AAC_LC) 0 else 2 },
            .{ fdk.AACENC_AFTERBURNER, 1 },
        };
        for (params) |p| {
            if (p[0] == fdk.AACENC_BITRATE and options.bitrate == null) continue;
            if (fdk.aacEncoder_SetParam(handle, p[0], p[1]) != fdk.AACENC_OK) return if (c_allocator.failed) error.OutOfMemory else error.UnsupportedFormat;
        }
        // Applies the parameters.
        switch (fdk.aacEncEncode(handle, null, null, null, null)) {
            fdk.AACENC_OK => {},
            else => return if (c_allocator.failed) error.OutOfMemory else error.UnsupportedFormat,
        }
        var info: fdk.AACENC_InfoStruct = undefined;
        if (fdk.aacEncInfo(handle, &info) != fdk.AACENC_OK) return error.UnsupportedFormat;
        const input = try gpa.alloc(i16, @as(usize, info.frameLength) * channels);
        errdefer gpa.free(input);
        const out = try gpa.alloc(u8, info.maxOutBufBytes);
        return .{
            .handle = handle,
            .gpa = gpa,
            .channels = channels,
            .frame_length = info.frameLength,
            .delay = info.nDelayCore,
            .decoder_delay = info.nDelay -| info.nDelayCore,
            .config = info.confBuf,
            .config_len = info.confSize,
            .input = input,
            .out = out,
        };
    }

    pub fn deinit(e: *Enc) void {
        const prev = c_allocator.set(e.gpa);
        var h: ?fdk.HANDLE_AACENCODER = e.handle;
        _ = fdk.aacEncClose(&h);
        c_allocator.restore(prev);
        e.gpa.free(e.input);
        e.gpa.free(e.out);
    }

    /// `samples`: interleaved canonical order. Float input clipped, NaN -> 0 (sample.convert).
    pub fn write(e: *Enc, comptime T: type, samples: []const T, sink: anytype) Error!void {
        const channels: usize = e.channels;
        var i: usize = 0;
        while (i < samples.len) {
            const k = @min((samples.len - i) / channels, e.frame_length - e.input_frames);
            const dst = e.input[e.input_frames * channels ..][0 .. k * channels];
            for (dst, samples[i..][0 .. k * channels]) |*d, x| d.* = sample.convert(i16, x);
            // fdk's WAV order for 6.1 is L R C LFE Ls Rs Cs; canonical has BC before SL SR.
            if (channels == 7) {
                var f: usize = 0;
                while (f < dst.len) : (f += 7) {
                    const bc = dst[f + 4];
                    dst[f + 4] = dst[f + 5];
                    dst[f + 5] = dst[f + 6];
                    dst[f + 6] = bc;
                }
            }
            e.input_frames += @intCast(k);
            i += k * channels;
            if (e.input_frames == e.frame_length) {
                try e.encode(false, sink);
                e.input_frames = 0;
            }
        }
    }

    /// Encodes the partial frame left and flushes the encoder (delay + padding).
    pub fn finish(e: *Enc, sink: anytype) Error!void {
        if (e.input_frames > 0) try e.encode(false, sink);
        e.input_frames = 0;
        try e.encode(true, sink);
    }

    fn encode(e: *Enc, eof: bool, sink: anytype) Error!void {
        const prev = c_allocator.set(e.gpa);
        defer c_allocator.restore(prev);
        const total: usize = @as(usize, e.input_frames) * e.channels;
        var done: usize = 0;
        while (true) {
            var in_ptr: ?*anyopaque = @ptrCast(e.input[done..].ptr);
            var in_id: fdk.INT = fdk.IN_AUDIO_DATA;
            var in_size: fdk.INT = @intCast((total - done) * 2);
            var in_el: fdk.INT = 2;
            const in_desc: fdk.AACENC_BufDesc = .{ .numBufs = 1, .bufs = @ptrCast(&in_ptr), .bufferIdentifiers = @ptrCast(&in_id), .bufSizes = @ptrCast(&in_size), .bufElSizes = @ptrCast(&in_el) };
            var out_ptr: ?*anyopaque = @ptrCast(e.out.ptr);
            var out_id: fdk.INT = fdk.OUT_BITSTREAM_DATA;
            var out_size: fdk.INT = @intCast(e.out.len);
            var out_el: fdk.INT = 1;
            const out_desc: fdk.AACENC_BufDesc = .{ .numBufs = 1, .bufs = @ptrCast(&out_ptr), .bufferIdentifiers = @ptrCast(&out_id), .bufSizes = @ptrCast(&out_size), .bufElSizes = @ptrCast(&out_el) };
            const in_args: fdk.AACENC_InArgs = .{ .numInSamples = if (eof) -1 else @intCast(total - done), .numAncBytes = 0 };
            var out_args: fdk.AACENC_OutArgs = std.mem.zeroes(fdk.AACENC_OutArgs);
            switch (fdk.aacEncEncode(e.handle, &in_desc, &out_desc, &in_args, &out_args)) {
                fdk.AACENC_OK => {},
                fdk.AACENC_ENCODE_EOF => return,
                else => return if (c_allocator.failed) error.OutOfMemory else error.UnsupportedFormat,
            }
            if (c_allocator.failed) return error.OutOfMemory;
            done += @intCast(out_args.numInSamples);
            if (out_args.numOutBytes > 0) try sink.packet(e.out[0..@intCast(out_args.numOutBytes)]);
            if (!eof and done >= total) return;
            // fdk takes a whole frame per call; anything else would loop forever.
            if (!eof and out_args.numInSamples == 0 and out_args.numOutBytes == 0) return error.UnsupportedFormat;
        }
    }
};

/// The channel layouts the encoder writes (AAC channel configurations 1-7, 11, 12); 4 channels
/// are 4.0 (front centre + back centre), not quad.
pub const layouts = [8]ChannelLayout{
    .mono,
    .stereo,
    .surround_3_0,
    .{ .front_left = true, .front_right = true, .front_center = true, .back_center = true },
    .surround_5_0,
    .surround_5_1,
    .surround_6_1,
    .surround_7_1,
};

// --- ADTS ---

const Header = struct {
    /// Profile (AOT - 1), sampling frequency index, channel configuration: fixed for a stream.
    fixed: u16,
    /// Whole frame, header included.
    len: u16,
    header_len: u8,
    blocks: u8,

    const fixed_mask = 0x3df; // profile 2, sf index 4, (private bit skipped), channel config 3

    fn parse(b: *const [7]u8) ?Header {
        if (b[0] != 0xff or b[1] & 0xf6 != 0xf0) return null; // sync, layer 0
        const sf_index = (b[2] >> 2) & 0xf;
        if (sf_index > 12) return null;
        const header_len: u8 = if (b[1] & 1 == 1) 7 else 9;
        const len: u16 = (@as(u16, b[3] & 3) << 11) | (@as(u16, b[4]) << 3) | (b[5] >> 5);
        if (len <= header_len) return null;
        const fixed = ((@as(u16, b[2]) << 2) | (b[3] >> 6)) & fixed_mask;
        return .{ .fixed = fixed, .len = len, .header_len = header_len, .blocks = b[6] & 3 };
    }
};

/// A plausible ADTS frame header: sniffing (the container prefix is only 12 bytes; open checks
/// that a second header follows the first).
pub fn isAdts(b: *const [12]u8) bool {
    return Header.parse(b[0..7]) != null;
}

pub const Decoder = struct {
    state: *State,

    /// Seek point spacing in ADTS frames.
    const point_step = 64;

    const State = struct {
        gpa: Allocator,
        reader: *std.Io.Reader,
        seeker: ?Seeker,
        info: root.Info,
        codec: Codec,
        format: Format = undefined,
        first: Header = undefined,
        /// One ADTS frame.
        frame: []u8 = &.{},
        pcm: []i16 = &.{},
        pcm_used: usize = 0,
        pcm_len: usize = 0,
        /// Index of the next ADTS frame to decode.
        next: u64 = 0,
        /// Output frames to drop (seek pre-roll).
        skip: u64 = 0,
        /// Byte offset of every `point_step`-th frame (with a seeker).
        points: []u64 = &.{},
        /// Complete frames in the stream (with a seeker).
        count: ?u64 = null,
        err: ?Error = null,
        eos: bool = false,

        fn deinit(s: *State) void {
            s.codec.close(s.gpa);
            s.gpa.free(s.frame);
            s.gpa.free(s.pcm);
            s.gpa.free(s.points);
        }

        /// Reads the next frame into `frame`; null at the end (or a cut-off last frame).
        fn readFrame(s: *State) Error!?[]const u8 {
            const head = s.reader.peek(7) catch |err| return switch (err) {
                error.EndOfStream => null,
                error.ReadFailed => error.ReadFailed,
            };
            const h = Header.parse(head[0..7]) orelse return error.InvalidFile;
            if (h.fixed != s.first.fixed) return error.UnsupportedFormat;
            // ponytail: several raw data blocks per frame (nobody writes them) are not split up.
            if (h.blocks != 0) return error.UnsupportedFormat;
            const buf = s.frame[0..h.len];
            s.reader.readSliceAll(buf) catch |err| return switch (err) {
                error.EndOfStream => null,
                error.ReadFailed => error.ReadFailed,
            };
            return buf;
        }
    };

    pub fn open(gpa: Allocator, reader: *std.Io.Reader, seeker: ?Seeker) Error!Decoder {
        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .reader = reader,
            .seeker = seeker,
            .info = undefined,
            .codec = try Codec.open(gpa, null),
        };
        errdefer s.deinit();
        s.frame = try gpa.alloc(u8, 1 << 13);
        s.pcm = try gpa.alloc(i16, max_frame * max_channels);

        const head = reader.peek(7) catch |err| return headerError(err);
        s.first = Header.parse(head[0..7]) orelse return error.InvalidFile;
        const first = try s.readFrame() orelse return error.InvalidFile;
        // A second header right behind the first (or the end): not an mp3 or junk by accident.
        if (reader.peek(7)) |next| {
            const h = Header.parse(next[0..7]) orelse return error.InvalidFile;
            if (h.fixed != s.first.fixed) return error.InvalidFile;
        } else |err| switch (err) {
            error.EndOfStream => {},
            error.ReadFailed => return error.ReadFailed,
        }
        if (seeker) |sk| try scan(s, sk, first.len);

        s.format = try s.codec.decode(gpa, first, s.pcm);
        s.next = 1;
        s.pcm_len = s.format.frame_size;
        s.pcm_used = @min(s.format.delay, s.pcm_len);
        s.skip = s.format.delay - s.pcm_used;
        s.info = .{
            .container = .adts,
            .codec = .aac,
            .sample_rate = s.format.rate,
            .channels = s.format.channels,
            .channel_layout = s.format.layout,
            .frames = if (s.count) |n| (n * s.format.frame_size) -| s.format.delay else null,
            .bits_per_sample = 0,
            .sample_format = null,
        };
        return .{ .state = s };
    }

    /// Walks the frame headers from the start: frame count and seek points. Leaves the reader
    /// at `resume_at`.
    fn scan(s: *State, sk: Seeker, resume_at: u64) Error!void {
        const size = try sk.size(sk.context);
        try sk.seekTo(sk.context, 0);
        var points: std.ArrayList(u64) = .empty;
        defer points.deinit(s.gpa);
        var offset: u64 = 0;
        var n: u64 = 0;
        while (size - offset >= 7) : (n += 1) {
            const head = s.reader.peek(7) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => return error.ReadFailed,
            };
            // Junk or a format change: the count ends there (read reports it when it gets there).
            const h = Header.parse(head[0..7]) orelse break;
            if (h.fixed != s.first.fixed or h.len > size - offset) break;
            if (n % point_step == 0) try points.append(s.gpa, offset);
            skip(s.reader, h.len) catch |err| return headerError(err);
            offset += h.len;
        }
        s.count = n;
        s.points = try points.toOwnedSlice(s.gpa);
        try sk.seekTo(sk.context, resume_at);
    }

    pub fn deinit(d: *Decoder) void {
        d.state.deinit();
        d.state.gpa.destroy(d.state);
    }

    pub fn info(d: *const Decoder) *const root.Info {
        return &d.state.info;
    }

    pub fn ended(d: *const Decoder) bool {
        const s = d.state;
        return s.eos and s.pcm_used == s.pcm_len;
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const s = d.state;
        const channels: usize = s.format.channels;
        const want = out.len / channels;
        var n: usize = 0;
        while (n < want) {
            if (s.pcm_used < s.pcm_len) {
                const k = @min(want - n, s.pcm_len - s.pcm_used);
                const src = s.pcm[s.pcm_used * channels ..][0 .. k * channels];
                for (out[n * channels ..][0 .. k * channels], src) |*o, x| o.* = sample.convert(T, x);
                s.pcm_used += k;
                n += k;
                continue;
            }
            if (s.err) |e| {
                if (n > 0) break;
                return e;
            }
            if (s.eos) break;
            decodeNext(s) catch |err| {
                s.err = err;
            };
        }
        return n;
    }

    fn decodeNext(s: *State) Error!void {
        if (s.count) |c| if (s.next >= c) {
            s.eos = true;
            return;
        };
        const frame = try s.readFrame() orelse {
            s.eos = true;
            return;
        };
        s.next += 1;
        const f = try s.codec.decode(s.gpa, frame, s.pcm);
        if (!f.eql(s.format)) return error.UnsupportedFormat;
        const drop = @min(s.skip, f.frame_size);
        s.skip -= drop;
        s.pcm_used = @intCast(drop);
        s.pcm_len = f.frame_size;
    }

    /// Sample exact position; the frames right after it converge to a linear decode (see Format.preroll).
    pub fn seek(d: *Decoder, frame: u64) Error!void {
        const s = d.state;
        const sk = s.seeker orelse return error.NotSeekable;
        const fs = s.format.frame_size;
        if (frame > s.info.frames.?) return error.SeekOutOfRange;
        const pos = frame + s.format.delay; // in fdk's output
        const target = pos / fs;
        const start = target -| s.format.preroll();
        const point = start / point_step;
        if (point >= s.points.len) {
            // frame == the end of an empty stream
            s.eos = true;
            s.pcm_used = s.pcm_len;
            return;
        }
        s.err = null;
        s.eos = false;
        s.pcm_used = 0;
        s.pcm_len = 0;
        try sk.seekTo(sk.context, s.points[@intCast(point)]);
        var i = point * point_step;
        while (i < start) : (i += 1) {
            const head = s.reader.peek(7) catch |err| return headerError(err);
            const h = Header.parse(head[0..7]) orelse return error.InvalidFile;
            skip(s.reader, h.len) catch |err| return headerError(err);
        }
        s.next = start;
        s.skip = pos - start * fs;
        s.codec.reset();
    }

    fn headerError(err: std.Io.Reader.Error) Error {
        return switch (err) {
            error.EndOfStream => error.InvalidFile,
            error.ReadFailed => error.ReadFailed,
        };
    }
};

pub const Encoder = struct {
    state: *State,

    const State = struct {
        writer: *std.Io.Writer,
        enc: Enc,
        err: ?Error = null,

        pub fn packet(s: *State, bytes: []const u8) Error!void {
            try s.writer.writeAll(bytes);
        }
    };

    /// No seeker needed, no tags (ADTS has no place for them: UnsupportedFormat).
    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: root.Encoder.Options) Error!Encoder {
        if (options.tags.len > 0) return error.UnsupportedFormat;
        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{ .writer = writer, .enc = try Enc.open(gpa, options, true) };
        return .{ .state = s };
    }

    pub fn deinit(e: *Encoder) void {
        const gpa = e.state.enc.gpa;
        e.state.enc.deinit();
        gpa.destroy(e.state);
    }

    pub fn write(e: *Encoder, comptime T: type, samples: []const T) Error!void {
        const s = e.state;
        std.debug.assert(samples.len % s.enc.channels == 0);
        if (s.err) |err| return err;
        s.enc.write(T, samples, s) catch |err| {
            s.err = err;
            return err;
        };
    }

    /// Every finished frame is already written; this pushes the writer.
    pub fn flush(e: *Encoder) Error!void {
        try e.state.writer.flush();
    }

    pub fn finish(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        try s.enc.finish(s);
        try s.writer.flush();
    }
};
