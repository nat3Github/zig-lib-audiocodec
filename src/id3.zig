//! ID3 tags of mp3 files: ID3v2.2/2.3/2.4 in front of the audio, ID3v1/v1.1 at the end.
//!
//! Tolerant, bounds-checked parser: a malformed frame ends the frame loop, never the decode. The
//! tag header's size alone says where the audio starts (the rest of the tag is skipped), which is
//! also how dr_mp3 and ffmpeg skip it (size bytes masked to 7 bits, v2.4 footer counted).
//!
//! Frames read: text frames (T***, TXXX), COMM, APIC/PIC (pictures only with TagMode.all). Text
//! encodings ISO-8859-1, UTF-16 with BOM, UTF-16BE, UTF-8 -> UTF-8; values that are not valid
//! UTF-8 in a UTF-8 frame are dropped. Multiple values in one v2.4 text frame become separate tags.
//! Unsynchronisation: tag level (v2.2/2.3: whole tag, decoded in memory; v2.4: every frame) and
//! frame level (v2.4). Extended header skipped.
//!
//! Streaming: only frames that are kept are read into memory; `.text` skips pictures without
//! allocating them. ponytail: a v2.2/2.3 tag with tag-level unsynchronisation (rare, old iTunes) is
//! read whole into memory first, pictures included. Compressed / encrypted frames are skipped
//! (add zlib via std.compress.flate if they show up). An appended ID3v2 tag at the end ("3DI"
//! footer) and ID3v1 extended "TAG+" are not read.

const std = @import("std");
const root = @import("root.zig");
const pcm = @import("pcm.zig");

const Allocator = std.mem.Allocator;

pub const ReadError = error{ ReadFailed, EndOfStream, OutOfMemory };

pub const header_len = 10;
pub const v1_len = 128;

/// Tags as they are collected; `get` sees earlier tags (ID3v1 only fills what v2 left empty).
pub const List = struct {
    items: std.ArrayList(root.Tag) = .empty,
    pictures: std.ArrayList(root.Picture) = .empty,

    pub fn tags(l: List) root.Tags {
        return .{ .items = l.items.items, .pictures = l.pictures.items };
    }

    fn get(l: List, key: []const u8) ?[]const u8 {
        return (root.Tags{ .items = l.items.items }).get(key);
    }
};

pub fn isV2(bytes: []const u8) bool {
    return bytes.len >= 3 and std.mem.eql(u8, bytes[0..3], "ID3");
}

/// Reads the ID3v2 tag the reader is at ("ID3" checked by the caller) and returns the number of
/// bytes consumed: header, body and footer, whatever the tag contains. `gpa` is only used for a
/// v2.2/2.3 tag with tag-level unsynchronisation (temporary copy).
pub fn readV2(gpa: Allocator, arena: Allocator, r: *std.Io.Reader, mode: root.TagMode, list: *List) ReadError!u64 {
    const h = (try r.takeArray(header_len)).*;
    std.debug.assert(isV2(&h));
    const version = h[3];
    const flags = h[5];
    const size = syncsafe(h[6..10]);
    const footer: u32 = if (version == 4 and flags & 0x10 != 0) header_len else 0;
    const total = header_len + @as(u64, size) + footer;
    // v2.2 flag 0x40: compression without a defined scheme, the tag is to be ignored.
    if (mode == .none or version < 2 or version > 4 or (version == 2 and flags & 0x40 != 0)) {
        try r.discardAll64(size + footer);
        return total;
    }
    const tag: Tag = .{ .version = version, .unsync = flags & 0x80 != 0, .extended = version > 2 and flags & 0x40 != 0 };
    if (tag.unsync and version < 4) {
        // Frame sizes count the decoded bytes: decode the whole body first.
        const body = try readChunked(gpa, r, size);
        defer gpa.free(body);
        const decoded = removeUnsync(body);
        var fixed: std.Io.Reader = .fixed(decoded);
        var left: u32 = @intCast(decoded.len);
        try tag.frames(arena, &fixed, &left, mode, list);
        return total;
    }
    var left = size;
    try tag.frames(arena, r, &left, mode, list);
    try r.discardAll64(left + footer);
    return total;
}

/// ID3v1 / v1.1 (the last 128 bytes of the file, "TAG" checked here). Fields only fill keys the
/// ID3v2 tag did not set. Copies what it keeps into `arena`.
pub fn parseV1(arena: Allocator, bytes: *const [v1_len]u8, list: *List) Allocator.Error!void {
    if (!std.mem.eql(u8, bytes[0..3], "TAG")) return;
    const fields = [_]struct { []const u8, []const u8 }{
        .{ "title", bytes[3..33] },
        .{ "artist", bytes[33..63] },
        .{ "album", bytes[63..93] },
        .{ "date", bytes[93..97] },
        .{ "comment", if (bytes[125] == 0) bytes[97..125] else bytes[97..127] },
    };
    for (fields) |f| {
        const end = std.mem.indexOfScalar(u8, f[1], 0) orelse f[1].len;
        const text = std.mem.trimEnd(u8, f[1][0..end], " ");
        if (text.len > 0) try addV1(arena, list, f[0], try latin1(arena, try arena.dupe(u8, text)));
    }
    // v1.1: a zero byte before the last comment byte makes that byte the track number.
    if (bytes[125] == 0 and bytes[126] != 0) try addV1(arena, list, "track", try std.fmt.allocPrint(arena, "{d}", .{bytes[126]}));
    if (bytes[127] < genres.len) try addV1(arena, list, "genre", genres[bytes[127]]);
}

fn addV1(arena: Allocator, list: *List, key: []const u8, value: []const u8) Allocator.Error!void {
    if (list.get(key) == null) try list.items.append(arena, .{ .key = key, .value = value });
}

fn syncsafe(b: *const [4]u8) u32 {
    return @as(u32, b[0] & 0x7f) << 21 | @as(u32, b[1] & 0x7f) << 14 | @as(u32, b[2] & 0x7f) << 7 | (b[3] & 0x7f);
}

/// Undoes unsynchronisation (every 0xFF 0x00 -> 0xFF) in place.
fn removeUnsync(bytes: []u8) []u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        bytes[n] = bytes[i];
        n += 1;
        if (bytes[i] == 0xff and i + 1 < bytes.len and bytes[i + 1] == 0) i += 1;
    }
    return bytes[0..n];
}

/// Reads `len` bytes, growing the buffer as data arrives: a size field larger than the stream
/// never allocates more than what is there (plus one 64 KiB step).
fn readChunked(allocator: Allocator, r: *std.Io.Reader, len: usize) ReadError![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    while (list.items.len < len) {
        const step = @min(len - list.items.len, 64 * 1024);
        r.appendExact(allocator, &list, step) catch |err| return switch (err) {
            error.EndOfStream, error.ReadFailed, error.OutOfMemory => |e| e,
        };
    }
    return list.toOwnedSlice(allocator);
}

const Tag = struct {
    version: u8,
    unsync: bool,
    extended: bool,

    /// Reads frames until padding, a malformed frame header or the end of the tag body; `left` is
    /// what remains of the body afterwards (for the caller to skip).
    fn frames(t: Tag, arena: Allocator, r: *std.Io.Reader, left: *u32, mode: root.TagMode, list: *List) ReadError!void {
        if (t.extended) {
            if (left.* < 4) return;
            const b = try r.takeArray(4);
            left.* -= 4;
            // v2.3: size excludes the size field; v2.4: syncsafe, includes it.
            const rest = if (t.version == 3) std.mem.readInt(u32, b, .big) else syncsafe(b) -| 4;
            if (rest > left.*) return;
            try r.discardAll(rest);
            left.* -= rest;
        }
        const head_len: u32 = if (t.version == 2) 6 else 10;
        while (left.* >= head_len) {
            const h = (try r.take(head_len));
            var id_buf: [4]u8 = undefined;
            const id = id_buf[0..if (t.version == 2) 3 else 4];
            @memcpy(id, h[0..id.len]);
            const size: u32, const flags: u16 = switch (t.version) {
                2 => .{ std.mem.readInt(u24, h[3..6], .big), 0 },
                3 => .{ std.mem.readInt(u32, h[4..8], .big), std.mem.readInt(u16, h[8..10], .big) },
                // ponytail: iTunes wrote plain big-endian sizes into v2.4; taken as such when a byte
                // has its top bit set. Mutagen's lookahead heuristic also covers sizes < 0x80 per byte.
                else => .{ if (h[4] | h[5] | h[6] | h[7] < 0x80) syncsafe(h[4..8]) else std.mem.readInt(u32, h[4..8], .big), std.mem.readInt(u16, h[8..10], .big) },
            };
            left.* -= head_len;
            for (id) |ch| if (!std.ascii.isUpper(ch) and !std.ascii.isDigit(ch)) return; // padding or garbage
            if (size > left.*) return;
            left.* -= size;
            try t.frame(arena, r, id, size, flags, mode, list);
        }
    }

    fn frame(t: Tag, arena: Allocator, r: *std.Io.Reader, id: []const u8, size: u32, flags: u16, mode: root.TagMode, list: *List) ReadError!void {
        const Kind = enum { text, comment, picture };
        const kind: Kind = if (id[0] == 'T')
            .text
        else if (std.mem.eql(u8, id, "COMM") or std.mem.eql(u8, id, "COM"))
            .comment
        else if (mode == .all and (std.mem.eql(u8, id, "APIC") or std.mem.eql(u8, id, "PIC")))
            .picture
        else
            return r.discardAll(size);

        // Frame format flags: what precedes the data, and whether we can read it at all.
        var prefix: usize = 0;
        var unsync = false;
        switch (t.version) {
            3 => {
                if (flags & 0x00c0 != 0) return r.discardAll(size); // compressed / encrypted
                if (flags & 0x0020 != 0) prefix += 1; // group id
            },
            4 => {
                if (flags & 0x000c != 0) return r.discardAll(size); // compressed / encrypted
                if (flags & 0x0040 != 0) prefix += 1; // group id
                if (flags & 0x0001 != 0) prefix += 4; // data length indicator
                unsync = t.unsync or flags & 0x0002 != 0;
            },
            else => {},
        }
        if (kind != .picture and size > pcm.max_tag_len + 64) return r.discardAll(size);
        const raw = if (kind == .picture) try readChunked(arena, r, size) else try r.readAlloc(arena, size);
        if (raw.len < prefix + 1) return;
        const body = if (unsync) removeUnsync(raw[prefix..]) else raw[prefix..];
        const enc = body[0];
        const data = body[1..];
        switch (kind) {
            .text => {
                if (std.mem.eql(u8, id, "TXXX") or std.mem.eql(u8, id, "TXX")) {
                    const desc, const rest = split(enc, data);
                    const name = try decode(arena, enc, desc) orelse return;
                    if (name.len == 0) return;
                    try addValues(arena, list, try std.ascii.allocLowerString(arena, name), enc, rest, false);
                    return;
                }
                const key = for (text_keys) |k| {
                    if (std.mem.eql(u8, k[0], id)) break k[1];
                } else try std.ascii.allocLowerString(arena, id);
                try addValues(arena, list, key, enc, data, std.mem.eql(u8, key, "genre"));
            },
            .comment => {
                if (data.len < 3) return; // language
                const desc, const rest = split(enc, data[3..]);
                const name = try decode(arena, enc, desc) orelse return;
                const key = if (name.len == 0) "comment" else try std.ascii.allocLowerString(arena, try std.fmt.allocPrint(arena, "comment:{s}", .{name}));
                const value = try decode(arena, enc, split(enc, rest)[0]) orelse return;
                if (value.len > 0) try list.items.append(arena, .{ .key = key, .value = value });
            },
            .picture => {
                var rest = data;
                const mime: []const u8 = if (t.version == 2) blk: {
                    if (rest.len < 3) return;
                    const format = rest[0..3];
                    rest = rest[3..];
                    break :blk if (std.ascii.eqlIgnoreCase(format, "PNG")) "image/png" else if (std.ascii.eqlIgnoreCase(format, "JPG")) "image/jpeg" else try std.ascii.allocLowerString(arena, format);
                } else blk: {
                    const end = std.mem.indexOfScalar(u8, rest, 0) orelse return;
                    const m = rest[0..end];
                    rest = rest[end + 1 ..];
                    break :blk try latin1(arena, m);
                };
                if (rest.len < 1) return;
                const kind_byte = rest[0];
                const desc, const pic = split(enc, rest[1..]);
                try list.pictures.append(arena, .{
                    .mime = mime,
                    .kind = kind_byte,
                    .description = try decode(arena, enc, desc) orelse "",
                    .data = pic,
                });
            },
        }
    }
};

/// Adds every terminator-separated value of a text frame (v2.4 multi-value) under `key`.
fn addValues(arena: Allocator, list: *List, key: []const u8, enc: u8, data: []const u8, genre: bool) Allocator.Error!void {
    var rest = data;
    while (rest.len > 0) {
        const one, rest = split(enc, rest);
        const value = try decode(arena, enc, one) orelse return;
        if (value.len == 0) continue;
        try list.items.append(arena, .{ .key = key, .value = if (genre) genreName(value) else value });
    }
}

/// v2.3 "(17)", "(17)Rock", v2.4 "17" -> the ID3v1 genre name; other text stays.
fn genreName(value: []const u8) []const u8 {
    var digits = value;
    if (value.len > 2 and value[0] == '(') {
        const close = std.mem.indexOfScalar(u8, value, ')') orelse return value;
        if (close + 1 < value.len) return value[close + 1 ..];
        digits = value[1..close];
    }
    const n = std.fmt.parseInt(u8, digits, 10) catch return value;
    return if (n < genres.len) genres[n] else value;
}

/// Splits off the first string by the encoding's terminator: {string, rest after terminator}.
fn split(enc: u8, data: []const u8) struct { []const u8, []const u8 } {
    if (enc == 1 or enc == 2) {
        var i: usize = 0;
        while (i + 1 < data.len) : (i += 2) {
            if (data[i] == 0 and data[i + 1] == 0) return .{ data[0..i], data[i + 2 ..] };
        }
        return .{ data[0 .. data.len & ~@as(usize, 1)], &.{} };
    }
    const end = std.mem.indexOfScalar(u8, data, 0) orelse return .{ data, &.{} };
    return .{ data[0..end], data[end + 1 ..] };
}

/// Text in one of the four ID3 encodings -> UTF-8 in `arena`; null for an unknown encoding or
/// invalid UTF-8 in a UTF-8 frame.
fn decode(arena: Allocator, enc: u8, bytes: []const u8) Allocator.Error!?[]const u8 {
    return switch (enc) {
        0 => try latin1(arena, bytes),
        1 => if (bytes.len >= 2 and bytes[0] == 0xfe and bytes[1] == 0xff)
            try utf16(arena, bytes[2..], .big)
        else if (bytes.len >= 2 and bytes[0] == 0xff and bytes[1] == 0xfe)
            try utf16(arena, bytes[2..], .little)
        else
            try utf16(arena, bytes, .little), // BOM missing: little endian, like most writers
        2 => try utf16(arena, bytes, .big),
        3 => if (std.unicode.utf8ValidateSlice(bytes)) bytes else null,
        else => null,
    };
}

fn latin1(arena: Allocator, bytes: []const u8) Allocator.Error![]const u8 {
    var high: usize = 0;
    for (bytes) |b| high += @intFromBool(b >= 0x80);
    if (high == 0) return bytes;
    const out = try arena.alloc(u8, bytes.len + high);
    var n: usize = 0;
    for (bytes) |b| n += std.unicode.utf8Encode(b, out[n..]) catch unreachable;
    return out;
}

/// Unpaired surrogates -> U+FFFD.
fn utf16(arena: Allocator, bytes: []const u8, endian: std.builtin.Endian) Allocator.Error![]const u8 {
    const units = bytes.len / 2;
    const out = try arena.alloc(u8, units * 3); // a surrogate pair (2 units) takes 4 bytes
    var n: usize = 0;
    var i: usize = 0;
    while (i < units) : (i += 1) {
        const u = std.mem.readInt(u16, bytes[2 * i ..][0..2], endian);
        var cp: u21 = u;
        if (u >= 0xd800 and u < 0xdc00 and i + 1 < units) {
            const lo = std.mem.readInt(u16, bytes[2 * i + 2 ..][0..2], endian);
            if (lo >= 0xdc00 and lo < 0xe000) {
                cp = 0x10000 + ((@as(u21, u) - 0xd800) << 10 | (lo - 0xdc00));
                i += 1;
            }
        }
        if (cp >= 0xd800 and cp < 0xe000) cp = 0xfffd;
        n += std.unicode.utf8Encode(cp, out[n..]) catch unreachable;
    }
    return out[0..n];
}

const text_keys = [_][2][]const u8{
    .{ "TIT2", "title" },        .{ "TT2", "title" },
    .{ "TPE1", "artist" },       .{ "TP1", "artist" },
    .{ "TALB", "album" },        .{ "TAL", "album" },
    .{ "TPE2", "album_artist" }, .{ "TP2", "album_artist" },
    .{ "TYER", "date" },         .{ "TYE", "date" },
    .{ "TDRC", "date" },         .{ "TRCK", "track" },
    .{ "TRK", "track" },         .{ "TPOS", "disc" },
    .{ "TPA", "disc" },          .{ "TCON", "genre" },
    .{ "TCO", "genre" },         .{ "TCOM", "composer" },
    .{ "TCM", "composer" },      .{ "TCOP", "copyright" },
    .{ "TCR", "copyright" },     .{ "TSSE", "encoder" },
    .{ "TSS", "encoder" },
};

/// ID3v1 genres 0..79 plus the Winamp extensions (as ffmpeg lists them).
const genres = [_][]const u8{
    "Blues",                  "Classic Rock",      "Country",           "Dance",            "Disco",
    "Funk",                   "Grunge",            "Hip-Hop",           "Jazz",             "Metal",
    "New Age",                "Oldies",            "Other",             "Pop",              "R&B",
    "Rap",                    "Reggae",            "Rock",              "Techno",           "Industrial",
    "Alternative",            "Ska",               "Death Metal",       "Pranks",           "Soundtrack",
    "Euro-Techno",            "Ambient",           "Trip-Hop",          "Vocal",            "Jazz+Funk",
    "Fusion",                 "Trance",            "Classical",         "Instrumental",     "Acid",
    "House",                  "Game",              "Sound Clip",        "Gospel",           "Noise",
    "AlternRock",             "Bass",              "Soul",              "Punk",             "Space",
    "Meditative",             "Instrumental Pop",  "Instrumental Rock", "Ethnic",           "Gothic",
    "Darkwave",               "Techno-Industrial", "Electronic",        "Pop-Folk",         "Eurodance",
    "Dream",                  "Southern Rock",     "Comedy",            "Cult",             "Gangsta",
    "Top 40",                 "Christian Rap",     "Pop/Funk",          "Jungle",           "Native American",
    "Cabaret",                "New Wave",          "Psychadelic",       "Rave",             "Showtunes",
    "Trailer",                "Lo-Fi",             "Tribal",            "Acid Punk",        "Acid Jazz",
    "Polka",                  "Retro",             "Musical",           "Rock & Roll",      "Hard Rock",
    "Folk",                   "Folk-Rock",         "National Folk",     "Swing",            "Fast Fusion",
    "Bebob",                  "Latin",             "Revival",           "Celtic",           "Bluegrass",
    "Avantgarde",             "Gothic Rock",       "Progressive Rock",  "Psychedelic Rock", "Symphonic Rock",
    "Slow Rock",              "Big Band",          "Chorus",            "Easy Listening",   "Acoustic",
    "Humour",                 "Speech",            "Chanson",           "Opera",            "Chamber Music",
    "Sonata",                 "Symphony",          "Booty Bass",        "Primus",           "Porn Groove",
    "Satire",                 "Slow Jam",          "Club",              "Tango",            "Samba",
    "Folklore",               "Ballad",            "Power Ballad",      "Rhythmic Soul",    "Freestyle",
    "Duet",                   "Punk Rock",         "Drum Solo",         "A capella",        "Euro-House",
    "Dance Hall",             "Goa",               "Drum & Bass",       "Club-House",       "Hardcore",
    "Terror",                 "Indie",             "BritPop",           "Negerpunk",        "Polsk Punk",
    "Beat",                   "Christian Gangsta", "Heavy Metal",       "Black Metal",      "Crossover",
    "Contemporary Christian", "Christian Rock",    "Merengue",          "Salsa",            "Thrash Metal",
    "Anime",                  "JPop",              "Synthpop",          "Abstract",         "Art Rock",
    "Baroque",                "Bhangra",           "Big Beat",          "Breakbeat",        "Chillout",
    "Downtempo",              "Dub",               "EBM",               "Eclectic",         "Electro",
    "Electroclash",           "Emo",               "Experimental",      "Garage",           "Global",
    "IDM",                    "Illbient",          "Industro-Goth",     "Jam Band",         "Krautrock",
    "Leftfield",              "Lounge",            "Math Rock",         "New Romantic",     "Nu-Breakz",
    "Post-Punk",              "Post-Rock",         "Psytrance",         "Shoegaze",         "Space Rock",
    "Trop Rock",              "World Music",       "Neoclassical",      "Audiobook",        "Audio Theatre",
    "Neue Deutsche Welle",    "Podcast",           "Indie Rock",        "G-Funk",           "Dubstep",
    "Garage Rock",            "Psybient",
};

comptime {
    std.debug.assert(genres.len == 192);
}
