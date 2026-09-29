//! Routes every heap allocation of the vendored C libraries to a std.mem.Allocator.
//!
//! The C libs compile against libc/include, which declares malloc & co. as avc_malloc ...;
//! src/libc.zig exports the functions below under those names. C has no per-instance context,
//! so the target allocator is a threadlocal: every Decoder/Encoder method that calls into C does
//! `const prev = c_allocator.set(self.allocator); defer c_allocator.restore(prev);`.
//! The C libs only allocate and free inside such calls, so a block is always freed through the
//! allocator that made it. Outside a call, allocations fail (return NULL) and the lib reports OOM.
//! ponytail: no C worker threads may allocate (the module builds libFLAC without pthreads).

const std = @import("std");
const Allocator = std.mem.Allocator;

threadlocal var current: ?Allocator = null;

/// True once a C allocation on this thread returned NULL since the last `set`. Some C code can
/// only report that as a generic error or even swallows it (libvorbis); backends check this after
/// the call and return error.OutOfMemory.
pub threadlocal var failed: bool = false;

/// Makes `allocator` receive this thread's C allocations; returns the previous one for `restore`.
pub fn set(allocator: Allocator) ?Allocator {
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

pub fn malloc(size: usize) callconv(.c) ?*anyopaque {
    return alloc(current orelse return oom(), size) orelse oom();
}

pub fn calloc(count: usize, size: usize) callconv(.c) ?*anyopaque {
    const total = std.math.mul(usize, count, size) catch return oom();
    const ptr = malloc(total) orelse return null;
    @memset(@as([*]u8, @ptrCast(ptr))[0..total], 0);
    return ptr;
}

pub fn realloc(ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    return resize(current orelse return oom(), ptr, new_size) orelse oom();
}

pub fn free(ptr: ?*anyopaque) callconv(.c) void {
    // A free outside a set/restore scope is a bug in our wrapper: the block would leak.
    release(current.?, ptr);
}

/// malloc / realloc / free with an explicit allocator, for C libs that take allocation callbacks
/// with a context pointer (dr_mp3). They do not touch `failed`.
pub fn alloc(allocator: Allocator, size: usize) ?*anyopaque {
    const len = std.math.add(usize, size, header) catch return null;
    const base = allocator.rawAlloc(len, alignment, @returnAddress()) orelse return null;
    return finish(base, size);
}

pub fn resize(allocator: Allocator, ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    const old_ptr = ptr orelse return alloc(allocator, new_size);
    const old = block(old_ptr);
    const len = std.math.add(usize, new_size, header) catch return null;
    if (allocator.rawRemap(old, alignment, len, @returnAddress())) |base| return finish(base, new_size);
    const new_ptr = alloc(allocator, new_size) orelse return null;
    const keep = @min(old.len, len) - header;
    @memcpy(@as([*]u8, @ptrCast(new_ptr))[0..keep], old[header..][0..keep]);
    allocator.rawFree(old, alignment, @returnAddress());
    return new_ptr;
}

pub fn release(allocator: Allocator, ptr: ?*anyopaque) void {
    allocator.rawFree(block(ptr orelse return), alignment, @returnAddress());
}

pub fn strdup(s: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const len = std.mem.len(s) + 1;
    const copy: [*]u8 = @ptrCast(malloc(len) orelse return null);
    @memcpy(copy[0..len], s[0..len]);
    return @ptrCast(copy);
}
