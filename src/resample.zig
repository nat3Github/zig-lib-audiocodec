//! Explicit sample rate conversion (r8brain, pure-Zig port). Nothing in the codec API resamples
//! implicitly; callers chain Decoder -> Resampler -> Encoder themselves.
//! Sample rate converter designed by Aleksey Vaneev of Voxengo.

const std = @import("std");
const Allocator = std.mem.Allocator;
const r8b = @import("r8brain");
const sample = @import("sample.zig");

const Stage = r8b.resampler.Resampler(f64);

pub const Resampler = struct {
    gpa: Allocator,
    channels: u16,
    in_rate: u32,
    out_rate: u32,
    // ponytail: filter cache owned per Resampler (init recomputes filters); share one across
    // Resamplers if init cost ever shows up in a profile. Heap-allocated: stages keep a pointer to it.
    cache: *r8b.FIRFilterCache,
    /// One mono stage per channel.
    stages: []*Stage,
    /// Deinterleaved input of one channel, `chunk_frames` long.
    scratch: []f64,
    /// Planar output of the last chunk not yet handed out: channel c at [c * max_out ..][0..pending_end].
    pending: []f64,
    max_out: usize,
    pending_start: usize = 0,
    pending_end: usize = 0,
    frames_in: u64 = 0,
    frames_out: u64 = 0,
    flushing: bool = false,

    pub const Quality = enum {
        /// ~136 dB stop band (r8brain CDSPResampler16).
        high,
        /// ~180 dB stop band (r8brain CDSPResampler24).
        max,
    };

    pub const Options = struct {
        channels: u16,
        in_rate: u32,
        out_rate: u32,
        quality: Quality = .high,
    };

    pub const Result = struct { consumed: usize, produced: usize };

    pub const Error = error{ InvalidOptions, OutOfMemory };

    const chunk_frames = 1024;
    /// Transition band in percent of the lower Nyquist frequency (r8brain's default).
    const transition_band = 2.0;

    pub fn init(gpa: Allocator, options: Options) Error!Resampler {
        if (options.channels == 0 or options.in_rate == 0 or options.out_rate == 0) return error.InvalidOptions;
        const attenuation: f64 = switch (options.quality) {
            .high => r8b.ResamplerQuality.quality16.attenuation(),
            .max => r8b.ResamplerQuality.quality24.attenuation(),
        };

        const cache = try gpa.create(r8b.FIRFilterCache);
        errdefer gpa.destroy(cache);
        cache.* = .init(gpa);
        errdefer cache.deinit();

        const stages = try gpa.alloc(*Stage, options.channels);
        errdefer gpa.free(stages);
        var created: usize = 0;
        errdefer for (stages[0..created]) |s| s.deinit();
        for (stages) |*s| {
            s.* = Stage.init(gpa, @floatFromInt(options.in_rate), @floatFromInt(options.out_rate), chunk_frames, transition_band, attenuation, .linearPhase, cache) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                // FFT size limits: ratio too extreme for the filter design.
                else => return error.InvalidOptions,
            };
            created += 1;
        }

        const scratch = try gpa.alloc(f64, chunk_frames);
        errdefer gpa.free(scratch);
        const max_out = stages[0].getMaxOutLen(chunk_frames);
        const pending = try gpa.alloc(f64, max_out * options.channels);

        return .{
            .gpa = gpa,
            .channels = options.channels,
            .in_rate = options.in_rate,
            .out_rate = options.out_rate,
            .cache = cache,
            .stages = stages,
            .scratch = scratch,
            .pending = pending,
            .max_out = max_out,
        };
    }

    pub fn deinit(r: *Resampler) void {
        for (r.stages) |s| s.deinit();
        r.gpa.free(r.stages);
        r.cache.deinit();
        r.gpa.destroy(r.cache);
        r.gpa.free(r.scratch);
        r.gpa.free(r.pending);
        r.* = undefined;
    }

    /// Input frames needed before the first output frame. The output itself is already aligned:
    /// output frame k is at input time k * in_rate / out_rate (r8brain drops its filter delay).
    pub fn latency(r: *Resampler) usize {
        return r.stages[0].getLatency();
    }

    /// Resamples interleaved `in` into interleaved `out` (T in {i16, i32, f32}). Consumes input only
    /// while `out` has room; returns frames consumed and produced. Call again with the rest.
    pub fn process(r: *Resampler, comptime T: type, in: []const T, out: []T) Result {
        std.debug.assert(!r.flushing);
        const ch = r.channels;
        const in_frames = in.len / ch;
        var result: Result = .{ .consumed = 0, .produced = 0 };
        while (true) {
            result.produced += r.drain(T, out[result.produced * ch ..], std.math.maxInt(u64));
            if (result.produced < out.len / ch and result.consumed < in_frames) {
                const n = @min(chunk_frames, in_frames - result.consumed);
                r.feed(T, in[result.consumed * ch ..][0 .. n * ch]);
                result.consumed += n;
                r.frames_in += n;
            } else return result;
        }
    }

    /// Ends the stream: writes the remaining output so that the total is round(frames_in * out_rate
    /// / in_rate). Returns frames written; call until it returns 0. `process` must not be called after.
    pub fn flush(r: *Resampler, comptime T: type, out: []T) usize {
        r.flushing = true;
        const total = (@as(u128, r.frames_in) * r.out_rate * 2 + r.in_rate) / (@as(u128, r.in_rate) * 2);
        var produced: usize = 0;
        while (true) {
            produced += r.drain(T, out[produced * r.channels ..], @intCast(total - r.frames_out));
            if (produced == out.len / r.channels or r.frames_out == total) return produced;
            r.feed(T, &.{});
        }
    }

    /// Runs one chunk (at most chunk_frames) through every channel into `pending`.
    /// Empty `in` feeds a chunk of silence (flush).
    fn feed(r: *Resampler, comptime T: type, in: []const T) void {
        std.debug.assert(r.pending_start == r.pending_end);
        const ch = r.channels;
        const n = if (in.len == 0) chunk_frames else in.len / ch;
        var produced: usize = 0;
        for (r.stages, 0..) |s, c| {
            if (in.len == 0) {
                @memset(r.scratch, 0);
            } else for (r.scratch[0..n], 0..) |*x, i| {
                const v = in[i * ch + c];
                // NaN would trip r8brain's input assertion and poison the filter state.
                x.* = if (@typeInfo(T) == .float and std.math.isNan(v)) 0 else sample.convert(f64, v);
            }
            produced = s.process(r.scratch[0..n], r.pending[c * r.max_out ..][0..r.max_out]);
        }
        r.pending_start = 0;
        r.pending_end = produced;
    }

    /// Moves up to `limit` pending frames into `out` (interleaved T).
    fn drain(r: *Resampler, comptime T: type, out: []T, limit: u64) usize {
        const ch = r.channels;
        const n: usize = @intCast(@min(r.pending_end - r.pending_start, out.len / ch, limit));
        for (0..n) |i| {
            for (0..ch) |c| out[i * ch + c] = sample.convert(T, r.pending[c * r.max_out + r.pending_start + i]);
        }
        r.pending_start += n;
        r.frames_out += n;
        return n;
    }
};
