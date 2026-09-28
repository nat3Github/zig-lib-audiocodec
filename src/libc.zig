//! The part of libc the vendored C libraries need, so they build with `link_libc = false`.
//!
//! Declared in libc/include/*.h. Functions compiler_rt already exports (mem*, strlen, sin, cos,
//! exp, log, floor, sqrt, ...) keep their names; everything else is exported as `avc_<name>`
//! (the headers map the C name with an asm label), so it never clashes with a real libc linked
//! into the same program. The printf family is in libc/printf.c.
//! There is no file system: FILE / fd / stat functions fail with ENOSYS. The libs are only used
//! through their callback and memory APIs.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    for (@typeInfo(exports).@"struct".decls) |decl| {
        @export(&@field(exports, decl.name), .{ .name = "avc_" ++ decl.name });
    }
}

const ENOENT = 2;
const EINVAL = 22;
const ERANGE = 34;
const ENOSYS = 38;
const EILSEQ = 84;

threadlocal var errno_value: c_int = 0;

fn fail(comptime T: type, code: c_int) T {
    errno_value = code;
    return switch (@typeInfo(T)) {
        .optional => null,
        .int => if (@typeInfo(T).int.signedness == .signed) -1 else std.math.maxInt(T),
        .void => {},
        else => @compileError("fail: " ++ @typeName(T)),
    };
}

const FILE = anyopaque;
const off_t = c_longlong;
const time_t = c_longlong;
const Stat = anyopaque;
/// clang: unsigned short on Windows, int elsewhere
const wchar_t = if (builtin.target.os.tag == .windows) u16 else u32;
const ComparFn = *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int;

fn span(s: [*:0]const u8) []const u8 {
    return std.mem.span(s);
}

fn lower(c: u8) u8 {
    return std.ascii.toLower(c);
}

fn isSpace(c: u8) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

/// Everything exported as avc_<decl name>. Public so test/nm_check.zig can list the names.
pub const exports = struct {
    // errno.h, assert.h, stdlib.h process control
    pub fn errno_location() callconv(.c) *c_int {
        return &errno_value;
    }
    pub fn assert_fail(expr: [*:0]const u8, file: [*:0]const u8, line: c_int) callconv(.c) noreturn {
        std.debug.panic("C assertion failed: {s} ({s}:{d})", .{ expr, file, line });
    }
    pub fn abort() callconv(.c) noreturn {
        @panic("C abort()");
    }
    pub fn exit(status: c_int) callconv(.c) noreturn {
        std.debug.panic("C exit({d})", .{status});
    }
    pub fn getenv(_: [*:0]const u8) callconv(.c) ?[*:0]u8 {
        return null;
    }

    // string.h / strings.h
    pub fn memchr(s: [*]const u8, c: c_int, n: usize) callconv(.c) ?*anyopaque {
        const i = std.mem.indexOfScalar(u8, s[0..n], @truncate(@as(c_uint, @bitCast(c)))) orelse return null;
        return @constCast(s + i);
    }
    pub fn strchr(s: [*:0]const u8, c: c_int) callconv(.c) ?[*:0]u8 {
        const ch: u8 = @truncate(@as(c_uint, @bitCast(c)));
        const str = span(s);
        // the terminator counts as part of the string
        const i = if (ch == 0) str.len else std.mem.indexOfScalar(u8, str, ch) orelse return null;
        return @constCast(s + i);
    }
    pub fn strrchr(s: [*:0]const u8, c: c_int) callconv(.c) ?[*:0]u8 {
        const ch: u8 = @truncate(@as(c_uint, @bitCast(c)));
        const str = span(s);
        const i = if (ch == 0) str.len else std.mem.lastIndexOfScalar(u8, str, ch) orelse return null;
        return @constCast(s + i);
    }
    pub fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) callconv(.c) ?[*:0]u8 {
        const i = std.mem.indexOf(u8, span(haystack), span(needle)) orelse return null;
        return @constCast(haystack + i);
    }
    pub fn strcmp(a: [*:0]const u8, b: [*:0]const u8) callconv(.c) c_int {
        return strncmp(a, b, std.math.maxInt(usize));
    }
    pub fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) callconv(.c) c_int {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (a[i] != b[i] or a[i] == 0) return @as(c_int, a[i]) - b[i];
        }
        return 0;
    }
    pub fn strcasecmp(a: [*:0]const u8, b: [*:0]const u8) callconv(.c) c_int {
        return strncasecmp(a, b, std.math.maxInt(usize));
    }
    pub fn strncasecmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) callconv(.c) c_int {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (lower(a[i]) != lower(b[i]) or a[i] == 0) return @as(c_int, lower(a[i])) - lower(b[i]);
        }
        return 0;
    }
    pub fn strcpy(dest: [*]u8, src: [*:0]const u8) callconv(.c) [*]u8 {
        const str = span(src);
        @memcpy(dest[0 .. str.len + 1], src[0 .. str.len + 1]);
        return dest;
    }
    pub fn strncpy(dest: [*]u8, src: [*:0]const u8, n: usize) callconv(.c) [*]u8 {
        const len = std.mem.indexOfSentinel(u8, 0, src);
        const copy = @min(len, n);
        @memcpy(dest[0..copy], src[0..copy]);
        @memset(dest[copy..n], 0);
        return dest;
    }
    pub fn strcat(dest: [*:0]u8, src: [*:0]const u8) callconv(.c) [*:0]u8 {
        _ = strcpy(dest + span(dest).len, src);
        return dest;
    }
    pub fn strncat(dest: [*:0]u8, src: [*:0]const u8, n: usize) callconv(.c) [*:0]u8 {
        const end = dest + span(dest).len;
        const copy = @min(std.mem.indexOfSentinel(u8, 0, src), n);
        @memcpy(end[0..copy], src[0..copy]);
        end[copy] = 0;
        return dest;
    }
    pub fn strerror(_: c_int) callconv(.c) [*:0]const u8 {
        return "error";
    }

    // stdlib.h
    pub fn qsort(base: ?*anyopaque, count: usize, size: usize, compar: ComparFn) callconv(.c) void {
        if (count < 2) return;
        const bytes: [*]u8 = @ptrCast(base.?);
        const Context = struct {
            bytes: [*]u8,
            size: usize,
            compar: ComparFn,
            fn item(ctx: @This(), i: usize) []u8 {
                return ctx.bytes[i * ctx.size ..][0..ctx.size];
            }
            pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                return ctx.compar(ctx.item(a).ptr, ctx.item(b).ptr) < 0;
            }
            pub fn swap(ctx: @This(), a: usize, b: usize) void {
                const x = ctx.item(a);
                const y = ctx.item(b);
                for (x, y) |*p, *q| std.mem.swap(u8, p, q);
            }
        };
        std.sort.pdqContext(0, count, Context{ .bytes = bytes, .size = size, .compar = compar });
    }
    pub fn strtod(s: [*:0]const u8, end: ?*[*:0]const u8) callconv(.c) f64 {
        const str = span(s);
        var start: usize = 0;
        while (start < str.len and isSpace(str[start])) start += 1;
        const len = floatPrefix(str[start..]);
        if (len == 0) {
            if (end) |e| e.* = s;
            return 0;
        }
        if (end) |e| e.* = s + start + len;
        const value = std.fmt.parseFloat(f64, str[start..][0..len]) catch unreachable;
        if (std.math.isInf(value) and !std.ascii.isAlphabetic(str[start + len - 1])) errno_value = ERANGE;
        return value;
    }
    pub fn atof(s: [*:0]const u8) callconv(.c) f64 {
        return strtod(s, null);
    }
    pub fn strtol(s: [*:0]const u8, end: ?*[*:0]const u8, base: c_int) callconv(.c) c_long {
        return strtoInt(c_long, s, end, base);
    }
    pub fn strtoul(s: [*:0]const u8, end: ?*[*:0]const u8, base: c_int) callconv(.c) c_ulong {
        return strtoInt(c_ulong, s, end, base);
    }
    pub fn atoi(s: [*:0]const u8) callconv(.c) c_int {
        return @truncate(strtol(s, null, 10));
    }
    pub fn arc4random() callconv(.c) u32 {
        // ponytail: not cryptographic; opusenc only uses it for the Ogg serial number.
        // Seeded from a stack address (ASLR) and a counter. Use std.Io randomness if it matters.
        const State = struct {
            var counter: std.atomic.Value(u32) = .init(0); // u32: no 64-bit atomics on some 32-bit targets
        };
        var seed: u8 = 0;
        var x: u64 = @as(u64, @intFromPtr(&seed)) +% @as(u64, State.counter.fetchAdd(1, .monotonic)) *% 0x9e3779b97f4a7c15;
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        return @truncate(x ^ (x >> 31));
    }

    // math.h
    pub fn pow(x: f64, y: f64) callconv(.c) f64 {
        return std.math.pow(f64, x, y);
    }
    pub fn powf(x: f32, y: f32) callconv(.c) f32 {
        return std.math.pow(f32, x, y);
    }
    pub fn acos(x: f64) callconv(.c) f64 {
        return std.math.acos(x);
    }
    pub fn acosf(x: f32) callconv(.c) f32 {
        return std.math.acos(x);
    }
    pub fn asin(x: f64) callconv(.c) f64 {
        return std.math.asin(x);
    }
    pub fn asinf(x: f32) callconv(.c) f32 {
        return std.math.asin(x);
    }
    pub fn atan(x: f64) callconv(.c) f64 {
        return std.math.atan(x);
    }
    pub fn atanf(x: f32) callconv(.c) f32 {
        return std.math.atan(x);
    }
    pub fn atan2(y: f64, x: f64) callconv(.c) f64 {
        return std.math.atan2(y, x);
    }
    pub fn atan2f(y: f32, x: f32) callconv(.c) f32 {
        return std.math.atan2(y, x);
    }
    pub fn sinh(x: f64) callconv(.c) f64 {
        return std.math.sinh(x);
    }
    pub fn cosh(x: f64) callconv(.c) f64 {
        return std.math.cosh(x);
    }
    pub fn tanh(x: f64) callconv(.c) f64 {
        return std.math.tanh(x);
    }
    pub fn tanhf(x: f32) callconv(.c) f32 {
        return std.math.tanh(x);
    }
    pub fn ldexp(x: f64, n: c_int) callconv(.c) f64 {
        return std.math.ldexp(x, n);
    }
    pub fn ldexpf(x: f32, n: c_int) callconv(.c) f32 {
        return std.math.ldexp(x, n);
    }
    pub fn frexp(x: f64, e: *c_int) callconv(.c) f64 {
        const r = std.math.frexp(x);
        e.* = r.exponent;
        return r.significand;
    }
    pub fn frexpf(x: f32, e: *c_int) callconv(.c) f32 {
        const r = std.math.frexp(x);
        e.* = r.exponent;
        return r.significand;
    }
    pub fn modf(x: f64, ipart: *f64) callconv(.c) f64 {
        const r = std.math.modf(x);
        ipart.* = r.ipart;
        return r.fpart;
    }
    pub fn hypot(x: f64, y: f64) callconv(.c) f64 {
        return std.math.hypot(x, y);
    }
    pub fn rint(x: f64) callconv(.c) f64 {
        return roundEven(x);
    }
    pub fn rintf(x: f32) callconv(.c) f32 {
        return roundEven(x);
    }
    pub fn lrint(x: f64) callconv(.c) c_long {
        return toLong(roundEven(x));
    }
    pub fn lrintf(x: f32) callconv(.c) c_long {
        return toLong(roundEven(x));
    }
    pub fn lround(x: f64) callconv(.c) c_long {
        return toLong(@round(x));
    }
    pub fn lroundf(x: f32) callconv(.c) c_long {
        return toLong(@round(x));
    }

    // wchar.h
    pub fn wcslen(s: [*:0]const wchar_t) callconv(.c) usize {
        return std.mem.indexOfSentinel(wchar_t, 0, s);
    }
    pub fn wcsrtombs(_: ?[*]u8, _: *?[*:0]const wchar_t, _: usize, _: ?*anyopaque) callconv(.c) usize {
        return fail(usize, EILSEQ);
    }

    // stdio.h: no files
    pub const stdin: ?*FILE = null;
    pub const stdout: ?*FILE = null;
    pub const stderr: ?*FILE = null;
    pub fn fopen(_: [*:0]const u8, _: [*:0]const u8) callconv(.c) ?*FILE {
        return fail(?*FILE, ENOSYS);
    }
    pub fn fdopen(_: c_int, _: [*:0]const u8) callconv(.c) ?*FILE {
        return fail(?*FILE, ENOSYS);
    }
    pub fn freopen(_: ?[*:0]const u8, _: [*:0]const u8, _: ?*FILE) callconv(.c) ?*FILE {
        return fail(?*FILE, ENOSYS);
    }
    pub fn tmpfile() callconv(.c) ?*FILE {
        return fail(?*FILE, ENOSYS);
    }
    pub fn fclose(_: ?*FILE) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn fread(_: ?*anyopaque, _: usize, _: usize, _: ?*FILE) callconv(.c) usize {
        errno_value = ENOSYS;
        return 0;
    }
    pub fn fwrite(_: ?*const anyopaque, _: usize, _: usize, _: ?*FILE) callconv(.c) usize {
        errno_value = ENOSYS;
        return 0;
    }
    pub fn fseek(_: ?*FILE, _: c_long, _: c_int) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn ftell(_: ?*FILE) callconv(.c) c_long {
        return fail(c_long, ENOSYS);
    }
    pub fn fseeko(_: ?*FILE, _: off_t, _: c_int) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn ftello(_: ?*FILE) callconv(.c) off_t {
        return fail(off_t, ENOSYS);
    }
    pub fn rewind(_: ?*FILE) callconv(.c) void {}
    pub fn feof(_: ?*FILE) callconv(.c) c_int {
        return 1;
    }
    pub fn ferror(_: ?*FILE) callconv(.c) c_int {
        return 1;
    }
    pub fn clearerr(_: ?*FILE) callconv(.c) void {}
    pub fn fflush(_: ?*FILE) callconv(.c) c_int {
        return 0;
    }
    pub fn fileno(_: ?*FILE) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn setvbuf(_: ?*FILE, _: ?[*]u8, _: c_int, _: usize) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn fgetc(_: ?*FILE) callconv(.c) c_int {
        return -1; // EOF
    }
    pub fn getchar() callconv(.c) c_int {
        return -1;
    }
    pub fn ungetc(_: c_int, _: ?*FILE) callconv(.c) c_int {
        return -1;
    }
    pub fn fgets(_: [*]u8, _: c_int, _: ?*FILE) callconv(.c) ?[*]u8 {
        return null;
    }
    pub fn fputc(c: c_int, _: ?*FILE) callconv(.c) c_int {
        return c; // discarded, like printf
    }
    pub fn fputs(_: [*:0]const u8, _: ?*FILE) callconv(.c) c_int {
        return 0;
    }
    pub fn puts(_: [*:0]const u8) callconv(.c) c_int {
        return 0;
    }
    pub fn remove(_: [*:0]const u8) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn rename(_: [*:0]const u8, _: [*:0]const u8) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn perror(_: ?[*:0]const u8) callconv(.c) void {}

    // unistd.h, fcntl.h, sys/stat.h, utime.h: no file system
    pub fn getpid() callconv(.c) c_int {
        return 0;
    }
    pub fn read(_: c_int, _: ?*anyopaque, _: usize) callconv(.c) isize {
        return fail(isize, ENOSYS);
    }
    pub fn write(_: c_int, _: ?*const anyopaque, _: usize) callconv(.c) isize {
        return fail(isize, ENOSYS);
    }
    pub fn close(_: c_int) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn lseek(_: c_int, _: off_t, _: c_int) callconv(.c) off_t {
        return fail(off_t, ENOSYS);
    }
    pub fn unlink(_: [*:0]const u8) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn readlink(_: [*:0]const u8, _: [*]u8, _: usize) callconv(.c) isize {
        return fail(isize, ENOSYS);
    }
    pub fn chown(_: [*:0]const u8, _: c_uint, _: c_uint) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn isatty(_: c_int) callconv(.c) c_int {
        return 0;
    }
    // Declared variadic in C; the extra argument is never read.
    pub fn open(_: [*:0]const u8, _: c_int) callconv(.c) c_int {
        return fail(c_int, ENOENT);
    }
    pub fn stat(_: [*:0]const u8, _: *Stat) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn fstat(_: c_int, _: *Stat) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn chmod(_: [*:0]const u8, _: c_uint) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }
    pub fn utime(_: [*:0]const u8, _: ?*const anyopaque) callconv(.c) c_int {
        return fail(c_int, ENOSYS);
    }

    // time.h: no clock
    pub fn time(t: ?*time_t) callconv(.c) time_t {
        if (t) |p| p.* = -1;
        return fail(time_t, ENOSYS);
    }
    pub fn clock() callconv(.c) c_long {
        return -1;
    }
    pub fn clock_gettime(_: c_int, _: *anyopaque) callconv(.c) c_int {
        return fail(c_int, EINVAL);
    }
};

fn roundEven(x: anytype) @TypeOf(x) {
    const r = @round(x);
    // @round rounds halfway away from zero; C's default rounding mode rounds to even
    if (@abs(x - @trunc(x)) == 0.5) return 2 * @round(x / 2);
    return r;
}

fn toLong(x: anytype) c_long {
    const min: @TypeOf(x) = @floatFromInt(std.math.minInt(c_long));
    if (std.math.isNan(x) or x < min or x >= -min) return std.math.minInt(c_long);
    return @intFromFloat(x);
}

/// Length of the longest prefix of `s` that parseFloat accepts the way strtod does:
/// [+-] (digits [. digits] | . digits) [(e|E) [+-] digits], or [+-] inf / infinity / nan.
fn floatPrefix(s: []const u8) usize {
    var i: usize = 0;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
    for ([_][]const u8{ "infinity", "inf", "nan" }) |word| {
        if (s.len - i >= word.len and std.ascii.eqlIgnoreCase(s[i..][0..word.len], word)) return i + word.len;
    }
    const int_start = i;
    while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
    var digits = i - int_start;
    if (i < s.len and s[i] == '.') {
        const frac_start = i + 1;
        var j = frac_start;
        while (j < s.len and std.ascii.isDigit(s[j])) j += 1;
        digits += j - frac_start;
        if (digits > 0) i = j;
    }
    if (digits == 0) return 0;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        var j = i + 1;
        if (j < s.len and (s[j] == '+' or s[j] == '-')) j += 1;
        const exp_start = j;
        while (j < s.len and std.ascii.isDigit(s[j])) j += 1;
        if (j > exp_start) i = j;
    }
    return i;
}

fn strtoInt(comptime T: type, s: [*:0]const u8, end: ?*[*:0]const u8, base_arg: c_int) T {
    const str = span(s);
    var i: usize = 0;
    while (i < str.len and isSpace(str[i])) i += 1;
    var negative = false;
    if (i < str.len and (str[i] == '+' or str[i] == '-')) {
        negative = str[i] == '-';
        i += 1;
    }
    var base: u8 = @intCast(base_arg);
    const has_hex_prefix = i + 1 < str.len and str[i] == '0' and lower(str[i + 1]) == 'x' and
        i + 2 < str.len and std.ascii.isHex(str[i + 2]);
    if ((base == 0 or base == 16) and has_hex_prefix) {
        base = 16;
        i += 2;
    } else if (base == 0) {
        base = if (i < str.len and str[i] == '0') 8 else 10;
    }
    const digits_start = i;
    var value: u64 = 0;
    var overflow = false;
    while (i < str.len) : (i += 1) {
        const d = std.fmt.charToDigit(str[i], base) catch break;
        const mul = @mulWithOverflow(value, base);
        const add = @addWithOverflow(mul[0], d);
        overflow = overflow or mul[1] != 0 or add[1] != 0;
        value = add[0];
    }
    if (i == digits_start) {
        if (end) |e| e.* = s;
        return 0;
    }
    if (end) |e| e.* = s + i;
    if (@typeInfo(T).int.signedness == .signed) {
        const limit: u64 = if (negative) @as(u64, std.math.maxInt(T)) + 1 else std.math.maxInt(T);
        if (overflow or value > limit) {
            errno_value = ERANGE;
            return if (negative) std.math.minInt(T) else std.math.maxInt(T);
        }
        return if (negative) @intCast(-@as(i128, value)) else @intCast(value);
    }
    if (overflow or value > std.math.maxInt(T)) {
        errno_value = ERANGE;
        return std.math.maxInt(T);
    }
    return if (negative) 0 -% @as(T, @intCast(value)) else @intCast(value);
}

test "strtod" {
    var end: [*:0]const u8 = undefined;
    const s: [*:0]const u8 = "  -1.5e3x";
    try std.testing.expectEqual(-1500.0, exports.strtod(s, &end));
    try std.testing.expectEqual(@as(u8, 'x'), end[0]);
    try std.testing.expectEqual(0.5, exports.strtod("0.5)", null));
    try std.testing.expectEqual(3.0, exports.strtod("3.e", null));
    const bad: [*:0]const u8 = "abc";
    try std.testing.expectEqual(0.0, exports.strtod(bad, &end));
    try std.testing.expectEqual(bad, end);
    try std.testing.expect(std.math.isInf(exports.strtod("-inf", null)));
}

test "strtol" {
    try std.testing.expectEqual(-42, exports.strtol(" -42z", null, 10));
    try std.testing.expectEqual(255, exports.strtol("0xff", null, 0));
    try std.testing.expectEqual(8, exports.strtol("010", null, 0));
    try std.testing.expectEqual(std.math.maxInt(c_long), exports.strtol("99999999999999999999999", null, 10));
}

test "qsort" {
    const cmp = struct {
        fn f(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
            const x: *const i32 = @ptrCast(@alignCast(a.?));
            const y: *const i32 = @ptrCast(@alignCast(b.?));
            return @as(c_int, @intFromBool(x.* > y.*)) - @intFromBool(x.* < y.*);
        }
    }.f;
    var v = [_]i32{ 5, -1, 3, 3, 0, 9, -7 };
    exports.qsort(&v, v.len, @sizeOf(i32), cmp);
    try std.testing.expectEqualSlices(i32, &.{ -7, -1, 0, 3, 3, 5, 9 }, &v);
}

test "string" {
    const s: [*:0]const u8 = "a,b,c";
    try std.testing.expectEqual(s + 1, exports.strchr(s, ','));
    try std.testing.expectEqual(s + 3, exports.strrchr(s, ','));
    try std.testing.expectEqual(s + 5, exports.strchr(s, 0));
    try std.testing.expectEqual(null, exports.strchr(s, 'z'));
    try std.testing.expectEqual(s + 2, exports.strstr(s, "b,"));
    try std.testing.expect(exports.strcmp("abc", "abd") < 0);
    try std.testing.expect(exports.strcmp("ab", "abc") < 0);
    try std.testing.expectEqual(0, exports.strncasecmp("TITLE=x", "title=y", 6));
}

test "rounding" {
    try std.testing.expectEqual(2.0, exports.rint(2.5));
    try std.testing.expectEqual(-4.0, exports.rint(-3.5));
    try std.testing.expectEqual(3, exports.lround(2.5));
    try std.testing.expectEqual(2, exports.lrintf(2.5));
    var e: c_int = 0;
    try std.testing.expectEqual(0.75, exports.frexp(6.0, &e));
    try std.testing.expectEqual(3, e);
}

test "snprintf" {
    const snprintf = @extern(*const fn ([*]u8, usize, [*:0]const u8, ...) callconv(.c) c_int, .{ .name = "avc_snprintf" });
    var buf: [32]u8 = undefined;
    try std.testing.expectEqual(22, snprintf(&buf, buf.len, "%s, %d|%-3u|%05ld|%x %c%%", "ab", @as(c_int, -7), @as(c_uint, 9), @as(c_long, -42), @as(c_uint, 255), @as(c_int, 'z')));
    try std.testing.expectEqualStrings("ab, -7|9  |-0042|ff z%", std.mem.sliceTo(&buf, 0));
    try std.testing.expectEqual(22, snprintf(&buf, 5, "%s, %d|%-3u|%05ld|%x %c%%", "ab", @as(c_int, -7), @as(c_uint, 9), @as(c_long, -42), @as(c_uint, 255), @as(c_int, 'z')));
    try std.testing.expectEqualStrings("ab, ", std.mem.sliceTo(&buf, 0));
    try std.testing.expectEqual(7, snprintf(&buf, buf.len, "%.3s%zu", "abcdef", @as(usize, 1234)));
    try std.testing.expectEqualStrings("abc1234", std.mem.sliceTo(&buf, 0));
}
