//! MPEG audio (mp3, also layer I/II) decode through dr_mp3, ID3 tags through id3.zig.
//!
//! Layout of the source: ID3v2 tag(s), frames, [APE tag], [ID3v1]. We read the ID3v2 tags
//! ourselves and hand dr_mp3 the stream from the first frame on; its stream offsets are relative
//! to that point (`base`). With a Seeker, dr_mp3 finds ID3v1 / APE at the end itself and stops
//! before them; we read the ID3v1 fields first (APE is skipped, not parsed). Without a Seeker it
//! cannot, and minimp3 treats the 128 bytes like junk between frames (no output).
//!
//! Gapless: dr_mp3 reads the Xing/Info frame and the LAME tag (encoder delay + 529 decoder delay,
//! padding - 529) and trims both ends. `frames`: from the Xing/Info frame count when there is one
//! (also without a Seeker); else, with a Seeker, dr_mp3 counts every frame header once at open
//! (reads the whole file, no decoding); else null.
//!
//! Output: dr_mp3 built with DR_MP3_FLOAT_OUTPUT; f32 is read straight into `out`, i16/i32 are
//! converted once by sample.zig. Channel order: mono or L R.
//!
//! Format changes: dr_mp3 plays a stream whose rate or channel count changes mid-way at the first
//! frame's settings (and with a channel change, reads the new frame with the wrong stride). We read
//! at most one mp3 frame per call and check each new frame: at a change `read` returns the frames
//! before it, then error.UnsupportedFormat, like a vorbis chain. ponytail: `frames` from the header
//! scan counts all frames, the ones after the change included.
//!
//! Damage: minimp3 resyncs on the next valid frame header; a damaged frame is skipped, not an error.
//!
//! Allocation: dr_mp3's allocation callbacks go to gpa directly (per-instance context, no
//! threadlocal); an allocation failure sets `oom`, since dr_mp3 reports it as end of stream.

const std = @import("std");
const root = @import("root.zig");
const sample = @import("sample.zig");
const id3 = @import("id3.zig");
const c_allocator = @import("c_allocator.zig");
const c = @import("zig-c-headers/dr_mp3.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Seeker = root.Seeker;

pub const Decoder = struct {
    state: *State,

    const State = struct {
        gpa: Allocator,
        reader: *std.Io.Reader,
        seeker: ?Seeker,
        mp3: c.drmp3 = undefined,
        info: root.Info,
        /// Source offset of the first frame (after the ID3v2 tags): dr_mp3's offset 0.
        base: u64 = 0,
        /// Source offset of the reader.
        pos: u64 = 0,
        /// One mp3 frame, interleaved, for i16 / i32 output.
        buf: [c.DRMP3_MAX_SAMPLES_PER_FRAME]f32 = undefined,
        /// dr_mp3's seek table, built on the first seek.
        seek_points: []c.drmp3_seek_point = &.{},
        /// Without a seeker: the last bytes seen, not yet handed to dr_mp3 (see `readHeld`).
        held: [id3.v1_len]u8 = undefined,
        held_len: usize = 0,
        /// Sticky until a successful seek.
        err: ?Error = null,
        oom: bool = false,
        eos: bool = false,

        fn readSource(s: *State, out: []u8) error{ReadFailed}!usize {
            const n = try s.reader.readSliceShort(out);
            s.pos += n;
            return n;
        }

        /// Reads through a 128-byte delay line and drops an ID3v1 tag at the very end. With a
        /// seeker dr_mp3 stops before it; here minimp3 would get it, and junk after the last frame
        /// makes minimp3 drop that frame (or, right after a reset, the up to 10 frames before it).
        /// ponytail: the tag's fields are not reported without a seeker (Info is fixed at open);
        /// an APE tag at the end still reaches minimp3.
        fn readHeld(s: *State, out: []u8) error{ReadFailed}!usize {
            const keep = s.held.len;
            while (true) {
                const n = try s.readSource(out);
                if (n == 0) {
                    // End of stream: hand out what is held, unless it is the tag.
                    if (s.held_len == keep and std.mem.eql(u8, s.held[0..3], "TAG")) s.held_len = 0;
                    const k = @min(out.len, s.held_len);
                    @memcpy(out[0..k], s.held[0..k]);
                    std.mem.copyForwards(u8, s.held[0 .. s.held_len - k], s.held[k..s.held_len]);
                    s.held_len -= k;
                    return k;
                }
                // Stream order: held ++ out[0..n]; the last `keep` bytes of it stay held.
                const total = s.held_len + n;
                if (total <= keep) {
                    @memcpy(s.held[s.held_len..total], out[0..n]);
                    s.held_len = total;
                    continue;
                }
                const give = total - keep;
                var next: [id3.v1_len]u8 = undefined;
                if (n >= keep) {
                    @memcpy(&next, out[n - keep .. n]);
                    std.mem.copyBackwards(u8, out[s.held_len..give], out[0 .. n - keep]);
                    @memcpy(out[0..s.held_len], s.held[0..s.held_len]);
                } else {
                    // give < held_len: the output comes from the held bytes only.
                    @memcpy(next[0 .. keep - n], s.held[give..s.held_len]);
                    @memcpy(next[keep - n ..], out[0..n]);
                    @memcpy(out[0..give], s.held[0..give]);
                }
                s.held = next;
                s.held_len = keep;
                return give;
            }
        }

        /// The pending reader / seeker / allocation error after a failed dr_mp3 call, else `fallback`.
        fn failure(s: *State, fallback: Error) Error {
            if (s.err) |e| return e;
            if (s.oom) return error.OutOfMemory;
            return fallback;
        }
    };

    pub fn open(gpa: Allocator, arena: Allocator, reader: *std.Io.Reader, seeker: ?Seeker, tag_mode: root.TagMode) Error!Decoder {
        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{
            .gpa = gpa,
            .reader = reader,
            .seeker = seeker,
            .info = .{
                .container = .mp3,
                .codec = .mp3,
                .sample_rate = 0,
                .channels = 0,
                .channel_layout = null,
                .frames = null,
                .bits_per_sample = 0,
                .sample_format = null,
            },
        };

        var tags: id3.List = .{};
        var v1: ?[id3.v1_len]u8 = null;
        if (seeker) |sk| if (tag_mode != .none) {
            const size = sk.size(sk.context) catch return error.SeekFailed;
            if (size >= id3.v1_len) {
                try sk.seekTo(sk.context, size - id3.v1_len);
                var b: [id3.v1_len]u8 = undefined;
                reader.readSliceAll(&b) catch |err| return readError(err);
                v1 = b;
                try sk.seekTo(sk.context, 0);
            }
        };
        while (true) {
            const head = reader.peek(3) catch |err| switch (err) {
                error.EndOfStream => break, // too short: dr_mp3 rejects it below
                error.ReadFailed => return error.ReadFailed,
            };
            if (!id3.isV2(head)) break;
            s.pos += id3.readV2(gpa, arena, reader, tag_mode, &tags) catch |err| return readError(err);
        }
        if (v1) |*b| try id3.parseV1(arena, b, &tags);
        s.info.tags = tags.tags();
        s.base = s.pos;

        const callbacks: c.drmp3_allocation_callbacks = .{
            .pUserData = s,
            .onMalloc = onMalloc,
            .onRealloc = onRealloc,
            .onFree = onFree,
        };
        const seekable = seeker != null;
        if (c.drmp3_init(&s.mp3, onRead, if (seekable) onSeek else null, if (seekable) onTell else null, null, s, &callbacks) == 0)
            return s.failure(error.InvalidFile);
        errdefer c.drmp3_uninit(&s.mp3);

        s.info.sample_rate = s.mp3.sampleRate;
        s.info.channels = @intCast(s.mp3.channels);
        s.info.channel_layout = root.ChannelLayout.default(s.info.channels);
        if (s.mp3.totalPCMFrameCount != std.math.maxInt(u64) or seekable) {
            const frames = c.drmp3_get_pcm_frame_count(&s.mp3);
            if (s.err != null or s.oom) return s.failure(error.InvalidFile);
            s.info.frames = frames;
        }
        return .{ .state = s };
    }

    fn readError(err: id3.ReadError) Error {
        return switch (err) {
            error.EndOfStream => error.InvalidFile,
            error.ReadFailed => error.ReadFailed,
            error.OutOfMemory => error.OutOfMemory,
        };
    }

    pub fn deinit(d: *Decoder) void {
        const s = d.state;
        c.drmp3_uninit(&s.mp3);
        s.gpa.free(s.seek_points);
        s.gpa.destroy(s);
    }

    pub fn info(d: *const Decoder) *const root.Info {
        return &d.state.info;
    }

    pub fn ended(d: *const Decoder) bool {
        return d.state.eos;
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const s = d.state;
        const channels: usize = s.info.channels;
        const want = out.len / channels;
        var n: usize = 0;
        while (n < want) {
            if (s.err) |e| {
                if (n > 0) break;
                return e;
            }
            if (s.eos) break;
            // Within the current mp3 frame, or exactly one frame into the next (checked below).
            const remaining = s.mp3.pcmFramesRemainingInMP3Frame;
            const ask = if (remaining > 0) @min(want - n, remaining) else 1;
            const dst: [*]f32 = if (T == f32) out[n * channels ..].ptr else &s.buf;
            const got: usize = @intCast(c.drmp3_read_pcm_frames_f32(&s.mp3, ask, dst));
            if (s.oom) s.err = error.OutOfMemory;
            if (s.err != null) continue;
            if (got == 0) {
                s.eos = true;
                continue;
            }
            if (remaining == 0 and (s.mp3.mp3FrameSampleRate != s.info.sample_rate or s.mp3.mp3FrameChannels != channels)) {
                s.err = error.UnsupportedFormat;
                continue;
            }
            if (T != f32) {
                for (out[n * channels ..][0 .. got * channels], s.buf[0 .. got * channels]) |*o, x| o.* = sample.convert(T, x);
            }
            n += got;
        }
        return n;
    }

    /// Sample exact (same samples as a linear read) through dr_mp3's seek table: a jump to a
    /// frame a little before the target, then decoding forward (warms up the bit reservoir and the
    /// filter banks). dr_mp3 checks the warm-up and decodes from the start of the stream when it
    /// fell short (damage, very low bitrates). The table is built on the first seek: one pass over
    /// the frame headers to count them, one to place the points (no decoding).
    pub fn seek(d: *Decoder, frame: u64) Error!void {
        const s = d.state;
        if (s.seeker == null) return error.NotSeekable;
        const total = s.info.frames.?;
        if (frame > total) return error.SeekOutOfRange;
        s.err = null;
        s.oom = false;
        s.eos = frame == total;
        if (s.eos) return;
        if (s.seek_points.len == 0) buildSeekTable(s, total) catch |err| {
            s.err = null;
            s.oom = false;
            return err;
        };
        if (c.drmp3_seek_to_pcm_frame(&s.mp3, frame) == 0) {
            const err = s.failure(error.InvalidFile);
            s.err = null;
            s.oom = false;
            return err;
        }
    }

    /// One seek point per second (24 bytes): a seek decodes at most a second plus the warm-up.
    fn buildSeekTable(s: *State, total: u64) Error!void {
        // dr_mp3 returns to the current position afterwards, decoding up to it: start from 0.
        if (c.drmp3_seek_to_pcm_frame(&s.mp3, 0) == 0) return s.failure(error.InvalidFile);
        // `total` can come from the Xing frame count (file-controlled, up to 2^32 frames): also cap
        // by the source size (an mp3 frame is > 16 bytes), dr_mp3 clamps to the real count later.
        const seeker = s.seeker.?;
        const size = seeker.size(seeker.context) catch return error.SeekFailed;
        var n: u32 = std.math.cast(u32, @min(total / s.info.sample_rate, size / 16) + 1) orelse std.math.maxInt(u32);
        const points = try s.gpa.alloc(c.drmp3_seek_point, n);
        errdefer s.gpa.free(points);
        if (c.drmp3_calculate_seek_points(&s.mp3, &n, points.ptr) == 0) return s.failure(error.InvalidFile);
        s.seek_points = points;
        _ = c.drmp3_bind_seek_table(&s.mp3, n, points.ptr);
    }

    fn client(ptr: ?*anyopaque) *State {
        return @ptrCast(@alignCast(ptr.?));
    }

    fn onMalloc(size: usize, user: ?*anyopaque) callconv(.c) ?*anyopaque {
        const s = client(user);
        return c_allocator.alloc(s.gpa, size) orelse {
            s.oom = true;
            return null;
        };
    }

    fn onRealloc(ptr: ?*anyopaque, size: usize, user: ?*anyopaque) callconv(.c) ?*anyopaque {
        const s = client(user);
        return c_allocator.resize(s.gpa, ptr, size) orelse {
            s.oom = true;
            return null;
        };
    }

    fn onFree(ptr: ?*anyopaque, user: ?*anyopaque) callconv(.c) void {
        c_allocator.release(client(user).gpa, ptr);
    }

    fn onRead(user: ?*anyopaque, out: ?*anyopaque, len: usize) callconv(.c) usize {
        const s = client(user);
        if (s.err != null or len == 0) return 0;
        const buf: [*]u8 = @ptrCast(out.?);
        if (s.seeker != null) return s.readSource(buf[0..len]) catch {
            s.err = error.ReadFailed;
            return 0;
        };
        // dr_mp3 takes a short read for the end of the stream.
        var n: usize = 0;
        while (n < len) {
            const k = s.readHeld(buf[n..len]) catch {
                s.err = error.ReadFailed;
                return 0;
            };
            if (k == 0) break;
            n += k;
        }
        return n;
    }

    fn onSeek(user: ?*anyopaque, offset: c_int, origin: c.drmp3_seek_origin) callconv(.c) c.drmp3_bool32 {
        const s = client(user);
        const seeker = s.seeker.?;
        const from: u64 = switch (origin) {
            c.DRMP3_SEEK_SET => s.base,
            c.DRMP3_SEEK_CUR => s.pos,
            c.DRMP3_SEEK_END => seeker.size(seeker.context) catch {
                s.err = error.SeekFailed;
                return 0;
            },
            else => return 0,
        };
        const target = std.math.cast(u64, @as(i65, from) + offset) orelse return 0;
        if (target < s.base) return 0;
        seeker.seekTo(seeker.context, target) catch {
            s.err = error.SeekFailed;
            return 0;
        };
        s.pos = target;
        return 1;
    }

    fn onTell(user: ?*anyopaque, cursor: *i64) callconv(.c) c.drmp3_bool32 {
        const s = client(user);
        cursor.* = std.math.cast(i64, s.pos - s.base) orelse return 0;
        return 1;
    }
};
