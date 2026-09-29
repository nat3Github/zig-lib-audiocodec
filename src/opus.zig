//! Ogg Opus: decode through libopusfile (reader callbacks), encode through libopusenc.
//!
//! Rate: Opus always decodes at 48 kHz, so `sample_rate` is 48000; OpusHead's input rate is only
//! informational and goes to `Info.original_sample_rate`. No resampling on either side: the
//! encoder takes 48 kHz input only (error.UnsupportedFormat otherwise).
//!
//! Gain: libopusfile applies the OpusHead output gain (its default, OP_HEADER_GAIN); R128 tags
//! are passed through as text tags, not applied.
//!
//! Chained streams, damage, seek: as in vorbis.zig. Links play back to back while they keep the
//! first link's channel count (the rate is always 48 kHz); at a change `read` returns the frames
//! before it, then error.UnsupportedFormat. A lost page (OP_HOLE) -> error.InvalidFile until a
//! successful `seek`. Pre-skip and end trimming come from libopusfile (granule positions).
//!
//! Channels: mapping family 0 (1-2 ch) and 1 (1..8 ch, Vorbis order) -> WAVE order,
//! `channel_layout = ChannelLayout.default(channels)`. Family 255 (and 2/3, ambisonics) are
//! rejected by libopusfile: error.UnsupportedFormat / error.InvalidFile.
//!
//! Every libopusfile / libopusenc call runs inside c_allocator.set(gpa) / restore. The callback
//! state lives on the heap (backends are moved by value).

const std = @import("std");
const root = @import("root.zig");
const sample = @import("sample.zig");
const vorbis = @import("vorbis.zig");
const c_allocator = @import("c_allocator.zig");
const c = @import("zig-c-headers/opusfile.zig");
const ope = @import("zig-c-headers/opusenc.zig");
const opus = @import("zig-c-headers/opus.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Seeker = root.Seeker;

pub const sample_rate = 48000;

/// 120 ms at 48 kHz, the longest Opus packet.
const max_packet_frames = 5760;

pub const Decoder = struct {
    state: *State,

    const State = struct {
        gpa: Allocator,
        reader: *std.Io.Reader,
        seeker: ?Seeker,
        of: *c.OggOpusFile = undefined,
        info: root.Info,
        /// Reader offset, for the tell callback.
        pos: u64 = 0,
        /// Link of the last decoded samples.
        link: c_int = 0,
        /// Interleaved, Vorbis channel order.
        buf: []f32 = &.{},
        buf_len: usize = 0,
        buf_pos: usize = 0,
        /// Sticky until a successful seek.
        err: ?Error = null,
        eos: bool = false,

        /// Decodes the next packet's samples into `buf`.
        fn step(s: *State) void {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            var link: c_int = 0;
            const n = c.op_read_float(s.of, s.buf.ptr, @intCast(s.buf.len), &link);
            if (s.err != null) return; // a reader / seeker error inside the call
            if (c_allocator.failed) {
                s.err = error.OutOfMemory;
                return;
            }
            if (n == 0) {
                s.eos = true;
                return;
            }
            if (n < 0) {
                s.err = opError(n);
                return;
            }
            if (link != s.link) {
                const head = c.op_head(s.of, link) orelse {
                    s.err = error.InvalidFile;
                    return;
                };
                if (head.channel_count != s.info.channels) {
                    s.err = error.UnsupportedFormat;
                    return;
                }
                s.link = link;
            }
            s.buf_len = @intCast(n);
            s.buf_pos = 0;
        }
    };

    /// `head`: the bytes ogg.head consumed; libopusfile takes them as its initial data.
    pub fn open(gpa: Allocator, arena: Allocator, reader: *std.Io.Reader, seeker: ?Seeker, tag_mode: root.TagMode, head: []const u8) Error!Decoder {
        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .reader = reader,
            .seeker = seeker,
            .pos = head.len,
            .info = .{
                .container = .ogg,
                .codec = .opus,
                .sample_rate = sample_rate,
                .channels = 0,
                .channel_layout = null,
                .frames = null,
                .bits_per_sample = 0,
                .sample_format = null,
            },
        };

        {
            const prev = c_allocator.set(gpa);
            defer c_allocator.restore(prev);
            const callbacks: c.OpusFileCallbacks = .{
                .read = readCallback,
                // No seek callback: libopusfile treats the stream as unseekable.
                .seek = if (seeker != null) seekCallback else null,
                .tell = tellCallback,
                .close = null,
            };
            var ret: c_int = 0;
            s.of = c.op_open_callbacks(s, &callbacks, head.ptr, head.len, &ret) orelse
                return s.err orelse opError(ret);
        }
        errdefer {
            const prev = c_allocator.set(gpa);
            c.op_free(s.of);
            c_allocator.restore(prev);
        }
        if (c_allocator.failed) return error.OutOfMemory;

        const h = c.op_head(s.of, 0) orelse return error.InvalidFile;
        s.info.channels = std.math.cast(u16, h.channel_count) orelse return error.InvalidFile;
        s.info.channel_layout = root.ChannelLayout.default(s.info.channels);
        if (h.input_sample_rate != 0) s.info.original_sample_rate = h.input_sample_rate;
        if (seeker != null) {
            // Links up to the first channel count change (see the chaining note above).
            var total: u64 = 0;
            for (0..@intCast(c.op_link_count(s.of))) |i| {
                const link: c_int = @intCast(i);
                const lh = c.op_head(s.of, link) orelse break;
                if (lh.channel_count != h.channel_count) break;
                total += std.math.cast(u64, c.op_pcm_total(s.of, link)) orelse return error.InvalidFile;
            }
            s.info.frames = total;
        }
        if (tag_mode != .none) if (c.op_tags(s.of, 0)) |tags| {
            s.info.tags = try vorbis.readTags(arena, tags, tag_mode == .all);
        };
        s.buf = try gpa.alloc(f32, max_packet_frames * @as(usize, s.info.channels));
        return .{ .state = s };
    }

    pub fn deinit(d: *Decoder) void {
        const s = d.state;
        const prev = c_allocator.set(s.gpa);
        c.op_free(s.of);
        c_allocator.restore(prev);
        s.gpa.free(s.buf);
        s.gpa.destroy(s);
    }

    pub fn info(d: *const Decoder) *const root.Info {
        return &d.state.info;
    }

    pub fn ended(d: *const Decoder) bool {
        const s = d.state;
        return s.eos and s.buf_pos == s.buf_len;
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const s = d.state;
        const channels: usize = s.info.channels;
        const want = out.len / channels;
        var n: usize = 0;
        while (n < want) {
            const k = @min(s.buf_len - s.buf_pos, want - n);
            if (k > 0) {
                for (0..k) |f| {
                    const frame = s.buf[(s.buf_pos + f) * channels ..][0..channels];
                    const o = out[(n + f) * channels ..][0..channels];
                    for (o, 0..) |*x, ch| x.* = sample.convert(T, frame[vorbis.vorbisChannel(channels, ch)]);
                }
                n += k;
                s.buf_pos += k;
                continue;
            }
            if (s.err) |e| {
                if (n > 0) break;
                return e;
            }
            if (s.eos) break;
            s.step();
        }
        return n;
    }

    pub fn seek(d: *Decoder, frame: u64) Error!void {
        const s = d.state;
        if (s.seeker == null) return error.NotSeekable;
        const total = s.info.frames.?;
        if (frame > total) return error.SeekOutOfRange;
        s.buf_len = 0;
        s.buf_pos = 0;
        s.err = null;
        s.eos = frame == total;
        if (s.eos) return;
        const prev = c_allocator.set(s.gpa);
        defer c_allocator.restore(prev);
        const ret = c.op_pcm_seek(s.of, @intCast(frame));
        if (ret != 0 or c_allocator.failed) {
            const err = s.err orelse if (c_allocator.failed) error.OutOfMemory else opError(ret);
            s.err = null;
            return err;
        }
        s.link = c.op_current_link(s.of);
    }

    /// A failed libopusfile call (no reader / seeker error behind it).
    fn opError(ret: c_int) Error {
        if (c_allocator.failed) return error.OutOfMemory;
        return switch (ret) {
            c.OP_EFAULT => error.OutOfMemory, // the only other cause is an internal bug
            c.OP_EIMPL => error.UnsupportedFormat, // mapping family 255
            else => error.InvalidFile,
        };
    }

    fn client(ptr: ?*anyopaque) *State {
        return @ptrCast(@alignCast(ptr.?));
    }

    fn readCallback(stream: ?*anyopaque, ptr: [*]u8, nbytes: c_int) callconv(.c) c_int {
        const s = client(stream);
        if (s.err != null or nbytes <= 0) return 0;
        const n = s.reader.readSliceShort(ptr[0..@intCast(nbytes)]) catch {
            s.err = error.ReadFailed;
            return -1;
        };
        s.pos += n;
        return @intCast(n);
    }

    fn seekCallback(stream: ?*anyopaque, offset: i64, whence: c_int) callconv(.c) c_int {
        const s = client(stream);
        const seeker = s.seeker.?;
        const base: i64 = switch (whence) {
            0 => 0, // SEEK_SET
            1 => @intCast(s.pos), // SEEK_CUR
            2 => @intCast(seeker.size(seeker.context) catch {
                s.err = error.SeekFailed;
                return -1;
            }),
            else => return -1,
        };
        const target = std.math.cast(u64, base +| offset) orelse return -1;
        seeker.seekTo(seeker.context, target) catch {
            s.err = error.SeekFailed;
            return -1;
        };
        s.pos = target;
        return 0;
    }

    fn tellCallback(stream: ?*anyopaque) callconv(.c) i64 {
        return std.math.cast(i64, client(stream).pos) orelse -1;
    }
};

pub const Encoder = struct {
    state: *State,

    /// Frames converted per ope_encoder_write_float call.
    const chunk_frames = 1024;

    const State = struct {
        gpa: Allocator,
        writer: *std.Io.Writer,
        channels: u16,
        enc: *ope.OggOpusEnc = undefined,
        /// Interleaved, Vorbis channel order.
        buf: []f32 = &.{},
        /// Sticky: after a failure the stream state is unknown. Also set by the write callback.
        err: ?Error = null,

        /// Maps a libopusenc return code (after a call) to the sticky error.
        fn check(s: *State, ret: c_int) Error!void {
            if (s.err) |err| return err;
            if (c_allocator.failed) s.err = error.OutOfMemory;
            if (ret != ope.OPE_OK and s.err == null) s.err = opeError(ret);
            if (s.err) |err| return err;
        }
    };

    /// Per-channel VBR target: quality 0..1 -> 32..256 kbit/s linear, null -> 64 kbit/s (about
    /// opusenc's stereo default). Channels 1..8 with the default layout (mapping family 0 for 1-2,
    /// 1 for 3-8). 48 kHz input only: libopusenc would resample other rates itself, which the
    /// API rules out. Complexity 10. No seeker needed (granule positions carry the length).
    /// Float input is clipped to [-1, 1] (NaN -> 0), as in vorbis.zig.
    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: root.Encoder.Options) Error!Encoder {
        if (options.sample_rate != sample_rate) return error.UnsupportedFormat;
        if (options.channels > 8) return error.UnsupportedFormat;
        if (options.channel_layout) |l| if (!std.meta.eql(@as(?root.ChannelLayout, l), root.ChannelLayout.default(options.channels))) return error.UnsupportedFormat;
        const per_channel: f32 = if (options.quality) |q| blk: {
            if (!(q >= 0 and q <= 1)) return error.InvalidOptions;
            break :blk 32_000 + 224_000 * q;
        } else 64_000;
        const bitrate: c_int = @intFromFloat(@round(per_channel) * @as(f32, @floatFromInt(options.channels)));

        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{ .gpa = gpa, .writer = writer, .channels = options.channels };
        s.buf = try gpa.alloc(f32, chunk_frames * @as(usize, options.channels));
        errdefer gpa.free(s.buf);

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        const comments = ope.ope_comments_create() orelse return error.OutOfMemory;
        defer ope.ope_comments_destroy(comments);
        for (options.tags) |tag| {
            const entry = try vorbis.formatComment(gpa, tag);
            defer gpa.free(entry);
            if (ope.ope_comments_add_string(comments, entry.ptr) != ope.OPE_OK) return error.OutOfMemory;
        }
        const callbacks: ope.OpusEncCallbacks = .{ .write = writeCallback, .close = closeCallback };
        const family: c_int = if (options.channels <= 2) 0 else 1;
        var ret: c_int = 0;
        s.enc = ope.ope_encoder_create_callbacks(&callbacks, s, comments, sample_rate, options.channels, family, &ret) orelse
            return if (c_allocator.failed) error.OutOfMemory else opeError(ret);
        errdefer ope.ope_encoder_destroy(s.enc);
        const serial = options.ogg_serial orelse vorbis.Encoder.defaultSerial(options);
        try s.check(ope.ope_encoder_ctl(s.enc, ope.OPE_SET_SERIALNO_REQUEST, @as(i32, @bitCast(serial))));
        try s.check(ope.ope_encoder_ctl(s.enc, opus.OPUS_SET_BITRATE_REQUEST, @as(i32, bitrate)));
        try s.check(ope.ope_encoder_ctl(s.enc, opus.OPUS_SET_COMPLEXITY_REQUEST, @as(i32, 10)));
        return .{ .state = s };
    }

    fn opeError(ret: c_int) Error {
        return switch (ret) {
            ope.OPE_ALLOC_FAIL => error.OutOfMemory,
            ope.OPE_WRITE_FAIL => error.WriteFailed,
            ope.OPE_BAD_ARG => error.InvalidOptions,
            else => error.UnsupportedFormat, // OPE_UNIMPLEMENTED, internal errors
        };
    }

    pub fn deinit(e: *Encoder) void {
        const s = e.state;
        const prev = c_allocator.set(s.gpa);
        ope.ope_encoder_destroy(s.enc);
        c_allocator.restore(prev);
        s.gpa.free(s.buf);
        s.gpa.destroy(s);
    }

    pub fn write(e: *Encoder, comptime T: type, samples: []const T) Error!void {
        const s = e.state;
        const channels: usize = s.channels;
        std.debug.assert(samples.len % channels == 0);
        if (s.err) |err| return err;
        const prev = c_allocator.set(s.gpa);
        defer c_allocator.restore(prev);
        var frame: usize = 0;
        const frames = samples.len / channels;
        while (frame < frames) {
            const n = @min(chunk_frames, frames - frame);
            for (0..n) |f| {
                const in = samples[(frame + f) * channels ..][0..channels];
                const o = s.buf[f * channels ..][0..channels];
                for (in, 0..) |x, ch| o[vorbis.vorbisChannel(channels, ch)] = vorbis.Encoder.clip(sample.convert(f32, x));
            }
            try s.check(ope.ope_encoder_write_float(s.enc, s.buf.ptr, @intCast(n)));
            frame += n;
        }
    }

    /// Writes the headers and flushes the writer. ponytail: audio pages only leave on
    /// libopusenc's schedule (decision delay 2 s, muxing delay 1 s); lower
    /// OPE_SET_DECISION_DELAY / OPE_SET_MUXING_DELAY if a live reader needs less latency.
    pub fn flush(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            try s.check(ope.ope_encoder_flush_header(s.enc));
        }
        try s.writer.flush();
    }

    pub fn finish(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            // End of stream: the last page's granule position is the exact length.
            try s.check(ope.ope_encoder_drain(s.enc));
        }
        try s.writer.flush();
    }

    fn client(ptr: ?*anyopaque) *State {
        return @ptrCast(@alignCast(ptr.?));
    }

    fn writeCallback(user_data: ?*anyopaque, ptr: [*]const u8, len: i32) callconv(.c) c_int {
        const s = client(user_data);
        s.writer.writeAll(ptr[0..@intCast(len)]) catch {
            s.err = error.WriteFailed;
            return 1;
        };
        return 0;
    }

    fn closeCallback(_: ?*anyopaque) callconv(.c) c_int {
        return 0;
    }
};
