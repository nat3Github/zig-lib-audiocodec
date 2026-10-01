//! RIFF/RF64/BW64 WAVE: PCM u8/s16/s24/s32, IEEE float 32/64, WAVE_FORMAT_EXTENSIBLE, LIST/INFO tags.
//! Live read-while-write per wav-reader-writer-design (dev repo): the writer leaves placeholder sizes
//! until finish, a reader treats a placeholder data size as "still growing".
//! ponytail: no wakeup (R6); read() returns 0 and the caller polls. Add kqueue NOTE_EXTEND /
//! inotify IN_MODIFY helpers when polling latency or CPU matters. open() on a file whose header is
//! not fully written yet (R7) returns error.InvalidFile; the caller retries.

const std = @import("std");
const root = @import("root.zig");
const pcm = @import("pcm.zig");
const sample = @import("sample.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const ReadError = Error || error{EndOfStream};

pub const placeholder: u32 = 0xffffffff;

const format_pcm = 1;
const format_float = 3;
const format_extensible = 0xfffe;
/// KSDATAFORMAT_SUBTYPE_* after the 2-byte format code.
const guid_tail = "\x00\x00\x00\x00\x10\x00\x80\x00\x00\xaa\x00\x38\x9b\x71";

const info_keys = [_][2][]const u8{
    .{ "INAM", "title" },   .{ "IART", "artist" },   .{ "IPRD", "album" },
    .{ "ICRD", "date" },    .{ "ITRK", "track" },    .{ "IPRT", "track" },
    .{ "IGNR", "genre" },   .{ "ICMT", "comment" },  .{ "ICOP", "copyright" },
    .{ "ISFT", "encoder" }, .{ "IMUS", "composer" },
};

const Fmt = struct {
    format: u16,
    channels: u16,
    rate: u32,
    block_align: u16,
    bits: u16,
    valid_bits: u16 = 0,
    mask: ?u32 = null,
};

pub fn open(gpa: Allocator, arena: Allocator, reader: *std.Io.Reader, seeker: ?root.Seeker, tags: root.TagMode) Error!pcm.Decoder {
    const header = parse(arena, reader, tags) catch |err| return pcm.headerError(err);
    return pcm.Decoder.init(gpa, reader, seeker, header);
}

fn parse(arena: Allocator, reader: *std.Io.Reader, tag_mode: root.TagMode) ReadError!pcm.Decoder.Header {
    const riff = try reader.takeArray(12);
    // Decoder.Options.container skips sniffing, so check the magic here too.
    if (root.sniff(riff) != .wav) return error.InvalidFile;
    const rf64 = !std.mem.eql(u8, riff[0..4], "RIFF");
    var offset: u64 = 12;
    var ds64_data: ?u64 = null;
    var fmt: ?Fmt = null;
    var tags: std.ArrayList(root.Tag) = .empty;

    const data_size = while (true) {
        const id = (try reader.takeArray(4)).*;
        const size = try reader.takeInt(u32, .little);
        offset += 8;
        if (std.mem.eql(u8, &id, "data")) break size;
        const padded = @as(u64, size) + (size & 1);
        if (std.mem.eql(u8, &id, "ds64")) {
            if (size < 24) return error.InvalidFile;
            _ = try reader.takeInt(u64, .little); // riff size
            ds64_data = try reader.takeInt(u64, .little);
            try pcm.skip(reader, padded - 16);
        } else if (std.mem.eql(u8, &id, "fmt ")) {
            fmt = try parseFmt(reader, size);
            try pcm.skip(reader, padded - size);
        } else if (std.mem.eql(u8, &id, "LIST") and tag_mode != .none) {
            try parseList(arena, reader, size, &tags);
            try pcm.skip(reader, padded - size);
        } else {
            try pcm.skip(reader, padded);
        }
        offset += padded;
    };

    const f = fmt orelse return error.InvalidFile;
    if (f.channels == 0 or f.rate == 0 or f.block_align == 0 or f.block_align % f.channels != 0) return error.InvalidFile;
    const bytes = f.block_align / f.channels;
    const format: root.SampleFormat = switch (f.format) {
        format_pcm => switch (bytes) {
            1 => .i8,
            2 => .i16,
            3 => .i24,
            4 => .i32,
            else => return error.UnsupportedFormat,
        },
        format_float => switch (bytes) {
            4 => .f32,
            8 => .f64,
            else => return error.UnsupportedFormat,
        },
        else => return error.UnsupportedFormat,
    };
    if (f.bits > bytes * 8) return error.InvalidFile;

    const layout: ?root.ChannelLayout = if (f.mask) |m| blk: {
        const l = root.ChannelLayout.fromMask(m);
        break :blk if (l.count() == f.channels) l else null;
    } else if (f.channels <= 2) root.ChannelLayout.default(f.channels) else null;

    const data_len: ?u64 = if (rf64 and data_size == placeholder)
        ds64_data orelse return error.InvalidFile
    else if (data_size == placeholder) null else data_size;

    const bits = if (f.valid_bits != 0 and f.valid_bits <= f.bits) f.valid_bits else if (f.bits != 0) f.bits else bytes * 8;
    return .{
        .info = .{
            .container = .wav,
            .codec = .pcm,
            .sample_rate = f.rate,
            .channels = f.channels,
            .channel_layout = layout,
            .frames = null,
            .bits_per_sample = @intCast(bits),
            .sample_format = format,
            .tags = .{ .items = tags.items },
        },
        .layout = .{ .format = format, .endian = .little, .unsigned8 = true },
        .data_start = offset,
        .data_len = data_len,
        .size_field = if (data_len == null) offset - 4 else null,
    };
}

fn parseFmt(reader: *std.Io.Reader, size: u32) ReadError!Fmt {
    if (size < 16) return error.InvalidFile;
    var f: Fmt = .{
        .format = try reader.takeInt(u16, .little),
        .channels = try reader.takeInt(u16, .little),
        .rate = try reader.takeInt(u32, .little),
        .block_align = undefined,
        .bits = undefined,
    };
    _ = try reader.takeInt(u32, .little); // byte rate
    f.block_align = try reader.takeInt(u16, .little);
    f.bits = try reader.takeInt(u16, .little);
    if (f.format != format_extensible) {
        try pcm.skip(reader, size - 16);
        return f;
    }
    if (size < 40) return error.InvalidFile;
    _ = try reader.takeInt(u16, .little); // cbSize
    f.valid_bits = try reader.takeInt(u16, .little);
    f.mask = try reader.takeInt(u32, .little);
    f.format = try reader.takeInt(u16, .little);
    // Tail in two takes: open() must work with any reader buffer >= min_buffer_len.
    if (!std.mem.eql(u8, try reader.takeArray(7), guid_tail[0..7])) return error.UnsupportedFormat;
    if (!std.mem.eql(u8, try reader.takeArray(7), guid_tail[7..])) return error.UnsupportedFormat;
    try pcm.skip(reader, size - 40);
    return f;
}

fn parseList(arena: Allocator, reader: *std.Io.Reader, size: u32, tags: *std.ArrayList(root.Tag)) ReadError!void {
    if (size < 4) return pcm.skip(reader, size);
    const kind = try reader.takeArray(4);
    var remaining: u64 = size - 4;
    if (!std.mem.eql(u8, kind, "INFO")) return pcm.skip(reader, remaining);
    while (remaining >= 8) {
        const id = (try reader.takeArray(4)).*;
        const len = try reader.takeInt(u32, .little);
        remaining -= 8;
        if (len > remaining) return error.InvalidFile;
        const padded = @min(remaining, @as(u64, len) + (len & 1));
        if (try pcm.readText(arena, reader, len)) |value| {
            const key = for (info_keys) |k| {
                if (std.mem.eql(u8, k[0], &id)) break k[1];
            } else try std.ascii.allocLowerString(arena, &id);
            try tags.append(arena, .{ .key = key, .value = value });
        }
        try pcm.skip(reader, padded - len);
        remaining -= padded;
    }
    try pcm.skip(reader, remaining);
}

pub fn writeHeader(writer: *std.Io.Writer, options: root.Encoder.Options) Error!pcm.Encoder.Header {
    const format = options.sample_format;
    const bytes = sample.size(format);
    const layout = options.channel_layout orelse root.ChannelLayout.default(options.channels);
    const default_mask = if (root.ChannelLayout.default(options.channels)) |l| l.mask() else 0;
    const mask = if (layout) |l| l.mask() else 0;
    const extensible = options.channels > 2 or bytes > 2 or mask != default_mask;
    const code: u16 = if (format == .f32 or format == .f64) format_float else format_pcm;
    const block_align = @as(u32, bytes) * options.channels;
    if (block_align > std.math.maxInt(u16)) return error.InvalidOptions;

    var header_len: u64 = 12;
    try writer.writeAll("RIFF");
    try writer.writeInt(u32, placeholder, .little);
    try writer.writeAll("WAVE");

    try writer.writeAll("fmt ");
    try writer.writeInt(u32, if (extensible) 40 else 16, .little);
    try writer.writeInt(u16, if (extensible) format_extensible else code, .little);
    try writer.writeInt(u16, options.channels, .little);
    try writer.writeInt(u32, options.sample_rate, .little);
    try writer.writeInt(u32, options.sample_rate *% block_align, .little);
    try writer.writeInt(u16, @intCast(block_align), .little);
    try writer.writeInt(u16, bytes * 8, .little);
    if (extensible) {
        try writer.writeInt(u16, 22, .little);
        try writer.writeInt(u16, bytes * 8, .little);
        try writer.writeInt(u32, mask, .little);
        try writer.writeInt(u16, code, .little);
        try writer.writeAll(guid_tail);
    }
    header_len += if (extensible) 48 else 24;

    header_len += try writeInfo(writer, options.tags);

    try writer.writeAll("data");
    try writer.writeInt(u32, placeholder, .little);
    header_len += 8;
    return .{
        .layout = .{ .format = format, .endian = .little, .unsigned8 = true },
        .fields = .{ header_len - 4, 4, 0 },
        .header_len = header_len,
        // RIFF size = file - 8 must stay below the placeholder, including a pad byte.
        .max_data = placeholder - 1 - (header_len - 8) - 1,
    };
}

/// ponytail: keys without an INFO id and not 4 characters long are dropped.
fn writeInfo(writer: *std.Io.Writer, tags: []const root.Tag) Error!u64 {
    var list_len: u64 = 4;
    for (tags) |t| {
        if (infoId(t.key) != null) list_len += 8 + padTo2(t.value.len + 1);
    }
    if (list_len == 4) return 0;
    if (list_len > std.math.maxInt(u32)) return error.InvalidOptions;
    try writer.writeAll("LIST");
    try writer.writeInt(u32, @intCast(list_len), .little);
    try writer.writeAll("INFO");
    for (tags) |t| {
        const id = infoId(t.key) orelse continue;
        try writer.writeAll(&id);
        try writer.writeInt(u32, @intCast(t.value.len + 1), .little);
        try writer.writeAll(t.value);
        try writer.splatByteAll(0, padTo2(t.value.len + 1) - t.value.len);
    }
    return 8 + list_len;
}

fn padTo2(len: usize) usize {
    return len + (len & 1);
}

fn infoId(key: []const u8) ?[4]u8 {
    for (info_keys) |k| if (std.mem.eql(u8, k[1], key)) return k[0][0..4].*;
    if (key.len != 4) return null;
    var id: [4]u8 = undefined;
    _ = std.ascii.upperString(&id, key);
    return id;
}

/// W4: data size first, then the RIFF size; a reader seeing the real data size knows the file is done.
pub fn patch(writer: *std.Io.Writer, s: root.Seeker, fields: [3]u64, data_bytes: u64, end: u64) Error!void {
    try pcm.patchInt(writer, s, fields[0], @intCast(data_bytes), .little);
    try pcm.patchInt(writer, s, fields[1], @intCast(end - 8), .little);
}
