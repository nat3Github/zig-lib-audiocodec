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
    // libc_alloc = false: the C libs' default allocator hooks return NULL instead of calling
    // malloc; src/c_allocator.zig installs the real hooks. flac threads = false: encoder
    // worker threads would allocate outside the calling thread's allocator.
    const hooked = .{ .target = target, .optimize = optimize, .libc_alloc = false };
    const vendored = .{
        .{ "ogg", .{"ogg"}, hooked },
        .{ "vorbis", .{"vorbis"}, hooked },
        .{ "opus", .{"opus"}, hooked },
        .{ "opusenc", .{"opusenc"}, hooked },
        .{ "opusfile", .{"opusfile"}, hooked },
        .{ "flac", .{"FLAC"}, .{ .target = target, .optimize = optimize, .libc_alloc = false, .threads = false } },
        .{ "dr_libs", .{ "dr_mp3", "dr_wav", "dr_flac" }, hooked },
        .{ "minimp4", .{"minimp4"}, hooked },
        .{ "fdk_aac", .{"fdk-aac"}, hooked },
        .{ "alac", .{"alac"}, .{ .target = target, .optimize = optimize } },
    };
    inline for (vendored) |v| {
        const dep = b.dependency(v[0], v[2]);
        inline for (v[1]) |name| {
            const lib = dep.artifact(name);
            b.installArtifact(lib);
            // dr_wav / dr_flac are test oracles only, never linked into the module.
            if (comptime !(std.mem.eql(u8, name, "dr_wav") or std.mem.eql(u8, name, "dr_flac"))) mod.linkLibrary(lib);
        }
    }
}
