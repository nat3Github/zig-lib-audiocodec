const std = @import("std");
const Container = @import("root.zig").Container;

/// Container from the first 12 bytes of a stream. Ogg codecs are told apart by the ogg backend.
pub fn sniff(b: *const [12]u8) ?Container {
    const eql = std.mem.eql;
    if ((eql(u8, b[0..4], "RIFF") or eql(u8, b[0..4], "RF64") or eql(u8, b[0..4], "BW64")) and eql(u8, b[8..12], "WAVE")) return .wav;
    if (eql(u8, b[0..4], "FORM") and (eql(u8, b[8..12], "AIFF") or eql(u8, b[8..12], "AIFC"))) return .aiff;
    if (eql(u8, b[0..4], "fLaC")) return .flac;
    if (eql(u8, b[0..4], "OggS")) return .ogg;
    if (eql(u8, b[4..8], "ftyp")) return .m4a;
    // ponytail: an ID3 tag in front of flac/aac is taken for mp3; skip the tag here if that shows up.
    if (eql(u8, b[0..3], "ID3")) return .mp3;
    if (b[0] == 0xff and b[1] & 0xe0 == 0xe0) return if (b[1] & 0x06 == 0) .adts else .mp3;
    return null;
}
