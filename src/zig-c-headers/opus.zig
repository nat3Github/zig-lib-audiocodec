//! Hand-written bindings for libopus (include/opus{,_defines,_multistream,_projection}.h).
//! opus_custom.h is skipped: the build has CUSTOM_MODES off.

// opus_defines.h

pub const OPUS_OK = 0;
pub const OPUS_BAD_ARG = -1;
pub const OPUS_BUFFER_TOO_SMALL = -2;
pub const OPUS_INTERNAL_ERROR = -3;
pub const OPUS_INVALID_PACKET = -4;
pub const OPUS_UNIMPLEMENTED = -5;
pub const OPUS_INVALID_STATE = -6;
pub const OPUS_ALLOC_FAIL = -7;

pub const OPUS_SET_APPLICATION_REQUEST = 4000;
pub const OPUS_GET_APPLICATION_REQUEST = 4001;
pub const OPUS_SET_BITRATE_REQUEST = 4002;
pub const OPUS_GET_BITRATE_REQUEST = 4003;
pub const OPUS_SET_MAX_BANDWIDTH_REQUEST = 4004;
pub const OPUS_GET_MAX_BANDWIDTH_REQUEST = 4005;
pub const OPUS_SET_VBR_REQUEST = 4006;
pub const OPUS_GET_VBR_REQUEST = 4007;
pub const OPUS_SET_BANDWIDTH_REQUEST = 4008;
pub const OPUS_GET_BANDWIDTH_REQUEST = 4009;
pub const OPUS_SET_COMPLEXITY_REQUEST = 4010;
pub const OPUS_GET_COMPLEXITY_REQUEST = 4011;
pub const OPUS_SET_INBAND_FEC_REQUEST = 4012;
pub const OPUS_GET_INBAND_FEC_REQUEST = 4013;
pub const OPUS_SET_PACKET_LOSS_PERC_REQUEST = 4014;
pub const OPUS_GET_PACKET_LOSS_PERC_REQUEST = 4015;
pub const OPUS_SET_DTX_REQUEST = 4016;
pub const OPUS_GET_DTX_REQUEST = 4017;
pub const OPUS_SET_VBR_CONSTRAINT_REQUEST = 4020;
pub const OPUS_GET_VBR_CONSTRAINT_REQUEST = 4021;
pub const OPUS_SET_FORCE_CHANNELS_REQUEST = 4022;
pub const OPUS_GET_FORCE_CHANNELS_REQUEST = 4023;
pub const OPUS_SET_SIGNAL_REQUEST = 4024;
pub const OPUS_GET_SIGNAL_REQUEST = 4025;
pub const OPUS_GET_LOOKAHEAD_REQUEST = 4027;
pub const OPUS_RESET_STATE = 4028;
pub const OPUS_GET_SAMPLE_RATE_REQUEST = 4029;
pub const OPUS_GET_FINAL_RANGE_REQUEST = 4031;
pub const OPUS_GET_PITCH_REQUEST = 4033;
pub const OPUS_SET_GAIN_REQUEST = 4034;
pub const OPUS_GET_GAIN_REQUEST = 4045;
pub const OPUS_SET_LSB_DEPTH_REQUEST = 4036;
pub const OPUS_GET_LSB_DEPTH_REQUEST = 4037;
pub const OPUS_GET_LAST_PACKET_DURATION_REQUEST = 4039;
pub const OPUS_SET_EXPERT_FRAME_DURATION_REQUEST = 4040;
pub const OPUS_GET_EXPERT_FRAME_DURATION_REQUEST = 4041;
pub const OPUS_SET_PREDICTION_DISABLED_REQUEST = 4042;
pub const OPUS_GET_PREDICTION_DISABLED_REQUEST = 4043;
pub const OPUS_SET_PHASE_INVERSION_DISABLED_REQUEST = 4046;
pub const OPUS_GET_PHASE_INVERSION_DISABLED_REQUEST = 4047;
pub const OPUS_GET_IN_DTX_REQUEST = 4049;
pub const OPUS_SET_DRED_DURATION_REQUEST = 4050;
pub const OPUS_GET_DRED_DURATION_REQUEST = 4051;
pub const OPUS_SET_DNN_BLOB_REQUEST = 4052;
pub const OPUS_SET_OSCE_BWE_REQUEST = 4054;
pub const OPUS_GET_OSCE_BWE_REQUEST = 4055;
pub const OPUS_SET_QEXT_REQUEST = 4056;
pub const OPUS_GET_QEXT_REQUEST = 4057;
pub const OPUS_SET_IGNORE_EXTENSIONS_REQUEST = 4058;
pub const OPUS_GET_IGNORE_EXTENSIONS_REQUEST = 4059;

pub const OPUS_AUTO = -1000;
pub const OPUS_BITRATE_MAX = -1;

pub const OPUS_APPLICATION_VOIP = 2048;
pub const OPUS_APPLICATION_AUDIO = 2049;
pub const OPUS_APPLICATION_RESTRICTED_LOWDELAY = 2051;
pub const OPUS_APPLICATION_RESTRICTED_SILK = 2052;
pub const OPUS_APPLICATION_RESTRICTED_CELT = 2053;

pub const OPUS_SIGNAL_VOICE = 3001;
pub const OPUS_SIGNAL_MUSIC = 3002;

pub const OPUS_BANDWIDTH_NARROWBAND = 1101;
pub const OPUS_BANDWIDTH_MEDIUMBAND = 1102;
pub const OPUS_BANDWIDTH_WIDEBAND = 1103;
pub const OPUS_BANDWIDTH_SUPERWIDEBAND = 1104;
pub const OPUS_BANDWIDTH_FULLBAND = 1105;

pub const OPUS_FRAMESIZE_ARG = 5000;
pub const OPUS_FRAMESIZE_2_5_MS = 5001;
pub const OPUS_FRAMESIZE_5_MS = 5002;
pub const OPUS_FRAMESIZE_10_MS = 5003;
pub const OPUS_FRAMESIZE_20_MS = 5004;
pub const OPUS_FRAMESIZE_40_MS = 5005;
pub const OPUS_FRAMESIZE_60_MS = 5006;
pub const OPUS_FRAMESIZE_80_MS = 5007;
pub const OPUS_FRAMESIZE_100_MS = 5008;
pub const OPUS_FRAMESIZE_120_MS = 5009;

pub extern fn opus_strerror(err: c_int) [*:0]const u8;
pub extern fn opus_get_version_string() [*:0]const u8;

// opus.h: encoder

pub const OpusEncoder = opaque {};

pub extern fn opus_encoder_get_size(channels: c_int) c_int;
pub extern fn opus_encoder_create(Fs: i32, channels: c_int, application: c_int, err: ?*c_int) ?*OpusEncoder;
pub extern fn opus_encoder_init(st: *OpusEncoder, Fs: i32, channels: c_int, application: c_int) c_int;
pub extern fn opus_encode(st: *OpusEncoder, pcm: [*]const i16, frame_size: c_int, data: [*]u8, max_data_bytes: i32) i32;
pub extern fn opus_encode24(st: *OpusEncoder, pcm: [*]const i32, frame_size: c_int, data: [*]u8, max_data_bytes: i32) i32;
pub extern fn opus_encode_float(st: *OpusEncoder, pcm: [*]const f32, frame_size: c_int, data: [*]u8, max_data_bytes: i32) i32;
pub extern fn opus_encoder_destroy(st: *OpusEncoder) void;
pub extern fn opus_encoder_ctl(st: *OpusEncoder, request: c_int, ...) c_int;

// opus.h: decoder

pub const OpusDecoder = opaque {};
pub const OpusDREDDecoder = opaque {};
pub const OpusDRED = opaque {};

pub extern fn opus_decoder_get_size(channels: c_int) c_int;
pub extern fn opus_decoder_create(Fs: i32, channels: c_int, err: ?*c_int) ?*OpusDecoder;
pub extern fn opus_decoder_init(st: *OpusDecoder, Fs: i32, channels: c_int) c_int;
pub extern fn opus_decode(st: *OpusDecoder, data: ?[*]const u8, len: i32, pcm: [*]i16, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_decode24(st: *OpusDecoder, data: ?[*]const u8, len: i32, pcm: [*]i32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_decode_float(st: *OpusDecoder, data: ?[*]const u8, len: i32, pcm: [*]f32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_decoder_ctl(st: *OpusDecoder, request: c_int, ...) c_int;
pub extern fn opus_decoder_destroy(st: *OpusDecoder) void;

// DRED entry points exist but return OPUS_UNIMPLEMENTED: the build has ENABLE_DRED off.
pub extern fn opus_dred_decoder_get_size() c_int;
pub extern fn opus_dred_decoder_create(err: ?*c_int) ?*OpusDREDDecoder;
pub extern fn opus_dred_decoder_init(dec: *OpusDREDDecoder) c_int;
pub extern fn opus_dred_decoder_destroy(dec: *OpusDREDDecoder) void;
pub extern fn opus_dred_decoder_ctl(dred_dec: *OpusDREDDecoder, request: c_int, ...) c_int;
pub extern fn opus_dred_get_size() c_int;
pub extern fn opus_dred_alloc(err: ?*c_int) ?*OpusDRED;
pub extern fn opus_dred_free(dec: ?*OpusDRED) void;
pub extern fn opus_dred_parse(dred_dec: *OpusDREDDecoder, dred: *OpusDRED, data: [*]const u8, len: i32, max_dred_samples: i32, sampling_rate: i32, dred_end: ?*c_int, defer_processing: c_int) c_int;
pub extern fn opus_dred_process(dred_dec: *OpusDREDDecoder, src: *const OpusDRED, dst: *OpusDRED) c_int;
pub extern fn opus_decoder_dred_decode(st: *OpusDecoder, dred: *const OpusDRED, dred_offset: i32, pcm: [*]i16, frame_size: i32) c_int;
pub extern fn opus_decoder_dred_decode24(st: *OpusDecoder, dred: *const OpusDRED, dred_offset: i32, pcm: [*]i32, frame_size: i32) c_int;
pub extern fn opus_decoder_dred_decode_float(st: *OpusDecoder, dred: *const OpusDRED, dred_offset: i32, pcm: [*]f32, frame_size: i32) c_int;

// opus.h: packets

pub extern fn opus_packet_parse(data: [*]const u8, len: i32, out_toc: ?*u8, frames: ?*[48][*]const u8, size: *[48]i16, payload_offset: ?*c_int) c_int;
pub extern fn opus_packet_get_bandwidth(data: [*]const u8) c_int;
pub extern fn opus_packet_get_samples_per_frame(data: [*]const u8, Fs: i32) c_int;
pub extern fn opus_packet_get_nb_channels(data: [*]const u8) c_int;
pub extern fn opus_packet_get_nb_frames(packet: [*]const u8, len: i32) c_int;
pub extern fn opus_packet_get_nb_samples(packet: [*]const u8, len: i32, Fs: i32) c_int;
pub extern fn opus_packet_has_lbrr(packet: [*]const u8, len: i32) c_int;
pub extern fn opus_decoder_get_nb_samples(dec: *const OpusDecoder, packet: [*]const u8, len: i32) c_int;
pub extern fn opus_pcm_soft_clip(pcm: [*]f32, frame_size: c_int, channels: c_int, softclip_mem: [*]f32) void;

// opus.h: repacketizer

pub const OpusRepacketizer = opaque {};

pub extern fn opus_repacketizer_get_size() c_int;
pub extern fn opus_repacketizer_init(rp: *OpusRepacketizer) *OpusRepacketizer;
pub extern fn opus_repacketizer_create() ?*OpusRepacketizer;
pub extern fn opus_repacketizer_destroy(rp: *OpusRepacketizer) void;
pub extern fn opus_repacketizer_cat(rp: *OpusRepacketizer, data: [*]const u8, len: i32) c_int;
pub extern fn opus_repacketizer_out_range(rp: *OpusRepacketizer, begin: c_int, end: c_int, data: [*]u8, maxlen: i32) i32;
pub extern fn opus_repacketizer_get_nb_frames(rp: *OpusRepacketizer) c_int;
pub extern fn opus_repacketizer_out(rp: *OpusRepacketizer, data: [*]u8, maxlen: i32) i32;
pub extern fn opus_packet_pad(data: [*]u8, len: i32, new_len: i32) c_int;
pub extern fn opus_packet_unpad(data: [*]u8, len: i32) i32;
pub extern fn opus_multistream_packet_pad(data: [*]u8, len: i32, new_len: i32, nb_streams: c_int) c_int;
pub extern fn opus_multistream_packet_unpad(data: [*]u8, len: i32, nb_streams: c_int) i32;

// opus_multistream.h

pub const OPUS_MULTISTREAM_GET_ENCODER_STATE_REQUEST = 5120;
pub const OPUS_MULTISTREAM_GET_DECODER_STATE_REQUEST = 5122;

pub const OpusMSEncoder = opaque {};
pub const OpusMSDecoder = opaque {};

pub extern fn opus_multistream_encoder_get_size(streams: c_int, coupled_streams: c_int) i32;
pub extern fn opus_multistream_surround_encoder_get_size(channels: c_int, mapping_family: c_int) i32;
pub extern fn opus_multistream_encoder_create(Fs: i32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*]const u8, application: c_int, err: ?*c_int) ?*OpusMSEncoder;
pub extern fn opus_multistream_surround_encoder_create(Fs: i32, channels: c_int, mapping_family: c_int, streams: *c_int, coupled_streams: *c_int, mapping: [*]u8, application: c_int, err: ?*c_int) ?*OpusMSEncoder;
pub extern fn opus_multistream_encoder_init(st: *OpusMSEncoder, Fs: i32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*]const u8, application: c_int) c_int;
pub extern fn opus_multistream_surround_encoder_init(st: *OpusMSEncoder, Fs: i32, channels: c_int, mapping_family: c_int, streams: *c_int, coupled_streams: *c_int, mapping: [*]u8, application: c_int) c_int;
pub extern fn opus_multistream_encode(st: *OpusMSEncoder, pcm: [*]const i16, frame_size: c_int, data: [*]u8, max_data_bytes: i32) c_int;
pub extern fn opus_multistream_encode24(st: *OpusMSEncoder, pcm: [*]const i32, frame_size: c_int, data: [*]u8, max_data_bytes: i32) c_int;
pub extern fn opus_multistream_encode_float(st: *OpusMSEncoder, pcm: [*]const f32, frame_size: c_int, data: [*]u8, max_data_bytes: i32) c_int;
pub extern fn opus_multistream_encoder_destroy(st: *OpusMSEncoder) void;
pub extern fn opus_multistream_encoder_ctl(st: *OpusMSEncoder, request: c_int, ...) c_int;

pub extern fn opus_multistream_decoder_get_size(streams: c_int, coupled_streams: c_int) i32;
pub extern fn opus_multistream_decoder_create(Fs: i32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*]const u8, err: ?*c_int) ?*OpusMSDecoder;
pub extern fn opus_multistream_decoder_init(st: *OpusMSDecoder, Fs: i32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*]const u8) c_int;
pub extern fn opus_multistream_decode(st: *OpusMSDecoder, data: ?[*]const u8, len: i32, pcm: [*]i16, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_multistream_decode24(st: *OpusMSDecoder, data: ?[*]const u8, len: i32, pcm: [*]i32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_multistream_decode_float(st: *OpusMSDecoder, data: ?[*]const u8, len: i32, pcm: [*]f32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_multistream_decoder_ctl(st: *OpusMSDecoder, request: c_int, ...) c_int;
pub extern fn opus_multistream_decoder_destroy(st: *OpusMSDecoder) void;

// opus_projection.h

pub const OPUS_PROJECTION_GET_DEMIXING_MATRIX_GAIN_REQUEST = 6001;
pub const OPUS_PROJECTION_GET_DEMIXING_MATRIX_SIZE_REQUEST = 6003;
pub const OPUS_PROJECTION_GET_DEMIXING_MATRIX_REQUEST = 6005;

pub const OpusProjectionEncoder = opaque {};
pub const OpusProjectionDecoder = opaque {};

pub extern fn opus_projection_ambisonics_encoder_get_size(channels: c_int, mapping_family: c_int) i32;
pub extern fn opus_projection_ambisonics_encoder_create(Fs: i32, channels: c_int, mapping_family: c_int, streams: *c_int, coupled_streams: *c_int, application: c_int, err: ?*c_int) ?*OpusProjectionEncoder;
pub extern fn opus_projection_ambisonics_encoder_init(st: *OpusProjectionEncoder, Fs: i32, channels: c_int, mapping_family: c_int, streams: *c_int, coupled_streams: *c_int, application: c_int) c_int;
pub extern fn opus_projection_encode(st: *OpusProjectionEncoder, pcm: [*]const i16, frame_size: c_int, data: [*]u8, max_data_bytes: i32) c_int;
pub extern fn opus_projection_encode24(st: *OpusProjectionEncoder, pcm: [*]const i32, frame_size: c_int, data: [*]u8, max_data_bytes: i32) c_int;
pub extern fn opus_projection_encode_float(st: *OpusProjectionEncoder, pcm: [*]const f32, frame_size: c_int, data: [*]u8, max_data_bytes: i32) c_int;
pub extern fn opus_projection_encoder_destroy(st: *OpusProjectionEncoder) void;
pub extern fn opus_projection_encoder_ctl(st: *OpusProjectionEncoder, request: c_int, ...) c_int;

pub extern fn opus_projection_decoder_get_size(channels: c_int, streams: c_int, coupled_streams: c_int) i32;
pub extern fn opus_projection_decoder_create(Fs: i32, channels: c_int, streams: c_int, coupled_streams: c_int, demixing_matrix: [*]u8, demixing_matrix_size: i32, err: ?*c_int) ?*OpusProjectionDecoder;
pub extern fn opus_projection_decoder_init(st: *OpusProjectionDecoder, Fs: i32, channels: c_int, streams: c_int, coupled_streams: c_int, demixing_matrix: [*]u8, demixing_matrix_size: i32) c_int;
pub extern fn opus_projection_decode(st: *OpusProjectionDecoder, data: ?[*]const u8, len: i32, pcm: [*]i16, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_projection_decode24(st: *OpusProjectionDecoder, data: ?[*]const u8, len: i32, pcm: [*]i32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_projection_decode_float(st: *OpusProjectionDecoder, data: ?[*]const u8, len: i32, pcm: [*]f32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_projection_decoder_ctl(st: *OpusProjectionDecoder, request: c_int, ...) c_int;
pub extern fn opus_projection_decoder_destroy(st: *OpusProjectionDecoder) void;

/// zig fork: allocator hook. `realloc(ctx, null, n)` must act like alloc; free never gets null.
pub const opus_allocator = extern struct {
    ctx: ?*anyopaque,
    alloc: *const fn (ctx: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque,
    realloc: *const fn (ctx: ?*anyopaque, ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque,
    free: *const fn (ctx: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void,
};
/// null restores the default (libc, or null-returning stubs in the module build).
pub extern fn opus_set_allocator(allocator: ?*const opus_allocator) void;
