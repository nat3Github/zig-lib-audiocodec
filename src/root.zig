//! Public API: one Decoder and one Encoder over every container/codec. See notes/api.md (dev repo).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const alac = @import("alac.zig");
pub const c_allocator = @import("c_allocator.zig");
pub const c = c_allocator.c;
pub const sample = @import("sample.zig");
pub const sniff = @import("sniff.zig").sniff;

const pcm = @import("pcm.zig");
const wav = @import("wav.zig");
const aiff = @import("aiff.zig");
const flac = @import("flac.zig");
const ogg = @import("ogg.zig");
const vorbis = @import("vorbis.zig");
const opus = @import("opus.zig");

comptime {
    _ = @import("libc.zig");
}

pub const Error = error{
    UnknownFormat,
    InvalidFile,
    UnsupportedFormat,
    NotSeekable,
    SeekOutOfRange,
    SeekFailed,
    BufferTooSmall,
    InvalidOptions,
    FileTooLarge,
    ReadFailed,
    WriteFailed,
    OutOfMemory,
};

pub const Container = enum { wav, aiff, flac, ogg, mp3, m4a, adts };
pub const Codec = enum { pcm, flac, vorbis, opus, mp3, aac, alac };

/// Stored sample layout. `.i8` is stored the container's way: unsigned (offset binary) in wav,
/// signed in aiff.
pub const SampleFormat = enum { i8, i16, i24, i32, f32, f64 };

/// Bit-identical to WAVE_FORMAT_EXTENSIBLE dwChannelMask. Interleaved channel order everywhere is
/// ascending bit order.
pub const ChannelLayout = packed struct(u32) {
    front_left: bool = false,
    front_right: bool = false,
    front_center: bool = false,
    lfe: bool = false,
    back_left: bool = false,
    back_right: bool = false,
    front_left_of_center: bool = false,
    front_right_of_center: bool = false,
    back_center: bool = false,
    side_left: bool = false,
    side_right: bool = false,
    top_center: bool = false,
    top_front_left: bool = false,
    top_front_center: bool = false,
    top_front_right: bool = false,
    top_back_left: bool = false,
    top_back_center: bool = false,
    top_back_right: bool = false,
    _: u14 = 0,

    pub const mono: ChannelLayout = .{ .front_center = true };
    pub const stereo: ChannelLayout = .{ .front_left = true, .front_right = true };
    pub const surround_3_0: ChannelLayout = .{ .front_left = true, .front_right = true, .front_center = true };
    pub const quad: ChannelLayout = .{ .front_left = true, .front_right = true, .back_left = true, .back_right = true };
    pub const surround_5_0: ChannelLayout = .{ .front_left = true, .front_right = true, .front_center = true, .back_left = true, .back_right = true };
    pub const surround_5_1: ChannelLayout = .{ .front_left = true, .front_right = true, .front_center = true, .lfe = true, .back_left = true, .back_right = true };
    pub const surround_6_1: ChannelLayout = .{ .front_left = true, .front_right = true, .front_center = true, .lfe = true, .back_center = true, .side_left = true, .side_right = true };
    pub const surround_7_1: ChannelLayout = .{ .front_left = true, .front_right = true, .front_center = true, .lfe = true, .back_left = true, .back_right = true, .side_left = true, .side_right = true };

    pub fn default(channels: u16) ?ChannelLayout {
        return switch (channels) {
            1 => mono,
            2 => stereo,
            3 => surround_3_0,
            4 => quad,
            5 => surround_5_0,
            6 => surround_5_1,
            7 => surround_6_1,
            8 => surround_7_1,
            else => null,
        };
    }

    pub fn fromMask(bits: u32) ChannelLayout {
        return @bitCast(bits & 0x3ffff);
    }

    pub fn mask(l: ChannelLayout) u32 {
        return @bitCast(l);
    }

    pub fn count(l: ChannelLayout) u16 {
        return @popCount(l.mask());
    }
};

pub const Tag = struct {
    /// Normalized lowercase key for known fields (title artist album album_artist date track disc
    /// genre comment composer copyright encoder); unknown fields keep their raw key, lowercased.
    key: []const u8,
    value: []const u8,
};

pub const Picture = struct { mime: []const u8, kind: u8, description: []const u8, data: []const u8 };

pub const Tags = struct {
    items: []const Tag = &.{},
    pictures: []const Picture = &.{},

    pub fn get(t: Tags, key: []const u8) ?[]const u8 {
        for (t.items) |tag| if (std.mem.eql(u8, tag.key, key)) return tag.value;
        return null;
    }
};

/// `.all` also loads pictures (can be MBs); `.none` skips tag chunks without allocating.
pub const TagMode = enum { none, text, all };

pub const Info = struct {
    container: Container,
    codec: Codec,
    sample_rate: u32,
    channels: u16,
    /// null: unspecified, channels in file order.
    channel_layout: ?ChannelLayout,
    /// null when unknown (e.g. a wav that is still being written).
    frames: ?u64,
    /// Source precision; 0 for lossy codecs.
    bits_per_sample: u8,
    /// Stored layout for pcm codecs, null otherwise.
    sample_format: ?SampleFormat,
    tags: Tags = .{},
    /// Rate of the audio before encoding, where the codec decodes at a fixed rate instead
    /// (opus: always 48 kHz, OpusHead's input rate here). null: same as `sample_rate` / unknown.
    original_sample_rate: ?u32 = null,
};

/// Random access for a reader or writer passed to `open`.
pub const Seeker = struct {
    context: *anyopaque,
    /// Must reposition the reader/writer passed to open (drop its buffered bytes / flush first).
    seekTo: *const fn (context: *anyopaque, offset: u64) error{SeekFailed}!void,
    /// Current total size, fresh on every call.
    size: *const fn (context: *anyopaque) error{SeekFailed}!u64,

    pub fn file(r: *std.Io.File.Reader) Seeker {
        const S = struct {
            fn seekTo(ctx: *anyopaque, offset: u64) error{SeekFailed}!void {
                const fr: *std.Io.File.Reader = @ptrCast(@alignCast(ctx));
                fr.seekTo(offset) catch return error.SeekFailed;
            }
            fn size(ctx: *anyopaque) error{SeekFailed}!u64 {
                const fr: *std.Io.File.Reader = @ptrCast(@alignCast(ctx));
                fr.size = null; // cached by File.Reader; a live file grows
                return fr.getSize() catch error.SeekFailed;
            }
        };
        return .{ .context = r, .seekTo = S.seekTo, .size = S.size };
    }

    /// For `std.Io.Reader.fixed`.
    pub fn fixed(r: *std.Io.Reader) Seeker {
        const S = struct {
            fn seekTo(ctx: *anyopaque, offset: u64) error{SeekFailed}!void {
                const fr: *std.Io.Reader = @ptrCast(@alignCast(ctx));
                if (offset > fr.end) return error.SeekFailed;
                fr.seek = @intCast(offset);
            }
            fn size(ctx: *anyopaque) error{SeekFailed}!u64 {
                const fr: *std.Io.Reader = @ptrCast(@alignCast(ctx));
                return fr.end;
            }
        };
        return .{ .context = r, .seekTo = S.seekTo, .size = S.size };
    }

    pub fn fileWriter(w: *std.Io.File.Writer) Seeker {
        const S = struct {
            fn seekTo(ctx: *anyopaque, offset: u64) error{SeekFailed}!void {
                const fw: *std.Io.File.Writer = @ptrCast(@alignCast(ctx));
                fw.seekTo(offset) catch return error.SeekFailed;
            }
            fn size(ctx: *anyopaque) error{SeekFailed}!u64 {
                const fw: *std.Io.File.Writer = @ptrCast(@alignCast(ctx));
                return fw.file.length(fw.io) catch error.SeekFailed;
            }
        };
        return .{ .context = w, .seekTo = S.seekTo, .size = S.size };
    }

    /// For `std.Io.Writer.fixed`.
    pub fn fixedWriter(w: *std.Io.Writer) Seeker {
        const S = struct {
            fn seekTo(ctx: *anyopaque, offset: u64) error{SeekFailed}!void {
                const fw: *std.Io.Writer = @ptrCast(@alignCast(ctx));
                if (offset > fw.buffer.len) return error.SeekFailed;
                fw.end = @intCast(offset);
            }
            fn size(ctx: *anyopaque) error{SeekFailed}!u64 {
                const fw: *std.Io.Writer = @ptrCast(@alignCast(ctx));
                return fw.end;
            }
        };
        return .{ .context = w, .seekTo = S.seekTo, .size = S.size };
    }
};

/// open() peeks this many bytes (not consumed) to sniff the container.
pub const min_buffer_len = 12;

// ponytail: codec build flags (prompt 13) gate these fields to `void` once more backends exist.
const DecoderBackend = union(enum) {
    pcm: pcm.Decoder,
    flac: flac.Decoder,
    vorbis: vorbis.Decoder,
    opus: opus.Decoder,
};

const EncoderBackend = union(enum) {
    pcm: pcm.Encoder,
    flac: flac.Encoder,
    vorbis: vorbis.Encoder,
    opus: opus.Encoder,
};

comptime {
    for (@typeInfo(DecoderBackend).@"union".fields) |f| {
        if (f.type == void) continue;
        for (.{ "info", "read", "ended", "seek", "deinit" }) |decl|
            if (!@hasDecl(f.type, decl)) @compileError("decoder backend " ++ f.name ++ " lacks " ++ decl);
    }
    for (@typeInfo(EncoderBackend).@"union".fields) |f| {
        if (f.type == void) continue;
        for (.{ "write", "flush", "finish", "deinit" }) |decl|
            if (!@hasDecl(f.type, decl)) @compileError("encoder backend " ++ f.name ++ " lacks " ++ decl);
    }
}

fn checkSampleType(comptime T: type) void {
    if (T != i16 and T != i32 and T != f32) @compileError("sample type must be i16, i32 or f32");
}

pub const Decoder = struct {
    arena: std.heap.ArenaAllocator,
    backend: DecoderBackend,

    pub const Options = struct {
        seeker: ?Seeker = null,
        /// Skip sniffing.
        container: ?Container = null,
        tags: TagMode = .text,
    };

    pub fn open(gpa: Allocator, reader: *std.Io.Reader, options: Options) Error!Decoder {
        if (reader.buffer.len < min_buffer_len) return error.BufferTooSmall;
        const container = options.container orelse blk: {
            const head = reader.peek(min_buffer_len) catch |err| return switch (err) {
                error.EndOfStream => error.UnknownFormat,
                error.ReadFailed => error.ReadFailed,
            };
            break :blk sniff(head[0..min_buffer_len]) orelse return error.UnknownFormat;
        };
        var arena: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena.deinit();
        const backend: DecoderBackend = switch (container) {
            .wav => .{ .pcm = try wav.open(gpa, arena.allocator(), reader, options.seeker, options.tags) },
            .aiff => .{ .pcm = try aiff.open(gpa, arena.allocator(), reader, options.seeker, options.tags) },
            .flac => .{ .flac = try flac.Decoder.open(gpa, arena.allocator(), reader, options.seeker, options.tags, null) },
            .ogg => blk: {
                var buf: [ogg.max_head]u8 = undefined;
                const head = try ogg.head(reader, &buf);
                break :blk switch (head.codec) {
                    .flac => .{ .flac = try flac.Decoder.open(gpa, arena.allocator(), reader, options.seeker, options.tags, head.bytes) },
                    .vorbis => .{ .vorbis = try vorbis.Decoder.open(gpa, arena.allocator(), reader, options.seeker, options.tags, head.bytes) },
                    .opus => .{ .opus = try opus.Decoder.open(gpa, arena.allocator(), reader, options.seeker, options.tags, head.bytes) },
                    else => return error.UnsupportedFormat,
                };
            },
            else => return error.UnsupportedFormat,
        };
        return .{ .arena = arena, .backend = backend };
    }

    pub fn info(d: *const Decoder) *const Info {
        return switch (d.backend) {
            inline else => |*b| b.info(),
        };
    }

    /// Fills `out` (interleaved, canonical channel order) with the whole frames available now and
    /// returns the number of frames. Never sleeps. 0 = nothing available now: see `ended`.
    pub fn read(d: *Decoder, comptime T: type, out: []T) Error!usize {
        comptime checkSampleType(T);
        return switch (d.backend) {
            inline else => |*b| b.read(T, out),
        };
    }

    /// True once the stream is complete and fully read. After `read` returned 0 this is false only
    /// for a wav that is still being written; the caller decides whether and how long to wait.
    pub fn ended(d: *const Decoder) bool {
        return switch (d.backend) {
            inline else => |*b| b.ended(),
        };
    }

    /// Next read starts at `frame`.
    pub fn seek(d: *Decoder, frame: u64) Error!void {
        return switch (d.backend) {
            inline else => |*b| b.seek(frame),
        };
    }

    pub fn deinit(d: *Decoder) void {
        switch (d.backend) {
            inline else => |*b| b.deinit(),
        }
        d.arena.deinit();
        d.* = undefined;
    }
};

pub const Encoder = struct {
    backend: EncoderBackend,

    pub const Options = struct {
        /// Needed for header patching (wav works without it, leaving placeholder sizes).
        seeker: ?Seeker = null,
        container: Container,
        /// null: the container's default.
        codec: ?Codec = null,
        sample_rate: u32,
        channels: u16,
        /// null: ChannelLayout.default(channels).
        channel_layout: ?ChannelLayout = null,
        sample_format: SampleFormat = .i16,
        /// 0..1 for lossy codecs; null = codec default.
        quality: ?f32 = null,
        tags: []const Tag = &.{},
        /// Ogg logical stream serial number (vorbis, opus). null: derived from the options, so output
        /// is reproducible. Files meant to be concatenated into a chain need distinct serials,
        /// e.g. from `std.Io.random`.
        ogg_serial: ?u32 = null,
    };

    pub fn open(gpa: Allocator, writer: *std.Io.Writer, options: Options) Error!Encoder {
        if (options.channels == 0 or options.sample_rate == 0) return error.InvalidOptions;
        if (options.channel_layout) |l| if (l.count() != options.channels) return error.InvalidOptions;
        const backend: EncoderBackend = switch (options.container) {
            .wav, .aiff => blk: {
                if (options.codec) |codec| if (codec != .pcm) return error.UnsupportedFormat;
                break :blk .{ .pcm = try pcm.Encoder.open(gpa, writer, options) };
            },
            .flac => blk: {
                if (options.codec) |codec| if (codec != .flac) return error.UnsupportedFormat;
                break :blk .{ .flac = try flac.Encoder.open(gpa, writer, options) };
            },
            .ogg => switch (options.codec orelse .vorbis) {
                .vorbis => .{ .vorbis = try vorbis.Encoder.open(gpa, writer, options) },
                .opus => .{ .opus = try opus.Encoder.open(gpa, writer, options) },
                .flac => .{ .flac = try flac.Encoder.open(gpa, writer, options) },
                else => return error.UnsupportedFormat,
            },
            else => return error.UnsupportedFormat,
        };
        return .{ .backend = backend };
    }

    /// `samples`: interleaved canonical order, len a multiple of channels.
    pub fn write(e: *Encoder, comptime T: type, samples: []const T) Error!void {
        comptime checkSampleType(T);
        return switch (e.backend) {
            inline else => |*b| b.write(T, samples),
        };
    }

    /// Pushes everything buffered through the writer and flushes it.
    pub fn flush(e: *Encoder) Error!void {
        return switch (e.backend) {
            inline else => |*b| b.flush(),
        };
    }

    /// Flush + header/trailer patching. Required for a complete file; afterwards only deinit.
    pub fn finish(e: *Encoder) Error!void {
        return switch (e.backend) {
            inline else => |*b| b.finish(),
        };
    }

    /// Without finish the file is left as-is (wav: placeholder sizes).
    pub fn deinit(e: *Encoder) void {
        switch (e.backend) {
            inline else => |*b| b.deinit(),
        }
        e.* = undefined;
    }
};
