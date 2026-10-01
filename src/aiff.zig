//! AIFF (big-endian PCM 8/16/24/32) and AIFF-C (NONE, twos, sowt, fl32, fl64); NAME/AUTH/ANNO/(c) tags.

const std = @import("std");
const root = @import("root.zig");
const pcm = @import("pcm.zig");
const sample = @import("sample.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const ReadError = Error || error{EndOfStream};

const aifc_version = 0xa2805140;

const text_keys = [_][2][]const u8{
    .{ "NAME", "title" }, .{ "AUTH", "artist" }, .{ "ANNO", "comment" }, .{ "(c) ", "copyright" },
};

const Comm = struct {
    channels: u16,
    frames: u32,
    sample_size: u16,
    rate: u32,
    compression: [4]u8,
};

pub fn open(gpa: Allocator, arena: Allocator, reader: *std.Io.Reader, seeker: ?root.Seeker, tags: root.TagMode) Error!pcm.Decoder {
    const header = parse(arena, reader, seeker, tags) catch |err| return pcm.headerError(err);
    return pcm.Decoder.init(gpa, reader, seeker, header);
}

fn parse(arena: Allocator, reader: *std.Io.Reader, seeker: ?root.Seeker, tag_mode: root.TagMode) ReadError!pcm.Decoder.Header {
    const form = try reader.takeArray(12);
    if (root.sniff(form) != .aiff) return error.InvalidFile;
    const aifc = std.mem.eql(u8, form[8..12], "AIFC");
    var offset: u64 = 12;
    var comm: ?Comm = null;
    var ssnd: ?struct { start: u64, len: u64 } = null;
    var tags: std.ArrayList(root.Tag) = .empty;

    while (comm == null or ssnd == null) {
        const id = (try reader.takeArray(4)).*;
        const size = try reader.takeInt(u32, .big);
        offset += 8;
        const padded = @as(u64, size) + (size & 1);
        if (std.mem.eql(u8, &id, "COMM")) {
            comm = try parseComm(reader, size, aifc);
            try pcm.skip(reader, padded - @as(u64, if (aifc) 22 else 18));
        } else if (std.mem.eql(u8, &id, "SSND")) {
            if (size < 8) return error.InvalidFile;
            const data_offset = try reader.takeInt(u32, .big);
            _ = try reader.takeInt(u32, .big); // block size
            if (data_offset > size - 8) return error.InvalidFile;
            ssnd = .{ .start = offset + 8 + data_offset, .len = size - 8 - data_offset };
            if (comm != null) {
                try pcm.skip(reader, data_offset);
                break;
            }
            // ponytail: COMM after SSND needs a seeker to come back; rare in practice.
            if (seeker == null) return error.UnsupportedFormat;
            try pcm.skip(reader, padded - 8);
        } else if (tag_mode != .none and textKey(&id) != null) {
            if (try pcm.readText(arena, reader, size)) |value|
                try tags.append(arena, .{ .key = textKey(&id).?, .value = value });
            try pcm.skip(reader, padded - size);
        } else {
            try pcm.skip(reader, padded);
        }
        offset += padded;
    } else {
        // SSND came first: go back to its data.
        const s = seeker.?;
        try s.seekTo(s.context, ssnd.?.start);
    }

    const c = comm.?;
    const eql = std.mem.eql;
    const cc = &c.compression;
    const format: root.SampleFormat, const endian: std.builtin.Endian = if (eql(u8, cc, "NONE") or eql(u8, cc, "twos") or eql(u8, cc, "sowt")) .{
        switch (c.sample_size) {
            1...8 => .i8,
            9...16 => .i16,
            17...24 => .i24,
            25...32 => .i32,
            else => return error.InvalidFile,
        },
        if (eql(u8, cc, "sowt")) .little else .big,
    } else if (eql(u8, cc, "fl32") or eql(u8, cc, "FL32"))
        .{ .f32, .big }
    else if (eql(u8, cc, "fl64") or eql(u8, cc, "FL64"))
        .{ .f64, .big }
    else
        return error.UnsupportedFormat;

    const block_align = @as(u64, sample.size(format)) * c.channels;
    const bits: u8 = if (format == .f32 or format == .f64) sample.size(format) * 8 else @intCast(c.sample_size);
    return .{
        .info = .{
            .container = .aiff,
            .codec = .pcm,
            .sample_rate = c.rate,
            .channels = c.channels,
            // ponytail: no CHAN chunk; >2 channels are file order (ffmpeg and afconvert write WAVE
            // order + CHAN, and report "unknown" without it). Read/write CHAN when layouts matter.
            .channel_layout = if (c.channels <= 2) root.ChannelLayout.default(c.channels) else null,
            .frames = null,
            .bits_per_sample = bits,
            .sample_format = format,
            .tags = .{ .items = tags.items },
        },
        .layout = .{ .format = format, .endian = endian },
        .data_start = ssnd.?.start,
        .data_len = @min(@as(u64, c.frames) * block_align, ssnd.?.len),
    };
}

fn parseComm(reader: *std.Io.Reader, size: u32, aifc: bool) ReadError!Comm {
    if (size < @as(u32, if (aifc) 22 else 18)) return error.InvalidFile;
    const channels = try reader.takeInt(i16, .big);
    const frames = try reader.takeInt(u32, .big);
    const sample_size = try reader.takeInt(i16, .big);
    const rate = readExtended(try reader.takeArray(10)) orelse return error.InvalidFile;
    const compression = if (aifc) (try reader.takeArray(4)).* else "NONE".*;
    if (channels <= 0 or sample_size <= 0) return error.InvalidFile;
    return .{
        .channels = @intCast(channels),
        .frames = frames,
        .sample_size = @intCast(sample_size),
        .rate = rate,
        .compression = compression,
    };
}

fn textKey(id: *const [4]u8) ?[]const u8 {
    for (text_keys) |k| if (std.mem.eql(u8, k[0], id)) return k[1];
    return null;
}

/// 80-bit IEEE 754 extended -> Hz, rounded; null for anything outside 1..maxInt(u32).
pub fn readExtended(b: *const [10]u8) ?u32 {
    const sign_exp = std.mem.readInt(u16, b[0..2], .big);
    const mantissa = std.mem.readInt(u64, b[2..10], .big);
    if (sign_exp & 0x8000 != 0 or sign_exp < 16383 or mantissa >> 63 == 0) return null;
    const shift = sign_exp - 16383;
    if (shift > 31) return null;
    const whole = mantissa >> @intCast(63 - shift);
    const round = (mantissa >> @intCast(62 - shift)) & 1;
    return std.math.cast(u32, whole + round);
}

pub fn writeExtended(rate: u32) [10]u8 {
    std.debug.assert(rate != 0);
    const lz: u16 = @clz(rate);
    var b: [10]u8 = undefined;
    std.mem.writeInt(u16, b[0..2], 16383 + 31 - lz, .big);
    std.mem.writeInt(u64, b[2..10], @as(u64, rate) << @intCast(32 + lz), .big);
    return b;
}

pub fn writeHeader(writer: *std.Io.Writer, options: root.Encoder.Options) Error!pcm.Encoder.Header {
    if (options.seeker == null) return error.NotSeekable;
    if (options.channels > std.math.maxInt(i16)) return error.InvalidOptions;
    const format = options.sample_format;
    const float = format == .f32 or format == .f64;

    try writer.writeAll("FORM");
    try writer.writeInt(u32, 0, .big);
    try writer.writeAll(if (float) "AIFC" else "AIFF");
    var len: u64 = 12;
    if (float) {
        try writer.writeAll("FVER");
        try writer.writeInt(u32, 4, .big);
        try writer.writeInt(u32, aifc_version, .big);
        len += 12;
    }

    try writer.writeAll("COMM");
    try writer.writeInt(u32, if (float) 24 else 18, .big);
    try writer.writeInt(i16, @intCast(options.channels), .big);
    const frames_field = len + 10;
    try writer.writeInt(u32, 0, .big);
    try writer.writeInt(i16, @as(i16, sample.size(format)) * 8, .big);
    try writer.writeAll(&writeExtended(options.sample_rate));
    if (float) try writer.writeAll(if (format == .f32) "fl32\x00\x00" else "fl64\x00\x00");
    len += if (float) 32 else 26;

    for (options.tags) |t| {
        const id = for (text_keys) |k| {
            if (std.mem.eql(u8, k[1], t.key)) break k[0];
        } else continue;
        if (t.value.len > std.math.maxInt(u32) - 1) return error.InvalidOptions;
        try writer.writeAll(id);
        try writer.writeInt(u32, @intCast(t.value.len), .big);
        try writer.writeAll(t.value);
        if (t.value.len & 1 != 0) try writer.writeByte(0);
        len += 8 + t.value.len + (t.value.len & 1);
    }

    try writer.writeAll("SSND");
    const ssnd_field = len + 4;
    try writer.writeInt(u32, 0, .big);
    try writer.writeInt(u32, 0, .big); // offset
    try writer.writeInt(u32, 0, .big); // block size
    len += 16;
    return .{
        .layout = .{ .format = format, .endian = .big },
        .fields = .{ frames_field, ssnd_field, 4 },
        .header_len = len,
        // FORM size = file - 8 must fit u32, including a pad byte.
        .max_data = std.math.maxInt(u32) - (len - 8) - 1,
    };
}

pub fn patch(writer: *std.Io.Writer, s: root.Seeker, fields: [3]u64, data_bytes: u64, block_align: u32, end: u64) Error!void {
    try pcm.patchInt(writer, s, fields[0], @intCast(data_bytes / block_align), .big);
    try pcm.patchInt(writer, s, fields[1], @intCast(data_bytes + 8), .big);
    try pcm.patchInt(writer, s, fields[2], @intCast(end - 8), .big);
}
