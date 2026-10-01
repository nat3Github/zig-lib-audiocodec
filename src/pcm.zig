//! Uncompressed sample data shared by wav and aiff: the containers parse / write their header, this
//! reads and writes the data chunk.

const std = @import("std");
const root = @import("root.zig");
const sample = @import("sample.zig");
const wav = @import("wav.zig");
const aiff = @import("aiff.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Info = root.Info;
const Seeker = root.Seeker;

/// Bytes of scratch per read/write round.
const chunk_bytes = 16 * 1024;

fn scratchLen(block_align: usize) usize {
    return @max(1, chunk_bytes / block_align) * block_align;
}

pub const Decoder = struct {
    gpa: Allocator,
    reader: *std.Io.Reader,
    seeker: ?Seeker,
    info_: Info,
    layout: sample.Layout,
    block_align: u32,
    data_start: u64,
    /// null while the size field is a live placeholder.
    data_len: ?u64,
    /// Offset of a little-endian u32 placeholder size field to reread while live (wav).
    size_field: ?u64 = null,
    /// Data bytes consumed as whole frames.
    pos: u64 = 0,
    /// Bytes of a partial frame at the start of scratch.
    carry: usize = 0,
    scratch: []u8,
    done: bool = false,

    /// Header fields from the container; `reader` must be positioned at `data_start`.
    pub const Header = struct {
        info: Info,
        layout: sample.Layout,
        data_start: u64,
        data_len: ?u64,
        size_field: ?u64 = null,
    };

    pub fn init(gpa: Allocator, reader: *std.Io.Reader, seeker: ?Seeker, h: Header) Error!Decoder {
        const block_align: u32 = @as(u32, sample.size(h.layout.format)) * h.info.channels;
        var data_len = h.data_len;
        // A header claiming more data than the file holds: trust the file.
        if (data_len) |len| if (seeker) |s| {
            const file_size = try s.size(s.context);
            data_len = @min(len, file_size -| h.data_start);
        };
        var hi = h.info;
        hi.frames = if (data_len) |len| len / block_align else null;
        return .{
            .gpa = gpa,
            .reader = reader,
            .seeker = seeker,
            .info_ = hi,
            .layout = h.layout,
            .block_align = block_align,
            .data_start = h.data_start,
            .data_len = data_len,
            .size_field = h.size_field,
            .scratch = try gpa.alloc(u8, scratchLen(block_align)),
        };
    }

    pub fn deinit(d: *Decoder) void {
        d.gpa.free(d.scratch);
    }

    pub fn info(d: *const Decoder) *const Info {
        return &d.info_;
    }

    pub fn ended(d: *const Decoder) bool {
        if (d.done) return true;
        const len = d.data_len orelse return false;
        return len - d.pos < d.block_align;
    }

    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        const channels = d.info_.channels;
        const block_align = d.block_align;
        const want = out.len / channels;
        var frames: usize = 0;
        while (frames < want and !d.ended()) {
            var room = @min(d.scratch.len, (want - frames) * block_align) - d.carry;
            if (d.data_len) |len| room = @min(room, len - d.pos - d.carry);
            const n = try d.reader.readSliceShort(d.scratch[d.carry..][0..room]);
            const have = d.carry + n;
            const whole = have / block_align;
            const dest = out[frames * channels ..][0 .. whole * channels];
            sample.decode(T, dest, d.scratch[0 .. whole * block_align], d.layout);
            d.carry = have - whole * block_align;
            std.mem.copyForwards(u8, d.scratch[0..d.carry], d.scratch[whole * block_align ..][0..d.carry]);
            d.pos += whole * block_align;
            frames += whole;
            if (n < room) {
                try d.endOfInput();
                break;
            }
        }
        return frames;
    }

    /// The reader ran dry: the end, unless this is a live wav whose writer has not finished.
    fn endOfInput(d: *Decoder) Error!void {
        if (d.data_len != null) {
            d.done = true; // truncated file
            return;
        }
        const field = d.size_field orelse {
            d.done = true;
            return;
        };
        const s = d.seeker orelse {
            d.done = true; // pipe: its end is the end
            return;
        };
        try s.seekTo(s.context, field);
        const value = d.reader.takeInt(u32, .little) catch |err| return switch (err) {
            error.EndOfStream => error.InvalidFile,
            error.ReadFailed => error.ReadFailed,
        };
        try s.seekTo(s.context, d.data_start + d.pos + d.carry);
        if (value == wav.placeholder) return;
        d.data_len = value;
        d.info_.frames = value / d.block_align;
        if (value < d.pos + d.carry) d.done = true;
    }

    pub fn seek(d: *Decoder, frame: u64) Error!void {
        const s = d.seeker orelse return error.NotSeekable;
        var available = ((try s.size(s.context)) -| d.data_start) / d.block_align;
        if (d.data_len) |len| available = @min(available, len / d.block_align);
        if (frame > available) return error.SeekOutOfRange;
        try s.seekTo(s.context, d.data_start + frame * d.block_align);
        d.pos = frame * d.block_align;
        d.carry = 0;
        d.done = false;
    }
};

pub const Encoder = struct {
    gpa: Allocator,
    writer: *std.Io.Writer,
    seeker: ?Seeker,
    container: root.Container,
    layout: sample.Layout,
    channels: u16,
    block_align: u32,
    /// Offsets of the size fields to patch in finish (container specific).
    fields: [3]u64,
    header_len: u64,
    data_bytes: u64 = 0,
    max_data: u64,
    scratch: []u8,

    /// What the container's header writer reports back.
    pub const Header = struct {
        layout: sample.Layout,
        fields: [3]u64,
        header_len: u64,
        max_data: u64,
    };

    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: root.Encoder.Options) Error!Encoder {
        const h = switch (options.container) {
            .wav => try wav.writeHeader(writer, options),
            .aiff => try aiff.writeHeader(writer, options),
            else => unreachable,
        };
        const block_align = @as(u32, sample.size(h.layout.format)) * options.channels;
        return .{
            .gpa = gpa,
            .writer = writer,
            .seeker = options.seeker,
            .container = options.container,
            .layout = h.layout,
            .channels = options.channels,
            .block_align = block_align,
            .fields = h.fields,
            .header_len = h.header_len,
            .max_data = h.max_data,
            .scratch = try gpa.alloc(u8, scratchLen(block_align)),
        };
    }

    pub fn deinit(e: *Encoder) void {
        e.gpa.free(e.scratch);
    }

    pub fn write(e: *Encoder, comptime T: type, samples: []const T) Error!void {
        std.debug.assert(samples.len % e.channels == 0);
        const bytes = samples.len / e.channels * e.block_align;
        if (bytes > e.max_data - e.data_bytes) return error.FileTooLarge;
        const per_round = e.scratch.len / e.block_align * e.channels;
        var i: usize = 0;
        while (i < samples.len) {
            const n = @min(per_round, samples.len - i);
            const out = e.scratch[0 .. n / e.channels * e.block_align];
            sample.encode(T, out, samples[i..][0..n], e.layout);
            try e.writer.writeAll(out);
            i += n;
        }
        e.data_bytes += bytes;
    }

    pub fn flush(e: *Encoder) Error!void {
        try e.writer.flush();
    }

    pub fn finish(e: *Encoder) Error!void {
        const pad = e.data_bytes & 1;
        if (pad != 0) try e.writer.writeByte(0);
        try e.writer.flush();
        const s = e.seeker orelse return; // wav on a pipe: placeholders stay
        const end = e.header_len + e.data_bytes + pad;
        switch (e.container) {
            .wav => try wav.patch(e.writer, s, e.fields, e.data_bytes, end),
            .aiff => try aiff.patch(e.writer, s, e.fields, e.data_bytes, e.block_align, end),
            else => unreachable,
        }
        try s.seekTo(s.context, end);
    }
};

/// Writes `value` at `offset` and flushes.
pub fn patchInt(writer: *std.Io.Writer, s: Seeker, offset: u64, value: u32, endian: std.builtin.Endian) Error!void {
    try s.seekTo(s.context, offset);
    try writer.writeInt(u32, value, endian);
    try writer.flush();
}

/// Maps a header read error: running out of input inside a header means a malformed file.
pub fn headerError(err: anytype) Error {
    return switch (err) {
        error.EndOfStream => error.InvalidFile,
        else => |e| e,
    };
}

/// Reader.discardAll / discardAll64 compute `seek + n` and overflow for an n near maxInt(usize)
/// (any u32 length on 32-bit targets, a u64 length everywhere), so every skip of a
/// file-supplied length goes through here in chunks.
pub fn skip(reader: *std.Io.Reader, n: u64) std.Io.Reader.Error!void {
    var left = n;
    while (left > 0) {
        const chunk: usize = @intCast(@min(left, 1 << 30));
        try reader.discardAll(chunk);
        left -= chunk;
    }
}

/// Reads a text tag value of `len` bytes into `arena` (trailing NULs / spaces trimmed), or skips it
/// when it is larger than max_tag_len. Never allocates more than max_tag_len per tag.
pub fn readText(arena: Allocator, reader: *std.Io.Reader, len: u64) (Error || error{EndOfStream})!?[]const u8 {
    if (len > max_tag_len) {
        try skip(reader, len);
        return null;
    }
    const buf = try reader.readAlloc(arena, @intCast(len));
    return std.mem.trimEnd(u8, buf, " \x00");
}

pub const max_tag_len = 64 * 1024;
