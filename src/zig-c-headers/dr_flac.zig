//! Hand-written bindings for dr_flac (dr_flac.h), built with DR_FLAC_NO_STDIO (module/build.zig, no file APIs); Ogg, CRC compiled in,
//! DR_FLAC_BUFFER_SIZE 4096).

pub const DRFLAC_VERSION_MAJOR = 0;
pub const DRFLAC_VERSION_MINOR = 13;
pub const DRFLAC_VERSION_REVISION = 4;

pub const drflac_bool8 = u8;
pub const drflac_bool32 = u32;
pub const DRFLAC_TRUE = 1;
pub const DRFLAC_FALSE = 0;

pub const drflac_result = i32;
pub const DRFLAC_SUCCESS = 0;
pub const DRFLAC_ERROR = -1;
pub const DRFLAC_INVALID_ARGS = -2;
pub const DRFLAC_INVALID_OPERATION = -3;
pub const DRFLAC_OUT_OF_MEMORY = -4;
pub const DRFLAC_OUT_OF_RANGE = -5;
pub const DRFLAC_ACCESS_DENIED = -6;
pub const DRFLAC_DOES_NOT_EXIST = -7;
pub const DRFLAC_ALREADY_EXISTS = -8;
pub const DRFLAC_TOO_MANY_OPEN_FILES = -9;
pub const DRFLAC_INVALID_FILE = -10;
pub const DRFLAC_TOO_BIG = -11;
pub const DRFLAC_PATH_TOO_LONG = -12;
pub const DRFLAC_NAME_TOO_LONG = -13;
pub const DRFLAC_NOT_DIRECTORY = -14;
pub const DRFLAC_IS_DIRECTORY = -15;
pub const DRFLAC_DIRECTORY_NOT_EMPTY = -16;
pub const DRFLAC_END_OF_FILE = -17;
pub const DRFLAC_NO_SPACE = -18;
pub const DRFLAC_BUSY = -19;
pub const DRFLAC_IO_ERROR = -20;
pub const DRFLAC_INTERRUPT = -21;
pub const DRFLAC_UNAVAILABLE = -22;
pub const DRFLAC_ALREADY_IN_USE = -23;
pub const DRFLAC_BAD_ADDRESS = -24;
pub const DRFLAC_BAD_SEEK = -25;
pub const DRFLAC_BAD_PIPE = -26;
pub const DRFLAC_DEADLOCK = -27;
pub const DRFLAC_TOO_MANY_LINKS = -28;
pub const DRFLAC_NOT_IMPLEMENTED = -29;
pub const DRFLAC_NO_MESSAGE = -30;
pub const DRFLAC_BAD_MESSAGE = -31;
pub const DRFLAC_NO_DATA_AVAILABLE = -32;
pub const DRFLAC_INVALID_DATA = -33;
pub const DRFLAC_TIMEOUT = -34;
pub const DRFLAC_NO_NETWORK = -35;
pub const DRFLAC_NOT_UNIQUE = -36;
pub const DRFLAC_NOT_SOCKET = -37;
pub const DRFLAC_NO_ADDRESS = -38;
pub const DRFLAC_BAD_PROTOCOL = -39;
pub const DRFLAC_PROTOCOL_UNAVAILABLE = -40;
pub const DRFLAC_PROTOCOL_NOT_SUPPORTED = -41;
pub const DRFLAC_PROTOCOL_FAMILY_NOT_SUPPORTED = -42;
pub const DRFLAC_ADDRESS_FAMILY_NOT_SUPPORTED = -43;
pub const DRFLAC_SOCKET_NOT_SUPPORTED = -44;
pub const DRFLAC_CONNECTION_RESET = -45;
pub const DRFLAC_ALREADY_CONNECTED = -46;
pub const DRFLAC_NOT_CONNECTED = -47;
pub const DRFLAC_CONNECTION_REFUSED = -48;
pub const DRFLAC_NO_HOST = -49;
pub const DRFLAC_IN_PROGRESS = -50;
pub const DRFLAC_CANCELLED = -51;
pub const DRFLAC_MEMORY_ALREADY_MAPPED = -52;
pub const DRFLAC_AT_END = -53;
pub const DRFLAC_CRC_MISMATCH = -100;

pub extern fn drflac_version(pMajor: ?*u32, pMinor: ?*u32, pRevision: ?*u32) void;
pub extern fn drflac_version_string() [*:0]const u8;

pub const drflac_allocation_callbacks = extern struct {
    pUserData: ?*anyopaque,
    onMalloc: ?*const fn (sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque,
    onRealloc: ?*const fn (p: ?*anyopaque, sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque,
    onFree: ?*const fn (p: ?*anyopaque, pUserData: ?*anyopaque) callconv(.c) void,
};

pub const DR_FLAC_BUFFER_SIZE = 4096;

/// 64-bit when _WIN64/_LP64 (i.e. 64-bit pointers), else 32-bit.
pub const drflac_cache_t = if (@sizeOf(usize) == 8) u64 else u32;

pub const DRFLAC_METADATA_BLOCK_TYPE_STREAMINFO = 0;
pub const DRFLAC_METADATA_BLOCK_TYPE_PADDING = 1;
pub const DRFLAC_METADATA_BLOCK_TYPE_APPLICATION = 2;
pub const DRFLAC_METADATA_BLOCK_TYPE_SEEKTABLE = 3;
pub const DRFLAC_METADATA_BLOCK_TYPE_VORBIS_COMMENT = 4;
pub const DRFLAC_METADATA_BLOCK_TYPE_CUESHEET = 5;
pub const DRFLAC_METADATA_BLOCK_TYPE_PICTURE = 6;
pub const DRFLAC_METADATA_BLOCK_TYPE_INVALID = 127;

pub const DRFLAC_PICTURE_TYPE_OTHER = 0;
pub const DRFLAC_PICTURE_TYPE_FILE_ICON = 1;
pub const DRFLAC_PICTURE_TYPE_OTHER_FILE_ICON = 2;
pub const DRFLAC_PICTURE_TYPE_COVER_FRONT = 3;
pub const DRFLAC_PICTURE_TYPE_COVER_BACK = 4;
pub const DRFLAC_PICTURE_TYPE_LEAFLET_PAGE = 5;
pub const DRFLAC_PICTURE_TYPE_MEDIA = 6;
pub const DRFLAC_PICTURE_TYPE_LEAD_ARTIST = 7;
pub const DRFLAC_PICTURE_TYPE_ARTIST = 8;
pub const DRFLAC_PICTURE_TYPE_CONDUCTOR = 9;
pub const DRFLAC_PICTURE_TYPE_BAND = 10;
pub const DRFLAC_PICTURE_TYPE_COMPOSER = 11;
pub const DRFLAC_PICTURE_TYPE_LYRICIST = 12;
pub const DRFLAC_PICTURE_TYPE_RECORDING_LOCATION = 13;
pub const DRFLAC_PICTURE_TYPE_DURING_RECORDING = 14;
pub const DRFLAC_PICTURE_TYPE_DURING_PERFORMANCE = 15;
pub const DRFLAC_PICTURE_TYPE_SCREEN_CAPTURE = 16;
pub const DRFLAC_PICTURE_TYPE_BRIGHT_COLORED_FISH = 17;
pub const DRFLAC_PICTURE_TYPE_ILLUSTRATION = 18;
pub const DRFLAC_PICTURE_TYPE_BAND_LOGOTYPE = 19;
pub const DRFLAC_PICTURE_TYPE_PUBLISHER_LOGOTYPE = 20;

pub const drflac_container = c_uint;
pub const drflac_container_native: drflac_container = 0;
pub const drflac_container_ogg: drflac_container = 1;
pub const drflac_container_unknown: drflac_container = 2;

pub const drflac_seek_origin = c_uint;
pub const DRFLAC_SEEK_SET: drflac_seek_origin = 0;
pub const DRFLAC_SEEK_CUR: drflac_seek_origin = 1;
pub const DRFLAC_SEEK_END: drflac_seek_origin = 2;

pub const drflac_seekpoint = extern struct {
    firstPCMFrame: u64,
    flacFrameOffset: u64,
    pcmFrameCount: u16,
};

pub const drflac_streaminfo = extern struct {
    minBlockSizeInPCMFrames: u16,
    maxBlockSizeInPCMFrames: u16,
    minFrameSizeInPCMFrames: u32,
    maxFrameSizeInPCMFrames: u32,
    sampleRate: u32,
    channels: u8,
    bitsPerSample: u8,
    totalPCMFrameCount: u64,
    md5: [16]u8,
};

pub const drflac_metadata = extern struct {
    type: u32,
    rawDataSize: u32,
    rawDataOffset: u64,
    pRawData: ?*const anyopaque,
    data: extern union {
        streaminfo: drflac_streaminfo,
        padding: extern struct {
            unused: c_int,
        },
        application: extern struct {
            id: u32,
            pData: ?*const anyopaque,
            dataSize: u32,
        },
        seektable: extern struct {
            seekpointCount: u32,
            pSeekpoints: ?[*]const drflac_seekpoint,
        },
        vorbis_comment: extern struct {
            vendorLength: u32,
            vendor: ?[*]const u8,
            commentCount: u32,
            pComments: ?*const anyopaque,
        },
        cuesheet: extern struct {
            catalog: [128]u8,
            leadInSampleCount: u64,
            isCD: drflac_bool32,
            trackCount: u8,
            pTrackData: ?*const anyopaque,
        },
        picture: extern struct {
            type: u32,
            mimeLength: u32,
            mime: ?[*]const u8,
            descriptionLength: u32,
            description: ?[*]const u8,
            width: u32,
            height: u32,
            colorDepth: u32,
            indexColorCount: u32,
            pictureDataSize: u32,
            pictureDataOffset: u64,
            pPictureData: ?[*]const u8,
        },
    },
};

pub const drflac_read_proc = *const fn (pUserData: ?*anyopaque, pBufferOut: ?*anyopaque, bytesToRead: usize) callconv(.c) usize;
pub const drflac_seek_proc = *const fn (pUserData: ?*anyopaque, offset: c_int, origin: drflac_seek_origin) callconv(.c) drflac_bool32;
pub const drflac_tell_proc = *const fn (pUserData: ?*anyopaque, pCursor: *i64) callconv(.c) drflac_bool32;
pub const drflac_meta_proc = *const fn (pUserData: ?*anyopaque, pMetadata: *drflac_metadata) callconv(.c) void;

pub const drflac__memory_stream = extern struct {
    data: ?[*]const u8,
    dataSize: usize,
    currentReadPos: usize,
};

pub const drflac_bs = extern struct {
    onRead: ?drflac_read_proc,
    onSeek: ?drflac_seek_proc,
    onTell: ?drflac_tell_proc,
    pUserData: ?*anyopaque,
    unalignedByteCount: usize,
    unalignedCache: drflac_cache_t,
    nextL2Line: u32,
    consumedBits: u32,
    cacheL2: [DR_FLAC_BUFFER_SIZE / @sizeOf(drflac_cache_t)]drflac_cache_t,
    cache: drflac_cache_t,
    crc16: u16,
    crc16Cache: drflac_cache_t,
    crc16CacheIgnoredBytes: u32,
};

pub const drflac_subframe = extern struct {
    subframeType: u8,
    wastedBitsPerSample: u8,
    lpcOrder: u8,
    pSamplesS32: ?[*]i32,
};

pub const drflac_frame_header = extern struct {
    pcmFrameNumber: u64,
    flacFrameNumber: u32,
    sampleRate: u32,
    blockSizeInPCMFrames: u16,
    channelAssignment: u8,
    bitsPerSample: u8,
    crc8: u8,
};

pub const drflac_frame = extern struct {
    header: drflac_frame_header,
    pcmFramesRemaining: u32,
    subframes: [8]drflac_subframe,
};

pub const drflac = extern struct {
    onMeta: ?drflac_meta_proc,
    pUserDataMD: ?*anyopaque,
    allocationCallbacks: drflac_allocation_callbacks,
    sampleRate: u32,
    channels: u8,
    bitsPerSample: u8,
    maxBlockSizeInPCMFrames: u16,
    totalPCMFrameCount: u64,
    container: drflac_container,
    seekpointCount: u32,
    currentFLACFrame: drflac_frame,
    currentPCMFrame: u64,
    firstFLACFramePosInBytes: u64,
    memoryStream: drflac__memory_stream,
    pDecodedSamples: ?[*]i32,
    pSeekpoints: ?[*]drflac_seekpoint,
    _oggbs: ?*anyopaque,
    /// C bitfields `drflac_bool32 _noSeekTableSeek:1, _noBinarySearchSeek:1, _noBruteForceSeek:1` (bits 0..2).
    _noSeekFlags: drflac_bool32,
    bs: drflac_bs,
    /// Variable-length tail; the real allocation is larger.
    pExtraData: [1]u8,
};

pub extern fn drflac_open(onRead: drflac_read_proc, onSeek: ?drflac_seek_proc, onTell: ?drflac_tell_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?*drflac;
pub extern fn drflac_open_relaxed(onRead: drflac_read_proc, onSeek: ?drflac_seek_proc, onTell: ?drflac_tell_proc, container: drflac_container, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?*drflac;
pub extern fn drflac_open_with_metadata(onRead: drflac_read_proc, onSeek: ?drflac_seek_proc, onTell: ?drflac_tell_proc, onMeta: ?drflac_meta_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?*drflac;
pub extern fn drflac_open_with_metadata_relaxed(onRead: drflac_read_proc, onSeek: ?drflac_seek_proc, onTell: ?drflac_tell_proc, onMeta: ?drflac_meta_proc, container: drflac_container, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?*drflac;
pub extern fn drflac_close(pFlac: ?*drflac) void;
pub extern fn drflac_read_pcm_frames_s32(pFlac: *drflac, framesToRead: u64, pBufferOut: ?[*]i32) u64;
pub extern fn drflac_read_pcm_frames_s16(pFlac: *drflac, framesToRead: u64, pBufferOut: ?[*]i16) u64;
pub extern fn drflac_read_pcm_frames_f32(pFlac: *drflac, framesToRead: u64, pBufferOut: ?[*]f32) u64;
pub extern fn drflac_seek_to_pcm_frame(pFlac: *drflac, pcmFrameIndex: u64) drflac_bool32;
pub extern fn drflac_open_memory(pData: *const anyopaque, dataSize: usize, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?*drflac;
pub extern fn drflac_open_memory_with_metadata(pData: *const anyopaque, dataSize: usize, onMeta: ?drflac_meta_proc, pUserData: ?*anyopaque, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?*drflac;
pub extern fn drflac_open_and_read_pcm_frames_s32(onRead: drflac_read_proc, onSeek: ?drflac_seek_proc, onTell: ?drflac_tell_proc, pUserData: ?*anyopaque, channels: ?*c_uint, sampleRate: ?*c_uint, totalPCMFrameCount: ?*u64, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?[*]i32;
pub extern fn drflac_open_and_read_pcm_frames_s16(onRead: drflac_read_proc, onSeek: ?drflac_seek_proc, onTell: ?drflac_tell_proc, pUserData: ?*anyopaque, channels: ?*c_uint, sampleRate: ?*c_uint, totalPCMFrameCount: ?*u64, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?[*]i16;
pub extern fn drflac_open_and_read_pcm_frames_f32(onRead: drflac_read_proc, onSeek: ?drflac_seek_proc, onTell: ?drflac_tell_proc, pUserData: ?*anyopaque, channels: ?*c_uint, sampleRate: ?*c_uint, totalPCMFrameCount: ?*u64, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?[*]f32;
pub extern fn drflac_open_memory_and_read_pcm_frames_s32(data: *const anyopaque, dataSize: usize, channels: ?*c_uint, sampleRate: ?*c_uint, totalPCMFrameCount: ?*u64, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?[*]i32;
pub extern fn drflac_open_memory_and_read_pcm_frames_s16(data: *const anyopaque, dataSize: usize, channels: ?*c_uint, sampleRate: ?*c_uint, totalPCMFrameCount: ?*u64, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?[*]i16;
pub extern fn drflac_open_memory_and_read_pcm_frames_f32(data: *const anyopaque, dataSize: usize, channels: ?*c_uint, sampleRate: ?*c_uint, totalPCMFrameCount: ?*u64, pAllocationCallbacks: ?*const drflac_allocation_callbacks) ?[*]f32;
pub extern fn drflac_free(p: ?*anyopaque, pAllocationCallbacks: ?*const drflac_allocation_callbacks) void;

pub const drflac_vorbis_comment_iterator = extern struct {
    countRemaining: u32,
    pRunningData: ?[*]const u8,
};

pub extern fn drflac_init_vorbis_comment_iterator(pIter: *drflac_vorbis_comment_iterator, commentCount: u32, pComments: ?*const anyopaque) void;
pub extern fn drflac_next_vorbis_comment(pIter: *drflac_vorbis_comment_iterator, pCommentLengthOut: ?*u32) ?[*]const u8;

pub const drflac_cuesheet_track_iterator = extern struct {
    countRemaining: u32,
    pRunningData: ?[*]const u8,
};

pub const drflac_cuesheet_track_index = extern struct {
    offset: u64,
    index: u8,
    reserved: [3]u8,
};

pub const drflac_cuesheet_track = extern struct {
    offset: u64,
    trackNumber: u8,
    ISRC: [12]u8,
    isAudio: drflac_bool8,
    preEmphasis: drflac_bool8,
    indexCount: u8,
    pIndexPoints: ?[*]const drflac_cuesheet_track_index,
};

pub extern fn drflac_init_cuesheet_track_iterator(pIter: *drflac_cuesheet_track_iterator, trackCount: u32, pTrackData: ?*const anyopaque) void;
pub extern fn drflac_next_cuesheet_track(pIter: *drflac_cuesheet_track_iterator, pCuesheetTrack: *drflac_cuesheet_track) drflac_bool32;
