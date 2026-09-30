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
//! Codecs: ALAC (alac.zig) and AAC (aac.zig, fdk-aac). AAC gapless: the edit list, else
//! iTunes' iTunSMPB (priming, padding, length); our encoder writes an edit list (media_time =
//! encoder delay) and shortens the last sample's duration, so the stts total is exact too.

const std = @import("std");
const root = @import("root.zig");
const sample = @import("sample.zig");
const alac = @import("alac.zig");
const aac = @import("aac.zig");
const id3 = @import("id3.zig");
const c_allocator = @import("c_allocator.zig");
const c = @import("zig-c-headers/minimp4.zig");
const build_options = @import("build_options");

/// A codec left out of the build (-Daac=false / -Dalac=false): never active, see root.zig.
fn On(comptime on: bool, comptime T: type) type {
    return if (on) T else noreturn;
}

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
    /// Header length: the header sits right in front of `body`.
    header: u8 = 8,

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
        return .{ .type = r[4..8].*, .body = r[header..len], .header = @intCast(header) };
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

/// iTunes' gapless info: ilst '----' item "iTunSMPB", text " 00000000 <priming> <padding>
/// <length> ..." in hex, media timescale units.
const Smpb = struct { delay: u64, length: u64 };

fn itunSmpb(moov: []const u8) ?Smpb {
    const meta = Boxes.path(moov, &.{ "udta", "meta" }) orelse return null;
    const children = if (meta.len >= 8 and std.mem.eql(u8, meta[4..8], "hdlr")) meta else if (meta.len >= 4) meta[4..] else return null;
    const ilst = Boxes.find(children, "ilst") orelse return null;
    var it: Boxes = .{ .rest = ilst };
    while (it.next()) |item| {
        if (!item.is("----")) continue;
        const name = Boxes.find(item.body, "name") orelse continue;
        if (name.len < 4 or !std.ascii.eqlIgnoreCase(name[4..], "iTunSMPB")) continue;
        const data = Boxes.find(item.body, "data") orelse return null;
        if (data.len < 8) return null;
        var fields = std.mem.tokenizeScalar(u8, data[8..], ' ');
        _ = fields.next() orelse return null;
        const delay = std.fmt.parseInt(u64, fields.next() orelse return null, 16) catch return null;
        _ = fields.next() orelse return null; // padding: implied by the length
        const length = std.fmt.parseInt(u64, fields.next() orelse return null, 16) catch return null;
        return .{ .delay = delay, .length = length };
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
    .{ "\xa9nam", "title" },     .{ "\xa9ART", "artist" },   .{ "\xa9alb", "album" },
    .{ "aART", "album_artist" }, .{ "\xa9day", "date" },     .{ "\xa9gen", "genre" },
    .{ "\xa9cmt", "comment" },   .{ "\xa9wrt", "composer" }, .{ "cprt", "copyright" },
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

    const Codec = union(enum) {
        alac: On(build_options.alac, alac.Decoder),
        aac: On(build_options.aac, aac.Codec),
    };

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
        /// Output frames per media timescale unit: 2 for HE-AAC with the core rate as timescale.
        scale: u32 = 1,
        codec: Codec = undefined,
        /// AAC: the format of the first access unit; a change is UnsupportedFormat.
        format: aac.Format = undefined,
        layout: sample.Layout = undefined,
        frame_bytes: usize = 0,
        /// Largest valid packet.
        max_packet: usize = 0,
        /// Source offset of the reader.
        pos: u64 = 0,
        packet: []u8 = &.{},
        /// One decoded packet, canonical channel order; frames [pcm_used, pcm_len) not read yet.
        pcm: []align(4) u8 = &.{},
        pcm_used: usize = 0,
        pcm_len: usize = 0,
        next: u32 = 0,
        /// Media time (output frames) of the next frame to output; the presentation is [start, end).
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
            s.gpa.free(s.packet);
            s.gpa.free(s.pcm);
        }

        fn deinitCodec(s: *State) void {
            switch (s.codec) {
                .alac => |*a| a.deinit(s.gpa),
                .aac => |*a| a.close(s.gpa),
            }
        }

        fn timestamp(s: *const State, k: u32) u64 {
            return @as(u64, s.timestamps[k]) * s.scale;
        }

        fn duration(s: *const State, k: u32) u64 {
            return @as(u64, s.durations[k]) * s.scale;
        }
    };

    pub fn open(gpa: Allocator, arena: Allocator, reader: *std.Io.Reader, seeker: ?Seeker, tag_mode: root.TagMode) Error!Decoder {
        var pos: u64 = 0;
        const moov = try readMoov(gpa, reader, seeker, &pos);
        defer gpa.free(moov);
        var top: Boxes = .{ .rest = moov };
        const moov_body = top.next().?.body;
        const track = findTrack(moov_body) orelse return error.InvalidFile;
        const is_alac = std.mem.eql(u8, &track.entry, "alac");
        if (!is_alac and !std.mem.eql(u8, &track.entry, "mp4a")) return error.UnsupportedFormat;

        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .reader = reader,
            .seeker = seeker,
            .pos = pos,
            .info = .{
                .container = .m4a,
                .codec = if (is_alac) .alac else .aac,
                .sample_rate = 0,
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
        errdefer {
            gpa.free(s.packet);
            gpa.free(s.pcm);
        }
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

        // The codec: output format, scale, pcm buffer. AAC decodes the first packet here.
        var first_frames: ?usize = null;
        if (is_alac) {
            if (!build_options.alac) return error.UnsupportedFormat;
            const cookie = alac.Decoder.unwrap(track.cookie); // the bytes init reads
            if (cookie.len < 24) return error.InvalidFile;
            const channels = cookie[9];
            const bit_depth = cookie[5];
            const frame_length = std.mem.readInt(u32, cookie[0..4], .big);
            const rate = std.mem.readInt(u32, cookie[20..24], .big);
            if (channels == 0 or channels > 8 or frame_length == 0 or frame_length > max_alac_frame or rate == 0) return error.InvalidFile;
            // ponytail: stts durations are taken as frames; other timescales would need rescaling.
            if (rate != track.timescale) return error.UnsupportedFormat;
            s.info.sample_rate = rate;
            s.info.channels = channels;
            s.info.channel_layout = alac_layouts[channels - 1];
            s.info.bits_per_sample = bit_depth;
            s.codec = .{ .alac = alac.Decoder.init(gpa, track.cookie) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidParameter => error.InvalidFile,
            } };
            errdefer s.deinitCodec();
            s.layout = alacLayout(bit_depth);
            s.frame_bytes = @as(usize, sample.size(s.layout.format)) * channels;
            s.max_packet = frame_length * s.frame_bytes + 64; // an uncompressed frame plus headers
            s.pcm = try gpa.alignedAlloc(u8, .@"4", frame_length * s.frame_bytes);
        } else {
            // MPEG-4 audio, or MPEG-2 AAC main / LC / SSR; all with an AudioSpecificConfig.
            switch (tr.object_type_indication) {
                c.MP4_OBJECT_TYPE_AUDIO_ISO_IEC_14496_3,
                c.MP4_OBJECT_TYPE_AUDIO_ISO_IEC_13818_7_MAIN_PROFILE,
                c.MP4_OBJECT_TYPE_AUDIO_ISO_IEC_13818_7_LC_PROFILE,
                c.MP4_OBJECT_TYPE_AUDIO_ISO_IEC_13818_7_SSR_PROFILE,
                => {},
                else => return error.UnsupportedFormat,
            }
            if (!build_options.aac) return error.UnsupportedFormat;
            const dsi = (tr.dsi orelse return error.InvalidFile)[0..tr.dsi_bytes];
            s.codec = .{ .aac = try aac.Codec.open(gpa, dsi) };
            errdefer s.deinitCodec();
            s.layout = .{ .format = .i16, .endian = native };
            s.pcm = try gpa.alignedAlloc(u8, .@"4", aac.max_frame * aac.max_channels * 2);
            s.max_packet = aac.max_frame * aac.max_channels * 2;
            if (s.samples == 0) return error.InvalidFile; // no packet to learn the format from
            const packet = try readPacket(s, 0) orelse return error.InvalidFile;
            s.format = try s.codec.aac.decode(gpa, packet, std.mem.bytesAsSlice(i16, s.pcm));
            first_frames = s.format.frame_size;
            s.info.sample_rate = s.format.rate;
            s.info.channels = s.format.channels;
            s.info.channel_layout = s.format.layout;
            s.frame_bytes = 2 * @as(usize, s.format.channels);
            // HE-AAC files may count time at the core rate (afconvert).
            s.scale = if (s.format.rate == track.timescale) 1 else if (s.format.rate == 2 * track.timescale) 2 else return error.UnsupportedFormat;
        }
        errdefer s.deinitCodec();

        total *= s.scale;
        s.end = total;
        if (track.edit) |e| {
            s.start = @min(e.media_time * s.scale, total);
            // The edit's duration is in the movie timescale (often 1/1000 s), so it only trims
            // when it is shorter than the media by more than its own rounding.
            const avail = total - s.start;
            const length = std.math.cast(u64, std.math.mulWide(u64, e.duration, s.info.sample_rate) / e.movie_timescale) orelse avail;
            const slack = std.math.divCeil(u32, s.info.sample_rate, e.movie_timescale) catch unreachable; // timescale > 0: firstEdit
            if (length +| slack <= avail) s.end = s.start + length;
        } else if (!is_alac) {
            if (itunSmpb(moov_body)) |g| {
                s.start = @min(g.delay * s.scale, total);
                if (g.length > 0) s.end = s.start + @min(g.length * s.scale, total - s.start);
            }
        }
        if (!is_alac) {
            // The edit / iTunSMPB count from an ideal decoder's output; fdk's lags by `delay`
            // and runs to the end of the last access unit.
            const avail = @max(total, s.timestamp(s.samples - 1) + s.format.frame_size);
            s.start = @min(s.start + s.format.delay, avail);
            s.end = @min(s.end + s.format.delay, avail);
        }
        s.info.frames = s.end - s.start;
        s.media_pos = s.start;
        if (first_frames) |n| {
            s.next = 1;
            window(s, 0, n);
        }
        s.info.tags = try parseTags(arena, moov_body, tag_mode);
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
        d.state.deinitCodec();
        d.state.deinit();
        d.state.gpa.destroy(d.state);
    }

    pub fn info(d: *const Decoder) *const root.Info {
        return &d.state.info;
    }

    pub fn ended(d: *const Decoder) bool {
        const s = d.state;
        return s.pcm_used == s.pcm_len and (s.eos or s.media_pos >= s.end);
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const s = d.state;
        const channels: usize = s.info.channels;
        const want = out.len / channels;
        var n: usize = 0;
        while (n < want) {
            if (s.pcm_used < s.pcm_len) {
                const k = @min(want - n, s.pcm_len - s.pcm_used);
                sample.decode(T, out[n * channels ..][0 .. k * channels], s.pcm[s.pcm_used * s.frame_bytes ..][0 .. k * s.frame_bytes], s.layout);
                s.pcm_used += k;
                s.media_pos += k;
                n += k;
                continue;
            }
            if (s.err) |e| {
                if (n > 0) break;
                return e;
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
        const t = s.timestamp(k);
        // A packet that decoded short leaves a gap; its missing frames are simply not output.
        if (s.media_pos < t) s.media_pos = t;
        // ALAC packets before the position are skipped; AAC ones are decoded (priming, pre-roll).
        if (s.codec == .alac and t + s.duration(k) <= s.media_pos) return;
        const packet = try readPacket(s, k) orelse {
            s.eos = true;
            return;
        };
        const frames: usize = switch (s.codec) {
            .alac => |*a| a.decode(packet, s.pcm, a.config.frameLength, s.info.channels) catch return error.InvalidFile,
            .aac => |*a| blk: {
                const f = try a.decode(s.gpa, packet, std.mem.bytesAsSlice(i16, s.pcm));
                if (!f.eql(s.format)) return error.UnsupportedFormat;
                break :blk f.frame_size;
            },
        };
        window(s, k, frames);
    }

    /// The part of packet `k`'s `frames` output inside the presentation, from media_pos on.
    fn window(s: *State, k: u32, frames: usize) void {
        const t = s.timestamp(k);
        // An AAC access unit always yields a whole frame; the last one's stts duration may
        // be cut short of fdk's own decoder delay (our encoder, see Encoder.State.release).
        const valid = if (s.codec == .aac) frames else @min(frames, s.duration(k));
        if (s.media_pos < t) s.media_pos = t;
        const lo: usize = @intCast(@min(s.media_pos - t, valid));
        const hi: usize = @intCast(@min(valid, s.end -| t));
        if (lo >= hi) return;
        const channels = s.info.channels;
        if (s.codec == .alac and channels > 2) remap(s.pcm[lo * s.frame_bytes .. hi * s.frame_bytes], alac_order[channels - 1], s.frame_bytes / channels);
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
        if (size == 0 or size > s.max_packet) return error.InvalidFile;
        if (s.packet.len < size) {
            s.gpa.free(s.packet);
            s.packet = &.{};
            s.packet = try s.gpa.alloc(u8, s.max_packet);
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

    /// Sample exact position. ALAC packets decode independently: same samples as a linear read.
    /// AAC decodes `Format.preroll` packets before the target first (MDCT overlap, SBR state).
    pub fn seek(d: *Decoder, frame: u64) Error!void {
        const s = d.state;
        if (s.seeker == null) return error.NotSeekable;
        if (frame > s.info.frames.?) return error.SeekOutOfRange;
        const target = s.start + frame;
        // Last sample starting at or before the target.
        const Ctx = struct {
            target: u64,
            scale: u32,
            fn order(ctx: @This(), ts: c_uint) std.math.Order {
                return std.math.order(ctx.target, @as(u64, ts) * ctx.scale);
            }
        };
        const after = std.sort.upperBound(c_uint, s.timestamps[0..s.samples], Ctx{ .target = target, .scale = s.scale }, Ctx.order);
        s.next = @intCast(after -| 1);
        if (s.codec == .aac) {
            s.next -|= s.format.preroll();
            s.codec.aac.reset();
        }
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

    const Alac = struct {
        codec: alac.Encoder,
        layout: sample.Layout,
        /// One packet of input, bitstream channel order, native endian.
        input: []align(4) u8,
        input_frames: u32 = 0,
        packet: []u8,
    };

    /// fdk's access units are held until they are known not to be the last one (its duration is
    /// cut to the end of the audio) or past the end (flush padding: dropped).
    const Aac = struct {
        enc: aac.Enc,
        held: std.ArrayList(u8) = .empty,
        held_sizes: std.ArrayList(u32) = .empty,
        /// Access units passed to MP4E.
        muxed: u64 = 0,
    };

    const State = struct {
        gpa: Allocator,
        writer: *std.Io.Writer,
        seeker: Seeker,
        mux: ?*c.MP4E_mux_t = null,
        codec: union(enum) { alac: On(build_options.alac, Alac), aac: On(build_options.aac, Aac) },
        channels: u16,
        rate: u32,
        udta: []u8 = &.{},
        /// Input frames.
        frames: u64 = 0,
        bytes: u64 = 0,
        /// Writer offset and the furthest byte written.
        pos: u64 = 0,
        end: u64 = 0,
        err: ?Error = null,
        /// In MP4E_close: its last write is the moov box, which gets our edts and udta.
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
                const moov = try s.finalMoov(bytes);
                defer s.gpa.free(moov);
                try s.writer.writeAll(moov);
                s.pos += moov.len;
            } else {
                try s.writer.writeAll(bytes);
                s.pos += bytes.len;
            }
            s.end = @max(s.end, s.pos);
        }

        /// MP4E's moov + our udta, and for AAC an edit list in front of the trak's mdia:
        /// media_time = encoder delay, duration = the input length. The stts can't carry the
        /// length (HE: the AUs cover fdk's decoder delay too, see `release`), so the movie
        /// timescale becomes the sample rate (MP4E's is 1000) and the edit is exact.
        fn finalMoov(s: *State, moov: []const u8) Error![]u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(s.gpa);
            try out.appendSlice(s.gpa, moov[0..8]);
            const length = std.math.cast(u32, s.frames) orelse return error.FileTooLarge;
            var it: Boxes = .{ .rest = moov[8..] };
            while (it.next()) |b| {
                const start = out.items.len;
                if (s.codec == .aac and b.is("mvhd") and b.body.len >= 20) {
                    try appendBox(s.gpa, &out, b);
                    const body = out.items[start + b.header ..];
                    std.mem.writeInt(u32, body[12..16], s.rate, .big);
                    std.mem.writeInt(u32, body[16..20], length, .big);
                } else if (s.codec == .aac and b.is("trak")) {
                    try out.appendSlice(s.gpa, &.{ 0, 0, 0, 0, 't', 'r', 'a', 'k' });
                    var children: Boxes = .{ .rest = b.body };
                    while (children.next()) |child| {
                        if (child.is("mdia")) try s.appendEdts(&out);
                        const at = out.items.len;
                        try appendBox(s.gpa, &out, child);
                        if (child.is("tkhd") and child.body.len >= 24)
                            std.mem.writeInt(u32, out.items[at + child.header ..][20..24], length, .big);
                    }
                    std.mem.writeInt(u32, out.items[start..][0..4], std.math.cast(u32, out.items.len - start) orelse return error.FileTooLarge, .big);
                } else {
                    try appendBox(s.gpa, &out, b);
                }
            }
            try out.appendSlice(s.gpa, s.udta);
            std.mem.writeInt(u32, out.items[0..4], std.math.cast(u32, out.items.len) orelse return error.FileTooLarge, .big);
            return out.toOwnedSlice(s.gpa);
        }

        fn appendEdts(s: *State, out: *std.ArrayList(u8)) Error!void {
            const a = &s.codec.aac;
            const duration = std.math.cast(u32, s.frames) orelse return error.FileTooLarge; // movie timescale = rate
            var edts: [36]u8 = undefined;
            std.mem.writeInt(u32, edts[0..4], 36, .big);
            @memcpy(edts[4..8], "edts");
            std.mem.writeInt(u32, edts[8..12], 28, .big);
            @memcpy(edts[12..16], "elst");
            std.mem.writeInt(u32, edts[16..20], 0, .big); // version, flags
            std.mem.writeInt(u32, edts[20..24], 1, .big); // entries
            std.mem.writeInt(u32, edts[24..28], duration, .big);
            std.mem.writeInt(u32, edts[28..32], a.enc.delay, .big);
            std.mem.writeInt(u32, edts[32..36], 0x00010000, .big); // rate 1.0
            try out.appendSlice(s.gpa, &edts);
        }

        fn encodePacket(s: *State) Error!void {
            const a = &s.codec.alac;
            const frames = a.input_frames;
            if (s.frames + frames > std.math.maxInt(u32)) return error.FileTooLarge; // 32-bit durations in MP4E
            var format = std.mem.zeroes(alac.AudioFormatDescription);
            format.mChannelsPerFrame = s.channels;
            format.mBytesPerPacket = @as(u32, s.channels) * sample.size(a.layout.format);
            const len = a.codec.encode(format, a.input[0 .. frames * format.mBytesPerPacket], a.packet) catch unreachable; // sizes are ours
            try s.put(a.packet[0..len], frames);
            s.frames += frames;
            a.input_frames = 0;
        }

        fn put(s: *State, bytes: []const u8, duration: u32) Error!void {
            const prev = c_allocator.set(s.gpa);
            defer c_allocator.restore(prev);
            if (c.MP4E_put_sample(s.mux.?, 0, bytes.ptr, @intCast(bytes.len), @intCast(duration), c.MP4E_SAMPLE_RANDOM_ACCESS) != c.MP4E_STATUS_OK)
                return s.fail(error.OutOfMemory);
            s.bytes += bytes.len;
        }

        /// aac.Enc sink.
        pub fn packet(s: *State, bytes: []const u8) Error!void {
            const a = &s.codec.aac;
            try a.held.appendSlice(s.gpa, bytes);
            try a.held_sizes.append(s.gpa, @intCast(bytes.len));
            try s.release(null);
        }

        /// Muxes held access units: with `total` (finish) all up to the end of the audio in
        /// fdk's own output (encoder + SBR decoder delay), the last one's duration cut so the
        /// stts ends where the audio does for an ideal decoder (can be 0 for HE); else those
        /// that are surely not the last (`frames` only grows).
        fn release(s: *State, total: ?u64) Error!void {
            const a = &s.codec.aac;
            const fl: u64 = a.enc.frame_length;
            const lag: u64 = a.enc.delay + a.enc.decoder_delay;
            const needed = if (total) |t| (lag + t + fl - 1) / fl else 0;
            var used: usize = 0;
            var n: usize = 0;
            for (a.held_sizes.items) |size| {
                const i = a.muxed;
                const duration = if (total) |t| blk: {
                    if (i >= needed) break;
                    break :blk if (i + 1 == needed) @min((a.enc.delay + t) -| i * fl, fl) else fl;
                } else blk: {
                    if ((i + 1) * fl >= lag + s.frames) break;
                    break :blk fl;
                };
                if (lag + s.frames + fl > std.math.maxInt(u32)) return error.FileTooLarge; // 32-bit durations in MP4E
                try s.put(a.held.items[used..][0..size], @intCast(duration));
                used += size;
                n += 1;
                a.muxed += 1;
            }
            if (total != null) {
                a.held.clearRetainingCapacity();
                a.held_sizes.clearRetainingCapacity();
                return;
            }
            a.held.replaceRangeAssumeCapacity(0, used, &.{});
            a.held_sizes.replaceRangeAssumeCapacity(0, n, &.{});
        }
    };

    fn appendBox(gpa: Allocator, out: *std.ArrayList(u8), b: Box) Allocator.Error!void {
        try out.appendSlice(gpa, (b.body.ptr - b.header)[0 .. b.header + b.body.len]);
    }

    /// ALAC: sample_format i16/i24/i32 -> 16/24/32-bit (ponytail: 20-bit would need an i20
    /// format); quality < 0.5 selects the encoder's fast mode (stereo only; lossless either way).
    /// Channels 1..8 in ALAC's own layouts (null = that layout).
    /// AAC: see aac.Enc; channels 1..8 in AAC's layouts (aac.layouts, null = that layout).
    /// Needs a seeker (moov at the end).
    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: root.Encoder.Options) Error!Encoder {
        const seeker = options.seeker orelse return error.NotSeekable;
        const is_aac = (options.codec orelse .aac) == .aac;
        if (options.channels > 8) return error.UnsupportedFormat;

        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .writer = writer,
            .seeker = seeker,
            .channels = options.channels,
            .rate = options.sample_rate,
            .codec = undefined,
        };
        if (is_aac) {
            if (!build_options.aac) return error.UnsupportedFormat;
            s.codec = .{ .aac = .{ .enc = try aac.Enc.open(gpa, options, false) } };
        } else {
            if (!build_options.alac) return error.UnsupportedFormat;
            s.codec = .{ .alac = try openAlac(gpa, options) };
        }
        errdefer deinitCodec(s);
        s.udta = try buildUdta(gpa, options.tags);
        errdefer gpa.free(s.udta);

        const prev = c_allocator.set(gpa);
        defer c_allocator.restore(prev);
        s.mux = c.MP4E_open(0, 0, s, onWrite) orelse return s.fail(error.OutOfMemory);
        errdefer {
            s.closing = true;
            _ = c.MP4E_close(s.mux.?);
        }
        const track: c.MP4E_track_t = .{
            .object_type_indication = if (is_aac) c.MP4_OBJECT_TYPE_AUDIO_ISO_IEC_14496_3 else c.MP4_OBJECT_TYPE_ALAC,
            .language = "und\x00".*,
            .track_media_kind = c.e_audio,
            .time_scale = options.sample_rate,
            .default_duration = 0,
            .u = .{ .a = .{ .channelcount = options.channels } },
        };
        if (c.MP4E_add_track(s.mux.?, &track) < 0) return error.OutOfMemory;
        if (is_aac) {
            const e = &s.codec.aac.enc;
            if (c.MP4E_set_dsi(s.mux.?, 0, &e.config, @intCast(e.config_len)) != c.MP4E_STATUS_OK) return error.OutOfMemory;
        }
        return .{ .state = s };
    }

    fn openAlac(gpa: Allocator, options: root.Encoder.Options) Error!Alac {
        const flags: u32, const format: sample.Layout = switch (options.sample_format) {
            .i16 => .{ 1, alacLayout(16) },
            .i24 => .{ 3, alacLayout(24) },
            .i32 => .{ 4, alacLayout(32) },
            else => return error.UnsupportedFormat,
        };
        if (options.channel_layout) |l| if (l.mask() != alac_layouts[options.channels - 1].mask()) return error.UnsupportedFormat;
        const fast = if (options.quality) |q| blk: {
            if (!(q >= 0 and q <= 1)) return error.InvalidOptions;
            break :blk q < 0.5;
        } else false;
        var description = std.mem.zeroes(alac.AudioFormatDescription);
        description.mSampleRate = @floatFromInt(options.sample_rate);
        description.mFormatFlags = flags;
        description.mChannelsPerFrame = options.channels;
        var codec = alac.Encoder.init(gpa, description, frame_size, fast) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidParameter => error.InvalidOptions,
        };
        errdefer codec.deinit(gpa);
        const input = try gpa.alignedAlloc(u8, .@"4", frame_size * @as(usize, options.channels) * sample.size(format.format));
        errdefer gpa.free(input);
        const packet_buf = try gpa.alloc(u8, codec.max_output_bytes);
        return .{ .codec = codec, .layout = format, .input = input, .packet = packet_buf };
    }

    fn deinitCodec(s: *State) void {
        switch (s.codec) {
            .alac => |*a| {
                a.codec.deinit(s.gpa);
                s.gpa.free(a.input);
                s.gpa.free(a.packet);
            },
            .aac => |*a| {
                a.enc.deinit();
                a.held.deinit(s.gpa);
                a.held_sizes.deinit(s.gpa);
            },
        }
    }

    pub fn deinit(e: *Encoder) void {
        const s = e.state;
        if (s.mux) |mux| {
            s.closing = true;
            const prev = c_allocator.set(s.gpa);
            _ = c.MP4E_close(mux);
            c_allocator.restore(prev);
        }
        deinitCodec(s);
        s.gpa.free(s.udta);
        s.gpa.destroy(s);
    }

    pub fn write(e: *Encoder, comptime T: type, samples: []const T) Error!void {
        const s = e.state;
        const channels: usize = s.channels;
        std.debug.assert(samples.len % channels == 0);
        if (s.err) |err| return err;
        writeCodec(s, T, samples) catch |err| {
            s.err = err;
            return err;
        };
    }

    fn writeCodec(s: *State, comptime T: type, samples: []const T) Error!void {
        const channels: usize = s.channels;
        switch (s.codec) {
            .aac => |*a| {
                // `frames` counts input before this call: a lower bound for `release`.
                try a.enc.write(T, samples, s);
                s.frames += samples.len / channels;
            },
            .alac => |*a| {
                const order = alac_order[channels - 1];
                const n = sample.size(a.layout.format);
                var i: usize = 0;
                while (i < samples.len) : (i += channels) {
                    const frame = samples[i..][0..channels];
                    const dst = a.input[a.input_frames * channels * n ..][0 .. channels * n];
                    for (order, 0..) |src, ch| switch (a.layout.format) {
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
                    a.input_frames += 1;
                    if (a.input_frames == frame_size) try s.encodePacket();
                }
            },
        }
    }

    /// Every finished packet is already written; this pushes the writer.
    pub fn flush(e: *Encoder) Error!void {
        try e.state.writer.flush();
    }

    pub fn finish(e: *Encoder) Error!void {
        const s = e.state;
        if (s.err) |err| return err;
        switch (s.codec) {
            .alac => |*a| {
                if (a.input_frames > 0) try s.encodePacket();
                var cookie: [48]u8 = undefined;
                const len = a.codec.getMagicCookie(&cookie);
                if (s.frames > 0) {
                    const bitrate = s.bytes * 8 * s.rate / s.frames;
                    std.mem.writeInt(u32, cookie[16..20], std.math.cast(u32, bitrate) orelse std.math.maxInt(u32), .big);
                }
                const prev = c_allocator.set(s.gpa);
                defer c_allocator.restore(prev);
                if (c.MP4E_set_dsi(s.mux.?, 0, &cookie, @intCast(len)) != c.MP4E_STATUS_OK) return error.OutOfMemory;
            },
            .aac => |*a| {
                a.enc.finish(s) catch |err| {
                    s.err = err;
                    return err;
                };
                try s.release(s.frames);
            },
        }
        const prev = c_allocator.set(s.gpa);
        defer c_allocator.restore(prev);
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
