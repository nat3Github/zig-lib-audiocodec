const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("audiocodec", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });

    // No libc anywhere: the C libs compile against libc/include; the few libc functions they need
    // come from src/libc.zig (exported by this module) and libc/printf.c. See notes/libc-free.md.
    const libc_include = b.path("libc/include");
    mod.addIncludePath(libc_include);
    mod.addCSourceFile(.{ .file = b.path("libc/printf.c") });

    // Every vendor artifact is installed so dependents (test/) reach them via
    // `dependency("audiocodec", ...).artifact(name)` instead of pinning them again.
    // Their malloc & co. resolve to avc_malloc ... (libc/include/stdlib.h, src/c_allocator.zig).
    // flac threads = false: encoder worker threads would allocate outside the calling thread's
    // allocator.
    const args = .{ .target = target, .optimize = optimize, .libc_include = libc_include };
    const vendored = .{
        .{ "ogg", .{"ogg"}, args },
        .{ "vorbis", .{"vorbis"}, args },
        .{ "opus", .{"opus"}, args },
        .{ "opusenc", .{"opusenc"}, args },
        .{ "opusfile", .{"opusfile"}, args },
        .{ "flac", .{"FLAC"}, .{ .target = target, .optimize = optimize, .libc_include = libc_include, .threads = false } },
        // dr_mp3 decodes to f32 natively; sample.zig does every other conversion (its f32 -> s16 truncates).
        .{ "dr_libs", .{ "dr_mp3", "dr_wav", "dr_flac" }, .{ .target = target, .optimize = optimize, .libc_include = libc_include, .no_stdio = true, .mp3_float_output = true } },
        .{ "minimp4", .{"minimp4"}, args },
        .{ "fdk_aac", .{"fdk-aac"}, args },
        .{ "alac", .{"alac"}, args },
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
