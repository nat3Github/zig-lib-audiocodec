//! Hand-written bindings for libopusfile (include/opusfile.h).
//! URL/HTTP API (op_*_url, op_url_stream_*, opus_server_info_*) is omitted: libopusurl is not built.

const ogg = @import("ogg.zig");
const opus = @import("opus.zig");

pub const OP_FALSE = -1;
pub const OP_EOF = -2;
pub const OP_HOLE = -3;
pub const OP_EREAD = -128;
pub const OP_EFAULT = -129;
pub const OP_EIMPL = -130;
pub const OP_EINVAL = -131;
pub const OP_ENOTFORMAT = -132;
pub const OP_EBADHEADER = -133;
pub const OP_EVERSION = -134;
pub const OP_ENOTAUDIO = -135;
pub const OP_EBADPACKET = -136;
pub const OP_EBADLINK = -137;
pub const OP_ENOSEEK = -138;
pub const OP_EBADTIMESTAMP = -139;

pub const OP_PIC_FORMAT_UNKNOWN = -1;
pub const OP_PIC_FORMAT_URL = 0;
pub const OP_PIC_FORMAT_JPEG = 1;
pub const OP_PIC_FORMAT_PNG = 2;
pub const OP_PIC_FORMAT_GIF = 3;

pub const OP_DEC_FORMAT_SHORT = 7008;
pub const OP_DEC_FORMAT_FLOAT = 7040;
pub const OP_DEC_USE_DEFAULT = 6720;

pub const OP_HEADER_GAIN = 0;
pub const OP_ALBUM_GAIN = 3007;
pub const OP_TRACK_GAIN = 3008;
pub const OP_ABSOLUTE_GAIN = 3009;

pub const OPUS_CHANNEL_COUNT_MAX = 255;

pub const OpusHead = extern struct {
    version: c_int,
    channel_count: c_int,
    pre_skip: c_uint,
    input_sample_rate: u32,
    output_gain: c_int,
    mapping_family: c_int,
    stream_count: c_int,
    coupled_count: c_int,
    mapping: [OPUS_CHANNEL_COUNT_MAX]u8,
};

pub const OpusTags = extern struct {
    user_comments: ?[*][*:0]u8,
    comment_lengths: ?[*]c_int,
    comments: c_int,
    vendor: ?[*:0]u8,
};

pub const OpusPictureTag = extern struct {
    type: i32,
    mime_type: ?[*:0]u8,
    description: ?[*:0]u8,
    width: u32,
    height: u32,
    depth: u32,
    colors: u32,
    data_length: u32,
    data: ?[*]u8,
    format: c_int,
};

pub const op_read_func = *const fn (stream: ?*anyopaque, ptr: [*]u8, nbytes: c_int) callconv(.c) c_int;
pub const op_seek_func = *const fn (stream: ?*anyopaque, offset: i64, whence: c_int) callconv(.c) c_int;
pub const op_tell_func = *const fn (stream: ?*anyopaque) callconv(.c) i64;
pub const op_close_func = *const fn (stream: ?*anyopaque) callconv(.c) c_int;

pub const OpusFileCallbacks = extern struct {
    read: ?op_read_func,
    seek: ?op_seek_func,
    tell: ?op_tell_func,
    close: ?op_close_func,
};

pub const OggOpusFile = opaque {};

pub const op_decode_cb_func = *const fn (ctx: ?*anyopaque, decoder: *opus.OpusMSDecoder, pcm: ?*anyopaque, op: *const ogg.ogg_packet, nsamples: c_int, nchannels: c_int, format: c_int, li: c_int) callconv(.c) c_int;

// header parsing
pub extern fn opus_head_parse(head: ?*OpusHead, data: [*]const u8, len: usize) c_int;
pub extern fn opus_granule_sample(head: *const OpusHead, gp: i64) i64;
pub extern fn opus_tags_parse(tags: ?*OpusTags, data: [*]const u8, len: usize) c_int;
pub extern fn opus_tags_copy(dst: *OpusTags, src: *const OpusTags) c_int;
pub extern fn opus_tags_init(tags: *OpusTags) void;
pub extern fn opus_tags_add(tags: *OpusTags, tag: [*:0]const u8, value: [*:0]const u8) c_int;
pub extern fn opus_tags_add_comment(tags: *OpusTags, comment: [*:0]const u8) c_int;
pub extern fn opus_tags_set_binary_suffix(tags: *OpusTags, data: ?[*]const u8, len: c_int) c_int;
pub extern fn opus_tags_query(tags: *const OpusTags, tag: [*:0]const u8, count: c_int) ?[*:0]const u8;
pub extern fn opus_tags_query_count(tags: *const OpusTags, tag: [*:0]const u8) c_int;
pub extern fn opus_tags_get_binary_suffix(tags: *const OpusTags, len: *c_int) ?[*]const u8;
pub extern fn opus_tags_get_album_gain(tags: *const OpusTags, gain_q8: *c_int) c_int;
pub extern fn opus_tags_get_track_gain(tags: *const OpusTags, gain_q8: *c_int) c_int;
pub extern fn opus_tags_clear(tags: *OpusTags) void;
pub extern fn opus_tagcompare(tag_name: [*:0]const u8, comment: [*:0]const u8) c_int;
pub extern fn opus_tagncompare(tag_name: [*]const u8, tag_len: c_int, comment: [*:0]const u8) c_int;
pub extern fn opus_picture_tag_parse(pic: *OpusPictureTag, tag: [*:0]const u8) c_int;
pub extern fn opus_picture_tag_init(pic: *OpusPictureTag) void;
pub extern fn opus_picture_tag_clear(pic: *OpusPictureTag) void;

// stream helpers
pub extern fn op_fopen(cb: *OpusFileCallbacks, path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
pub extern fn op_fdopen(cb: *OpusFileCallbacks, fd: c_int, mode: [*:0]const u8) ?*anyopaque;
pub extern fn op_freopen(cb: *OpusFileCallbacks, path: [*:0]const u8, mode: [*:0]const u8, stream: ?*anyopaque) ?*anyopaque;
pub extern fn op_mem_stream_create(cb: *OpusFileCallbacks, data: [*]const u8, size: usize) ?*anyopaque;

// open / close
pub extern fn op_test(head: ?*OpusHead, initial_data: [*]const u8, initial_bytes: usize) c_int;
pub extern fn op_open_file(path: [*:0]const u8, err: ?*c_int) ?*OggOpusFile;
pub extern fn op_open_memory(data: [*]const u8, size: usize, err: ?*c_int) ?*OggOpusFile;
pub extern fn op_open_callbacks(stream: ?*anyopaque, cb: *const OpusFileCallbacks, initial_data: ?[*]const u8, initial_bytes: usize, err: ?*c_int) ?*OggOpusFile;
pub extern fn op_test_file(path: [*:0]const u8, err: ?*c_int) ?*OggOpusFile;
pub extern fn op_test_memory(data: [*]const u8, size: usize, err: ?*c_int) ?*OggOpusFile;
pub extern fn op_test_callbacks(stream: ?*anyopaque, cb: *const OpusFileCallbacks, initial_data: ?[*]const u8, initial_bytes: usize, err: ?*c_int) ?*OggOpusFile;
pub extern fn op_test_open(of: *OggOpusFile) c_int;
pub extern fn op_free(of: ?*OggOpusFile) void;

// stream info
pub extern fn op_seekable(of: *const OggOpusFile) c_int;
pub extern fn op_link_count(of: *const OggOpusFile) c_int;
pub extern fn op_serialno(of: *const OggOpusFile, li: c_int) u32;
pub extern fn op_channel_count(of: *const OggOpusFile, li: c_int) c_int;
pub extern fn op_raw_total(of: *const OggOpusFile, li: c_int) i64;
pub extern fn op_pcm_total(of: *const OggOpusFile, li: c_int) i64;
pub extern fn op_head(of: *const OggOpusFile, li: c_int) ?*const OpusHead;
pub extern fn op_tags(of: *const OggOpusFile, li: c_int) ?*const OpusTags;
pub extern fn op_current_link(of: *const OggOpusFile) c_int;
pub extern fn op_bitrate(of: *const OggOpusFile, li: c_int) i32;
pub extern fn op_bitrate_instant(of: *OggOpusFile) i32;
pub extern fn op_raw_tell(of: *const OggOpusFile) i64;
pub extern fn op_pcm_tell(of: *const OggOpusFile) i64;

// seeking
pub extern fn op_raw_seek(of: *OggOpusFile, byte_offset: i64) c_int;
pub extern fn op_pcm_seek(of: *OggOpusFile, pcm_offset: i64) c_int;

// decoding
pub extern fn op_set_decode_callback(of: *OggOpusFile, decode_cb: ?op_decode_cb_func, ctx: ?*anyopaque) void;
pub extern fn op_set_gain_offset(of: *OggOpusFile, gain_type: c_int, gain_offset_q8: i32) c_int;
pub extern fn op_set_dither_enabled(of: *OggOpusFile, enabled: c_int) void;
pub extern fn op_read(of: *OggOpusFile, pcm: [*]i16, buf_size: c_int, li: ?*c_int) c_int;
pub extern fn op_read_float(of: *OggOpusFile, pcm: [*]f32, buf_size: c_int, li: ?*c_int) c_int;
pub extern fn op_read_stereo(of: *OggOpusFile, pcm: [*]i16, buf_size: c_int) c_int;
pub extern fn op_read_float_stereo(of: *OggOpusFile, pcm: [*]f32, buf_size: c_int) c_int;
