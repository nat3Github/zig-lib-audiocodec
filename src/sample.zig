//! Conversion between stored sample layouts and the API sample types (i16, i32, f32).
//! int <-> int: left-aligned shifts (truncating). int -> float: x / 2^(bits-1).
//! float -> int: x * 2^(bits-1), rounded, clamped, NaN -> 0. No dither (caller's signal chain).

const std = @import("std");
const SampleFormat = @import("root.zig").SampleFormat;
const Endian = std.builtin.Endian;

pub const Layout = struct {
    format: SampleFormat,
    endian: Endian,
    /// 8-bit stored as offset binary (wav).
    unsigned8: bool = false,
};

pub fn size(format: SampleFormat) u8 {
    return switch (format) {
        .i8 => 1,
        .i16 => 2,
        .i24 => 3,
        .i32, .f32 => 4,
        .f64 => 8,
    };
}

fn Stored(comptime format: SampleFormat) type {
    return switch (format) {
        .i8 => i8,
        .i16 => i16,
        .i24 => i24,
        .i32 => i32,
        .f32 => f32,
        .f64 => f64,
    };
}

/// Decodes `out.len` samples from `in` (`out.len * size(layout.format)` bytes).
pub fn decode(comptime T: type, out: []T, in: []const u8, layout: Layout) void {
    switch (layout.format) {
        inline else => |format| switch (layout.endian) {
            inline else => |endian| {
                const S = Stored(format);
                const n = comptime size(format);
                std.debug.assert(in.len == out.len * n);
                for (out, 0..) |*o, i| {
                    const bytes = in[i * n ..][0..n];
                    o.* = switch (@typeInfo(S)) {
                        .int => fromInt(T, leftAlign(S, load(S, bytes, endian, layout.unsigned8))),
                        else => fromFloat(T, load(S, bytes, endian, false)),
                    };
                }
            },
        },
    }
}

/// Encodes `in` into `out` (`in.len * size(layout.format)` bytes).
pub fn encode(comptime T: type, out: []u8, in: []const T, layout: Layout) void {
    switch (layout.format) {
        inline else => |format| switch (layout.endian) {
            inline else => |endian| {
                const S = Stored(format);
                const n = comptime size(format);
                std.debug.assert(out.len == in.len * n);
                for (in, 0..) |x, i| store(S, out[i * n ..][0..n], convert(S, x), endian, layout.unsigned8);
            },
        },
    }
}

/// Converts one sample between any two of i8 i16 i24 i32 f32 f64 by the rules above.
pub fn convert(comptime To: type, x: anytype) To {
    const From = @TypeOf(x);
    return switch (@typeInfo(From)) {
        .int => switch (@typeInfo(To)) {
            .int => narrow(To, leftAlign(From, x)),
            else => @floatCast(@as(f64, @floatFromInt(x)) / scale(From)),
        },
        else => fromFloat(To, x),
    };
}

fn load(comptime S: type, bytes: *const [@divExact(@bitSizeOf(S), 8)]u8, endian: Endian, unsigned8: bool) S {
    const U = std.meta.Int(.unsigned, @bitSizeOf(S));
    var u = std.mem.readInt(U, bytes, endian);
    if (S == i8 and unsigned8) u ^= 0x80;
    return @bitCast(u);
}

fn store(comptime S: type, bytes: *[@divExact(@bitSizeOf(S), 8)]u8, x: S, endian: Endian, unsigned8: bool) void {
    const U = std.meta.Int(.unsigned, @bitSizeOf(S));
    var u: U = @bitCast(x);
    if (S == i8 and unsigned8) u ^= 0x80;
    std.mem.writeInt(U, bytes, u, endian);
}

fn leftAlign(comptime S: type, x: S) i32 {
    return @as(i32, x) << (32 - @bitSizeOf(S));
}

fn narrow(comptime To: type, x: i32) To {
    return @intCast(x >> (32 - @bitSizeOf(To)));
}

fn fromInt(comptime T: type, x: i32) T {
    return switch (@typeInfo(T)) {
        .int => narrow(T, x),
        else => @floatCast(@as(f64, @floatFromInt(x)) / scale(i32)),
    };
}

fn fromFloat(comptime T: type, x: anytype) T {
    if (@typeInfo(T) == .float) return @floatCast(x);
    const v: f64 = x;
    if (std.math.isNan(v)) return 0;
    const scaled = @round(v * scale(T));
    return @intFromFloat(std.math.clamp(scaled, @as(f64, std.math.minInt(T)), @as(f64, std.math.maxInt(T))));
}

fn scale(comptime I: type) f64 {
    return @floatFromInt(@as(i64, 1) << (@bitSizeOf(I) - 1));
}
