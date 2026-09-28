//! Hand-written bindings for minimp4 (minimp4.h), built with the header's default config:
//! MINIMP4_ALLOW_64BIT, MP4D_INFO_SUPPORTED, MP4D_TIMESTAMPS_SUPPORTED, MINIMP4_TRANSCODE_SPS_ID = 1,
//! MP4D_PRINT_INFO_SUPPORTED = 0 (no MP4D_printf_info).

pub const MINIMP4_MAX_SPS = 32;
pub const MINIMP4_MAX_PPS = 256;

pub const MP4_OBJECT_TYPE_AUDIO_ISO_IEC_14496_3 = 0x40;
pub const MP4_OBJECT_TYPE_AUDIO_ISO_IEC_13818_7_MAIN_PROFILE = 0x66;
pub const MP4_OBJECT_TYPE_AUDIO_ISO_IEC_13818_7_LC_PROFILE = 0x67;
pub const MP4_OBJECT_TYPE_AUDIO_ISO_IEC_13818_7_SSR_PROFILE = 0x68;
pub const MP4_OBJECT_TYPE_AVC = 0x21;
pub const MP4_OBJECT_TYPE_HEVC = 0x23;
pub const MP4_OBJECT_TYPE_USER_PRIVATE = 0xC0;

pub const MP4E_STATUS_OK = 0;
pub const MP4E_STATUS_BAD_ARGUMENTS = -1;
pub const MP4E_STATUS_NO_MEMORY = -2;
pub const MP4E_STATUS_FILE_WRITE_ERROR = -3;
pub const MP4E_STATUS_ONLY_ONE_DSI_ALLOWED = -4;

pub const MP4E_SAMPLE_DEFAULT = 0;
pub const MP4E_SAMPLE_RANDOM_ACCESS = 1;
pub const MP4E_SAMPLE_CONTINUATION = 2;

pub const MP4D_HANDLER_TYPE_VIDE = 0x76696465;
pub const MP4D_HANDLER_TYPE_SOUN = 0x736F756E;
pub const MP4E_HANDLER_TYPE_GESM = 0x6765736D;

pub const HEVC_NAL_VPS = 32;
pub const HEVC_NAL_SPS = 33;
pub const HEVC_NAL_PPS = 34;
pub const HEVC_NAL_BLA_W_LP = 16;
pub const HEVC_NAL_CRA_NUT = 21;

pub const boxsize_t = u64;
pub const MP4D_file_offset_t = boxsize_t;

pub const MP4E_mux_t = opaque {};

pub const track_media_kind_t = c_uint;
pub const e_audio: track_media_kind_t = 0;
pub const e_video: track_media_kind_t = 1;
pub const e_private: track_media_kind_t = 2;

pub const MP4E_track_t = extern struct {
    object_type_indication: c_uint,
    language: [4]u8,
    track_media_kind: track_media_kind_t,
    time_scale: c_uint,
    default_duration: c_uint,
    u: extern union {
        a: extern struct {
            channelcount: c_uint,
        },
        v: extern struct {
            width: c_int,
            height: c_int,
        },
    },
};

pub const MP4D_sample_to_chunk_t = extern struct {
    first_chunk: c_uint,
    samples_per_chunk: c_uint,
};

pub const MP4D_track_t = extern struct {
    sample_count: c_uint,
    dsi: ?[*]u8,
    dsi_bytes: c_uint,
    object_type_indication: c_uint,

    handler_type: c_uint,
    duration_hi: c_uint,
    duration_lo: c_uint,
    timescale: c_uint,
    avg_bitrate_bps: c_uint,
    language: [4]u8,
    stream_type: c_uint,
    SampleDescription: extern union {
        audio: extern struct {
            channelcount: c_uint,
            samplerate_hz: c_uint,
        },
        video: extern struct {
            width: c_uint,
            height: c_uint,
        },
    },

    entry_size: ?[*]c_uint,
    sample_to_chunk_count: c_uint,
    sample_to_chunk: ?[*]MP4D_sample_to_chunk_t,
    chunk_count: c_uint,
    chunk_offset: ?[*]MP4D_file_offset_t,
    stc_cache_group: c_uint,
    stc_cache_nc: c_uint,
    stc_cache_sum: c_uint,
    fo_cache_valid: c_uint,
    fo_cache_nsample: c_uint,
    fo_cache_offset: MP4D_file_offset_t,

    timestamp: ?[*]c_uint,
    duration: ?[*]c_uint,
    timestamp_count: c_uint,
};

pub const MP4D_read_callback = *const fn (offset: i64, buffer: ?*anyopaque, size: usize, token: ?*anyopaque) callconv(.c) c_int;
pub const MP4E_write_callback = *const fn (offset: i64, buffer: ?*const anyopaque, size: usize, token: ?*anyopaque) callconv(.c) c_int;

pub const MP4D_demux_t = extern struct {
    read_pos: i64,
    read_size: i64,
    track: ?[*]MP4D_track_t,
    read_callback: ?MP4D_read_callback,
    token: ?*anyopaque,
    track_count: c_uint,

    duration_hi: c_uint,
    duration_lo: c_uint,
    timescale: c_uint,
    tag: extern struct {
        title: ?[*:0]u8,
        artist: ?[*:0]u8,
        album: ?[*:0]u8,
        year: ?[*:0]u8,
        comment: ?[*:0]u8,
        genre: ?[*:0]u8,
    },
};

pub const h264_sps_id_patcher_t = extern struct {
    sps_cache: [MINIMP4_MAX_SPS]?*anyopaque,
    pps_cache: [MINIMP4_MAX_PPS]?*anyopaque,
    sps_bytes: [MINIMP4_MAX_SPS]c_int,
    pps_bytes: [MINIMP4_MAX_PPS]c_int,
    map_sps: [MINIMP4_MAX_SPS]c_int,
    map_pps: [MINIMP4_MAX_PPS]c_int,
};

pub const mp4_h26x_writer_t = extern struct {
    sps_patcher: h264_sps_id_patcher_t,
    mux: ?*MP4E_mux_t,
    mux_track_id: c_int,
    is_hevc: c_int,
    need_vps: c_int,
    need_sps: c_int,
    need_pps: c_int,
    need_idr: c_int,
};

pub extern fn mp4_h26x_write_init(h: *mp4_h26x_writer_t, mux: *MP4E_mux_t, width: c_int, height: c_int, is_hevc: c_int) c_int;
pub extern fn mp4_h26x_write_close(h: *mp4_h26x_writer_t) void;
pub extern fn mp4_h26x_write_nal(h: *mp4_h26x_writer_t, nal: [*]const u8, length: c_int, timeStamp90kHz_next: c_uint) c_int;

pub extern fn MP4D_open(mp4: *MP4D_demux_t, read_callback: MP4D_read_callback, token: ?*anyopaque, file_size: i64) c_int;
pub extern fn MP4D_frame_offset(mp4: *const MP4D_demux_t, ntrack: c_uint, nsample: c_uint, frame_bytes: *c_uint, timestamp: ?*c_uint, duration: ?*c_uint) MP4D_file_offset_t;
pub extern fn MP4D_close(mp4: *MP4D_demux_t) void;
pub extern fn MP4D_read_sps(mp4: *const MP4D_demux_t, ntrack: c_uint, nsps: c_int, sps_bytes: *c_int) ?*const anyopaque;
pub extern fn MP4D_read_pps(mp4: *const MP4D_demux_t, ntrack: c_uint, npps: c_int, pps_bytes: *c_int) ?*const anyopaque;

pub extern fn MP4E_open(sequential_mode_flag: c_int, enable_fragmentation: c_int, token: ?*anyopaque, write_callback: MP4E_write_callback) ?*MP4E_mux_t;
pub extern fn MP4E_add_track(mux: *MP4E_mux_t, track_data: *const MP4E_track_t) c_int;
pub extern fn MP4E_put_sample(mux: *MP4E_mux_t, track_num: c_int, data: ?*const anyopaque, data_bytes: c_int, duration: c_int, kind: c_int) c_int;
pub extern fn MP4E_close(mux: *MP4E_mux_t) c_int;
pub extern fn MP4E_set_dsi(mux: *MP4E_mux_t, track_id: c_int, dsi: *const anyopaque, bytes: c_int) c_int;
pub extern fn MP4E_set_vps(mux: *MP4E_mux_t, track_id: c_int, vps: *const anyopaque, bytes: c_int) c_int;
pub extern fn MP4E_set_sps(mux: *MP4E_mux_t, track_id: c_int, sps: *const anyopaque, bytes: c_int) c_int;
pub extern fn MP4E_set_pps(mux: *MP4E_mux_t, track_id: c_int, pps: *const anyopaque, bytes: c_int) c_int;
pub extern fn MP4E_set_text_comment(mux: *MP4E_mux_t, comment: ?[*:0]const u8) c_int;

/// zig fork: allocator hook. `realloc(ctx, null, n)` must act like alloc; free never gets null.
pub const minimp4_allocator = extern struct {
    ctx: ?*anyopaque,
    alloc: *const fn (ctx: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque,
    realloc: *const fn (ctx: ?*anyopaque, ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque,
    free: *const fn (ctx: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void,
};
/// null restores the default (libc, or null-returning stubs in the module build).
pub extern fn minimp4_set_allocator(allocator: ?*const minimp4_allocator) void;
