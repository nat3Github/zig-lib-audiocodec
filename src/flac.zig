//! FLAC, native (.flac) and in Ogg, through libFLAC's stream callbacks.
//!
//! Decode error policy: a damaged stream is an error, not silently patched audio. libFLAC reports
//! lost sync, bad frame headers, CRC mismatches, out-of-range residuals and missing frames through
//! its error callback, resyncs and would substitute silence. Once audio continues after such an
//! error, `read` returns the frames decoded before the damage, then error.InvalidFile on every
//! call until a successful `seek`. If the stream ends instead, the damage was a truncated tail
//! (libFLAC reports a cut-off last frame as lost sync): no error, `read` returns the whole frames
//! that exist, like the pcm backends. So damage inside the last frame drops that frame silently.
//! Trailing bytes after the last frame are ignored when STREAMINFO knows the length (libFLAC
//! stops at total_samples). In `open` (metadata) any error fails at once.
//!
//! MD5: not checked. The per-frame CRC-16 already catches damage, and libFLAC can only verify the
//! MD5 at the very end and disables it after any seek. ponytail: add a Decoder.Options flag
//! (API change) when someone needs whole-stream verification.
//!
//! Every libFLAC call runs inside c_allocator.set(gpa) / restore. The C side keeps a pointer to
//! the callback state, so it lives on the heap (backends are moved by value).

const std = @import("std");
const root = @import("root.zig");
const sample = @import("sample.zig");
const c_allocator = @import("c_allocator.zig");
const vorbis = @import("vorbis.zig");
const c = @import("zig-c-headers/flac.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Seeker = root.Seeker;

pub const Decoder = struct {
    state: *State,

    const State = struct {
        gpa: Allocator,
        arena: Allocator,
        reader: *std.Io.Reader,
        seeker: ?Seeker,
        /// Ogg: the page head ogg.zig consumed, served before the reader (dropped on a seek).
        prefix: []const u8,
        flac: *c.FLAC__StreamDecoder = undefined,
        info: root.Info,
        tags: std.ArrayList(root.Tag) = .empty,
        pictures: std.ArrayList(root.Picture) = .empty,
        has_streaminfo: bool = false,
        /// Reader offset, for the tell callback.
        pos: u64 = 0,
        /// Decoded samples, interleaved, left-aligned to 32 bits; `block_pos` is the next one.
        block: std.ArrayList(i32) = .empty,
        block_pos: usize = 0,
        /// Sticky until a successful seek (see the policy above).
        err: ?Error = null,
        /// libFLAC reported damage; becomes `err` if audio follows, is dropped at end of stream.
        damaged: bool = false,
        opening: bool = true,
        eos: bool = false,

        fn clearBlock(s: *State) void {
            s.block.clearRetainingCapacity();
            s.block_pos = 0;
        }

        fn stateError(s: *State) Error {
            if (s.err) |e| return e;
            return switch (c.FLAC__stream_decoder_get_state(s.flac)) {
                c.FLAC__STREAM_DECODER_MEMORY_ALLOCATION_ERROR => error.OutOfMemory,
                else => error.InvalidFile,
            };
        }

        /// Decodes the next frame (or metadata / sync search) into `block`.
        fn step(s: *State) void {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            const ok = c.FLAC__stream_decoder_process_single(s.flac) != 0;
            // A truncated frame also ends here (process_single returns false at end of input);
            // damage right before the end is that truncation, not an error.
            if (c.FLAC__stream_decoder_get_state(s.flac) == c.FLAC__STREAM_DECODER_END_OF_STREAM) {
                s.eos = true;
                s.damaged = false;
            } else if (!ok and s.err == null) {
                s.err = s.stateError();
            }
        }
    };

    /// `ogg_head`: the stream is Ogg FLAC and ogg.head consumed these bytes (first logical
    /// stream, first link only). null: native FLAC, checked by libFLAC (which also skips an
    /// ID3v2 prefix).
    /// ponytail: chained Ogg FLAC (set_decode_chained_stream) not decoded past the first link.
    pub fn open(gpa: Allocator, arena: Allocator, reader: *std.Io.Reader, seeker: ?Seeker, tag_mode: root.TagMode, ogg_head: ?[]const u8) Error!Decoder {
        const ogg = ogg_head != null;
        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .arena = arena,
            .reader = reader,
            .seeker = seeker,
            .prefix = try arena.dupe(u8, ogg_head orelse ""),
            .info = .{
                .container = if (ogg) .ogg else .flac,
                .codec = .flac,
                .sample_rate = 0,
                .channels = 0,
                .channel_layout = null,
                .frames = null,
                .bits_per_sample = 0,
                .sample_format = null,
            },
        };
        errdefer s.block.deinit(gpa);

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        s.flac = c.FLAC__stream_decoder_new() orelse return error.OutOfMemory;
        errdefer c.FLAC__stream_decoder_delete(s.flac);
        if (tag_mode != .none) _ = c.FLAC__stream_decoder_set_metadata_respond(s.flac, c.FLAC__METADATA_TYPE_VORBIS_COMMENT);
        if (tag_mode == .all) _ = c.FLAC__stream_decoder_set_metadata_respond(s.flac, c.FLAC__METADATA_TYPE_PICTURE);

        const init = if (ogg) &c.FLAC__stream_decoder_init_ogg_stream else &c.FLAC__stream_decoder_init_stream;
        switch (init(s.flac, readCallback, seekCallback, tellCallback, lengthCallback, eofCallback, writeCallback, metadataCallback, errorCallback, s)) {
            c.FLAC__STREAM_DECODER_INIT_STATUS_OK => {},
            // ERROR_OPENING_FILE from a stream init: libogg could not allocate its state.
            c.FLAC__STREAM_DECODER_INIT_STATUS_MEMORY_ALLOCATION_ERROR, c.FLAC__STREAM_DECODER_INIT_STATUS_ERROR_OPENING_FILE => return error.OutOfMemory,
            else => return error.InvalidFile,
        }
        const ok = c.FLAC__stream_decoder_process_until_end_of_metadata(s.flac) != 0;
        s.opening = false;
        if (s.err) |e| return e;
        if (!s.has_streaminfo) {
            if (c.FLAC__stream_decoder_get_state(s.flac) == c.FLAC__STREAM_DECODER_MEMORY_ALLOCATION_ERROR) return error.OutOfMemory;
            // No fLaC marker (libFLAC would go on looking for raw frames) or a damaged Ogg FLAC
            // header.
            return error.InvalidFile;
        }
        if (!ok or s.damaged) return s.stateError();
        s.info.tags = .{ .items = s.tags.items, .pictures = s.pictures.items };
        // total_samples 0 means "unknown": decode ahead one frame, an empty stream then says so.
        if (s.info.frames == null) {
            s.step();
            if (s.eos and s.block.items.len == 0 and s.err == null) s.info.frames = 0;
        }
        return .{ .state = s };
    }

    pub fn deinit(d: *Decoder) void {
        const s = d.state;
        const prev = c_allocator.set(s.gpa);
        c.FLAC__stream_decoder_delete(s.flac);
        c_allocator.restore(prev);
        s.block.deinit(s.gpa);
        s.gpa.destroy(s);
    }

    pub fn info(d: *const Decoder) *const root.Info {
        return &d.state.info;
    }

    pub fn ended(d: *const Decoder) bool {
        const s = d.state;
        return s.eos and s.block_pos == s.block.items.len;
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const s = d.state;
        const channels = s.info.channels;
        const want = out.len / channels * channels;
        var n: usize = 0;
        while (n < want) {
            const avail = s.block.items[s.block_pos..];
            if (avail.len > 0) {
                const k = @min(avail.len, want - n);
                for (out[n..][0..k], avail[0..k]) |*o, x| o.* = sample.convert(T, x);
                n += k;
                s.block_pos += k;
                continue;
            }
            if (s.err) |e| {
                if (n > 0) break;
                return e;
            }
            if (s.eos) break;
            s.step();
        }
        return n / channels;
    }

    pub fn seek(d: *Decoder, frame: u64) Error!void {
        const s = d.state;
        if (s.seeker == null) return error.NotSeekable;
        s.clearBlock();
        s.err = null;
        s.damaged = false;
        if (s.info.frames) |total| {
            if (frame > total) return error.SeekOutOfRange;
            // libFLAC refuses to seek to the end itself.
            if (frame == total) {
                s.eos = true;
                return;
            }
        }
        s.eos = false;
        const prev = c_allocator.set(s.gpa);
        defer c_allocator.restore(prev);
        switch (c.FLAC__stream_decoder_get_state(s.flac)) {
            // An aborted read (our error) or failed seek leaves the decoder unusable until a flush.
            c.FLAC__STREAM_DECODER_ABORTED, c.FLAC__STREAM_DECODER_SEEK_ERROR => _ = c.FLAC__stream_decoder_flush(s.flac),
            else => {},
        }
        // The target frame arrives through the write callback, already trimmed to `frame`.
        if (c.FLAC__stream_decoder_seek_absolute(s.flac, frame) != 0) return;
        const err = s.err orelse if (s.info.frames == null) error.SeekOutOfRange else error.InvalidFile;
        s.err = null;
        s.clearBlock();
        _ = c.FLAC__stream_decoder_flush(s.flac);
        return err;
    }

    fn client(ptr: ?*anyopaque) *State {
        return @ptrCast(@alignCast(ptr.?));
    }

    fn readCallback(_: *const c.FLAC__StreamDecoder, buffer: [*]u8, bytes: *usize, data: ?*anyopaque) callconv(.c) c.FLAC__StreamDecoderReadStatus {
        const s = client(data);
        const len = bytes.*;
        bytes.* = 0;
        // Stop libFLAC from scanning on through a stream we already rejected.
        if (s.err != null or (s.damaged and s.opening)) return c.FLAC__STREAM_DECODER_READ_STATUS_ABORT;
        if (s.prefix.len > 0) {
            const n = @min(len, s.prefix.len);
            @memcpy(buffer[0..n], s.prefix[0..n]);
            s.prefix = s.prefix[n..];
            s.pos += n;
            bytes.* = n;
            return c.FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
        }
        const n = s.reader.readSliceShort(buffer[0..len]) catch {
            s.err = error.ReadFailed;
            return c.FLAC__STREAM_DECODER_READ_STATUS_ABORT;
        };
        s.pos += n;
        bytes.* = n;
        return if (n == 0) c.FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM else c.FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
    }

    fn seekCallback(_: *const c.FLAC__StreamDecoder, offset: u64, data: ?*anyopaque) callconv(.c) c.FLAC__StreamDecoderSeekStatus {
        const s = client(data);
        const seeker = s.seeker orelse return c.FLAC__STREAM_DECODER_SEEK_STATUS_UNSUPPORTED;
        seeker.seekTo(seeker.context, offset) catch {
            s.err = error.SeekFailed;
            return c.FLAC__STREAM_DECODER_SEEK_STATUS_ERROR;
        };
        s.prefix = "";
        s.pos = offset;
        return c.FLAC__STREAM_DECODER_SEEK_STATUS_OK;
    }

    fn tellCallback(_: *const c.FLAC__StreamDecoder, offset: *u64, data: ?*anyopaque) callconv(.c) c.FLAC__StreamDecoderTellStatus {
        const s = client(data);
        if (s.seeker == null) return c.FLAC__STREAM_DECODER_TELL_STATUS_UNSUPPORTED;
        offset.* = s.pos;
        return c.FLAC__STREAM_DECODER_TELL_STATUS_OK;
    }

    fn lengthCallback(_: *const c.FLAC__StreamDecoder, length: *u64, data: ?*anyopaque) callconv(.c) c.FLAC__StreamDecoderLengthStatus {
        const s = client(data);
        const seeker = s.seeker orelse return c.FLAC__STREAM_DECODER_LENGTH_STATUS_UNSUPPORTED;
        length.* = seeker.size(seeker.context) catch return c.FLAC__STREAM_DECODER_LENGTH_STATUS_ERROR;
        return c.FLAC__STREAM_DECODER_LENGTH_STATUS_OK;
    }

    fn eofCallback(_: *const c.FLAC__StreamDecoder, data: ?*anyopaque) callconv(.c) c.FLAC__bool {
        const s = client(data);
        if (s.prefix.len > 0) return 0;
        _ = s.reader.peekByte() catch |err| {
            if (err == error.ReadFailed) s.err = error.ReadFailed;
            return 1;
        };
        return 0;
    }

    fn writeCallback(_: *const c.FLAC__StreamDecoder, frame: *const c.FLAC__Frame, buffer: [*]const [*]const i32, data: ?*anyopaque) callconv(.c) c.FLAC__StreamDecoderWriteStatus {
        const s = client(data);
        if (s.err != null) return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        // Audio after damage (possibly libFLAC's substitute silence): now it is an error.
        if (s.damaged) {
            s.err = error.InvalidFile;
            return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
        const h = frame.header;
        if (h.channels != s.info.channels or h.bits_per_sample == 0 or h.bits_per_sample > 32) {
            s.err = error.InvalidFile;
            return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
        if (s.block_pos == s.block.items.len) s.clearBlock();
        const channels = s.info.channels;
        const dest = s.block.addManyAsSlice(s.gpa, h.blocksize * channels) catch {
            s.err = error.OutOfMemory;
            return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        };
        const shift: u5 = @intCast(32 - h.bits_per_sample);
        for (0..channels) |ch| {
            for (buffer[ch][0..h.blocksize], 0..) |x, i|
                dest[i * channels + ch] = @bitCast(@as(u32, @bitCast(x)) << shift);
        }
        return c.FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
    }

    fn metadataCallback(_: *const c.FLAC__StreamDecoder, metadata: *const c.FLAC__StreamMetadata, data: ?*anyopaque) callconv(.c) void {
        const s = client(data);
        addMetadata(s, metadata) catch |err| {
            s.err = err;
        };
    }

    fn addMetadata(s: *State, metadata: *const c.FLAC__StreamMetadata) Error!void {
        switch (metadata.type) {
            c.FLAC__METADATA_TYPE_STREAMINFO => {
                const si = metadata.data.stream_info;
                if (si.sample_rate == 0 or si.channels == 0 or si.channels > 8 or si.bits_per_sample < 4 or si.bits_per_sample > 32) return error.InvalidFile;
                const channels: u16 = @intCast(si.channels);
                s.info.sample_rate = si.sample_rate;
                s.info.channels = channels;
                // The FLAC spec fixes the order for 1..8 channels, and it is WAVE order.
                s.info.channel_layout = root.ChannelLayout.default(channels);
                s.info.bits_per_sample = @intCast(si.bits_per_sample);
                s.info.frames = if (si.total_samples == 0) null else si.total_samples;
                s.has_streaminfo = true;
            },
            c.FLAC__METADATA_TYPE_VORBIS_COMMENT => {
                const vc = metadata.data.vorbis_comment;
                const comments = vc.comments orelse return;
                for (comments[0..vc.num_comments]) |entry| {
                    const bytes = (entry.entry orelse continue)[0..entry.length];
                    if (try vorbis.parseComment(s.arena, bytes)) |tag| try s.tags.append(s.arena, tag);
                }
            },
            c.FLAC__METADATA_TYPE_PICTURE => {
                const p = metadata.data.picture;
                try s.pictures.append(s.arena, .{
                    .mime = try s.arena.dupe(u8, std.mem.span(p.mime_type orelse return)),
                    .kind = @truncate(p.type),
                    .description = try s.arena.dupe(u8, std.mem.span(p.description orelse return)),
                    .data = try s.arena.dupe(u8, (p.data orelse return)[0..p.data_length]),
                });
            },
            else => {},
        }
    }

    fn errorCallback(decoder: *const c.FLAC__StreamDecoder, _: c.FLAC__StreamDecoderErrorStatus, data: ?*anyopaque) callconv(.c) void {
        const s = client(data);
        // A failed allocation inside a metadata block also shows up as BAD_METADATA.
        if (c.FLAC__stream_decoder_get_state(decoder) == c.FLAC__STREAM_DECODER_MEMORY_ALLOCATION_ERROR) {
            if (s.err == null) s.err = error.OutOfMemory;
        } else s.damaged = true;
    }
};

pub const Encoder = struct {
    state: *State,

    /// Bytes of PADDING after the tags, so they can be edited in place later.
    const padding = 4096;
    /// Frames converted per process_interleaved call.
    const chunk_frames = 1024;

    const State = struct {
        gpa: Allocator,
        writer: *std.Io.Writer,
        seeker: Seeker,
        flac: *c.FLAC__StreamEncoder = undefined,
        metadata: [2]*c.FLAC__StreamMetadata = undefined,
        metadata_len: u32 = 0,
        format: root.SampleFormat,
        channels: u16,
        scratch: []i32 = &.{},
        /// Writer offset (tell callback) and the furthest byte written.
        pos: u64 = 0,
        end: u64 = 0,
        /// Copy of the first bytes written: libFLAC reads the first Ogg page back to patch
        /// STREAMINFO in finish, and our sink is write-only.
        head: [4096]u8 = undefined,
        err: ?Error = null,
        /// deinit without finish: libFLAC's delete would still flush a partial block; drop it.
        closing: bool = false,

        fn stateError(s: *State) Error {
            if (s.err) |e| return e;
            return switch (c.FLAC__stream_encoder_get_state(s.flac)) {
                // libogg fails only on allocation (our own write failures set `err`).
                c.FLAC__STREAM_ENCODER_MEMORY_ALLOCATION_ERROR, c.FLAC__STREAM_ENCODER_OGG_ERROR => error.OutOfMemory,
                else => error.WriteFailed,
            };
        }
    };

    /// quality 0..1 -> compression level round(q * 8) (flac -0 .. -8); null -> 5 (flac's default).
    /// sample_format i8/i16/i24/i32 -> 8/16/24/32 bits per sample. Needs a seeker: STREAMINFO
    /// (length, MD5) is rewritten in finish.
    /// ponytail: no SEEKTABLE (the frame count is not known at open); seeking uses libFLAC's
    /// binary search. Add one via set_total_samples_estimate if Options ever carries a length.
    /// ponytail: single-threaded (the module builds libFLAC without threads, see c_allocator.zig).
    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: root.Encoder.Options) Error!Encoder {
        const seeker = options.seeker orelse return error.NotSeekable;
        const bits: u32 = switch (options.sample_format) {
            .i8 => 8,
            .i16 => 16,
            .i24 => 24,
            .i32 => 32,
            .f32, .f64 => return error.UnsupportedFormat,
        };
        if (options.channels > 8 or options.sample_rate > c.FLAC__MAX_SAMPLE_RATE) return error.UnsupportedFormat;
        // FLAC has no channel mask of its own. ponytail: other layouts would need the
        // WAVEFORMATEXTENSIBLE_CHANNEL_MASK comment.
        if (options.channel_layout) |l| if (!std.meta.eql(@as(?root.ChannelLayout, l), root.ChannelLayout.default(options.channels))) return error.UnsupportedFormat;
        const level: u32 = if (options.quality) |q| blk: {
            if (!(q >= 0 and q <= 1)) return error.InvalidOptions;
            break :blk @intFromFloat(@round(q * 8));
        } else 5;

        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{ .gpa = gpa, .writer = writer, .seeker = seeker, .format = options.sample_format, .channels = options.channels };
        s.scratch = try gpa.alloc(i32, chunk_frames * @as(usize, options.channels));
        errdefer gpa.free(s.scratch);

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        s.flac = c.FLAC__stream_encoder_new() orelse return error.OutOfMemory;
        errdefer c.FLAC__stream_encoder_delete(s.flac);
        errdefer for (s.metadata[0..s.metadata_len]) |m| c.FLAC__metadata_object_delete(m);
        try addTags(s, options.tags);
        const pad = c.FLAC__metadata_object_new(c.FLAC__METADATA_TYPE_PADDING) orelse return error.OutOfMemory;
        pad.length = padding;
        s.metadata[s.metadata_len] = pad;
        s.metadata_len += 1;

        const e = s.flac;
        _ = c.FLAC__stream_encoder_set_channels(e, options.channels);
        _ = c.FLAC__stream_encoder_set_bits_per_sample(e, bits);
        _ = c.FLAC__stream_encoder_set_sample_rate(e, options.sample_rate);
        _ = c.FLAC__stream_encoder_set_compression_level(e, level);
        // 32-bit samples and rates above 655350 Hz are outside the streamable subset; the level
        // presets keep everything else inside it anyway.
        _ = c.FLAC__stream_encoder_set_streamable_subset(e, 0);
        if (c.FLAC__stream_encoder_set_metadata(e, &s.metadata, s.metadata_len) == 0) return error.OutOfMemory;

        const status = if (options.container == .ogg)
            c.FLAC__stream_encoder_init_ogg_stream(e, readCallback, writeCallback, seekCallback, tellCallback, null, s)
        else
            c.FLAC__stream_encoder_init_stream(e, writeCallback, seekCallback, tellCallback, null, s);
        switch (status) {
            c.FLAC__STREAM_ENCODER_INIT_STATUS_OK => {},
            c.FLAC__STREAM_ENCODER_INIT_STATUS_ENCODER_ERROR => return s.stateError(),
            else => return error.InvalidOptions,
        }
        return .{ .state = s };
    }

    fn addTags(s: *State, tags: []const root.Tag) Error!void {
        if (tags.len == 0) return;
        const vc = c.FLAC__metadata_object_new(c.FLAC__METADATA_TYPE_VORBIS_COMMENT) orelse return error.OutOfMemory;
        s.metadata[s.metadata_len] = vc;
        s.metadata_len += 1;
        for (tags) |tag| {
            const entry = try vorbis.formatComment(s.gpa, tag);
            defer s.gpa.free(entry);
            const len = std.math.cast(u32, entry.len) orelse return error.InvalidOptions;
            if (c.FLAC__metadata_object_vorbiscomment_append_comment(vc, .{ .length = len, .entry = entry.ptr }, 1) == 0) return error.OutOfMemory;
        }
    }

    pub fn deinit(e: *Encoder) void {
        const s = e.state;
        s.closing = true;
        const prev = c_allocator.set(s.gpa);
        c.FLAC__stream_encoder_delete(s.flac);
        for (s.metadata[0..s.metadata_len]) |m| c.FLAC__metadata_object_delete(m);
        c_allocator.restore(prev);
        s.gpa.free(s.scratch);
        s.gpa.destroy(s);
    }

    pub fn write(e: *Encoder, comptime T: type, samples: []const T) Error!void {
        const s = e.state;
        std.debug.assert(samples.len % s.channels == 0);
        if (s.err) |err| return err;
        const prev = c_allocator.set(s.gpa);
        defer c_allocator.restore(prev);
        var i: usize = 0;
        while (i < samples.len) {
            const n = @min(s.scratch.len, samples.len - i);
            switch (s.format) {
                inline .i8, .i16, .i24, .i32 => |f| {
                    const S = switch (f) {
                        .i8 => i8,
                        .i16 => i16,
                        .i24 => i24,
                        else => i32,
                    };
                    for (s.scratch[0..n], samples[i..][0..n]) |*o, x| o.* = sample.convert(S, x);
                },
                else => unreachable,
            }
            if (c.FLAC__stream_encoder_process_interleaved(s.flac, s.scratch.ptr, @intCast(n / s.channels)) == 0) return s.stateError();
            i += n;
        }
    }

    /// libFLAC holds back up to one block (4096 frames at the default levels) until it is full,
    /// and in Ogg also the current page until libogg decides to emit it.
    pub fn flush(e: *Encoder) Error!void {
        try e.state.writer.flush();
    }

    pub fn finish(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            // Encodes the last partial block, then seeks back and rewrites STREAMINFO.
            if (c.FLAC__stream_encoder_finish(s.flac) == 0) return s.stateError();
        }
        try s.writer.flush();
        try s.seeker.seekTo(s.seeker.context, s.end);
    }

    fn client(ptr: ?*anyopaque) *State {
        return @ptrCast(@alignCast(ptr.?));
    }

    fn writeCallback(_: *const c.FLAC__StreamEncoder, buffer: [*]const u8, bytes: usize, _: u32, _: u32, data: ?*anyopaque) callconv(.c) c.FLAC__StreamEncoderWriteStatus {
        const s = client(data);
        if (s.closing) return c.FLAC__STREAM_ENCODER_WRITE_STATUS_FATAL_ERROR;
        const out = buffer[0..bytes];
        s.writer.writeAll(out) catch {
            s.err = error.WriteFailed;
            return c.FLAC__STREAM_ENCODER_WRITE_STATUS_FATAL_ERROR;
        };
        if (s.pos < s.head.len) {
            const n = @min(out.len, s.head.len - s.pos);
            @memcpy(s.head[@intCast(s.pos)..][0..n], out[0..n]);
        }
        s.pos += bytes;
        s.end = @max(s.end, s.pos);
        return c.FLAC__STREAM_ENCODER_WRITE_STATUS_OK;
    }

    fn seekCallback(_: *const c.FLAC__StreamEncoder, offset: u64, data: ?*anyopaque) callconv(.c) c.FLAC__StreamEncoderSeekStatus {
        const s = client(data);
        s.seeker.seekTo(s.seeker.context, offset) catch {
            s.err = error.SeekFailed;
            return c.FLAC__STREAM_ENCODER_SEEK_STATUS_ERROR;
        };
        s.pos = offset;
        return c.FLAC__STREAM_ENCODER_SEEK_STATUS_OK;
    }

    fn tellCallback(_: *const c.FLAC__StreamEncoder, offset: *u64, data: ?*anyopaque) callconv(.c) c.FLAC__StreamEncoderTellStatus {
        offset.* = client(data).pos;
        return c.FLAC__STREAM_ENCODER_TELL_STATUS_OK;
    }

    /// Ogg only: serves the read-back of the first page from `head`.
    fn readCallback(_: *const c.FLAC__StreamEncoder, buffer: [*]u8, bytes: *usize, data: ?*anyopaque) callconv(.c) c.FLAC__StreamEncoderReadStatus {
        const s = client(data);
        const avail = @min(s.end, s.head.len) -| s.pos;
        if (avail == 0) {
            bytes.* = 0;
            return c.FLAC__STREAM_ENCODER_READ_STATUS_ABORT;
        }
        const n: usize = @intCast(@min(avail, bytes.*));
        @memcpy(buffer[0..n], s.head[@intCast(s.pos)..][0..n]);
        s.pos += n;
        bytes.* = n;
        return c.FLAC__STREAM_ENCODER_READ_STATUS_CONTINUE;
    }
};
