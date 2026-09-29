//! Ogg: which codec a stream carries, from the first packet of its first page.

const std = @import("std");
const root = @import("root.zig");

const Error = root.Error;

/// Page header, segment table, first 8 bytes of the first packet.
pub const max_head = 27 + 255 + 8;

pub const Head = struct {
    codec: root.Codec,
    /// Consumed from the reader; the backend replays them before reading on.
    bytes: []const u8,
};

/// Reads the first page's head into `buf` (any reader buffer size works, nothing is peeked).
/// ponytail: first logical stream only; a Skeleton or Theora BOS page first is
/// error.UnsupportedFormat. Multiplexed audio+video Ogg would need a page demuxer here.
pub fn head(reader: *std.Io.Reader, buf: *[max_head]u8) Error!Head {
    if (try reader.readSliceShort(buf[0..27]) < 27 or !std.mem.eql(u8, buf[0..4], "OggS")) return error.InvalidFile;
    const segments = buf[26];
    const lacing = buf[27..][0..segments];
    if (try reader.readSliceShort(lacing) < segments) return error.InvalidFile;
    var len: usize = 0;
    for (lacing) |l| {
        len += l;
        if (l < 255) break;
    }
    const start = 27 + @as(usize, segments);
    const packet = buf[start..][0..try reader.readSliceShort(buf[start..][0..@min(len, 8)])];
    const codec: root.Codec = if (std.mem.startsWith(u8, packet, "\x01vorbis"))
        .vorbis
    else if (std.mem.startsWith(u8, packet, "\x7fFLAC"))
        .flac
    else if (std.mem.startsWith(u8, packet, "OpusHead"))
        .opus
    else
        return error.UnsupportedFormat;
    return .{ .codec = codec, .bytes = buf[0 .. start + packet.len] };
}
