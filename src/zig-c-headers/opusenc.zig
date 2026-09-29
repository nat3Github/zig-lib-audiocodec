//! Hand-written bindings for libopusenc (include/opusenc.h).

pub const OPE_API_VERSION = 0;

pub const OPE_OK = 0;
pub const OPE_BAD_ARG = -11;
pub const OPE_INTERNAL_ERROR = -13;
pub const OPE_UNIMPLEMENTED = -15;
pub const OPE_ALLOC_FAIL = -17;
pub const OPE_CANNOT_OPEN = -30;
pub const OPE_TOO_LATE = -31;
pub const OPE_INVALID_PICTURE = -32;
pub const OPE_INVALID_ICON = -33;
pub const OPE_WRITE_FAIL = -34;
pub const OPE_CLOSE_FAIL = -35;

pub const OPE_SET_DECISION_DELAY_REQUEST = 14000;
pub const OPE_GET_DECISION_DELAY_REQUEST = 14001;
pub const OPE_SET_MUXING_DELAY_REQUEST = 14002;
pub const OPE_GET_MUXING_DELAY_REQUEST = 14003;
pub const OPE_SET_COMMENT_PADDING_REQUEST = 14004;
pub const OPE_GET_COMMENT_PADDING_REQUEST = 14005;
pub const OPE_SET_SERIALNO_REQUEST = 14006;
pub const OPE_GET_SERIALNO_REQUEST = 14007;
pub const OPE_SET_PACKET_CALLBACK_REQUEST = 14008;
pub const OPE_SET_HEADER_GAIN_REQUEST = 14010;
pub const OPE_GET_HEADER_GAIN_REQUEST = 14011;
pub const OPE_GET_NB_STREAMS_REQUEST = 14013;
pub const OPE_GET_NB_COUPLED_STREAMS_REQUEST = 14015;

pub const ope_write_func = *const fn (user_data: ?*anyopaque, ptr: [*]const u8, len: i32) callconv(.c) c_int;
pub const ope_close_func = *const fn (user_data: ?*anyopaque) callconv(.c) c_int;
pub const ope_packet_func = *const fn (user_data: ?*anyopaque, packet_ptr: [*]const u8, packet_len: i32, flags: u32) callconv(.c) void;

pub const OpusEncCallbacks = extern struct {
    write: ope_write_func,
    close: ?ope_close_func,
};

pub const OggOpusComments = opaque {};
pub const OggOpusEnc = opaque {};

pub extern fn ope_comments_create() ?*OggOpusComments;
pub extern fn ope_comments_copy(comments: *OggOpusComments) ?*OggOpusComments;
pub extern fn ope_comments_destroy(comments: *OggOpusComments) void;
pub extern fn ope_comments_add(comments: *OggOpusComments, tag: [*:0]const u8, val: [*:0]const u8) c_int;
pub extern fn ope_comments_add_string(comments: *OggOpusComments, tag_and_val: [*:0]const u8) c_int;
pub extern fn ope_comments_add_picture(comments: *OggOpusComments, filename: [*:0]const u8, picture_type: c_int, description: ?[*:0]const u8) c_int;
pub extern fn ope_comments_add_picture_from_memory(comments: *OggOpusComments, ptr: [*]const u8, size: usize, picture_type: c_int, description: ?[*:0]const u8) c_int;

pub extern fn ope_encoder_create_file(path: [*:0]const u8, comments: *OggOpusComments, rate: i32, channels: c_int, family: c_int, err: ?*c_int) ?*OggOpusEnc;
pub extern fn ope_encoder_create_callbacks(callbacks: *const OpusEncCallbacks, user_data: ?*anyopaque, comments: *OggOpusComments, rate: i32, channels: c_int, family: c_int, err: ?*c_int) ?*OggOpusEnc;
pub extern fn ope_encoder_create_pull(comments: *OggOpusComments, rate: i32, channels: c_int, family: c_int, err: ?*c_int) ?*OggOpusEnc;
pub extern fn ope_encoder_deferred_init_with_mapping(enc: *OggOpusEnc, family: c_int, streams: c_int, coupled_streams: c_int, mapping: [*]const u8) c_int;
pub extern fn ope_encoder_write_float(enc: *OggOpusEnc, pcm: [*]const f32, samples_per_channel: c_int) c_int;
pub extern fn ope_encoder_write(enc: *OggOpusEnc, pcm: [*]const i16, samples_per_channel: c_int) c_int;
pub extern fn ope_encoder_get_page(enc: *OggOpusEnc, page: *[*]u8, len: *i32, flush: c_int) c_int;
pub extern fn ope_encoder_drain(enc: *OggOpusEnc) c_int;
pub extern fn ope_encoder_destroy(enc: *OggOpusEnc) void;
pub extern fn ope_encoder_chain_current(enc: *OggOpusEnc, comments: *OggOpusComments) c_int;
pub extern fn ope_encoder_continue_new_file(enc: *OggOpusEnc, path: [*:0]const u8, comments: *OggOpusComments) c_int;
pub extern fn ope_encoder_continue_new_callbacks(enc: *OggOpusEnc, user_data: ?*anyopaque, comments: *OggOpusComments) c_int;
pub extern fn ope_encoder_flush_header(enc: *OggOpusEnc) c_int;
pub extern fn ope_encoder_ctl(enc: *OggOpusEnc, request: c_int, ...) c_int;

pub extern fn ope_strerror(err: c_int) [*:0]const u8;
pub extern fn ope_get_version_string() [*:0]const u8;
pub extern fn ope_get_abi_version() c_int;
