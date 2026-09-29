//! Routes every heap allocation of the vendored C libraries to a std.mem.Allocator.
//!
//! The C hooks are process-global and have no per-instance context, so the target allocator is a
//! threadlocal: every Decoder/Encoder method that calls into C does
//! `const prev = c_allocator.set(self.allocator); defer c_allocator.restore(prev);`.
//! The C libs only allocate and free inside such calls, so a block is always freed through the
//! allocator that made it. Outside a call, allocations fail (return NULL) and the lib reports OOM.
//! ponytail: no C worker threads may allocate (the module builds libFLAC without pthreads).

const std = @import("std");

pub const c = struct {
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
};

const Allocator = std.mem.Allocator;

threadlocal var current: ?Allocator = null;

/// True once a C allocation on this thread returned NULL since the last `set`. Some C code can
/// only report that as a generic error or even swallows it (libvorbis); backends check this after
/// the call and return error.OutOfMemory.
pub threadlocal var failed: bool = false;

/// Makes `allocator` receive this thread's C allocations; returns the previous one for `restore`.
pub fn set(allocator: Allocator) ?Allocator {
    install();
    const prev = current;
    current = allocator;
    failed = false;
    return prev;
}

pub fn restore(prev: ?Allocator) void {
    current = prev;
}

/// C code only guarantees alignof(max_align_t) (16 on every supported target); the header in front
/// of each block stores its size, since C free() does not pass one.
const header = 16;
const alignment: std.mem.Alignment = .@"16";

fn block(ptr: *anyopaque) []u8 {
    const base: [*]u8 = @as([*]u8, @ptrCast(ptr)) - header;
    const size = @as(*const usize, @ptrCast(@alignCast(base))).*;
    return base[0 .. header + size];
}

fn finish(base: [*]u8, size: usize) *anyopaque {
    @as(*usize, @ptrCast(@alignCast(base))).* = size;
    return base + header;
}

fn oom() ?*anyopaque {
    failed = true;
    return null;
}

fn alloc(_: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    const allocator = current orelse return oom();
    const len = std.math.add(usize, size, header) catch return oom();
    const base = allocator.rawAlloc(len, alignment, @returnAddress()) orelse return oom();
    return finish(base, size);
}

fn realloc(ctx: ?*anyopaque, ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    const old_ptr = ptr orelse return alloc(ctx, new_size);
    const allocator = current orelse return oom();
    const old = block(old_ptr);
    const len = std.math.add(usize, new_size, header) catch return oom();
    if (allocator.rawRemap(old, alignment, len, @returnAddress())) |base| return finish(base, new_size);
    const new_ptr = alloc(ctx, new_size) orelse return null;
    const keep = @min(old.len, len) - header;
    @memcpy(@as([*]u8, @ptrCast(new_ptr))[0..keep], old[header..][0..keep]);
    allocator.rawFree(old, alignment, @returnAddress());
    return new_ptr;
}

fn free(_: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void {
    // A free outside a set/restore scope is a bug in our wrapper: the block would leak.
    current.?.rawFree(block(ptr orelse return), alignment, @returnAddress());
}

fn hook(comptime T: type) T {
    return .{ .ctx = null, .alloc = alloc, .realloc = realloc, .free = free };
}

const ogg_hook = hook(c.ogg.ogg_allocator);
const opus_hook = hook(c.opus.opus_allocator);
const ope_hook = hook(c.opusenc.ope_allocator);
const flac_hook = hook(c.flac.FLAC__Allocator);
const minimp4_hook = hook(c.minimp4.minimp4_allocator);
const fdk_hook = hook(c.fdk_aac.fdk_allocator);

var install_state: std.atomic.Value(u8) = .init(0); // 0 none, 1 installing, 2 done

fn install() void {
    if (install_state.load(.acquire) == 2) return;
    if (install_state.cmpxchgStrong(0, 1, .acquire, .acquire) != null) {
        while (install_state.load(.acquire) != 2) std.atomic.spinLoopHint();
        return;
    }
    c.ogg.ogg_set_allocator(&ogg_hook);
    c.opus.opus_set_allocator(&opus_hook);
    c.opusenc.ope_set_allocator(&ope_hook);
    c.flac.FLAC__set_allocator(&flac_hook);
    c.minimp4.minimp4_set_allocator(&minimp4_hook);
    c.fdk_aac.fdk_set_allocator(&fdk_hook);
    install_state.store(2, .release);
}

fn drMalloc(size: usize, ctx: ?*anyopaque) callconv(.c) ?*anyopaque {
    return alloc(ctx, size);
}

fn drRealloc(ptr: ?*anyopaque, size: usize, ctx: ?*anyopaque) callconv(.c) ?*anyopaque {
    return realloc(ctx, ptr, size);
}

fn drFree(ptr: ?*anyopaque, ctx: ?*anyopaque) callconv(.c) void {
    free(ctx, ptr);
}

/// dr_mp3 takes callbacks per instance instead of a global hook; pass these to drmp3_init*.
/// They use the same threadlocal, so the calls still need a set/restore scope.
pub const drmp3_callbacks: c.dr_mp3.drmp3_allocation_callbacks = .{
    .pUserData = null,
    .onMalloc = drMalloc,
    .onRealloc = drRealloc,
    .onFree = drFree,
};
