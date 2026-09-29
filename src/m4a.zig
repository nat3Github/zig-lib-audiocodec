//! MPEG-4 audio files (.m4a / .mp4): container through minimp4, the ALAC codec through alac.zig.
//!
//! Demux: we walk the top-level boxes ourselves and load `moov` into memory; minimp4 (MP4D) parses
//! only that buffer and resolves the sample table (stsz/stsc/stco/stts). Our own bounds-checked
//! box walker reads what MP4D does not expose: the sample entry (fourcc, ALAC cookie), the edit
//! list and the iTunes tags (udta/meta/ilst). Samples are then read from the source by offset.
//! Without a Seeker this works when `moov` comes before `mdat` and the samples are stored in
//! increasing file order (every muxer does that); `moov` after `mdat` -> error.NotSeekable at open.
//!
//! Mux: minimp4 (MP4E, fork patch "zig: alac sample entry") writes ftyp, mdat, then moov at the
//! end and patches the mdat size in front: needs a Seeker. Tags: MP4E can only write one comment,
//! so our write callback appends our own udta/meta/ilst to the moov it writes last in MP4E_close
//! (moov's size patched on the way through).
//!
//! Codec specifics live in the Alac structs; 10-aac adds its own next to them.

const std = @import("std");
const root = @import("root.zig");
const sample = @import("sample.zig");
const alac = @import("alac.zig");
const id3 = @import("id3.zig");
const c_allocator = @import("c_allocator.zig");
const c = @import("zig-c-headers/minimp4.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Seeker = root.Seeker;
const ChannelLayout = root.ChannelLayout;
const native = @import("builtin").cpu.arch.endian();

/// ponytail: a bigger moov is rejected (InvalidFile). ALAC needs ~0.3 MB per hour of audio.
const max_moov = 64 << 20;

// --- boxes ---

const Box = struct {
    type: [4]u8,
    body: []const u8,

    fn is(b: Box, t: *const [4]u8) bool {
        return std.mem.eql(u8, &b.type, t);
    }
};

/// Iterates the boxes in a byte range; ends at the first malformed size.
const Boxes = struct {
    rest: []const u8,

    fn next(it: *Boxes) ?Box {
        const r = it.rest;
        if (r.len < 8) return null;
        var header: usize = 8;
        const size: u64 = switch (std.mem.readInt(u32, r[0..4], .big)) {
            0 => r.len,
            1 => blk: {
                if (r.len < 16) return null;
                header = 16;
                break :blk std.mem.readInt(u64, r[8..16], .big);
            },
            else => |s| s,
        };
        if (size < header or size > r.len) return null;
        const len: usize = @intCast(size);
        it.rest = r[len..];
        return .{ .type = r[4..8].*, .body = r[header..len] };
    }

    fn find(bytes: []const u8, t: *const [4]u8) ?[]const u8 {
        var it: Boxes = .{ .rest = bytes };
        while (it.next()) |b| if (b.is(t)) return b.body;
        return null;
    }

    fn path(bytes: []const u8, comptime types: []const *const [4]u8) ?[]const u8 {
        var body = bytes;
        inline for (types) |t| body = find(body, t) orelse return null;
        return body;
    }
};

fn be32(bytes: []const u8, at: usize) ?u32 {
    if (bytes.len < at + 4) return null;
    return std.mem.readInt(u32, bytes[at..][0..4], .big);
}

fn be64(bytes: []const u8, at: usize) ?u64 {
    if (bytes.len < at + 8) return null;
    return std.mem.readInt(u64, bytes[at..][0..8], .big);
}

/// The first sound track of a moov body.
const Track = struct {
    /// Ordinal of its trak box: minimp4's track index.
    index: u32,
    /// Sample entry type ('alac', 'mp4a', ...).
    entry: [4]u8,
    /// ALAC: the magic cookie (the 'alac' box body after its version/flags).
    cookie: []const u8 = &.{},
    timescale: u32,
    edit: ?Edit = null,
};

/// First non-empty edit of the edit list: where the presentation starts in the media and how
/// long it is. ponytail: further edits and empty edits (delays) are ignored.
const Edit = struct {
    media_time: u64,
    /// In the movie timescale.
    duration: u64,
    movie_timescale: u32,
};

fn findTrack(moov: []const u8) ?Track {
    const movie_timescale = blk: {
        const mvhd = Boxes.find(moov, "mvhd") orelse break :blk 0;
        break :blk (if (mvhd.len > 0 and mvhd[0] == 1) be32(mvhd, 20) else be32(mvhd, 12)) orelse 0;
    };
    var it: Boxes = .{ .rest = moov };
    var index: u32 = 0;
    while (it.next()) |b| {
        if (!b.is("trak")) continue;
        defer index += 1;
        const mdia = Boxes.find(b.body, "mdia") orelse continue;
        const hdlr = Boxes.find(mdia, "hdlr") orelse continue;
        if (hdlr.len < 12 or !std.mem.eql(u8, hdlr[8..12], "soun")) continue;
        const mdhd = Boxes.find(mdia, "mdhd") orelse continue;
        const timescale = (if (mdhd.len > 0 and mdhd[0] == 1) be32(mdhd, 20) else be32(mdhd, 12)) orelse continue;
        const stsd = Boxes.path(mdia, &.{ "minf", "stbl", "stsd" }) orelse continue;
        if (stsd.len < 8) continue;
        var entries: Boxes = .{ .rest = stsd[8..] };
        const entry = entries.next() orelse continue;
        var track: Track = .{ .index = index, .entry = entry.type, .timescale = timescale };
        track.cookie = alacCookie(entry.body) orelse &.{};
        if (Boxes.path(b.body, &.{ "edts", "elst" })) |elst| track.edit = firstEdit(elst, movie_timescale);
        return track;
    }
    return null;
}

/// The 'alac' box inside an AudioSampleEntry (ISO), or inside its 'wave' box (QuickTime).
fn alacCookie(entry: []const u8) ?[]const u8 {
    if (entry.len < 28) return null;
    // SampleEntry (8) + sound description version 0: 20 bytes; QuickTime v1 adds 16, v2 36.
    const extra: usize = switch (std.mem.readInt(u16, entry[8..10], .big)) {
        1 => 16,
        2 => 36,
        else => 0,
    };
    if (entry.len < 28 + extra) return null;
    const children = entry[28 + extra ..];
    const box = Boxes.find(children, "alac") orelse Boxes.path(children, &.{ "wave", "alac" }) orelse return null;
    return if (box.len >= 4) box[4..] else null;
}

fn firstEdit(elst: []const u8, movie_timescale: u32) ?Edit {
    if (elst.len < 8 or movie_timescale == 0) return null;
    const v1 = elst[0] == 1;
    const entry_len: usize = if (v1) 20 else 12;
    const count = be32(elst, 4).?;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const at = 8 + i * entry_len;
        if (elst.len < at + entry_len) return null;
        const duration = if (v1) be64(elst, at).? else be32(elst, at).?;
        const media_time: i64 = if (v1) @bitCast(be64(elst, at + 8).?) else @as(i32, @bitCast(be32(elst, at + 4).?));
        if (media_time < 0) continue; // empty edit
        return .{ .media_time = @intCast(media_time), .duration = duration, .movie_timescale = movie_timescale };
    }
    return null;
}

/// Reads the top-level boxes up to and including moov; returns the moov box (header included)
/// and leaves the source right behind it (`pos`). Boxes in front are skipped: by seeking with a
/// seeker, else by reading through them, except mdat (the audio would be gone): NotSeekable.
fn readMoov(gpa: Allocator, reader: *std.Io.Reader, seeker: ?Seeker, pos: *u64) Error![]u8 {
    var offset: u64 = 0;
    while (true) {
        var head: [16]u8 = undefined;
        reader.readSliceAll(head[0..8]) catch |err| return headerError(err);
        var header: u64 = 8;
        const size32 = std.mem.readInt(u32, head[0..4], .big);
        var size: ?u64 = size32;
        if (size32 == 1) {
            reader.readSliceAll(head[8..16]) catch |err| return headerError(err);
            header = 16;
            size = std.mem.readInt(u64, head[8..16], .big);
        } else if (size32 == 0) {
            size = null; // to the end of the file
        }
        if (size) |s| if (s < header) return error.InvalidFile;
        const is_moov = std.mem.eql(u8, head[4..8], "moov");
        if (is_moov) {
            if (size) |s| {
                if (s > max_moov) return error.InvalidFile;
                const buf = try gpa.alloc(u8, @intCast(s));
                errdefer gpa.free(buf);
                @memcpy(buf[0..@intCast(header)], head[0..@intCast(header)]);
                reader.readSliceAll(buf[@intCast(header)..]) catch |err| return headerError(err);
                pos.* = offset + s;
                return buf;
            }
            const rest = reader.allocRemaining(gpa, .limited(max_moov - 8)) catch |err| return switch (err) {
                error.StreamTooLong => error.InvalidFile,
                error.OutOfMemory => error.OutOfMemory,
                error.ReadFailed => error.ReadFailed,
            };
            defer gpa.free(rest);
            const buf = try gpa.alloc(u8, rest.len + 8);
            std.mem.writeInt(u32, buf[0..4], @intCast(buf.len), .big);
            @memcpy(buf[4..8], "moov");
            @memcpy(buf[8..], rest);
            pos.* = offset + buf.len;
            return buf;
        }
        // A box that runs to the end of the file with no moov before it: no moov at all.
        const s = size orelse return error.InvalidFile;
        if (seeker) |sk| {
            const end = std.math.add(u64, offset, s) catch return error.InvalidFile;
            if (end > try sk.size(sk.context)) return error.InvalidFile;
            try sk.seekTo(sk.context, end);
        } else {
            if (std.mem.eql(u8, head[4..8], "mdat")) return error.NotSeekable;
            reader.discardAll64(s - header) catch |err| return headerError(err);
        }
        offset += s;
    }
}

fn headerError(err: std.Io.Reader.Error) Error {
    return switch (err) {
        error.EndOfStream => error.InvalidFile,
        error.ReadFailed => error.ReadFailed,
    };
}

// --- tags (iTunes ilst) ---

/// ilst item atoms <-> normalized keys. 0xA9 is the (c) sign of the iTunes atoms.
const text_atoms = [_]struct { *const [4]u8, []const u8 }{
    .{ "\xa9nam", "title" },    .{ "\xa9ART", "artist" },   .{ "\xa9alb", "album" },
    .{ "aART", "album_artist" }, .{ "\xa9day", "date" },     .{ "\xa9gen", "genre" },
    .{ "\xa9cmt", "comment" },  .{ "\xa9wrt", "composer" }, .{ "cprt", "copyright" },
    .{ "\xa9too", "encoder" },
};

/// Freeform ('----') items are written with this mean and read whatever their mean.
const freeform_mean = "com.apple.iTunes";

fn parseTags(arena: Allocator, moov: []const u8, mode: root.TagMode) Allocator.Error!root.Tags {
    if (mode == .none) return .{};
    const meta = Boxes.path(moov, &.{ "udta", "meta" }) orelse return .{};
    // meta is a full box; some writers (QuickTime, old Android) leave out the version/flags.
    const children = if (meta.len >= 8 and std.mem.eql(u8, meta[4..8], "hdlr")) meta else if (meta.len >= 4) meta[4..] else return .{};
    const ilst = Boxes.find(children, "ilst") orelse return .{};

    var items: std.ArrayList(root.Tag) = .empty;
    var pictures: std.ArrayList(root.Picture) = .empty;
    var it: Boxes = .{ .rest = ilst };
    while (it.next()) |item| {
        var key: []const u8 = undefined;
        if (item.is("----")) {
            const name = Boxes.find(item.body, "name") orelse continue;
            if (name.len < 4) continue;
            key = try lowerKey(arena, name[4..]);
        } else {
            key = for (text_atoms) |a| {
                if (item.is(a[0])) break a[1];
            } else if (item.is("trkn")) "track" else if (item.is("disk")) "disc" else if (item.is("gnre")) "genre" else try lowerKey(arena, &item.type);
        }
        var data_boxes: Boxes = .{ .rest = item.body };
        while (data_boxes.next()) |d| {
            if (!d.is("data") or d.body.len < 8) continue;
            const kind = std.mem.readInt(u32, d.body[0..4], .big) & 0xffffff;
            const value = d.body[8..];
            if (item.is("covr")) {
                if (mode != .all) continue;
                const mime: []const u8 = switch (kind) {
                    13 => "image/jpeg",
                    14 => "image/png",
                    27 => "image/bmp",
                    else => "",
                };
                try pictures.append(arena, .{ .mime = mime, .kind = 3, .description = "", .data = try arena.dupe(u8, value) });
            } else if (item.is("trkn") or item.is("disk")) {
                // binary: 2 reserved, number u16, total u16 [, 2 reserved]
                if (value.len < 6) continue;
                const n = std.mem.readInt(u16, value[2..4], .big);
                const total = std.mem.readInt(u16, value[4..6], .big);
                if (n == 0) continue;
                const text = if (total != 0) try std.fmt.allocPrint(arena, "{d}/{d}", .{ n, total }) else try std.fmt.allocPrint(arena, "{d}", .{n});
                try items.append(arena, .{ .key = key, .value = text });
            } else if (item.is("gnre")) {
                // ID3v1 genre number + 1
                if (value.len < 2) continue;
                const g = std.mem.readInt(u16, value[0..2], .big);
                if (g == 0 or g > id3.genres.len) continue;
                try items.append(arena, .{ .key = key, .value = id3.genres[g - 1] });
            } else if (kind == 21 or kind == 22) {
                // big-endian signed / unsigned integer (tmpo, cpil, rtng ...)
                const text = switch (value.len) {
                    inline 1, 2, 4, 8 => |len| blk: {
                        const bits = len * 8;
                        const u = std.mem.readInt(std.meta.Int(.unsigned, bits), value[0..len], .big);
                        break :blk if (kind == 21)
                            try std.fmt.allocPrint(arena, "{d}", .{@as(std.meta.Int(.signed, bits), @bitCast(u))})
                        else
                            try std.fmt.allocPrint(arena, "{d}", .{u});
                    },
                    else => continue,
                };
                try items.append(arena, .{ .key = key, .value = text });
            } else if (kind == 1 or kind == 0) {
                // ponytail: UTF-16 (kind 2) text is dropped, nobody writes it.
                if (!std.unicode.utf8ValidateSlice(value)) continue;
                try items.append(arena, .{ .key = key, .value = try arena.dupe(u8, value) });
            }
        }
    }
    return .{ .items = items.items, .pictures = pictures.items };
}

/// Lowercased key; 0xA9 (iTunes' (c) in Latin-1) becomes UTF-8, other non-ASCII bytes '?'.
fn lowerKey(arena: Allocator, raw: []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (raw) |b| {
        if (b == 0xa9) {
            try out.appendSlice(arena, "\u{a9}");
        } else {
            try out.append(arena, if (b < 0x80) std.ascii.toLower(b) else '?');
        }
    }
    return out.items;
}

/// udta { meta { hdlr mdir, ilst { items } } } for the encoder's tags; empty without tags.
fn buildUdta(gpa: Allocator, tags: []const root.Tag) Error![]u8 {
    if (tags.len == 0) return &.{};
    var b: BoxWriter = .{ .gpa = gpa };
    errdefer b.out.deinit(gpa);
    const udta = try b.begin("udta");
    const meta = try b.begin("meta");
    try b.int(u32, 0);
    const hdlr = try b.begin("hdlr");
    try b.bytes(&[_]u8{0} ** 8); // version/flags, pre_defined
    try b.bytes("mdirappl"); // handler type, reserved[0] as iTunes writes it
    try b.bytes(&[_]u8{0} ** 9); // reserved[1..2], empty name
    b.end(hdlr);
    const ilst = try b.begin("ilst");
    for (tags) |tag| {
        if (!std.unicode.utf8ValidateSlice(tag.value)) return error.InvalidOptions;
        const atom: ?*const [4]u8 = for (text_atoms) |a| {
            if (std.mem.eql(u8, tag.key, a[1])) break a[0];
        } else null;
        if (atom) |a| {
            const item = try b.begin(a);
            try b.data(1, tag.value);
            b.end(item);
            continue;
        }
        const is_track = std.mem.eql(u8, tag.key, "track");
        if (is_track or std.mem.eql(u8, tag.key, "disc")) {
            if (numberPair(tag.value)) |p| {
                const item = try b.begin(if (is_track) "trkn" else "disk");
                var v: [8]u8 = @splat(0);
                std.mem.writeInt(u16, v[2..4], p[0], .big);
                std.mem.writeInt(u16, v[4..6], p[1], .big);
                try b.data(0, if (is_track) &v else v[0..6]);
                b.end(item);
                continue;
            }
        }
        const item = try b.begin("----");
        const mean = try b.begin("mean");
        try b.int(u32, 0);
        try b.bytes(freeform_mean);
        b.end(mean);
        const name = try b.begin("name");
        try b.int(u32, 0);
        try b.bytes(tag.key);
        b.end(name);
        try b.data(1, tag.value);
        b.end(item);
    }
    b.end(ilst);
    b.end(meta);
    b.end(udta);
    if (b.out.items.len > std.math.maxInt(u32)) return error.FileTooLarge;
    return b.out.toOwnedSlice(gpa);
}

/// "n" or "n/total", both 1..65535 (total may be absent).
fn numberPair(value: []const u8) ?[2]u16 {
    var parts = std.mem.splitScalar(u8, value, '/');
    const n = std.fmt.parseInt(u16, parts.first(), 10) catch return null;
    const total = if (parts.next()) |t| std.fmt.parseInt(u16, t, 10) catch return null else 0;
    if (parts.next() != null or n == 0) return null;
    return .{ n, total };
}

const BoxWriter = struct {
    gpa: Allocator,
    out: std.ArrayList(u8) = .empty,

    fn begin(w: *BoxWriter, t: *const [4]u8) Allocator.Error!usize {
        const at = w.out.items.len;
        try w.out.appendSlice(w.gpa, &.{ 0, 0, 0, 0 });
        try w.out.appendSlice(w.gpa, t);
        return at;
    }

    /// Sizes are patched as u32; buildUdta rejects anything that could overflow them.
    fn end(w: *BoxWriter, at: usize) void {
        std.mem.writeInt(u32, w.out.items[at..][0..4], @truncate(w.out.items.len - at), .big);
    }

    fn bytes(w: *BoxWriter, b: []const u8) Allocator.Error!void {
        try w.out.appendSlice(w.gpa, b);
    }

    fn int(w: *BoxWriter, comptime T: type, v: T) Allocator.Error!void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, v, .big);
        try w.bytes(&buf);
    }

    /// 'data' box: type indicator (1 = UTF-8, 0 = binary), locale 0, value.
    fn data(w: *BoxWriter, kind: u32, value: []const u8) Allocator.Error!void {
        const at = try w.begin("data");
        try w.int(u32, kind);
        try w.int(u32, 0);
        try w.bytes(value);
        w.end(at);
    }
};

// --- ALAC ---

/// ALAC's fixed channel orders (ALACChannelLayoutTags), labelled as ffmpeg does: layout per
/// channel count, and for each bitstream channel its index in canonical (WAVE) order.
const alac_layouts = [8]ChannelLayout{
    .mono,
    .stereo,
    .surround_3_0,
    .{ .front_left = true, .front_right = true, .front_center = true, .back_center = true },
    .surround_5_0,
    .surround_5_1,
    .{ .front_left = true, .front_right = true, .front_center = true, .lfe = true, .back_left = true, .back_right = true, .back_center = true },
    .{ .front_left = true, .front_right = true, .front_center = true, .lfe = true, .back_left = true, .back_right = true, .front_left_of_center = true, .front_right_of_center = true },
};
const alac_order = [8][]const u8{
    &.{0},
    &.{ 0, 1 },
    &.{ 2, 0, 1 }, // C L R
    &.{ 2, 0, 1, 3 }, // C L R Cs
    &.{ 2, 0, 1, 3, 4 }, // C L R Ls Rs
    &.{ 2, 0, 1, 4, 5, 3 }, // C L R Ls Rs LFE
    &.{ 2, 0, 1, 4, 5, 6, 3 }, // C L R Ls Rs Cs LFE
    &.{ 2, 6, 7, 0, 1, 4, 5, 3 }, // C Lc Rc L R Ls Rs LFE
};

/// ponytail: frame lengths above this are rejected (Apple's default is 4096).
const max_alac_frame = 1 << 16;

fn alacLayout(bit_depth: u8) sample.Layout {
    // 20-bit samples come left-aligned in 3 bytes, like 24-bit.
    return .{ .format = switch (bit_depth) {
        16 => .i16,
        20, 24 => .i24,
        else => .i32,
    }, .endian = native };
}

// --- Decoder ---

pub const Decoder = struct {
    state: *State,

    const State = struct {
        gpa: Allocator,
        reader: *std.Io.Reader,
        seeker: ?Seeker,
        info: root.Info,
        mp4: c.MP4D_demux_t = undefined,
        track: u32 = 0,
        /// Samples with a size, offset and duration.
        samples: u32 = 0,
        /// Per-sample timestamps / durations in the media timescale (minimp4's stts tables).
        timestamps: [*]const c_uint = undefined,
        durations: [*]const c_uint = undefined,
        codec: alac.Decoder = undefined,
        layout: sample.Layout = undefined,
        frame_bytes: usize = 0,
        /// Source offset of the reader.
        pos: u64 = 0,
        packet: []u8 = &.{},
        /// One decoded packet, canonical channel order; frames [pcm_used, pcm_len) not read yet.
        pcm: []align(4) u8 = &.{},
        pcm_used: usize = 0,
        pcm_len: usize = 0,
        next: u32 = 0,
        /// Media time of the next frame to output; the presentation is [start, end).
        media_pos: u64 = 0,
        start: u64 = 0,
        end: u64 = 0,
        /// Sticky until a successful seek.
        err: ?Error = null,
        /// Source ended before the last sample (truncated file).
        eos: bool = false,

        fn deinit(s: *State) void {
            const prev = c_allocator.set(s.gpa);
            c.MP4D_close(&s.mp4);
            c_allocator.restore(prev);
            s.codec.deinit(s.gpa);
            s.gpa.free(s.packet);
            s.gpa.free(s.pcm);
        }
    };

    pub fn open(gpa: Allocator, arena: Allocator, reader: *std.Io.Reader, seeker: ?Seeker, tag_mode: root.TagMode) Error!Decoder {
        var pos: u64 = 0;
        const moov = try readMoov(gpa, reader, seeker, &pos);
        defer gpa.free(moov);
        var top: Boxes = .{ .rest = moov };
        const moov_body = top.next().?.body;
        const track = findTrack(moov_body) orelse return error.InvalidFile;
        if (!std.mem.eql(u8, &track.entry, "alac")) return error.UnsupportedFormat;
        if (track.cookie.len < 24) return error.InvalidFile;
        const channels = track.cookie[9];
        const bit_depth = track.cookie[5];
        const frame_length = std.mem.readInt(u32, track.cookie[0..4], .big);
        const rate = std.mem.readInt(u32, track.cookie[20..24], .big);
        if (channels == 0 or channels > 8 or frame_length == 0 or frame_length > max_alac_frame) return error.InvalidFile;
        // ponytail: stts durations are taken as frames; other timescales would need rescaling.
        if (rate != track.timescale) return error.UnsupportedFormat;

        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .reader = reader,
            .seeker = seeker,
            .pos = pos,
            .info = .{
                .container = .m4a,
                .codec = .alac,
                .sample_rate = rate,
                .channels = channels,
                .channel_layout = alac_layouts[channels - 1],
                .frames = null,
                .bits_per_sample = bit_depth,
                .sample_format = null,
                .tags = try parseTags(arena, moov_body, tag_mode),
            },
        };

        {
            const prev = c_allocator.set(gpa);
            defer c_allocator.restore(prev);
            var bytes: []const u8 = moov;
            if (c.MP4D_open(&s.mp4, readMoovBuffer, @ptrCast(&bytes), @intCast(moov.len)) == 0)
                return if (c_allocator.failed) error.OutOfMemory else error.InvalidFile;
        }
        errdefer {
            const prev = c_allocator.set(gpa);
            c.MP4D_close(&s.mp4);
            c_allocator.restore(prev);
        }
        if (c_allocator.failed) return error.OutOfMemory;
        if (track.index >= s.mp4.track_count) return error.InvalidFile;
        const tr = &s.mp4.track.?[track.index];
        s.track = track.index;
        s.samples = @min(tr.sample_count, tr.timestamp_count);
        if (s.samples > 0) {
            if (tr.entry_size == null or tr.timestamp == null or tr.duration == null) return error.InvalidFile;
            s.timestamps = tr.timestamp.?;
            s.durations = tr.duration.?;
        }
        var total: u64 = 0;
        for (0..s.samples) |i| total += s.durations[i];
        // minimp4's timestamps are 32-bit. ponytail: longer tracks (27 h at 44.1 kHz) unsupported.
        if (total > std.math.maxInt(c_uint)) return error.UnsupportedFormat;
        s.end = total;
        if (track.edit) |e| {
            s.start = @min(e.media_time, total);
            // The edit's duration is in the movie timescale (often 1/1000 s), so it only trims
            // when it is shorter than the media by more than its own rounding.
            const avail = total - s.start;
            const length = std.math.cast(u64, std.math.mulWide(u64, e.duration, track.timescale) / e.movie_timescale) orelse avail;
            const slack = track.timescale / e.movie_timescale + 1;
            if (length +| slack < avail) s.end = s.start + length;
        }
        s.info.frames = s.end - s.start;
        s.media_pos = s.start;

        s.codec = alac.Decoder.init(gpa, track.cookie) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidParameter => error.InvalidFile,
        };
        errdefer s.codec.deinit(gpa);
        s.layout = alacLayout(bit_depth);
        s.frame_bytes = @as(usize, sample.size(s.layout.format)) * channels;
        s.pcm = try gpa.alignedAlloc(u8, .@"4", frame_length * s.frame_bytes);
        return .{ .state = s };
    }

    fn readMoovBuffer(offset: i64, buffer: ?*anyopaque, size: usize, token: ?*anyopaque) callconv(.c) c_int {
        const bytes: *const []const u8 = @ptrCast(@alignCast(token.?));
        const start = std.math.cast(usize, offset) orelse return 1;
        if (start > bytes.len or size > bytes.len - start) return 1;
        @memcpy(@as([*]u8, @ptrCast(buffer.?))[0..size], bytes.*[start..][0..size]);
        return 0;
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
        return s.eos or s.media_pos >= s.end;
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const s = d.state;
        const channels: usize = s.info.channels;
        const want = out.len / channels;
        var n: usize = 0;
        while (n < want) {
            if (s.err) |e| {
                if (n > 0) break;
                return e;
            }
            if (s.pcm_used < s.pcm_len) {
                const k = @min(want - n, s.pcm_len - s.pcm_used);
                sample.decode(T, out[n * channels ..][0 .. k * channels], s.pcm[s.pcm_used * s.frame_bytes ..][0 .. k * s.frame_bytes], s.layout);
                s.pcm_used += k;
                s.media_pos += k;
                n += k;
                continue;
            }
            if (s.eos or s.media_pos >= s.end or s.next >= s.samples) {
                s.eos = true;
                break;
            }
            decodeNext(s) catch |err| {
                s.err = err;
            };
        }
        return n;
    }

    /// Decodes sample `next` into `pcm` and sets the window to the part inside the presentation.
    fn decodeNext(s: *State) Error!void {
        const k = s.next;
        s.next += 1;
        const t: u64 = s.timestamps[k];
        const duration: u64 = s.durations[k];
        // A packet that decoded short leaves a gap; its missing frames are simply not output.
        if (s.media_pos < t) s.media_pos = t;
        if (t + duration <= s.media_pos) return;
        const packet = try readPacket(s, k) orelse {
            s.eos = true;
            return;
        };
        const channels = s.info.channels;
        const frames = s.codec.decode(packet, s.pcm, s.codec.config.frameLength, channels) catch return error.InvalidFile;
        const valid = @min(frames, duration);
        const lo: usize = @intCast(s.media_pos - t);
        const hi: usize = @intCast(@min(valid, s.end - t));
        if (lo >= hi) return;
        if (channels > 2) remap(s.pcm[lo * s.frame_bytes .. hi * s.frame_bytes], alac_order[channels - 1], s.frame_bytes / channels);
        s.pcm_used = lo;
        s.pcm_len = hi;
    }

    /// Bitstream channel order -> canonical, in place.
    fn remap(pcm: []u8, order: []const u8, sample_bytes: usize) void {
        const frame_bytes = order.len * sample_bytes;
        var tmp: [8 * 4]u8 = undefined;
        var i: usize = 0;
        while (i < pcm.len) : (i += frame_bytes) {
            const frame = pcm[i..][0..frame_bytes];
            @memcpy(tmp[0..frame_bytes], frame);
            for (order, 0..) |dst, src| @memcpy(frame[dst * sample_bytes ..][0..sample_bytes], tmp[src * sample_bytes ..][0..sample_bytes]);
        }
    }

    /// Reads sample `k`'s bytes; null when the source ends before them (truncated file).
    fn readPacket(s: *State, k: u32) Error!?[]const u8 {
        var size: c_uint = 0;
        const offset = c.MP4D_frame_offset(&s.mp4, s.track, k, &size, null, null);
        // An uncompressed ALAC frame plus headers; anything bigger is damage.
        const max = s.codec.config.frameLength * s.frame_bytes + 64;
        if (size == 0 or size > max) return error.InvalidFile;
        if (s.packet.len < size) {
            s.gpa.free(s.packet);
            s.packet = &.{};
            s.packet = try s.gpa.alloc(u8, max);
        }
        if (offset != s.pos) {
            if (s.seeker) |sk| {
                if (offset + size > try sk.size(sk.context)) return null;
                try sk.seekTo(sk.context, offset);
            } else {
                if (offset < s.pos) return error.NotSeekable;
                s.reader.discardAll64(offset - s.pos) catch |err| return switch (err) {
                    error.EndOfStream => null,
                    error.ReadFailed => error.ReadFailed,
                };
            }
            s.pos = offset;
        }
        const buf = s.packet[0..size];
        s.reader.readSliceAll(buf) catch |err| return switch (err) {
            error.EndOfStream => null,
            error.ReadFailed => error.ReadFailed,
        };
        s.pos += size;
        return buf;
    }

    /// Sample exact: ALAC packets decode independently.
    pub fn seek(d: *Decoder, frame: u64) Error!void {
        const s = d.state;
        if (s.seeker == null) return error.NotSeekable;
        if (frame > s.info.frames.?) return error.SeekOutOfRange;
        const target = s.start + frame;
        // Last sample starting at or before the target.
        const Ctx = struct {
            fn order(t: u64, ts: c_uint) std.math.Order {
                return std.math.order(t, ts);
            }
        };
        const after = std.sort.upperBound(c_uint, s.timestamps[0..s.samples], target, Ctx.order);
        s.next = @intCast(after -| 1);
        s.media_pos = target;
        s.pcm_used = 0;
        s.pcm_len = 0;
        s.err = null;
        s.eos = false;
    }
};

// --- Encoder ---

pub const Encoder = struct {
    state: *State,

    const frame_size = alac.default_frame_size;

    const State = struct {
        gpa: Allocator,
        writer: *std.Io.Writer,
        seeker: Seeker,
        mux: ?*c.MP4E_mux_t = null,
        codec: alac.Encoder = undefined,
        format: root.SampleFormat,
        channels: u16,
        rate: u32,
        layout: sample.Layout,
        /// One packet of input, bitstream channel order, native endian.
        input: []align(4) u8 = &.{},
        input_frames: u32 = 0,
        packet: []u8 = &.{},
        udta: []u8 = &.{},
        frames: u64 = 0,
        bytes: u64 = 0,
        /// Writer offset and the furthest byte written.
        pos: u64 = 0,
        end: u64 = 0,
        err: ?Error = null,
        /// In MP4E_close: its last write is the moov box, which gets our udta appended.
        finishing: bool = false,
        /// deinit without finish: MP4E_close still writes the index; drop it.
        closing: bool = false,

        fn fail(s: *State, fallback: Error) Error {
            return s.err orelse fallback;
        }

        fn writeAt(s: *State, offset: u64, bytes: []const u8) Error!void {
            if (offset != s.pos) {
                const target = @min(offset, s.end);
                if (target != s.pos) try s.seeker.seekTo(s.seeker.context, target);
                s.pos = target;
                // MP4E reserves 8 bytes in front of mdat that it only writes at the end.
                try s.writer.splatByteAll(0, @intCast(offset - target));
                s.pos = offset;
            }
            if (s.finishing and bytes.len >= 8 and std.mem.eql(u8, bytes[4..8], "moov")) {
                var head = bytes[0..8].*;
                const size = std.math.add(u32, std.mem.readInt(u32, head[0..4], .big), @intCast(s.udta.len)) catch return error.FileTooLarge;
                std.mem.writeInt(u32, head[0..4], size, .big);
                try s.writer.writeAll(&head);
                try s.writer.writeAll(bytes[8..]);
                try s.writer.writeAll(s.udta);
                s.pos += bytes.len + s.udta.len;
            } else {
                try s.writer.writeAll(bytes);
                s.pos += bytes.len;
            }
            s.end = @max(s.end, s.pos);
        }

        fn encodePacket(s: *State) Error!void {
            const frames = s.input_frames;
            if (s.frames + frames > std.math.maxInt(u32)) return error.FileTooLarge; // 32-bit durations in MP4E
            var format = std.mem.zeroes(alac.AudioFormatDescription);
            format.mChannelsPerFrame = s.channels;
            format.mBytesPerPacket = @as(u32, s.channels) * sample.size(s.layout.format);
            const len = s.codec.encode(format, s.input[0 .. frames * format.mBytesPerPacket], s.packet) catch unreachable; // sizes are ours
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            if (c.MP4E_put_sample(s.mux.?, 0, s.packet.ptr, @intCast(len), @intCast(frames), c.MP4E_SAMPLE_RANDOM_ACCESS) != c.MP4E_STATUS_OK)
                return s.fail(error.OutOfMemory);
            s.frames += frames;
            s.bytes += len;
            s.input_frames = 0;
        }
    };

    /// sample_format i16/i24/i32 -> 16/24/32-bit ALAC (ponytail: 20-bit would need an i20 format).
    /// quality < 0.5 selects the encoder's fast mode (stereo only; ALAC is lossless either way).
    /// Channels 1..8 in ALAC's own layouts (null = that layout). Needs a seeker (moov at the end).
    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: root.Encoder.Options) Error!Encoder {
        const seeker = options.seeker orelse return error.NotSeekable;
        const flags: u32, const format: sample.Layout = switch (options.sample_format) {
            .i16 => .{ 1, alacLayout(16) },
            .i24 => .{ 3, alacLayout(24) },
            .i32 => .{ 4, alacLayout(32) },
            else => return error.UnsupportedFormat,
        };
        if (options.channels > 8) return error.UnsupportedFormat;
        if (options.channel_layout) |l| if (l.mask() != alac_layouts[options.channels - 1].mask()) return error.UnsupportedFormat;
        const fast = if (options.quality) |q| blk: {
            if (!(q >= 0 and q <= 1)) return error.InvalidOptions;
            break :blk q < 0.5;
        } else false;

        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .writer = writer,
            .seeker = seeker,
            .format = options.sample_format,
            .channels = options.channels,
            .rate = options.sample_rate,
            .layout = format,
        };
        s.udta = try buildUdta(gpa, options.tags);
        errdefer gpa.free(s.udta);
        var description = std.mem.zeroes(alac.AudioFormatDescription);
        description.mSampleRate = @floatFromInt(options.sample_rate);
        description.mFormatFlags = flags;
        description.mChannelsPerFrame = options.channels;
        s.codec = alac.Encoder.init(gpa, description, frame_size, fast) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidParameter => error.InvalidOptions,
        };
        errdefer s.codec.deinit(gpa);
        s.input = try gpa.alignedAlloc(u8, .@"4", frame_size * @as(usize, options.channels) * sample.size(format.format));
        errdefer gpa.free(s.input);
        s.packet = try gpa.alloc(u8, s.codec.max_output_bytes);
        errdefer gpa.free(s.packet);

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        s.mux = c.MP4E_open(0, 0, s, onWrite) orelse return s.fail(error.OutOfMemory);
        errdefer {
            s.closing = true;
            _ = c.MP4E_close(s.mux.?);
        }
        const track: c.MP4E_track_t = .{
            .object_type_indication = c.MP4_OBJECT_TYPE_ALAC,
            .language = "und\x00".*,
            .track_media_kind = c.e_audio,
            .time_scale = options.sample_rate,
            .default_duration = 0,
            .u = .{ .a = .{ .channelcount = options.channels } },
        };
        if (c.MP4E_add_track(s.mux.?, &track) < 0) return error.OutOfMemory;
        return .{ .state = s };
    }

    pub fn deinit(e: *Encoder) void {
        const s = e.state;
        if (s.mux) |mux| {
            s.closing = true;
            const prev = c_allocator.set(s.gpa);
            _ = c.MP4E_close(mux);
            c_allocator.restore(prev);
        }
        s.codec.deinit(s.gpa);
        s.gpa.free(s.input);
        s.gpa.free(s.packet);
        s.gpa.free(s.udta);
        s.gpa.destroy(s);
    }

    pub fn write(e: *Encoder, comptime T: type, samples: []const T) Error!void {
        const s = e.state;
        const channels: usize = s.channels;
        std.debug.assert(samples.len % channels == 0);
        if (s.err) |err| return err;
        const order = alac_order[channels - 1];
        const n = sample.size(s.layout.format);
        var i: usize = 0;
        while (i < samples.len) : (i += channels) {
            const frame = samples[i..][0..channels];
            const dst = s.input[s.input_frames * channels * n ..][0 .. channels * n];
            for (order, 0..) |src, ch| switch (s.layout.format) {
                inline .i16, .i24, .i32 => |f| {
                    const S = switch (f) {
                        .i16 => i16,
                        .i24 => i24,
                        else => i32,
                    };
                    std.mem.writeInt(S, dst[ch * n ..][0 .. @bitSizeOf(S) / 8], sample.convert(S, frame[src]), native);
                },
                else => unreachable,
            };
            s.input_frames += 1;
            if (s.input_frames == frame_size) s.encodePacket() catch |err| {
                s.err = err;
                return err;
            };
        }
    }

    /// Every finished packet is already written; this pushes the writer.
    pub fn flush(e: *Encoder) Error!void {
        try e.state.writer.flush();
    }

    pub fn finish(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        if (s.input_frames > 0) try s.encodePacket();
        var cookie: [48]u8 = undefined;
        const len = s.codec.getMagicCookie(&cookie);
        if (s.frames > 0) {
            const bitrate = s.bytes * 8 * s.rate / s.frames;
            std.mem.writeInt(u32, cookie[16..20], std.math.cast(u32, bitrate) orelse std.math.maxInt(u32), .big);
        }
        const prev = c_allocator.set(s.gpa);
        defer c_allocator.restore(prev);
        if (c.MP4E_set_dsi(s.mux.?, 0, &cookie, @intCast(len)) != c.MP4E_STATUS_OK) return error.OutOfMemory;
        s.finishing = true;
        const status = c.MP4E_close(s.mux.?);
        s.mux = null;
        if (status != c.MP4E_STATUS_OK) return s.fail(error.OutOfMemory);
        try s.writer.flush();
        try s.seeker.seekTo(s.seeker.context, s.end);
    }

    fn onWrite(offset: i64, buffer: ?*const anyopaque, size: usize, token: ?*anyopaque) callconv(.c) c_int {
        const s: *State = @ptrCast(@alignCast(token.?));
        if (s.closing) return 0;
        const bytes = @as([*]const u8, @ptrCast(buffer.?))[0..size];
        s.writeAt(@intCast(offset), bytes) catch |err| {
            s.err = err;
            return 1;
        };
        return 0;
    }
};
