const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("audiocodec", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Every vendor artifact is installed so dependents (test/) reach them via
    // `dependency("audiocodec", ...).artifact(name)` instead of pinning them again.
    const vendored = [_]struct { dep: []const u8, artifacts: []const []const u8 }{
        .{ .dep = "ogg", .artifacts = &.{"ogg"} },
        .{ .dep = "vorbis", .artifacts = &.{"vorbis"} },
        .{ .dep = "opus", .artifacts = &.{"opus"} },
        .{ .dep = "opusenc", .artifacts = &.{"opusenc"} },
        .{ .dep = "opusfile", .artifacts = &.{"opusfile"} },
        .{ .dep = "flac", .artifacts = &.{"FLAC"} },
        .{ .dep = "dr_libs", .artifacts = &.{ "dr_mp3", "dr_wav", "dr_flac" } },
        .{ .dep = "minimp4", .artifacts = &.{"minimp4"} },
        .{ .dep = "fdk_aac", .artifacts = &.{"fdk-aac"} },
        .{ .dep = "alac", .artifacts = &.{"alac"} },
    };
    for (vendored) |v| {
        const dep = b.dependency(v.dep, .{ .target = target, .optimize = optimize });
        for (v.artifacts) |name| {
            const lib = dep.artifact(name);
            b.installArtifact(lib);
            // dr_wav / dr_flac are test oracles only, never linked into the module.
            if (std.mem.eql(u8, name, "dr_wav") or std.mem.eql(u8, name, "dr_flac")) continue;
            mod.linkLibrary(lib);
        }
    }
}
