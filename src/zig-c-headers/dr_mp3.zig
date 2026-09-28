//! Hand-written bindings for dr_mp3 (dr_mp3.h), stock config (stdio and wchar compiled in).

const builtin = @import("builtin");

pub const wchar_t = if (builtin.os.tag == .windows) u16 else i32;

pub const DRMP3_VERSION_MAJOR = 0;
pub const DRMP3_VERSION_MINOR = 7;
pub const DRMP3_VERSION_REVISION = 4;

pub const drmp3_bool8 = u8;
pub const drmp3_bool32 = u32;
pub const DRMP3_TRUE = 1;
pub const DRMP3_FALSE = 0;

pub const drmp3_result = i32;
pub const DRMP3_SUCCESS = 0;
pub const DRMP3_ERROR = -1;
pub const DRMP3_INVALID_ARGS = -2;
pub const DRMP3_INVALID_OPERATION = -3;
pub const DRMP3_OUT_OF_MEMORY = -4;
pub const DRMP3_OUT_OF_RANGE = -5;
pub const DRMP3_ACCESS_DENIED = -6;
pub const DRMP3_DOES_NOT_EXIST = -7;
pub const DRMP3_ALREADY_EXISTS = -8;
pub const DRMP3_TOO_MANY_OPEN_FILES = -9;
pub const DRMP3_INVALID_FILE = -10;
pub const DRMP3_TOO_BIG = -11;
pub const DRMP3_PATH_TOO_LONG = -12;
pub const DRMP3_NAME_TOO_LONG = -13;
pub const DRMP3_NOT_DIRECTORY = -14;
pub const DRMP3_IS_DIRECTORY = -15;
pub const DRMP3_DIRECTORY_NOT_EMPTY = -16;
pub const DRMP3_END_OF_FILE = -17;
pub const DRMP3_NO_SPACE = -18;
pub const DRMP3_BUSY = -19;
pub const DRMP3_IO_ERROR = -20;
pub const DRMP3_INTERRUPT = -21;
pub const DRMP3_UNAVAILABLE = -22;
pub const DRMP3_ALREADY_IN_USE = -23;
pub const DRMP3_BAD_ADDRESS = -24;
pub const DRMP3_BAD_SEEK = -25;
pub const DRMP3_BAD_PIPE = -26;
pub const DRMP3_DEADLOCK = -27;
pub const DRMP3_TOO_MANY_LINKS = -28;
pub const DRMP3_NOT_IMPLEMENTED = -29;
pub const DRMP3_NO_MESSAGE = -30;
pub const DRMP3_BAD_MESSAGE = -31;
pub const DRMP3_NO_DATA_AVAILABLE = -32;
pub const DRMP3_INVALID_DATA = -33;
pub const DRMP3_TIMEOUT = -34;
pub const DRMP3_NO_NETWORK = -35;
pub const DRMP3_NOT_UNIQUE = -36;
pub const DRMP3_NOT_SOCKET = -37;
pub const DRMP3_NO_ADDRESS = -38;
pub const DRMP3_BAD_PROTOCOL = -39;
pub const DRMP3_PROTOCOL_UNAVAILABLE = -40;
pub const DRMP3_PROTOCOL_NOT_SUPPORTED = -41;
pub const DRMP3_PROTOCOL_FAMILY_NOT_SUPPORTED = -42;
pub const DRMP3_ADDRESS_FAMILY_NOT_SUPPORTED = -43;
pub const DRMP3_SOCKET_NOT_SUPPORTED = -44;
pub const DRMP3_CONNECTION_RESET = -45;
pub const DRMP3_ALREADY_CONNECTED = -46;
pub const DRMP3_NOT_CONNECTED = -47;
pub const DRMP3_CONNECTION_REFUSED = -48;
pub const DRMP3_NO_HOST = -49;
pub const DRMP3_IN_PROGRESS = -50;
pub const DRMP3_CANCELLED = -51;
pub const DRMP3_MEMORY_ALREADY_MAPPED = -52;
pub const DRMP3_AT_END = -53;

pub const DRMP3_MAX_PCM_FRAMES_PER_MP3_FRAME = 1152;
pub const DRMP3_MAX_SAMPLES_PER_FRAME = DRMP3_MAX_PCM_FRAMES_PER_MP3_FRAME * 2;
pub const DRMP3_MAX_BITRESERVOIR_BYTES = 511;
pub const DRMP3_MAX_FREE_FORMAT_FRAME_SIZE = 2304;
pub const DRMP3_MAX_L3_FRAME_PAYLOAD_BYTES = DRMP3_MAX_FREE_FORMAT_FRAME_SIZE;

pub extern fn drmp3_version(pMajor: ?*u32, pMinor: ?*u32, pRevision: ?*u32) void;
pub extern fn drmp3_version_string() [*:0]const u8;

pub const drmp3_allocation_callbacks = extern struct {
    pUserData: ?*anyopaque,
    onMalloc: ?*const fn (sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque,
    onRealloc: ?*const fn (p: ?*anyopaque, sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque,
    onFree: ?*const fn (p: ?*anyopaque, pUserData: ?*anyopaque) callconv(.c) void,
};

pub const drmp3dec_frame_info = extern struct {
    frame_bytes: c_int,
    channels: c_int,
    sample_rate: c_int,
    layer: c_int,
    bitrate_kbps: c_int,
};

pub const drmp3_bs = extern struct {
    buf: ?[*]const u8,
    pos: c_int,
    limit: c_int,
};

pub const drmp3_L3_gr_info = extern struct {
    sfbtab: ?[*]const u8,
    part_23_length: u16,
    big_values: u16,
    scalefac_compress: u16,
    global_gain: u8,
    block_type: u8,
    mixed_block_flag: u8,
    n_long_sfb: u8,
    n_short_sfb: u8,
    table_select: [3]u8,
    region_count: [3]u8,
    subblock_gain: [3]u8,
    preflag: u8,
    scalefac_scale: u8,
    count1_table: u8,
    scfsi: u8,
};

pub const drmp3dec_scratch = extern struct {
    bs: drmp3_bs,
    maindata: [DRMP3_MAX_BITRESERVOIR_BYTES + DRMP3_MAX_L3_FRAME_PAYLOAD_BYTES]u8,
    gr_info: [4]drmp3_L3_gr_info,
    grbuf: [2][576]f32,
    scf: [40]f32,
    syn: [18 + 15][2 * 32]f32,
    ist_pos: [2][39]u8,
};

pub const drmp3dec = extern struct {
    mdct_overlap: [2][9 * 32]f32,
    qmf_state: [15 * 2 * 32]f32,
    reserv: c_int,
    free_format_bytes: c_int,
    header: [4]u8,
    reserv_buf: [511]u8,
    scratch: drmp3dec_scratch,
};

pub extern fn drmp3dec_init(dec: *drmp3dec) void;
/// pcm is drmp3_int16 or float depending on how the stream was set up; NULL skips output.
pub extern fn drmp3dec_decode_frame(dec: *drmp3dec, mp3: [*]const u8, mp3_bytes: c_int, pcm: ?*anyopaque, info: *drmp3dec_frame_info) c_int;
pub extern fn drmp3dec_f32_to_s16(in: [*]const f32, out: [*]i16, num_samples: usize) void;

pub const drmp3_seek_origin = c_uint;
pub const DRMP3_SEEK_SET: drmp3_seek_origin = 0;
pub const DRMP3_SEEK_CUR: drmp3_seek_origin = 1;
pub const DRMP3_SEEK_END: drmp3_seek_origin = 2;

pub const drmp3_seek_point = extern struct {
    seekPosInBytes: u64,
    pcmFrameIndex: u64,
    mp3FramesToDiscard: u16,
    pcmFramesToDiscard: u16,
};

pub const drmp3_metadata_type = c_uint;
pub const DRMP3_METADATA_TYPE_ID3V1: drmp3_metadata_type = 0;
pub const DRMP3_METADATA_TYPE_ID3V2: drmp3_metadata_type = 1;
pub const DRMP3_METADATA_TYPE_APE: drmp3_metadata_type = 2;
pub const DRMP3_METADATA_TYPE_XING: drmp3_metadata_type = 3;
pub const DRMP3_METADATA_TYPE_VBRI: drmp3_metadata_type = 4;

pub const drmp3_metadata = extern struct {
    type: drmp3_metadata_type,
    pRawData: ?*const anyopaque,
    rawDataSize: usize,
};

pub const drmp3_read_proc = *const fn (pUserData: ?*anyopaque, pBufferOut: ?*anyopaque, bytesToRead: usize) callconv(.c) usize;
pub const drmp3_seek_proc = *const fn (pUserData: ?*anyopaque, offset: c_int, origin: drmp3_seek_origin) callconv(.c) drmp3_bool32;
pub const drmp3_tell_proc = *const fn (pUserData: ?*anyopaque, pCursor: *i64) callconv(.c) drmp3_bool32;
pub const drmp3_meta_proc = *const fn (pUserData: ?*anyopaque, pMetadata: *const drmp3_metadata) callconv(.c) void;

pub const drmp3_config = extern struct {
    channels: u32,
    sampleRate: u32,
};

pub const drmp3 = extern struct {
    decoder: drmp3dec,
    channels: u32,
    sampleRate: u32,
    onRead: ?drmp3_read_proc,
    onSeek: ?drmp3_seek_proc,
    onMeta: ?drmp3_meta_proc,
    pUserData: ?*anyopaque,
    pUserDataMeta: ?*anyopaque,
    allocationCallbacks: drmp3_allocation_callbacks,
    mp3FrameChannels: u32,
    mp3FrameSampleRate: u32,
    pcmFramesConsumedInMP3Frame: u32,
    pcmFramesRemainingInMP3Frame: u32,
    pcmFrames: [@sizeOf(f32) * DRMP3_MAX_SAMPLES_PER_FRAME]u8,
    currentPCMFrame: u64,
    streamCursor: u64,
    streamLength: u64,
    streamStartOffset: u64,
    pSeekPoints: ?[*]drmp3_seek_point,
    seekPointCount: u32,
    delayInPCMFrames: u32,
    paddingInPCMFrames: u32,
    totalPCMFrameCount: u64,
    isVBR: drmp3_bool32,
    isCBR: drmp3_bool32,
    dataSize: usize,
    dataCapacity: usize,
    dataConsumed: usize,
    pData: ?[*]u8,
    atEnd: drmp3_bool32,
    memory: extern struct {
        pData: ?[*]const u8,
        dataSize: usize,
        currentReadPos: usize,
    },
};

pub extern fn drmp3_init(pMP3: *drmp3, onRead: drmp3_read_proc, onSeek: ?drmp3_seek_proc, onTell: ?drmp3_tell_proc, onMeta: ?drmp3_meta_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) drmp3_bool32;
pub extern fn drmp3_init_memory_with_metadata(pMP3: *drmp3, pData: *const anyopaque, dataSize: usize, onMeta: ?drmp3_meta_proc, pUserDataMeta: ?*anyopaque, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) drmp3_bool32;
pub extern fn drmp3_init_memory(pMP3: *drmp3, pData: *const anyopaque, dataSize: usize, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) drmp3_bool32;
pub extern fn drmp3_init_file_with_metadata(pMP3: *drmp3, pFilePath: [*:0]const u8, onMeta: ?drmp3_meta_proc, pUserDataMeta: ?*anyopaque, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) drmp3_bool32;
pub extern fn drmp3_init_file_with_metadata_w(pMP3: *drmp3, pFilePath: [*:0]const wchar_t, onMeta: ?drmp3_meta_proc, pUserDataMeta: ?*anyopaque, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) drmp3_bool32;
pub extern fn drmp3_init_file(pMP3: *drmp3, pFilePath: [*:0]const u8, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) drmp3_bool32;
pub extern fn drmp3_init_file_w(pMP3: *drmp3, pFilePath: [*:0]const wchar_t, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) drmp3_bool32;
pub extern fn drmp3_uninit(pMP3: *drmp3) void;
pub extern fn drmp3_read_pcm_frames_f32(pMP3: *drmp3, framesToRead: u64, pBufferOut: ?[*]f32) u64;
pub extern fn drmp3_read_pcm_frames_s16(pMP3: *drmp3, framesToRead: u64, pBufferOut: ?[*]i16) u64;
pub extern fn drmp3_seek_to_pcm_frame(pMP3: *drmp3, frameIndex: u64) drmp3_bool32;
pub extern fn drmp3_get_pcm_frame_count(pMP3: *drmp3) u64;
pub extern fn drmp3_get_mp3_frame_count(pMP3: *drmp3) u64;
pub extern fn drmp3_get_mp3_and_pcm_frame_count(pMP3: *drmp3, pMP3FrameCount: ?*u64, pPCMFrameCount: ?*u64) drmp3_bool32;
pub extern fn drmp3_calculate_seek_points(pMP3: *drmp3, pSeekPointCount: *u32, pSeekPoints: [*]drmp3_seek_point) drmp3_bool32;
pub extern fn drmp3_bind_seek_table(pMP3: *drmp3, seekPointCount: u32, pSeekPoints: ?[*]drmp3_seek_point) drmp3_bool32;
pub extern fn drmp3_open_and_read_pcm_frames_f32(onRead: drmp3_read_proc, onSeek: ?drmp3_seek_proc, onTell: ?drmp3_tell_proc, pUserData: ?*anyopaque, pConfig: ?*drmp3_config, pTotalFrameCount: ?*u64, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) ?[*]f32;
pub extern fn drmp3_open_and_read_pcm_frames_s16(onRead: drmp3_read_proc, onSeek: ?drmp3_seek_proc, onTell: ?drmp3_tell_proc, pUserData: ?*anyopaque, pConfig: ?*drmp3_config, pTotalFrameCount: ?*u64, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) ?[*]i16;
pub extern fn drmp3_open_memory_and_read_pcm_frames_f32(pData: *const anyopaque, dataSize: usize, pConfig: ?*drmp3_config, pTotalFrameCount: ?*u64, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) ?[*]f32;
pub extern fn drmp3_open_memory_and_read_pcm_frames_s16(pData: *const anyopaque, dataSize: usize, pConfig: ?*drmp3_config, pTotalFrameCount: ?*u64, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) ?[*]i16;
pub extern fn drmp3_open_file_and_read_pcm_frames_f32(filePath: [*:0]const u8, pConfig: ?*drmp3_config, pTotalFrameCount: ?*u64, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) ?[*]f32;
pub extern fn drmp3_open_file_and_read_pcm_frames_s16(filePath: [*:0]const u8, pConfig: ?*drmp3_config, pTotalFrameCount: ?*u64, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) ?[*]i16;
pub extern fn drmp3_malloc(sz: usize, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) ?*anyopaque;
pub extern fn drmp3_free(p: ?*anyopaque, pAllocationCallbacks: ?*const drmp3_allocation_callbacks) void;
