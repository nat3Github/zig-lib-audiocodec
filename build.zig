const std = @import("std");
const zon = @import("build.zig.zon");

/// Codecs that can be left out with -D<name>=false (wav/aiff are always on). The name is also the
/// field in the generated `build_options` module and in `audiocodec.enabled`.
const codecs = [_][]const u8{ "flac", "vorbis", "opus", "mp3", "aac", "alac" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var enabled: std.StringHashMapUnmanaged(bool) = .empty;
    const build_options = b.addOptions();
    for (codecs) |name| {
        const on = b.option(bool, name, b.fmt("Include the {s} codec and its C libraries (default: true)", .{name})) orelse true;
        enabled.put(b.allocator, name, on) catch @panic("OOM");
        build_options.addOption(bool, name, on);
    }

    const mod = b.addModule("audiocodec", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    mod.addOptions("build_options", build_options);

    // No libc anywhere: the C libs compile against libc/include; the few libc functions they need
    // come from src/libc.zig (exported by this module) and libc/printf.c. See notes/libc-free.md.
    const libc_include = b.path("libc/include");
    mod.addIncludePath(libc_include);
    // Own archive, not a C file of `mod`: zig's --fuzz instruments every C file of the test
    // compilation with a pc table its fuzzer can't read (0.16: clang's __sancov_pcs vs __sancov_pcs1).
    const printf = b.addLibrary(.{ .name = "avc_printf", .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = false }) });
    printf.root_module.addIncludePath(libc_include);
    printf.root_module.addCSourceFile(.{ .file = b.path("libc/printf.c") });
    mod.linkLibrary(printf);

    var notices: std.ArrayList(u8) = .empty;
    notices.appendSlice(b.allocator, "Third-party software linked into this build of zig-lib-audiocodec, with the codecs enabled at build time.\n") catch @panic("OOM");

    // Pure Zig (src/resample.zig), untouched by the libc work. Always on.
    const r8brain = b.dependency("r8brain", .{ .target = target, .optimize = optimize });
    mod.addImport("r8brain", r8brain.module("r8brain"));
    addNotice(b, &notices, r8brain, "r8brain", zon.dependencies.r8brain.url, &.{"LICENSE"}, "Sample rate converter designed by Aleksey Vaneev of Voxengo\n\n");
    const zpffft = r8brain.builder.dependency("zpffft", .{ .target = target, .optimize = optimize });
    addNotice(b, &notices, zpffft, "zpffft", "(dependency of r8brain)", &.{"LICENSE.txt"}, "");

    // Every vendor artifact is installed so dependents (test/) reach them via
    // `dependency("audiocodec", ...).artifact(name)` instead of pinning them again.
    // Their malloc & co. resolve to avc_malloc ... (libc/include/stdlib.h, src/c_allocator.zig).
    // Lazy: a vendor lib is fetched and linked only when one of the codecs needing it is enabled.
    // flac threads = false: encoder worker threads would allocate outside the calling thread's
    // allocator.
    const args = .{ .target = target, .optimize = optimize, .libc_include = libc_include };
    const vendored = .{
        // name, artifacts, needed by, extra args, license files
        .{ "ogg", .{"ogg"}, .{ "flac", "vorbis", "opus" }, args, .{"COPYING"} },
        .{ "vorbis", .{"vorbis"}, .{"vorbis"}, args, .{"COPYING"} },
        .{ "opus", .{"opus"}, .{"opus"}, args, .{"COPYING"} },
        .{ "opusenc", .{"opusenc"}, .{"opus"}, args, .{"COPYING"} },
        .{ "opusfile", .{"opusfile"}, .{"opus"}, args, .{"COPYING"} },
        .{ "flac", .{"FLAC"}, .{"flac"}, .{ .target = target, .optimize = optimize, .libc_include = libc_include, .threads = false }, .{"COPYING.Xiph"} },
        // dr_mp3 decodes to f32 natively; sample.zig does every other conversion (its f32 -> s16 truncates).
        .{ "dr_libs", .{ "dr_mp3", "dr_wav", "dr_flac" }, .{"mp3"}, .{ .target = target, .optimize = optimize, .libc_include = libc_include, .no_stdio = true, .mp3_float_output = true }, .{"LICENSE"} },
        .{ "minimp4", .{"minimp4"}, .{ "aac", "alac" }, args, .{"LICENSE"} },
        // MODIFICATIONS: the "Third-Party Modified Version" notice with our change dates (NOTICE section 2).
        .{ "fdk_aac", .{"fdk-aac"}, .{"aac"}, args, .{ "MODIFICATIONS", "NOTICE" } },
        .{ "alac", .{"alac"}, .{"alac"}, args, .{"LICENSE"} },
    };
    inline for (vendored) |v| {
        var needed = false;
        inline for (v[2]) |codec| needed = needed or enabled.get(codec).?;
        if (needed) if (b.lazyDependency(v[0], v[3])) |dep| {
            inline for (v[1]) |name| {
                const lib = dep.artifact(name);
                b.installArtifact(lib);
                // dr_wav / dr_flac are test oracles only, never linked into the module.
                if (comptime !(std.mem.eql(u8, name, "dr_wav") or std.mem.eql(u8, name, "dr_flac"))) mod.linkLibrary(lib);
            }
            addNotice(b, &notices, dep, v[0], @field(zon.dependencies, v[0]).url, &v[4], "");
        };
    }

    const notices_file = b.addWriteFiles().add("THIRD_PARTY_NOTICES", notices.items);
    mod.addAnonymousImport("THIRD_PARTY_NOTICES", .{ .root_source_file = notices_file });
    b.addNamedLazyPath("THIRD_PARTY_NOTICES", notices_file);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(notices_file, .lib, "THIRD_PARTY_NOTICES").step);
    b.addNamedLazyPath("package/audiocodec", b.path(""));
}

/// Appends `files` of `dep` to `notices` (read at configure time: packages are immutable) and
/// exposes the package root as `package/<name>` for the license scan in test/.
fn addNotice(b: *std.Build, notices: *std.ArrayList(u8), dep: *std.Build.Dependency, name: []const u8, source: []const u8, files: []const []const u8, preamble: []const u8) void {
    const gpa = b.allocator;
    notices.print(gpa, "\n\n==== {s}  {s}\n\n{s}", .{ name, source, preamble }) catch @panic("OOM");
    for (files) |file| {
        const text = dep.builder.build_root.handle.readFileAlloc(b.graph.io, file, gpa, .unlimited) catch |err|
            std.debug.panic("{s}: cannot read license file {s}: {t}", .{ name, file, err });
        notices.appendSlice(gpa, text) catch @panic("OOM");
        notices.append(gpa, '\n') catch @panic("OOM");
    }
    b.addNamedLazyPath(b.fmt("package/{s}", .{name}), dep.path(""));
}
