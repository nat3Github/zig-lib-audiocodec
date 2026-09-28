//! Hand-written bindings for dr_wav (dr_wav.h), stock config (stdio, wchar and conversion API compiled in).

const builtin = @import("builtin");

pub const wchar_t = if (builtin.os.tag == .windows) u16 else i32;

pub const DRWAV_VERSION_MAJOR = 0;
pub const DRWAV_VERSION_MINOR = 14;
pub const DRWAV_VERSION_REVISION = 6;

pub const drwav_bool8 = u8;
pub const drwav_bool32 = u32;
pub const DRWAV_TRUE = 1;
pub const DRWAV_FALSE = 0;

pub const drwav_result = i32;
pub const DRWAV_SUCCESS = 0;
pub const DRWAV_ERROR = -1;
pub const DRWAV_INVALID_ARGS = -2;
pub const DRWAV_INVALID_OPERATION = -3;
pub const DRWAV_OUT_OF_MEMORY = -4;
pub const DRWAV_OUT_OF_RANGE = -5;
pub const DRWAV_ACCESS_DENIED = -6;
pub const DRWAV_DOES_NOT_EXIST = -7;
pub const DRWAV_ALREADY_EXISTS = -8;
pub const DRWAV_TOO_MANY_OPEN_FILES = -9;
pub const DRWAV_INVALID_FILE = -10;
pub const DRWAV_TOO_BIG = -11;
pub const DRWAV_PATH_TOO_LONG = -12;
pub const DRWAV_NAME_TOO_LONG = -13;
pub const DRWAV_NOT_DIRECTORY = -14;
pub const DRWAV_IS_DIRECTORY = -15;
pub const DRWAV_DIRECTORY_NOT_EMPTY = -16;
pub const DRWAV_END_OF_FILE = -17;
pub const DRWAV_NO_SPACE = -18;
pub const DRWAV_BUSY = -19;
pub const DRWAV_IO_ERROR = -20;
pub const DRWAV_INTERRUPT = -21;
pub const DRWAV_UNAVAILABLE = -22;
pub const DRWAV_ALREADY_IN_USE = -23;
pub const DRWAV_BAD_ADDRESS = -24;
pub const DRWAV_BAD_SEEK = -25;
pub const DRWAV_BAD_PIPE = -26;
pub const DRWAV_DEADLOCK = -27;
pub const DRWAV_TOO_MANY_LINKS = -28;
pub const DRWAV_NOT_IMPLEMENTED = -29;
pub const DRWAV_NO_MESSAGE = -30;
pub const DRWAV_BAD_MESSAGE = -31;
pub const DRWAV_NO_DATA_AVAILABLE = -32;
pub const DRWAV_INVALID_DATA = -33;
pub const DRWAV_TIMEOUT = -34;
pub const DRWAV_NO_NETWORK = -35;
pub const DRWAV_NOT_UNIQUE = -36;
pub const DRWAV_NOT_SOCKET = -37;
pub const DRWAV_NO_ADDRESS = -38;
pub const DRWAV_BAD_PROTOCOL = -39;
pub const DRWAV_PROTOCOL_UNAVAILABLE = -40;
pub const DRWAV_PROTOCOL_NOT_SUPPORTED = -41;
pub const DRWAV_PROTOCOL_FAMILY_NOT_SUPPORTED = -42;
pub const DRWAV_ADDRESS_FAMILY_NOT_SUPPORTED = -43;
pub const DRWAV_SOCKET_NOT_SUPPORTED = -44;
pub const DRWAV_CONNECTION_RESET = -45;
pub const DRWAV_ALREADY_CONNECTED = -46;
pub const DRWAV_NOT_CONNECTED = -47;
pub const DRWAV_CONNECTION_REFUSED = -48;
pub const DRWAV_NO_HOST = -49;
pub const DRWAV_IN_PROGRESS = -50;
pub const DRWAV_CANCELLED = -51;
pub const DRWAV_MEMORY_ALREADY_MAPPED = -52;
pub const DRWAV_AT_END = -53;

pub const DR_WAVE_FORMAT_PCM = 0x1;
pub const DR_WAVE_FORMAT_ADPCM = 0x2;
pub const DR_WAVE_FORMAT_IEEE_FLOAT = 0x3;
pub const DR_WAVE_FORMAT_ALAW = 0x6;
pub const DR_WAVE_FORMAT_MULAW = 0x7;
pub const DR_WAVE_FORMAT_DTS = 0x8;
pub const DR_WAVE_FORMAT_DVI_ADPCM = 0x11;
pub const DR_WAVE_FORMAT_EXTENSIBLE = 0xFFFE;

pub const DRWAV_SEQUENTIAL = 0x00000001;
pub const DRWAV_WITH_METADATA = 0x00000002;

pub extern fn drwav_version(pMajor: ?*u32, pMinor: ?*u32, pRevision: ?*u32) void;
pub extern fn drwav_version_string() [*:0]const u8;

pub const drwav_allocation_callbacks = extern struct {
    pUserData: ?*anyopaque,
    onMalloc: ?*const fn (sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque,
    onRealloc: ?*const fn (p: ?*anyopaque, sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque,
    onFree: ?*const fn (p: ?*anyopaque, pUserData: ?*anyopaque) callconv(.c) void,
};

pub const drwav_seek_origin = c_uint;
pub const DRWAV_SEEK_SET: drwav_seek_origin = 0;
pub const DRWAV_SEEK_CUR: drwav_seek_origin = 1;
pub const DRWAV_SEEK_END: drwav_seek_origin = 2;

pub const drwav_container = c_uint;
pub const drwav_container_riff: drwav_container = 0;
pub const drwav_container_rifx: drwav_container = 1;
pub const drwav_container_w64: drwav_container = 2;
pub const drwav_container_rf64: drwav_container = 3;
pub const drwav_container_aiff: drwav_container = 4;

pub const drwav_chunk_header = extern struct {
    id: extern union {
        fourcc: [4]u8,
        guid: [16]u8,
    },
    sizeInBytes: u64,
    paddingSize: c_uint,
};

pub const drwav_fmt = extern struct {
    formatTag: u16,
    channels: u16,
    sampleRate: u32,
    avgBytesPerSec: u32,
    blockAlign: u16,
    bitsPerSample: u16,
    extendedSize: u16,
    validBitsPerSample: u16,
    channelMask: u32,
    subFormat: [16]u8,
};

pub extern fn drwav_fmt_get_format(pFMT: *const drwav_fmt) u16;

pub const drwav_read_proc = *const fn (pUserData: ?*anyopaque, pBufferOut: ?*anyopaque, bytesToRead: usize) callconv(.c) usize;
pub const drwav_write_proc = *const fn (pUserData: ?*anyopaque, pData: ?*const anyopaque, bytesToWrite: usize) callconv(.c) usize;
pub const drwav_seek_proc = *const fn (pUserData: ?*anyopaque, offset: c_int, origin: drwav_seek_origin) callconv(.c) drwav_bool32;
pub const drwav_tell_proc = *const fn (pUserData: ?*anyopaque, pCursor: *i64) callconv(.c) drwav_bool32;
pub const drwav_chunk_proc = *const fn (pChunkUserData: ?*anyopaque, onRead: drwav_read_proc, onSeek: drwav_seek_proc, pReadSeekUserData: ?*anyopaque, pChunkHeader: *const drwav_chunk_header, container: drwav_container, pFMT: *const drwav_fmt) callconv(.c) u64;

pub const drwav__memory_stream = extern struct {
    data: ?[*]const u8,
    dataSize: usize,
    currentReadPos: usize,
};

pub const drwav__memory_stream_write = extern struct {
    ppData: ?*?*anyopaque,
    pDataSize: ?*usize,
    dataSize: usize,
    dataCapacity: usize,
    currentWritePos: usize,
};

pub const drwav_data_format = extern struct {
    container: drwav_container,
    format: u32,
    channels: u32,
    sampleRate: u32,
    bitsPerSample: u32,
};

pub const drwav_metadata_type = c_int;
pub const drwav_metadata_type_none: drwav_metadata_type = 0;
pub const drwav_metadata_type_unknown: drwav_metadata_type = 1 << 0;
pub const drwav_metadata_type_smpl: drwav_metadata_type = 1 << 1;
pub const drwav_metadata_type_inst: drwav_metadata_type = 1 << 2;
pub const drwav_metadata_type_cue: drwav_metadata_type = 1 << 3;
pub const drwav_metadata_type_acid: drwav_metadata_type = 1 << 4;
pub const drwav_metadata_type_bext: drwav_metadata_type = 1 << 5;
pub const drwav_metadata_type_list_label: drwav_metadata_type = 1 << 6;
pub const drwav_metadata_type_list_note: drwav_metadata_type = 1 << 7;
pub const drwav_metadata_type_list_labelled_cue_region: drwav_metadata_type = 1 << 8;
pub const drwav_metadata_type_list_info_software: drwav_metadata_type = 1 << 9;
pub const drwav_metadata_type_list_info_copyright: drwav_metadata_type = 1 << 10;
pub const drwav_metadata_type_list_info_title: drwav_metadata_type = 1 << 11;
pub const drwav_metadata_type_list_info_artist: drwav_metadata_type = 1 << 12;
pub const drwav_metadata_type_list_info_comment: drwav_metadata_type = 1 << 13;
pub const drwav_metadata_type_list_info_date: drwav_metadata_type = 1 << 14;
pub const drwav_metadata_type_list_info_genre: drwav_metadata_type = 1 << 15;
pub const drwav_metadata_type_list_info_album: drwav_metadata_type = 1 << 16;
pub const drwav_metadata_type_list_info_tracknumber: drwav_metadata_type = 1 << 17;
pub const drwav_metadata_type_list_info_location: drwav_metadata_type = 1 << 18;
pub const drwav_metadata_type_list_info_organization: drwav_metadata_type = 1 << 19;
pub const drwav_metadata_type_list_info_keywords: drwav_metadata_type = 1 << 20;
pub const drwav_metadata_type_list_info_medium: drwav_metadata_type = 1 << 21;
pub const drwav_metadata_type_list_info_description: drwav_metadata_type = 1 << 22;
pub const drwav_metadata_type_list_all_info_strings: drwav_metadata_type = 0x7ffe00; // info_software .. info_description
pub const drwav_metadata_type_list_all_adtl: drwav_metadata_type = 0x1c0; // label | note | labelled_cue_region
pub const drwav_metadata_type_all: drwav_metadata_type = -2;
pub const drwav_metadata_type_all_including_unknown: drwav_metadata_type = -1;

pub const drwav_smpl_loop_type = c_uint;
pub const drwav_smpl_loop_type_forward: drwav_smpl_loop_type = 0;
pub const drwav_smpl_loop_type_pingpong: drwav_smpl_loop_type = 1;
pub const drwav_smpl_loop_type_backward: drwav_smpl_loop_type = 2;

pub const drwav_smpl_loop = extern struct {
    cuePointId: u32,
    type: u32,
    firstSampleOffset: u32,
    lastSampleOffset: u32,
    sampleFraction: u32,
    playCount: u32,
};

pub const drwav_smpl = extern struct {
    manufacturerId: u32,
    productId: u32,
    samplePeriodNanoseconds: u32,
    midiUnityNote: u32,
    midiPitchFraction: u32,
    smpteFormat: u32,
    smpteOffset: u32,
    sampleLoopCount: u32,
    samplerSpecificDataSizeInBytes: u32,
    pLoops: ?[*]drwav_smpl_loop,
    pSamplerSpecificData: ?[*]u8,
};

pub const drwav_inst = extern struct {
    midiUnityNote: i8,
    fineTuneCents: i8,
    gainDecibels: i8,
    lowNote: i8,
    highNote: i8,
    lowVelocity: i8,
    highVelocity: i8,
};

pub const drwav_cue_point = extern struct {
    id: u32,
    playOrderPosition: u32,
    dataChunkId: [4]u8,
    chunkStart: u32,
    blockStart: u32,
    sampleOffset: u32,
};

pub const drwav_cue = extern struct {
    cuePointCount: u32,
    pCuePoints: ?[*]drwav_cue_point,
};

pub const drwav_acid_flag = c_uint;
pub const drwav_acid_flag_one_shot: drwav_acid_flag = 1;
pub const drwav_acid_flag_root_note_set: drwav_acid_flag = 2;
pub const drwav_acid_flag_stretch: drwav_acid_flag = 4;
pub const drwav_acid_flag_disk_based: drwav_acid_flag = 8;
pub const drwav_acid_flag_acidizer: drwav_acid_flag = 16;

pub const drwav_acid = extern struct {
    flags: u32,
    midiUnityNote: u16,
    reserved1: u16,
    reserved2: f32,
    numBeats: u32,
    meterDenominator: u16,
    meterNumerator: u16,
    tempo: f32,
};

pub const drwav_list_label_or_note = extern struct {
    cuePointId: u32,
    stringLength: u32,
    pString: ?[*:0]u8,
};

pub const drwav_bext = extern struct {
    pDescription: ?[*:0]u8,
    pOriginatorName: ?[*:0]u8,
    pOriginatorReference: ?[*:0]u8,
    pOriginationDate: [10]u8,
    pOriginationTime: [8]u8,
    timeReference: u64,
    version: u16,
    pCodingHistory: ?[*]u8,
    codingHistorySize: u32,
    pUMID: ?[*]u8,
    loudnessValue: u16,
    loudnessRange: u16,
    maxTruePeakLevel: u16,
    maxMomentaryLoudness: u16,
    maxShortTermLoudness: u16,
};

pub const drwav_list_info_text = extern struct {
    stringLength: u32,
    pString: ?[*:0]u8,
};

pub const drwav_list_labelled_cue_region = extern struct {
    cuePointId: u32,
    sampleLength: u32,
    purposeId: [4]u8,
    country: u16,
    language: u16,
    dialect: u16,
    codePage: u16,
    stringLength: u32,
    pString: ?[*:0]u8,
};

pub const drwav_metadata_location = c_uint;
pub const drwav_metadata_location_invalid: drwav_metadata_location = 0;
pub const drwav_metadata_location_top_level: drwav_metadata_location = 1;
pub const drwav_metadata_location_inside_info_list: drwav_metadata_location = 2;
pub const drwav_metadata_location_inside_adtl_list: drwav_metadata_location = 3;

pub const drwav_unknown_metadata = extern struct {
    id: [4]u8,
    chunkLocation: drwav_metadata_location,
    dataSizeInBytes: u32,
    pData: ?[*]u8,
};

pub const drwav_metadata = extern struct {
    type: drwav_metadata_type,
    data: extern union {
        cue: drwav_cue,
        smpl: drwav_smpl,
        acid: drwav_acid,
        inst: drwav_inst,
        bext: drwav_bext,
        labelOrNote: drwav_list_label_or_note,
        labelledCueRegion: drwav_list_labelled_cue_region,
        infoText: drwav_list_info_text,
        unknown: drwav_unknown_metadata,
    },
};

pub const drwav = extern struct {
    onRead: ?drwav_read_proc,
    onWrite: ?drwav_write_proc,
    onSeek: ?drwav_seek_proc,
    onTell: ?drwav_tell_proc,
    pUserData: ?*anyopaque,
    allocationCallbacks: drwav_allocation_callbacks,
    container: drwav_container,
    fmt: drwav_fmt,
    sampleRate: u32,
    channels: u16,
    bitsPerSample: u16,
    translatedFormatTag: u16,
    totalPCMFrameCount: u64,
    dataChunkDataSize: u64,
    dataChunkDataPos: u64,
    bytesRemaining: u64,
    readCursorInPCMFrames: u64,
    dataChunkDataSizeTargetWrite: u64,
    isSequentialWrite: drwav_bool32,
    pMetadata: ?[*]drwav_metadata,
    metadataCount: u32,
    memoryStream: drwav__memory_stream,
    memoryStreamWrite: drwav__memory_stream_write,
    msadpcm: extern struct {
        bytesRemainingInBlock: u32,
        predictor: [2]u16,
        delta: [2]i32,
        cachedFrames: [4]i32,
        cachedFrameCount: u32,
        prevFrames: [2][2]i32,
    },
    ima: extern struct {
        bytesRemainingInBlock: u32,
        predictor: [2]i32,
        stepIndex: [2]i32,
        cachedFrames: [16]i32,
        cachedFrameCount: u32,
    },
    aiff: extern struct {
        isLE: drwav_bool8,
        isUnsigned: drwav_bool8,
    },
};

pub extern fn drwav_init(pWav: *drwav, onRead: drwav_read_proc, onSeek: ?drwav_seek_proc, onTell: ?drwav_tell_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_ex(pWav: *drwav, onRead: drwav_read_proc, onSeek: ?drwav_seek_proc, onTell: ?drwav_tell_proc, onChunk: ?drwav_chunk_proc, pReadSeekTellUserData: ?*anyopaque, pChunkUserData: ?*anyopaque, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_with_metadata(pWav: *drwav, onRead: drwav_read_proc, onSeek: ?drwav_seek_proc, onTell: ?drwav_tell_proc, pUserData: ?*anyopaque, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_write(pWav: *drwav, pFormat: *const drwav_data_format, onWrite: drwav_write_proc, onSeek: ?drwav_seek_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_write_sequential(pWav: *drwav, pFormat: *const drwav_data_format, totalSampleCount: u64, onWrite: drwav_write_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_write_sequential_pcm_frames(pWav: *drwav, pFormat: *const drwav_data_format, totalPCMFrameCount: u64, onWrite: drwav_write_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_write_with_metadata(pWav: *drwav, pFormat: *const drwav_data_format, onWrite: drwav_write_proc, onSeek: ?drwav_seek_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drwav_allocation_callbacks, pMetadata: ?[*]drwav_metadata, metadataCount: u32) drwav_bool32;
pub extern fn drwav_target_write_size_bytes(pFormat: *const drwav_data_format, totalFrameCount: u64, pMetadata: ?[*]drwav_metadata, metadataCount: u32) u64;
pub extern fn drwav_take_ownership_of_metadata(pWav: *drwav) ?[*]drwav_metadata;
pub extern fn drwav_uninit(pWav: *drwav) drwav_result;
pub extern fn drwav_read_raw(pWav: *drwav, bytesToRead: usize, pBufferOut: ?*anyopaque) usize;
pub extern fn drwav_read_pcm_frames(pWav: *drwav, framesToRead: u64, pBufferOut: ?*anyopaque) u64;
pub extern fn drwav_read_pcm_frames_le(pWav: *drwav, framesToRead: u64, pBufferOut: ?*anyopaque) u64;
pub extern fn drwav_read_pcm_frames_be(pWav: *drwav, framesToRead: u64, pBufferOut: ?*anyopaque) u64;
pub extern fn drwav_seek_to_pcm_frame(pWav: *drwav, targetFrameIndex: u64) drwav_bool32;
pub extern fn drwav_get_cursor_in_pcm_frames(pWav: *drwav, pCursor: *u64) drwav_result;
pub extern fn drwav_get_length_in_pcm_frames(pWav: *drwav, pLength: *u64) drwav_result;
pub extern fn drwav_write_raw(pWav: *drwav, bytesToWrite: usize, pData: ?*const anyopaque) usize;
pub extern fn drwav_write_pcm_frames(pWav: *drwav, framesToWrite: u64, pData: ?*const anyopaque) u64;
pub extern fn drwav_write_pcm_frames_le(pWav: *drwav, framesToWrite: u64, pData: ?*const anyopaque) u64;
pub extern fn drwav_write_pcm_frames_be(pWav: *drwav, framesToWrite: u64, pData: ?*const anyopaque) u64;

pub extern fn drwav_read_pcm_frames_s16(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]i16) u64;
pub extern fn drwav_read_pcm_frames_s16le(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]i16) u64;
pub extern fn drwav_read_pcm_frames_s16be(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]i16) u64;
pub extern fn drwav_u8_to_s16(pOut: [*]i16, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_s24_to_s16(pOut: [*]i16, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_s32_to_s16(pOut: [*]i16, pIn: [*]const i32, sampleCount: usize) void;
pub extern fn drwav_f32_to_s16(pOut: [*]i16, pIn: [*]const f32, sampleCount: usize) void;
pub extern fn drwav_f64_to_s16(pOut: [*]i16, pIn: [*]const f64, sampleCount: usize) void;
pub extern fn drwav_alaw_to_s16(pOut: [*]i16, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_mulaw_to_s16(pOut: [*]i16, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_read_pcm_frames_f32(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]f32) u64;
pub extern fn drwav_read_pcm_frames_f32le(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]f32) u64;
pub extern fn drwav_read_pcm_frames_f32be(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]f32) u64;
pub extern fn drwav_u8_to_f32(pOut: [*]f32, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_s16_to_f32(pOut: [*]f32, pIn: [*]const i16, sampleCount: usize) void;
pub extern fn drwav_s24_to_f32(pOut: [*]f32, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_s32_to_f32(pOut: [*]f32, pIn: [*]const i32, sampleCount: usize) void;
pub extern fn drwav_f64_to_f32(pOut: [*]f32, pIn: [*]const f64, sampleCount: usize) void;
pub extern fn drwav_alaw_to_f32(pOut: [*]f32, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_mulaw_to_f32(pOut: [*]f32, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_read_pcm_frames_s32(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]i32) u64;
pub extern fn drwav_read_pcm_frames_s32le(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]i32) u64;
pub extern fn drwav_read_pcm_frames_s32be(pWav: *drwav, framesToRead: u64, pBufferOut: ?[*]i32) u64;
pub extern fn drwav_u8_to_s32(pOut: [*]i32, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_s16_to_s32(pOut: [*]i32, pIn: [*]const i16, sampleCount: usize) void;
pub extern fn drwav_s24_to_s32(pOut: [*]i32, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_f32_to_s32(pOut: [*]i32, pIn: [*]const f32, sampleCount: usize) void;
pub extern fn drwav_f64_to_s32(pOut: [*]i32, pIn: [*]const f64, sampleCount: usize) void;
pub extern fn drwav_alaw_to_s32(pOut: [*]i32, pIn: [*]const u8, sampleCount: usize) void;
pub extern fn drwav_mulaw_to_s32(pOut: [*]i32, pIn: [*]const u8, sampleCount: usize) void;

pub extern fn drwav_init_file(pWav: *drwav, filename: [*:0]const u8, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_ex(pWav: *drwav, filename: [*:0]const u8, onChunk: ?drwav_chunk_proc, pChunkUserData: ?*anyopaque, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_w(pWav: *drwav, filename: [*:0]const wchar_t, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_ex_w(pWav: *drwav, filename: [*:0]const wchar_t, onChunk: ?drwav_chunk_proc, pChunkUserData: ?*anyopaque, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_with_metadata(pWav: *drwav, filename: [*:0]const u8, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_with_metadata_w(pWav: *drwav, filename: [*:0]const wchar_t, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_write(pWav: *drwav, filename: [*:0]const u8, pFormat: *const drwav_data_format, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_write_sequential(pWav: *drwav, filename: [*:0]const u8, pFormat: *const drwav_data_format, totalSampleCount: u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_write_sequential_pcm_frames(pWav: *drwav, filename: [*:0]const u8, pFormat: *const drwav_data_format, totalPCMFrameCount: u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_write_w(pWav: *drwav, filename: [*:0]const wchar_t, pFormat: *const drwav_data_format, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_write_sequential_w(pWav: *drwav, filename: [*:0]const wchar_t, pFormat: *const drwav_data_format, totalSampleCount: u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_file_write_sequential_pcm_frames_w(pWav: *drwav, filename: [*:0]const wchar_t, pFormat: *const drwav_data_format, totalPCMFrameCount: u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;

pub extern fn drwav_init_memory(pWav: *drwav, data: *const anyopaque, dataSize: usize, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_memory_ex(pWav: *drwav, data: *const anyopaque, dataSize: usize, onChunk: ?drwav_chunk_proc, pChunkUserData: ?*anyopaque, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_memory_with_metadata(pWav: *drwav, data: *const anyopaque, dataSize: usize, flags: u32, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_memory_write(pWav: *drwav, ppData: *?*anyopaque, pDataSize: *usize, pFormat: *const drwav_data_format, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_memory_write_sequential(pWav: *drwav, ppData: *?*anyopaque, pDataSize: *usize, pFormat: *const drwav_data_format, totalSampleCount: u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;
pub extern fn drwav_init_memory_write_sequential_pcm_frames(pWav: *drwav, ppData: *?*anyopaque, pDataSize: *usize, pFormat: *const drwav_data_format, totalPCMFrameCount: u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) drwav_bool32;

pub extern fn drwav_open_and_read_pcm_frames_s16(onRead: drwav_read_proc, onSeek: ?drwav_seek_proc, onTell: ?drwav_tell_proc, pUserData: ?*anyopaque, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i16;
pub extern fn drwav_open_and_read_pcm_frames_f32(onRead: drwav_read_proc, onSeek: ?drwav_seek_proc, onTell: ?drwav_tell_proc, pUserData: ?*anyopaque, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]f32;
pub extern fn drwav_open_and_read_pcm_frames_s32(onRead: drwav_read_proc, onSeek: ?drwav_seek_proc, onTell: ?drwav_tell_proc, pUserData: ?*anyopaque, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i32;
pub extern fn drwav_open_file_and_read_pcm_frames_s16(filename: [*:0]const u8, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i16;
pub extern fn drwav_open_file_and_read_pcm_frames_f32(filename: [*:0]const u8, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]f32;
pub extern fn drwav_open_file_and_read_pcm_frames_s32(filename: [*:0]const u8, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i32;
pub extern fn drwav_open_file_and_read_pcm_frames_s16_w(filename: [*:0]const wchar_t, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i16;
pub extern fn drwav_open_file_and_read_pcm_frames_f32_w(filename: [*:0]const wchar_t, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]f32;
pub extern fn drwav_open_file_and_read_pcm_frames_s32_w(filename: [*:0]const wchar_t, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i32;
pub extern fn drwav_open_memory_and_read_pcm_frames_s16(data: *const anyopaque, dataSize: usize, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i16;
pub extern fn drwav_open_memory_and_read_pcm_frames_f32(data: *const anyopaque, dataSize: usize, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]f32;
pub extern fn drwav_open_memory_and_read_pcm_frames_s32(data: *const anyopaque, dataSize: usize, channelsOut: ?*c_uint, sampleRateOut: ?*c_uint, totalFrameCountOut: ?*u64, pAllocationCallbacks: ?*const drwav_allocation_callbacks) ?[*]i32;

pub extern fn drwav_free(p: ?*anyopaque, pAllocationCallbacks: ?*const drwav_allocation_callbacks) void;
pub extern fn drwav_bytes_to_u16(data: [*]const u8) u16;
pub extern fn drwav_bytes_to_s16(data: [*]const u8) i16;
pub extern fn drwav_bytes_to_u32(data: [*]const u8) u32;
pub extern fn drwav_bytes_to_s32(data: [*]const u8) i32;
pub extern fn drwav_bytes_to_u64(data: [*]const u8) u64;
pub extern fn drwav_bytes_to_s64(data: [*]const u8) i64;
pub extern fn drwav_bytes_to_f32(data: [*]const u8) f32;
pub extern fn drwav_guid_equal(a: *const [16]u8, b: *const [16]u8) drwav_bool32;
pub extern fn drwav_fourcc_equal(a: [*]const u8, b: [*:0]const u8) drwav_bool32;
