//! The hand-written C bindings (src/zig-c-headers/), one namespace per lib.

pub const ogg = @import("zig-c-headers/ogg.zig");
pub const vorbis = @import("zig-c-headers/vorbis.zig");
pub const opus = @import("zig-c-headers/opus.zig");
pub const opusenc = @import("zig-c-headers/opusenc.zig");
pub const opusfile = @import("zig-c-headers/opusfile.zig");
pub const flac = @import("zig-c-headers/flac.zig");
pub const minimp4 = @import("zig-c-headers/minimp4.zig");
pub const dr_wav = @import("zig-c-headers/dr_wav.zig");
pub const dr_mp3 = @import("zig-c-headers/dr_mp3.zig");
pub const dr_flac = @import("zig-c-headers/dr_flac.zig");
pub const fdk_aac = @import("zig-c-headers/fdk_aac.zig");
pub const alac = @import("zig-c-headers/alac.zig");
