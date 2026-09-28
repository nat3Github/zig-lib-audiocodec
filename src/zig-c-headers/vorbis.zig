//! Hand-written bindings for libvorbis (include/vorbis/{codec,vorbisenc,vorbisfile}.h).

const ogg = @import("ogg.zig");
const ogg_packet = ogg.ogg_packet;

pub const FILE = opaque {};

// codec.h

pub const vorbis_info = extern struct {
    version: c_int,
    channels: c_int,
    rate: c_long,
    bitrate_upper: c_long,
    bitrate_nominal: c_long,
    bitrate_lower: c_long,
    bitrate_window: c_long,
    codec_setup: ?*anyopaque,
};

pub const vorbis_dsp_state = extern struct {
    analysisp: c_int,
    vi: ?*vorbis_info,
    pcm: ?[*][*]f32,
    pcmret: ?[*][*]f32,
    pcm_storage: c_int,
    pcm_current: c_int,
    pcm_returned: c_int,
    preextrapolate: c_int,
    eofflag: c_int,
    lW: c_long,
    W: c_long,
    nW: c_long,
    centerW: c_long,
    granulepos: i64,
    sequence: i64,
    glue_bits: i64,
    time_bits: i64,
    floor_bits: i64,
    res_bits: i64,
    backend_state: ?*anyopaque,
};

pub const alloc_chain = extern struct {
    ptr: ?*anyopaque,
    next: ?*alloc_chain,
};

pub const vorbis_block = extern struct {
    pcm: ?[*][*]f32,
    opb: ogg.oggpack_buffer,
    lW: c_long,
    W: c_long,
    nW: c_long,
    pcmend: c_int,
    mode: c_int,
    eofflag: c_int,
    granulepos: i64,
    sequence: i64,
    vd: ?*vorbis_dsp_state,
    localstore: ?*anyopaque,
    localtop: c_long,
    localalloc: c_long,
    totaluse: c_long,
    reap: ?*alloc_chain,
    glue_bits: c_long,
    time_bits: c_long,
    floor_bits: c_long,
    res_bits: c_long,
    internal: ?*anyopaque,
};

pub const vorbis_comment = extern struct {
    user_comments: ?[*][*:0]u8,
    comment_lengths: ?[*]c_int,
    comments: c_int,
    vendor: ?[*:0]u8,
};

pub extern fn vorbis_info_init(vi: *vorbis_info) void;
pub extern fn vorbis_info_clear(vi: *vorbis_info) void;
pub extern fn vorbis_info_blocksize(vi: *vorbis_info, zo: c_int) c_int;
pub extern fn vorbis_comment_init(vc: *vorbis_comment) void;
pub extern fn vorbis_comment_add(vc: *vorbis_comment, comment: [*:0]const u8) void;
pub extern fn vorbis_comment_add_tag(vc: *vorbis_comment, tag: [*:0]const u8, contents: [*:0]const u8) void;
pub extern fn vorbis_comment_query(vc: *vorbis_comment, tag: [*:0]const u8, count: c_int) ?[*:0]u8;
pub extern fn vorbis_comment_query_count(vc: *vorbis_comment, tag: [*:0]const u8) c_int;
pub extern fn vorbis_comment_clear(vc: *vorbis_comment) void;

pub extern fn vorbis_block_init(v: *vorbis_dsp_state, vb: *vorbis_block) c_int;
pub extern fn vorbis_block_clear(vb: *vorbis_block) c_int;
pub extern fn vorbis_dsp_clear(v: *vorbis_dsp_state) void;
pub extern fn vorbis_granule_time(v: *vorbis_dsp_state, granulepos: i64) f64;
pub extern fn vorbis_version_string() [*:0]const u8;

// analysis (encode)
pub extern fn vorbis_analysis_init(v: *vorbis_dsp_state, vi: *vorbis_info) c_int;
pub extern fn vorbis_commentheader_out(vc: *vorbis_comment, op: *ogg_packet) c_int;
pub extern fn vorbis_analysis_headerout(v: *vorbis_dsp_state, vc: *vorbis_comment, op: *ogg_packet, op_comm: *ogg_packet, op_code: *ogg_packet) c_int;
pub extern fn vorbis_analysis_buffer(v: *vorbis_dsp_state, vals: c_int) ?[*][*]f32;
pub extern fn vorbis_analysis_wrote(v: *vorbis_dsp_state, vals: c_int) c_int;
pub extern fn vorbis_analysis_blockout(v: *vorbis_dsp_state, vb: *vorbis_block) c_int;
pub extern fn vorbis_analysis(vb: *vorbis_block, op: ?*ogg_packet) c_int;
pub extern fn vorbis_bitrate_addblock(vb: *vorbis_block) c_int;
pub extern fn vorbis_bitrate_flushpacket(vd: *vorbis_dsp_state, op: *ogg_packet) c_int;

// synthesis (decode)
pub extern fn vorbis_synthesis_idheader(op: *ogg_packet) c_int;
pub extern fn vorbis_synthesis_headerin(vi: *vorbis_info, vc: *vorbis_comment, op: *ogg_packet) c_int;
pub extern fn vorbis_synthesis_init(v: *vorbis_dsp_state, vi: *vorbis_info) c_int;
pub extern fn vorbis_synthesis_restart(v: *vorbis_dsp_state) c_int;
pub extern fn vorbis_synthesis(vb: *vorbis_block, op: *ogg_packet) c_int;
pub extern fn vorbis_synthesis_trackonly(vb: *vorbis_block, op: *ogg_packet) c_int;
pub extern fn vorbis_synthesis_blockin(v: *vorbis_dsp_state, vb: *vorbis_block) c_int;
pub extern fn vorbis_synthesis_pcmout(v: *vorbis_dsp_state, pcm: ?*[*][*]f32) c_int;
pub extern fn vorbis_synthesis_lapout(v: *vorbis_dsp_state, pcm: ?*[*][*]f32) c_int;
pub extern fn vorbis_synthesis_read(v: *vorbis_dsp_state, samples: c_int) c_int;
pub extern fn vorbis_packet_blocksize(vi: *vorbis_info, op: *ogg_packet) c_long;
pub extern fn vorbis_synthesis_halfrate(v: *vorbis_info, flag: c_int) c_int;
pub extern fn vorbis_synthesis_halfrate_p(v: *vorbis_info) c_int;

pub const OV_FALSE = -1;
pub const OV_EOF = -2;
pub const OV_HOLE = -3;
pub const OV_EREAD = -128;
pub const OV_EFAULT = -129;
pub const OV_EIMPL = -130;
pub const OV_EINVAL = -131;
pub const OV_ENOTVORBIS = -132;
pub const OV_EBADHEADER = -133;
pub const OV_EVERSION = -134;
pub const OV_ENOTAUDIO = -135;
pub const OV_EBADPACKET = -136;
pub const OV_EBADLINK = -137;
pub const OV_ENOSEEK = -138;

// vorbisenc.h

pub extern fn vorbis_encode_init(vi: *vorbis_info, channels: c_long, rate: c_long, max_bitrate: c_long, nominal_bitrate: c_long, min_bitrate: c_long) c_int;
pub extern fn vorbis_encode_setup_managed(vi: *vorbis_info, channels: c_long, rate: c_long, max_bitrate: c_long, nominal_bitrate: c_long, min_bitrate: c_long) c_int;
pub extern fn vorbis_encode_setup_vbr(vi: *vorbis_info, channels: c_long, rate: c_long, quality: f32) c_int;
pub extern fn vorbis_encode_init_vbr(vi: *vorbis_info, channels: c_long, rate: c_long, base_quality: f32) c_int;
pub extern fn vorbis_encode_setup_init(vi: *vorbis_info) c_int;
pub extern fn vorbis_encode_ctl(vi: *vorbis_info, number: c_int, arg: ?*anyopaque) c_int;

pub const ovectl_ratemanage_arg = extern struct {
    management_active: c_int,
    bitrate_hard_min: c_long,
    bitrate_hard_max: c_long,
    bitrate_hard_window: f64,
    bitrate_av_lo: c_long,
    bitrate_av_hi: c_long,
    bitrate_av_window: f64,
    bitrate_av_window_center: f64,
};

pub const ovectl_ratemanage2_arg = extern struct {
    management_active: c_int,
    bitrate_limit_min_kbps: c_long,
    bitrate_limit_max_kbps: c_long,
    bitrate_limit_reservoir_bits: c_long,
    bitrate_limit_reservoir_bias: f64,
    bitrate_average_kbps: c_long,
    bitrate_average_damping: f64,
};

pub const OV_ECTL_RATEMANAGE2_GET = 0x14;
pub const OV_ECTL_RATEMANAGE2_SET = 0x15;
pub const OV_ECTL_LOWPASS_GET = 0x20;
pub const OV_ECTL_LOWPASS_SET = 0x21;
pub const OV_ECTL_IBLOCK_GET = 0x30;
pub const OV_ECTL_IBLOCK_SET = 0x31;
pub const OV_ECTL_COUPLING_GET = 0x40;
pub const OV_ECTL_COUPLING_SET = 0x41;
pub const OV_ECTL_RATEMANAGE_GET = 0x10;
pub const OV_ECTL_RATEMANAGE_SET = 0x11;
pub const OV_ECTL_RATEMANAGE_AVG = 0x12;
pub const OV_ECTL_RATEMANAGE_HARD = 0x13;

// vorbisfile.h
// ponytail: the header's static OV_CALLBACKS_* presets (fread/fseek wrappers) are not ported; build ov_callbacks in Zig.

pub const ov_callbacks = extern struct {
    read_func: ?*const fn (ptr: ?*anyopaque, size: usize, nmemb: usize, datasource: ?*anyopaque) callconv(.c) usize,
    seek_func: ?*const fn (datasource: ?*anyopaque, offset: i64, whence: c_int) callconv(.c) c_int,
    close_func: ?*const fn (datasource: ?*anyopaque) callconv(.c) c_int,
    tell_func: ?*const fn (datasource: ?*anyopaque) callconv(.c) c_long,
};

pub const NOTOPEN = 0;
pub const PARTOPEN = 1;
pub const OPENED = 2;
pub const STREAMSET = 3;
pub const INITSET = 4;

pub const OggVorbis_File = extern struct {
    datasource: ?*anyopaque,
    seekable: c_int,
    offset: i64,
    end: i64,
    oy: ogg.ogg_sync_state,
    links: c_int,
    offsets: ?[*]i64,
    dataoffsets: ?[*]i64,
    serialnos: ?[*]c_long,
    pcmlengths: ?[*]i64,
    vi: ?[*]vorbis_info,
    vc: ?[*]vorbis_comment,
    pcm_offset: i64,
    ready_state: c_int,
    current_serialno: c_long,
    current_link: c_int,
    bittrack: f64,
    samptrack: f64,
    os: ogg.ogg_stream_state,
    vd: vorbis_dsp_state,
    vb: vorbis_block,
    callbacks: ov_callbacks,
};

pub const ov_filter_fn = *const fn (pcm: [*][*]f32, channels: c_long, samples: c_long, filter_param: ?*anyopaque) callconv(.c) void;

pub extern fn ov_clear(vf: *OggVorbis_File) c_int;
pub extern fn ov_fopen(path: [*:0]const u8, vf: *OggVorbis_File) c_int;
pub extern fn ov_open(f: *FILE, vf: *OggVorbis_File, initial: ?[*]const u8, ibytes: c_long) c_int;
pub extern fn ov_open_callbacks(datasource: ?*anyopaque, vf: *OggVorbis_File, initial: ?[*]const u8, ibytes: c_long, callbacks: ov_callbacks) c_int;
pub extern fn ov_test(f: *FILE, vf: *OggVorbis_File, initial: ?[*]const u8, ibytes: c_long) c_int;
pub extern fn ov_test_callbacks(datasource: ?*anyopaque, vf: *OggVorbis_File, initial: ?[*]const u8, ibytes: c_long, callbacks: ov_callbacks) c_int;
pub extern fn ov_test_open(vf: *OggVorbis_File) c_int;

pub extern fn ov_bitrate(vf: *OggVorbis_File, i: c_int) c_long;
pub extern fn ov_bitrate_instant(vf: *OggVorbis_File) c_long;
pub extern fn ov_streams(vf: *OggVorbis_File) c_long;
pub extern fn ov_seekable(vf: *OggVorbis_File) c_long;
pub extern fn ov_serialnumber(vf: *OggVorbis_File, i: c_int) c_long;

pub extern fn ov_raw_total(vf: *OggVorbis_File, i: c_int) i64;
pub extern fn ov_pcm_total(vf: *OggVorbis_File, i: c_int) i64;
pub extern fn ov_time_total(vf: *OggVorbis_File, i: c_int) f64;

pub extern fn ov_raw_seek(vf: *OggVorbis_File, pos: i64) c_int;
pub extern fn ov_pcm_seek(vf: *OggVorbis_File, pos: i64) c_int;
pub extern fn ov_pcm_seek_page(vf: *OggVorbis_File, pos: i64) c_int;
pub extern fn ov_time_seek(vf: *OggVorbis_File, pos: f64) c_int;
pub extern fn ov_time_seek_page(vf: *OggVorbis_File, pos: f64) c_int;
pub extern fn ov_raw_seek_lap(vf: *OggVorbis_File, pos: i64) c_int;
pub extern fn ov_pcm_seek_lap(vf: *OggVorbis_File, pos: i64) c_int;
pub extern fn ov_pcm_seek_page_lap(vf: *OggVorbis_File, pos: i64) c_int;
pub extern fn ov_time_seek_lap(vf: *OggVorbis_File, pos: f64) c_int;
pub extern fn ov_time_seek_page_lap(vf: *OggVorbis_File, pos: f64) c_int;

pub extern fn ov_raw_tell(vf: *OggVorbis_File) i64;
pub extern fn ov_pcm_tell(vf: *OggVorbis_File) i64;
pub extern fn ov_time_tell(vf: *OggVorbis_File) f64;

pub extern fn ov_info(vf: *OggVorbis_File, link: c_int) ?*vorbis_info;
pub extern fn ov_comment(vf: *OggVorbis_File, link: c_int) ?*vorbis_comment;

pub extern fn ov_read_float(vf: *OggVorbis_File, pcm_channels: *[*][*]f32, samples: c_int, bitstream: ?*c_int) c_long;
pub extern fn ov_read_filter(vf: *OggVorbis_File, buffer: [*]u8, length: c_int, bigendianp: c_int, word: c_int, sgned: c_int, bitstream: ?*c_int, filter: ?ov_filter_fn, filter_param: ?*anyopaque) c_long;
pub extern fn ov_read(vf: *OggVorbis_File, buffer: [*]u8, length: c_int, bigendianp: c_int, word: c_int, sgned: c_int, bitstream: ?*c_int) c_long;
pub extern fn ov_crosslap(vf1: *OggVorbis_File, vf2: *OggVorbis_File) c_int;

pub extern fn ov_halfrate(vf: *OggVorbis_File, flag: c_int) c_int;
pub extern fn ov_halfrate_p(vf: *OggVorbis_File) c_int;
