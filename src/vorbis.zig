//! Ogg Vorbis: decode through libvorbisfile (reader callbacks), encode through libvorbisenc +
//! libogg framing.
//!
//! Chained streams: links are decoded back to back as long as they keep the first link's rate and
//! channel count; `frames` (seekable) counts those links. At the first link with another format,
//! `read` returns the frames before it, then error.UnsupportedFormat. Tags come from the first
//! link. ponytail: link changes are not exposed; that needs an Info-changed signal in the API.
//!
//! Damage: a lost page or packet (OV_HOLE) is an error like in flac.zig: `read` returns the frames
//! before it, then error.InvalidFile until a successful `seek`. A truncated tail is no error.
//!
//! Channel order: the Vorbis I spec fixes 1..8 channels (5.1 = FL FC FR BL BR LFE); those are
//! remapped to WAVE order, `channel_layout = ChannelLayout.default(channels)`. More channels are
//! application-defined: file order, layout null.
//!
//! Every libvorbis call runs inside c_allocator.set(gpa) / restore. libvorbis keeps pointers into
//! its own structs, so they live on the heap (backends are moved by value).

const std = @import("std");
const root = @import("root.zig");
const sample = @import("sample.zig");
const pcm = @import("pcm.zig");
const c_allocator = @import("c_allocator.zig");
const c = @import("zig-c-headers/vorbis.zig");
const ogg = @import("zig-c-headers/ogg.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Seeker = root.Seeker;

/// Vorbis channel index of each canonical (WAVE order) channel, for 1..8 channels.
const vorbis_order = [8][]const u8{
    &.{0},
    &.{ 0, 1 },
    &.{ 0, 2, 1 },
    &.{ 0, 1, 2, 3 },
    &.{ 0, 2, 1, 3, 4 },
    &.{ 0, 2, 1, 5, 3, 4 },
    &.{ 0, 2, 1, 6, 5, 3, 4 },
    &.{ 0, 2, 1, 7, 5, 6, 3, 4 },
};

pub fn vorbisChannel(channels: usize, canonical: usize) usize {
    return if (channels <= 8) vorbis_order[channels - 1][canonical] else canonical;
}

/// A failed libvorbis call: out of memory if an allocation failed during it (the zig fork checks
/// every allocation, but can report it only as some error code, or not at all), else bad data.
fn ovError() Error {
    return if (c_allocator.failed) error.OutOfMemory else error.InvalidFile;
}

pub const Decoder = struct {
    state: *State,

    const State = struct {
        gpa: Allocator,
        reader: *std.Io.Reader,
        seeker: ?Seeker,
        vf: c.OggVorbis_File = undefined,
        info: root.Info,
        /// Reader offset, for the tell callback.
        pos: u64 = 0,
        /// Link of the last decoded samples.
        link: c_int = 0,
        /// Planar output of the last ov_read_float (valid until the next libvorbisfile call).
        pcm: [*][*]f32 = undefined,
        pcm_len: usize = 0,
        pcm_pos: usize = 0,
        /// Sticky until a successful seek.
        err: ?Error = null,
        eos: bool = false,

        /// Decodes the next packet's samples into `pcm`.
        fn step(s: *State) void {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            var link: c_int = 0;
            const n = c.ov_read_float(&s.vf, &s.pcm, 4096, &link);
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
                s.err = error.InvalidFile;
                return;
            }
            if (link != s.link) {
                const vi = c.ov_info(&s.vf, -1) orelse {
                    s.err = error.InvalidFile;
                    return;
                };
                if (vi.channels != s.info.channels or vi.rate != s.info.sample_rate) {
                    s.err = error.UnsupportedFormat;
                    return;
                }
                s.link = link;
            }
            s.pcm_len = @intCast(n);
            s.pcm_pos = 0;
        }
    };

    /// `head`: the bytes ogg.head consumed; libvorbisfile takes them as its initial data.
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
                .codec = .vorbis,
                .sample_rate = 0,
                .channels = 0,
                .channel_layout = null,
                .frames = null,
                .bits_per_sample = 0,
                .sample_format = null,
            },
        };

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        const callbacks: c.ov_callbacks = .{
            .read_func = readCallback,
            // No seek callback: libvorbisfile treats the stream as unseekable.
            .seek_func = if (seeker != null) seekCallback else null,
            .close_func = null,
            .tell_func = tellCallback,
        };
        const ret = c.ov_open_callbacks(s, &s.vf, head.ptr, @intCast(head.len), callbacks);
        if (ret != 0) return s.err orelse ovError();
        errdefer _ = c.ov_clear(&s.vf);
        if (c_allocator.failed) return error.OutOfMemory;

        const vi = c.ov_info(&s.vf, 0) orelse return error.InvalidFile;
        s.info.sample_rate = std.math.cast(u32, vi.rate) orelse return error.InvalidFile;
        s.info.channels = std.math.cast(u16, vi.channels) orelse return error.InvalidFile;
        if (s.info.sample_rate == 0 or s.info.channels == 0) return error.InvalidFile;
        s.info.channel_layout = root.ChannelLayout.default(s.info.channels);
        if (seeker != null) {
            // Links up to the first format change (see the chaining note above).
            var total: u64 = 0;
            for (0..@intCast(c.ov_streams(&s.vf))) |i| {
                const link: c_int = @intCast(i);
                const li = c.ov_info(&s.vf, link) orelse break;
                if (li.channels != vi.channels or li.rate != vi.rate) break;
                total += std.math.cast(u64, c.ov_pcm_total(&s.vf, link)) orelse return error.InvalidFile;
            }
            s.info.frames = total;
        }
        if (tag_mode != .none) if (c.ov_comment(&s.vf, 0)) |vc| {
            s.info.tags = try readTags(arena, vc, tag_mode == .all);
        };
        return .{ .state = s };
    }

    pub fn deinit(d: *Decoder) void {
        const s = d.state;
        const prev = c_allocator.set(s.gpa);
        _ = c.ov_clear(&s.vf);
        c_allocator.restore(prev);
        s.gpa.destroy(s);
    }

    pub fn info(d: *const Decoder) *const root.Info {
        return &d.state.info;
    }

    pub fn ended(d: *const Decoder) bool {
        const s = d.state;
        return s.eos and s.pcm_pos == s.pcm_len;
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const s = d.state;
        const channels: usize = s.info.channels;
        const want = out.len / channels;
        var n: usize = 0;
        while (n < want) {
            const k = @min(s.pcm_len - s.pcm_pos, want - n);
            if (k > 0) {
                for (0..channels) |ch| {
                    const plane = s.pcm[vorbisChannel(channels, ch)][s.pcm_pos..][0..k];
                    for (plane, 0..) |x, f| out[(n + f) * channels + ch] = sample.convert(T, x);
                }
                n += k;
                s.pcm_pos += k;
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
        s.pcm_len = 0;
        s.pcm_pos = 0;
        s.err = null;
        s.eos = frame == total;
        if (s.eos) return;
        const prev = c_allocator.set(s.gpa);
        defer c_allocator.restore(prev);
        const ret = c.ov_pcm_seek(&s.vf, @intCast(frame));
        if (ret != 0 or c_allocator.failed) {
            const err = s.err orelse ovError();
            s.err = null;
            return err;
        }
        s.link = s.vf.current_link;
    }

    fn client(ptr: ?*anyopaque) *State {
        return @ptrCast(@alignCast(ptr.?));
    }

    fn readCallback(ptr: ?*anyopaque, size: usize, nmemb: usize, data: ?*anyopaque) callconv(.c) usize {
        const s = client(data);
        if (s.err != null or size == 0) return 0;
        const buffer: [*]u8 = @ptrCast(ptr.?);
        const n = s.reader.readSliceShort(buffer[0 .. size * nmemb]) catch {
            s.err = error.ReadFailed;
            return 0;
        };
        s.pos += n;
        return n / size;
    }

    fn seekCallback(data: ?*anyopaque, offset: i64, whence: c_int) callconv(.c) c_int {
        const s = client(data);
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

    /// ponytail: c_long is 32 bits on Windows; there a seekable file over 2 GiB fails to open.
    /// Fix in the fork (an ogg_int64_t tell) if that ever matters.
    fn tellCallback(data: ?*anyopaque) callconv(.c) c_long {
        return std.math.cast(c_long, client(data).pos) orelse -1;
    }
};

// --- vorbis comments (also used by flac.zig) ---

/// Normalized key <-> vorbis comment field name, where they differ beyond case.
const vorbis_keys = [_][2][]const u8{
    .{ "album_artist", "ALBUMARTIST" },
    .{ "track", "TRACKNUMBER" },
    .{ "disc", "DISCNUMBER" },
    .{ "comment", "DESCRIPTION" },
};

/// "KEY=value" -> Tag in `arena`; null for entries without '=' or over pcm.max_tag_len.
pub fn parseComment(arena: Allocator, entry: []const u8) Allocator.Error!?root.Tag {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return null;
    const value = entry[eq + 1 ..];
    if (value.len > pcm.max_tag_len) return null;
    const upper = entry[0..eq];
    const key = for (vorbis_keys) |k| {
        if (std.ascii.eqlIgnoreCase(k[1], upper)) break k[0];
    } else try std.ascii.allocLowerString(arena, upper);
    return .{ .key = key, .value = try arena.dupe(u8, value) };
}

/// Tag -> "KEY=value" in `gpa`. error.InvalidOptions for keys vorbis comments cannot hold
/// (0x20..0x7D without '=') and values that are not UTF-8 or contain NUL.
pub fn formatComment(gpa: Allocator, tag: root.Tag) Error![:0]u8 {
    if (tag.key.len == 0 or !std.unicode.utf8ValidateSlice(tag.value)) return error.InvalidOptions;
    if (std.mem.indexOfScalar(u8, tag.value, 0) != null) return error.InvalidOptions;
    for (tag.key) |ch| if (ch < 0x20 or ch > 0x7d or ch == '=') return error.InvalidOptions;
    const name = for (vorbis_keys) |k| {
        if (std.mem.eql(u8, k[0], tag.key)) break k[1];
    } else tag.key;
    const out = try std.fmt.allocPrintSentinel(gpa, "{s}={s}", .{ name, tag.value }, 0);
    _ = std.ascii.upperString(out[0..name.len], out[0..name.len]);
    return out;
}

const picture_key = "METADATA_BLOCK_PICTURE";

/// Text tags, plus METADATA_BLOCK_PICTURE entries as pictures when `pictures` (skipped
/// otherwise, they can be MBs). ponytail: the legacy COVERART field is ignored.
/// `vc`: a vorbis_comment or an OpusTags (same layout).
pub fn readTags(arena: Allocator, vc: anytype, pictures: bool) Error!root.Tags {
    const comments = vc.user_comments orelse return .{};
    const lengths = vc.comment_lengths orelse return .{};
    var items: std.ArrayList(root.Tag) = .empty;
    var pics: std.ArrayList(root.Picture) = .empty;
    const n: usize = @intCast(vc.comments);
    for (comments[0..n], lengths[0..n]) |entry, len| {
        const bytes = entry[0..@intCast(len)];
        if (bytes.len > picture_key.len and std.ascii.eqlIgnoreCase(bytes[0..picture_key.len], picture_key) and bytes[picture_key.len] == '=') {
            if (pictures) if (try parsePicture(arena, bytes[picture_key.len + 1 ..])) |p| try pics.append(arena, p);
            continue;
        }
        if (try parseComment(arena, bytes)) |tag| try items.append(arena, tag);
    }
    return .{ .items = items.items, .pictures = pics.items };
}

/// Base64 FLAC PICTURE block -> Picture in `arena`; null when malformed.
fn parsePicture(arena: Allocator, base64: []const u8) Allocator.Error!?root.Picture {
    const decoder = std.base64.standard.Decoder;
    const size = decoder.calcSizeForSlice(base64) catch return null;
    const block = try arena.alloc(u8, size);
    decoder.decode(block, base64) catch return null;
    var r: std.Io.Reader = .fixed(block);
    return parsePictureBlock(&r) catch null;
}

fn parsePictureBlock(r: *std.Io.Reader) !root.Picture {
    const kind = try r.takeInt(u32, .big);
    const mime = try r.take(try r.takeInt(u32, .big));
    const description = try r.take(try r.takeInt(u32, .big));
    try pcm.skip(r, 16); // width, height, depth, colors
    const data = try r.take(try r.takeInt(u32, .big));
    return .{ .mime = mime, .kind = @truncate(kind), .description = description, .data = data };
}

pub const Encoder = struct {
    state: *State,

    /// Frames handed to libvorbis per analysis round.
    const chunk_frames = 1024;

    const State = struct {
        gpa: Allocator,
        writer: *std.Io.Writer,
        channels: u16,
        vi: c.vorbis_info = undefined,
        vc: c.vorbis_comment = undefined,
        vd: c.vorbis_dsp_state = undefined,
        vb: c.vorbis_block = undefined,
        os: ogg.ogg_stream_state = undefined,
        /// Sticky: after a failure the stream state is unknown.
        err: ?Error = null,

        /// Analysis of every complete block, packets into pages, full pages out (all with
        /// `flush_pages`).
        fn drain(s: *State, flush_pages: bool) Error!void {
            var op: ogg.ogg_packet = undefined;
            while (true) {
                const ret = c.vorbis_analysis_blockout(&s.vd, &s.vb);
                if (ret == 0) break;
                if (ret < 0) return error.OutOfMemory;
                if (c.vorbis_analysis(&s.vb, null) != 0) return error.OutOfMemory;
                if (c.vorbis_bitrate_addblock(&s.vb) != 0) return error.OutOfMemory;
                while (true) {
                    const got = c.vorbis_bitrate_flushpacket(&s.vd, &op);
                    if (got == 0) break;
                    if (got < 0) return error.OutOfMemory;
                    if (ogg.ogg_stream_packetin(&s.os, &op) != 0) return error.OutOfMemory;
                    try s.pages(false);
                }
            }
            if (flush_pages) try s.pages(true);
            // Allocations libvorbis could only skip (a floor or residue left out).
            if (c_allocator.failed) return error.OutOfMemory;
        }

        fn pages(s: *State, force: bool) Error!void {
            var og: ogg.ogg_page = undefined;
            while ((if (force) ogg.ogg_stream_flush(&s.os, &og) else ogg.ogg_stream_pageout(&s.os, &og)) != 0) {
                try s.writer.writeAll(og.header.?[0..@intCast(og.header_len)]);
                try s.writer.writeAll(og.body.?[0..@intCast(og.body_len)]);
            }
            if (ogg.ogg_stream_check(&s.os) != 0) return error.OutOfMemory;
        }

        fn fail(s: *State, err: Error) Error {
            s.err = err;
            return err;
        }
    };

    /// quality 0..1 -> vorbis VBR quality -0.1..1.0 (oggenc -q -1..10); null -> 0.3 (oggenc's
    /// default -q 3). Channels 1..255, the default layout only (1..8) or none (more). No seeker
    /// needed: the last page's granule position carries the exact length.
    /// Float input is clipped to [-1, 1] (NaN -> 0): libvorbis' quantizer is undefined beyond.
    /// ponytail: no managed bitrate mode (Options has no bitrate); add vorbis_encode_setup_managed
    /// when it does.
    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: root.Encoder.Options) Error!Encoder {
        if (options.channels > 255) return error.UnsupportedFormat;
        if (options.channel_layout) |l| if (!std.meta.eql(@as(?root.ChannelLayout, l), root.ChannelLayout.default(options.channels))) return error.UnsupportedFormat;
        const rate = std.math.cast(c_long, options.sample_rate) orelse return error.UnsupportedFormat;
        const quality: f32 = if (options.quality) |q| blk: {
            if (!(q >= 0 and q <= 1)) return error.InvalidOptions;
            break :blk -0.1 + 1.1 * q;
        } else 0.3;

        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{ .gpa = gpa, .writer = writer, .channels = options.channels };

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        c.vorbis_info_init(&s.vi);
        errdefer c.vorbis_info_clear(&s.vi);
        if (c.vorbis_encode_init_vbr(&s.vi, options.channels, rate, quality) != 0) {
            // OV_EIMPL: no mode for this rate / channel count.
            return if (c_allocator.failed) error.OutOfMemory else error.UnsupportedFormat;
        }
        c.vorbis_comment_init(&s.vc);
        errdefer c.vorbis_comment_clear(&s.vc);
        for (options.tags) |tag| {
            const entry = try formatComment(gpa, tag);
            defer gpa.free(entry);
            const before = s.vc.comments;
            c.vorbis_comment_add(&s.vc, entry.ptr);
            if (s.vc.comments == before) return error.OutOfMemory;
        }
        if (c.vorbis_analysis_init(&s.vd, &s.vi) != 0) return error.OutOfMemory;
        errdefer c.vorbis_dsp_clear(&s.vd);
        if (c.vorbis_block_init(&s.vd, &s.vb) != 0) return error.OutOfMemory;
        errdefer _ = c.vorbis_block_clear(&s.vb);
        const serial = options.ogg_serial orelse defaultSerial(options);
        if (ogg.ogg_stream_init(&s.os, @bitCast(serial)) != 0) return error.OutOfMemory;
        errdefer _ = ogg.ogg_stream_clear(&s.os);

        var header: [3]ogg.ogg_packet = undefined;
        if (c.vorbis_analysis_headerout(&s.vd, &s.vc, &header[0], &header[1], &header[2]) != 0) return error.OutOfMemory;
        for (&header) |*p| if (ogg.ogg_stream_packetin(&s.os, p) != 0) return error.OutOfMemory;
        // Audio starts on a fresh page (Vorbis I spec).
        try s.pages(true);
        return .{ .state = s };
    }

    /// Deterministic: the same options give the same file. Chaining files needs distinct
    /// serials; pass Options.ogg_serial then.
    pub fn defaultSerial(options: root.Encoder.Options) u32 {
        var h: std.hash.Wyhash = .init(0);
        h.update(&std.mem.toBytes(std.mem.nativeToLittle(u32, options.sample_rate)));
        h.update(&std.mem.toBytes(std.mem.nativeToLittle(u16, options.channels)));
        for (options.tags) |t| {
            h.update(t.key);
            h.update(t.value);
        }
        return @truncate(h.final());
    }

    pub fn deinit(e: *Encoder) void {
        const s = e.state;
        const prev = c_allocator.set(s.gpa);
        _ = ogg.ogg_stream_clear(&s.os);
        _ = c.vorbis_block_clear(&s.vb);
        c.vorbis_dsp_clear(&s.vd);
        c.vorbis_comment_clear(&s.vc);
        c.vorbis_info_clear(&s.vi);
        c_allocator.restore(prev);
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
            const buffer = c.vorbis_analysis_buffer(&s.vd, @intCast(n)) orelse return s.fail(error.OutOfMemory);
            for (0..channels) |ch| {
                const plane = buffer[vorbisChannel(channels, ch)][0..n];
                for (plane, 0..) |*o, f| o.* = clip(sample.convert(f32, samples[(frame + f) * channels + ch]));
            }
            if (c.vorbis_analysis_wrote(&s.vd, @intCast(n)) != 0) return s.fail(error.OutOfMemory);
            s.drain(false) catch |err| return s.fail(err);
            frame += n;
        }
    }

    pub fn clip(x: f32) f32 {
        return if (std.math.isNan(x)) 0 else std.math.clamp(x, -1, 1);
    }

    /// Emits the pages of every packet made so far (short pages; libvorbis still holds back the
    /// current block's overlap).
    pub fn flush(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        s.pages(true) catch |err| return s.fail(err);
        try s.writer.flush();
    }

    pub fn finish(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            // End of stream: the last packet's granule position is the exact length.
            if (c.vorbis_analysis_wrote(&s.vd, 0) != 0) return s.fail(error.OutOfMemory);
            s.drain(true) catch |err| return s.fail(err);
        }
        try s.writer.flush();
    }
};
