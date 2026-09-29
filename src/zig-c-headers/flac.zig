//! Hand-written bindings for libFLAC (include/FLAC/{ordinals,callback,format,metadata,stream_decoder,stream_encoder}.h).
//! Ogg FLAC is compiled in. Omitted: the FLAC__*_LEN / *_MASK bit-width constants from format.h
//! (bitstream internals). The library is built with _FILE_OFFSET_BITS=64, so off_t is i64.

const builtin = @import("builtin");

pub const FILE = opaque {};

// ordinals.h

pub const FLAC__bool = c_int;
pub const FLAC__byte = u8;

// callback.h

pub const FLAC__IOHandle = ?*anyopaque;
pub const FLAC__IOCallback_Read = *const fn (ptr: ?*anyopaque, size: usize, nmemb: usize, handle: FLAC__IOHandle) callconv(.c) usize;
pub const FLAC__IOCallback_Write = *const fn (ptr: ?*const anyopaque, size: usize, nmemb: usize, handle: FLAC__IOHandle) callconv(.c) usize;
pub const FLAC__IOCallback_Seek = *const fn (handle: FLAC__IOHandle, offset: i64, whence: c_int) callconv(.c) c_int;
pub const FLAC__IOCallback_Tell = *const fn (handle: FLAC__IOHandle) callconv(.c) i64;
pub const FLAC__IOCallback_Eof = *const fn (handle: FLAC__IOHandle) callconv(.c) c_int;
pub const FLAC__IOCallback_Close = *const fn (handle: FLAC__IOHandle) callconv(.c) c_int;

pub const FLAC__IOCallbacks = extern struct {
    read: ?FLAC__IOCallback_Read,
    write: ?FLAC__IOCallback_Write,
    seek: ?FLAC__IOCallback_Seek,
    tell: ?FLAC__IOCallback_Tell,
    eof: ?FLAC__IOCallback_Eof,
    close: ?FLAC__IOCallback_Close,
};

// format.h

pub const FLAC__MAX_METADATA_TYPE_CODE = 126;
pub const FLAC__MIN_BLOCK_SIZE = 16;
pub const FLAC__MAX_BLOCK_SIZE = 65535;
pub const FLAC__SUBSET_MAX_BLOCK_SIZE_48000HZ = 4608;
pub const FLAC__MAX_CHANNELS = 8;
pub const FLAC__MIN_BITS_PER_SAMPLE = 4;
pub const FLAC__MAX_BITS_PER_SAMPLE = 32;
pub const FLAC__REFERENCE_CODEC_MAX_BITS_PER_SAMPLE = 32;
pub const FLAC__MAX_SAMPLE_RATE = 1048575;
pub const FLAC__MAX_LPC_ORDER = 32;
pub const FLAC__SUBSET_MAX_LPC_ORDER_48000HZ = 12;
pub const FLAC__MIN_QLP_COEFF_PRECISION = 5;
pub const FLAC__MAX_QLP_COEFF_PRECISION = 15;
pub const FLAC__MAX_FIXED_ORDER = 4;
pub const FLAC__MAX_RICE_PARTITION_ORDER = 15;
pub const FLAC__SUBSET_MAX_RICE_PARTITION_ORDER = 8;
pub const FLAC__STREAM_SYNC_LENGTH = 4;
pub const FLAC__STREAM_METADATA_STREAMINFO_LENGTH = 34;
pub const FLAC__STREAM_METADATA_SEEKPOINT_LENGTH = 18;
pub const FLAC__STREAM_METADATA_HEADER_LENGTH = 4;

pub extern const FLAC__VERSION_STRING: [*:0]const u8;
pub extern const FLAC__VENDOR_STRING: [*:0]const u8;
pub extern const FLAC__STREAM_SYNC_STRING: [4]FLAC__byte;
pub extern const FLAC__STREAM_SYNC: u32;
pub extern const FLAC__STREAM_METADATA_SEEKPOINT_PLACEHOLDER: u64;

pub const FLAC__EntropyCodingMethodType = c_uint;
pub const FLAC__ENTROPY_CODING_METHOD_PARTITIONED_RICE: FLAC__EntropyCodingMethodType = 0;
pub const FLAC__ENTROPY_CODING_METHOD_PARTITIONED_RICE2: FLAC__EntropyCodingMethodType = 1;
pub extern const FLAC__EntropyCodingMethodTypeString: [2][*:0]const u8;

pub const FLAC__EntropyCodingMethod_PartitionedRiceContents = extern struct {
    parameters: ?[*]u32,
    raw_bits: ?[*]u32,
    capacity_by_order: u32,
};

pub const FLAC__EntropyCodingMethod_PartitionedRice = extern struct {
    order: u32,
    contents: ?*const FLAC__EntropyCodingMethod_PartitionedRiceContents,
};

pub const FLAC__EntropyCodingMethod = extern struct {
    type: FLAC__EntropyCodingMethodType,
    data: extern union {
        partitioned_rice: FLAC__EntropyCodingMethod_PartitionedRice,
    },
};

pub const FLAC__SubframeType = c_uint;
pub const FLAC__SUBFRAME_TYPE_CONSTANT: FLAC__SubframeType = 0;
pub const FLAC__SUBFRAME_TYPE_VERBATIM: FLAC__SubframeType = 1;
pub const FLAC__SUBFRAME_TYPE_FIXED: FLAC__SubframeType = 2;
pub const FLAC__SUBFRAME_TYPE_LPC: FLAC__SubframeType = 3;
pub extern const FLAC__SubframeTypeString: [4][*:0]const u8;

pub const FLAC__Subframe_Constant = extern struct {
    value: i64,
};

pub const FLAC__VerbatimSubframeDataType = c_uint;
pub const FLAC__VERBATIM_SUBFRAME_DATA_TYPE_INT32: FLAC__VerbatimSubframeDataType = 0;
pub const FLAC__VERBATIM_SUBFRAME_DATA_TYPE_INT64: FLAC__VerbatimSubframeDataType = 1;

pub const FLAC__Subframe_Verbatim = extern struct {
    data: extern union {
        int32: [*]const i32,
        int64: [*]const i64,
    },
    data_type: FLAC__VerbatimSubframeDataType,
};

pub const FLAC__Subframe_Fixed = extern struct {
    entropy_coding_method: FLAC__EntropyCodingMethod,
    order: u32,
    warmup: [FLAC__MAX_FIXED_ORDER]i64,
    residual: ?[*]const i32,
};

pub const FLAC__Subframe_LPC = extern struct {
    entropy_coding_method: FLAC__EntropyCodingMethod,
    order: u32,
    qlp_coeff_precision: u32,
    quantization_level: c_int,
    qlp_coeff: [FLAC__MAX_LPC_ORDER]i32,
    warmup: [FLAC__MAX_LPC_ORDER]i64,
    residual: ?[*]const i32,
};

pub const FLAC__Subframe = extern struct {
    type: FLAC__SubframeType,
    data: extern union {
        constant: FLAC__Subframe_Constant,
        fixed: FLAC__Subframe_Fixed,
        lpc: FLAC__Subframe_LPC,
        verbatim: FLAC__Subframe_Verbatim,
    },
    wasted_bits: u32,
};

pub const FLAC__ChannelAssignment = c_uint;
pub const FLAC__CHANNEL_ASSIGNMENT_INDEPENDENT: FLAC__ChannelAssignment = 0;
pub const FLAC__CHANNEL_ASSIGNMENT_LEFT_SIDE: FLAC__ChannelAssignment = 1;
pub const FLAC__CHANNEL_ASSIGNMENT_RIGHT_SIDE: FLAC__ChannelAssignment = 2;
pub const FLAC__CHANNEL_ASSIGNMENT_MID_SIDE: FLAC__ChannelAssignment = 3;
pub extern const FLAC__ChannelAssignmentString: [4][*:0]const u8;

pub const FLAC__FrameNumberType = c_uint;
pub const FLAC__FRAME_NUMBER_TYPE_FRAME_NUMBER: FLAC__FrameNumberType = 0;
pub const FLAC__FRAME_NUMBER_TYPE_SAMPLE_NUMBER: FLAC__FrameNumberType = 1;
pub extern const FLAC__FrameNumberTypeString: [2][*:0]const u8;

pub const FLAC__FrameHeader = extern struct {
    blocksize: u32,
    sample_rate: u32,
    channels: u32,
    channel_assignment: FLAC__ChannelAssignment,
    bits_per_sample: u32,
    number_type: FLAC__FrameNumberType,
    number: extern union {
        frame_number: u32,
        sample_number: u64,
    },
    crc: u8,
};

pub const FLAC__FrameFooter = extern struct {
    crc: u16,
};

pub const FLAC__Frame = extern struct {
    header: FLAC__FrameHeader,
    subframes: [FLAC__MAX_CHANNELS]FLAC__Subframe,
    footer: FLAC__FrameFooter,
};

pub const FLAC__MetadataType = c_uint;
pub const FLAC__METADATA_TYPE_STREAMINFO: FLAC__MetadataType = 0;
pub const FLAC__METADATA_TYPE_PADDING: FLAC__MetadataType = 1;
pub const FLAC__METADATA_TYPE_APPLICATION: FLAC__MetadataType = 2;
pub const FLAC__METADATA_TYPE_SEEKTABLE: FLAC__MetadataType = 3;
pub const FLAC__METADATA_TYPE_VORBIS_COMMENT: FLAC__MetadataType = 4;
pub const FLAC__METADATA_TYPE_CUESHEET: FLAC__MetadataType = 5;
pub const FLAC__METADATA_TYPE_PICTURE: FLAC__MetadataType = 6;
pub const FLAC__METADATA_TYPE_UNDEFINED: FLAC__MetadataType = 7;
pub const FLAC__MAX_METADATA_TYPE: FLAC__MetadataType = FLAC__MAX_METADATA_TYPE_CODE;
pub extern const FLAC__MetadataTypeString: [7][*:0]const u8;

pub const FLAC__StreamMetadata_StreamInfo = extern struct {
    min_blocksize: u32,
    max_blocksize: u32,
    min_framesize: u32,
    max_framesize: u32,
    sample_rate: u32,
    channels: u32,
    bits_per_sample: u32,
    total_samples: u64,
    md5sum: [16]FLAC__byte,
};

pub const FLAC__StreamMetadata_Padding = extern struct {
    dummy: c_int,
};

pub const FLAC__StreamMetadata_Application = extern struct {
    id: [4]FLAC__byte,
    data: ?[*]FLAC__byte,
};

pub const FLAC__StreamMetadata_SeekPoint = extern struct {
    sample_number: u64,
    stream_offset: u64,
    frame_samples: u32,
};

pub const FLAC__StreamMetadata_SeekTable = extern struct {
    num_points: u32,
    points: ?[*]FLAC__StreamMetadata_SeekPoint,
};

pub const FLAC__StreamMetadata_VorbisComment_Entry = extern struct {
    length: u32,
    entry: ?[*]FLAC__byte,
};

pub const FLAC__StreamMetadata_VorbisComment = extern struct {
    vendor_string: FLAC__StreamMetadata_VorbisComment_Entry,
    num_comments: u32,
    comments: ?[*]FLAC__StreamMetadata_VorbisComment_Entry,
};

pub const FLAC__StreamMetadata_CueSheet_Index = extern struct {
    offset: u64,
    number: FLAC__byte,
};

pub const FLAC__StreamMetadata_CueSheet_Track = extern struct {
    offset: u64,
    number: FLAC__byte,
    isrc: [13]u8,
    /// C bitfields `uint32_t type:1; uint32_t pre_emphasis:1;` -> bit 0 = type, bit 1 = pre_emphasis.
    /// Itanium layout packs them into the byte after isrc; MS layout (windows) opens a new uint32_t.
    type_pre_emphasis: if (builtin.os.tag == .windows) u32 else u8,
    num_indices: FLAC__byte,
    indices: ?[*]FLAC__StreamMetadata_CueSheet_Index,
};

pub const FLAC__StreamMetadata_CueSheet = extern struct {
    media_catalog_number: [129]u8,
    lead_in: u64,
    is_cd: FLAC__bool,
    num_tracks: u32,
    tracks: ?[*]FLAC__StreamMetadata_CueSheet_Track,
};

pub const FLAC__StreamMetadata_Picture_Type = c_uint;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_OTHER: FLAC__StreamMetadata_Picture_Type = 0;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_FILE_ICON_STANDARD: FLAC__StreamMetadata_Picture_Type = 1;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_FILE_ICON: FLAC__StreamMetadata_Picture_Type = 2;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER: FLAC__StreamMetadata_Picture_Type = 3;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_BACK_COVER: FLAC__StreamMetadata_Picture_Type = 4;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_LEAFLET_PAGE: FLAC__StreamMetadata_Picture_Type = 5;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_MEDIA: FLAC__StreamMetadata_Picture_Type = 6;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_LEAD_ARTIST: FLAC__StreamMetadata_Picture_Type = 7;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_ARTIST: FLAC__StreamMetadata_Picture_Type = 8;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_CONDUCTOR: FLAC__StreamMetadata_Picture_Type = 9;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_BAND: FLAC__StreamMetadata_Picture_Type = 10;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_COMPOSER: FLAC__StreamMetadata_Picture_Type = 11;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_LYRICIST: FLAC__StreamMetadata_Picture_Type = 12;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_RECORDING_LOCATION: FLAC__StreamMetadata_Picture_Type = 13;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_DURING_RECORDING: FLAC__StreamMetadata_Picture_Type = 14;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_DURING_PERFORMANCE: FLAC__StreamMetadata_Picture_Type = 15;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_VIDEO_SCREEN_CAPTURE: FLAC__StreamMetadata_Picture_Type = 16;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_FISH: FLAC__StreamMetadata_Picture_Type = 17;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_ILLUSTRATION: FLAC__StreamMetadata_Picture_Type = 18;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_BAND_LOGOTYPE: FLAC__StreamMetadata_Picture_Type = 19;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_PUBLISHER_LOGOTYPE: FLAC__StreamMetadata_Picture_Type = 20;
pub const FLAC__STREAM_METADATA_PICTURE_TYPE_UNDEFINED: FLAC__StreamMetadata_Picture_Type = 21;
pub extern const FLAC__StreamMetadata_Picture_TypeString: [21][*:0]const u8;

pub const FLAC__StreamMetadata_Picture = extern struct {
    type: FLAC__StreamMetadata_Picture_Type,
    mime_type: ?[*:0]u8,
    description: ?[*:0]FLAC__byte,
    width: u32,
    height: u32,
    depth: u32,
    colors: u32,
    data_length: u32,
    data: ?[*]FLAC__byte,
};

pub const FLAC__StreamMetadata_Unknown = extern struct {
    data: ?[*]FLAC__byte,
};

pub const FLAC__StreamMetadata = extern struct {
    type: FLAC__MetadataType,
    is_last: FLAC__bool,
    length: u32,
    data: extern union {
        stream_info: FLAC__StreamMetadata_StreamInfo,
        padding: FLAC__StreamMetadata_Padding,
        application: FLAC__StreamMetadata_Application,
        seek_table: FLAC__StreamMetadata_SeekTable,
        vorbis_comment: FLAC__StreamMetadata_VorbisComment,
        cue_sheet: FLAC__StreamMetadata_CueSheet,
        picture: FLAC__StreamMetadata_Picture,
        unknown: FLAC__StreamMetadata_Unknown,
    },
};

pub extern fn FLAC__format_sample_rate_is_valid(sample_rate: u32) FLAC__bool;
pub extern fn FLAC__format_blocksize_is_subset(blocksize: u32, sample_rate: u32) FLAC__bool;
pub extern fn FLAC__format_sample_rate_is_subset(sample_rate: u32) FLAC__bool;
pub extern fn FLAC__format_vorbiscomment_entry_name_is_legal(name: [*:0]const u8) FLAC__bool;
pub extern fn FLAC__format_vorbiscomment_entry_value_is_legal(value: [*]const FLAC__byte, length: u32) FLAC__bool;
pub extern fn FLAC__format_vorbiscomment_entry_is_legal(entry: [*]const FLAC__byte, length: u32) FLAC__bool;
pub extern fn FLAC__format_seektable_is_legal(seek_table: *const FLAC__StreamMetadata_SeekTable) FLAC__bool;
pub extern fn FLAC__format_seektable_sort(seek_table: *FLAC__StreamMetadata_SeekTable) u32;
pub extern fn FLAC__format_cuesheet_is_legal(cue_sheet: *const FLAC__StreamMetadata_CueSheet, check_cd_da_subset: FLAC__bool, violation: ?*[*:0]const u8) FLAC__bool;
pub extern fn FLAC__format_picture_is_legal(picture: *const FLAC__StreamMetadata_Picture, violation: ?*[*:0]const u8) FLAC__bool;

// stream_decoder.h

pub const FLAC__StreamDecoderState = c_uint;
pub const FLAC__STREAM_DECODER_SEARCH_FOR_METADATA: FLAC__StreamDecoderState = 0;
pub const FLAC__STREAM_DECODER_READ_METADATA: FLAC__StreamDecoderState = 1;
pub const FLAC__STREAM_DECODER_SEARCH_FOR_FRAME_SYNC: FLAC__StreamDecoderState = 2;
pub const FLAC__STREAM_DECODER_READ_FRAME: FLAC__StreamDecoderState = 3;
pub const FLAC__STREAM_DECODER_END_OF_STREAM: FLAC__StreamDecoderState = 4;
pub const FLAC__STREAM_DECODER_OGG_ERROR: FLAC__StreamDecoderState = 5;
pub const FLAC__STREAM_DECODER_SEEK_ERROR: FLAC__StreamDecoderState = 6;
pub const FLAC__STREAM_DECODER_ABORTED: FLAC__StreamDecoderState = 7;
pub const FLAC__STREAM_DECODER_MEMORY_ALLOCATION_ERROR: FLAC__StreamDecoderState = 8;
pub const FLAC__STREAM_DECODER_UNINITIALIZED: FLAC__StreamDecoderState = 9;
pub const FLAC__STREAM_DECODER_END_OF_LINK: FLAC__StreamDecoderState = 10;
pub extern const FLAC__StreamDecoderStateString: [11][*:0]const u8;

pub const FLAC__StreamDecoderInitStatus = c_uint;
pub const FLAC__STREAM_DECODER_INIT_STATUS_OK: FLAC__StreamDecoderInitStatus = 0;
pub const FLAC__STREAM_DECODER_INIT_STATUS_UNSUPPORTED_CONTAINER: FLAC__StreamDecoderInitStatus = 1;
pub const FLAC__STREAM_DECODER_INIT_STATUS_INVALID_CALLBACKS: FLAC__StreamDecoderInitStatus = 2;
pub const FLAC__STREAM_DECODER_INIT_STATUS_MEMORY_ALLOCATION_ERROR: FLAC__StreamDecoderInitStatus = 3;
pub const FLAC__STREAM_DECODER_INIT_STATUS_ERROR_OPENING_FILE: FLAC__StreamDecoderInitStatus = 4;
pub const FLAC__STREAM_DECODER_INIT_STATUS_ALREADY_INITIALIZED: FLAC__StreamDecoderInitStatus = 5;
pub extern const FLAC__StreamDecoderInitStatusString: [6][*:0]const u8;

pub const FLAC__StreamDecoderReadStatus = c_uint;
pub const FLAC__STREAM_DECODER_READ_STATUS_CONTINUE: FLAC__StreamDecoderReadStatus = 0;
pub const FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM: FLAC__StreamDecoderReadStatus = 1;
pub const FLAC__STREAM_DECODER_READ_STATUS_ABORT: FLAC__StreamDecoderReadStatus = 2;
pub const FLAC__STREAM_DECODER_READ_STATUS_END_OF_LINK: FLAC__StreamDecoderReadStatus = 3;
pub extern const FLAC__StreamDecoderReadStatusString: [4][*:0]const u8;

pub const FLAC__StreamDecoderSeekStatus = c_uint;
pub const FLAC__STREAM_DECODER_SEEK_STATUS_OK: FLAC__StreamDecoderSeekStatus = 0;
pub const FLAC__STREAM_DECODER_SEEK_STATUS_ERROR: FLAC__StreamDecoderSeekStatus = 1;
pub const FLAC__STREAM_DECODER_SEEK_STATUS_UNSUPPORTED: FLAC__StreamDecoderSeekStatus = 2;
pub extern const FLAC__StreamDecoderSeekStatusString: [3][*:0]const u8;

pub const FLAC__StreamDecoderTellStatus = c_uint;
pub const FLAC__STREAM_DECODER_TELL_STATUS_OK: FLAC__StreamDecoderTellStatus = 0;
pub const FLAC__STREAM_DECODER_TELL_STATUS_ERROR: FLAC__StreamDecoderTellStatus = 1;
pub const FLAC__STREAM_DECODER_TELL_STATUS_UNSUPPORTED: FLAC__StreamDecoderTellStatus = 2;
pub extern const FLAC__StreamDecoderTellStatusString: [3][*:0]const u8;

pub const FLAC__StreamDecoderLengthStatus = c_uint;
pub const FLAC__STREAM_DECODER_LENGTH_STATUS_OK: FLAC__StreamDecoderLengthStatus = 0;
pub const FLAC__STREAM_DECODER_LENGTH_STATUS_ERROR: FLAC__StreamDecoderLengthStatus = 1;
pub const FLAC__STREAM_DECODER_LENGTH_STATUS_UNSUPPORTED: FLAC__StreamDecoderLengthStatus = 2;
pub extern const FLAC__StreamDecoderLengthStatusString: [3][*:0]const u8;

pub const FLAC__StreamDecoderWriteStatus = c_uint;
pub const FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE: FLAC__StreamDecoderWriteStatus = 0;
pub const FLAC__STREAM_DECODER_WRITE_STATUS_ABORT: FLAC__StreamDecoderWriteStatus = 1;
pub extern const FLAC__StreamDecoderWriteStatusString: [2][*:0]const u8;

pub const FLAC__StreamDecoderErrorStatus = c_uint;
pub const FLAC__STREAM_DECODER_ERROR_STATUS_LOST_SYNC: FLAC__StreamDecoderErrorStatus = 0;
pub const FLAC__STREAM_DECODER_ERROR_STATUS_BAD_HEADER: FLAC__StreamDecoderErrorStatus = 1;
pub const FLAC__STREAM_DECODER_ERROR_STATUS_FRAME_CRC_MISMATCH: FLAC__StreamDecoderErrorStatus = 2;
pub const FLAC__STREAM_DECODER_ERROR_STATUS_UNPARSEABLE_STREAM: FLAC__StreamDecoderErrorStatus = 3;
pub const FLAC__STREAM_DECODER_ERROR_STATUS_BAD_METADATA: FLAC__StreamDecoderErrorStatus = 4;
pub const FLAC__STREAM_DECODER_ERROR_STATUS_OUT_OF_BOUNDS: FLAC__StreamDecoderErrorStatus = 5;
pub const FLAC__STREAM_DECODER_ERROR_STATUS_MISSING_FRAME: FLAC__StreamDecoderErrorStatus = 6;
pub extern const FLAC__StreamDecoderErrorStatusString: [7][*:0]const u8;

pub const FLAC__StreamDecoderProtected = opaque {};
pub const FLAC__StreamDecoderPrivate = opaque {};

pub const FLAC__StreamDecoder = extern struct {
    protected_: ?*FLAC__StreamDecoderProtected,
    private_: ?*FLAC__StreamDecoderPrivate,
};

pub const FLAC__StreamDecoderReadCallback = *const fn (decoder: *const FLAC__StreamDecoder, buffer: [*]FLAC__byte, bytes: *usize, client_data: ?*anyopaque) callconv(.c) FLAC__StreamDecoderReadStatus;
pub const FLAC__StreamDecoderSeekCallback = *const fn (decoder: *const FLAC__StreamDecoder, absolute_byte_offset: u64, client_data: ?*anyopaque) callconv(.c) FLAC__StreamDecoderSeekStatus;
pub const FLAC__StreamDecoderTellCallback = *const fn (decoder: *const FLAC__StreamDecoder, absolute_byte_offset: *u64, client_data: ?*anyopaque) callconv(.c) FLAC__StreamDecoderTellStatus;
pub const FLAC__StreamDecoderLengthCallback = *const fn (decoder: *const FLAC__StreamDecoder, stream_length: *u64, client_data: ?*anyopaque) callconv(.c) FLAC__StreamDecoderLengthStatus;
pub const FLAC__StreamDecoderEofCallback = *const fn (decoder: *const FLAC__StreamDecoder, client_data: ?*anyopaque) callconv(.c) FLAC__bool;
pub const FLAC__StreamDecoderWriteCallback = *const fn (decoder: *const FLAC__StreamDecoder, frame: *const FLAC__Frame, buffer: [*]const [*]const i32, client_data: ?*anyopaque) callconv(.c) FLAC__StreamDecoderWriteStatus;
pub const FLAC__StreamDecoderMetadataCallback = *const fn (decoder: *const FLAC__StreamDecoder, metadata: *const FLAC__StreamMetadata, client_data: ?*anyopaque) callconv(.c) void;
pub const FLAC__StreamDecoderErrorCallback = *const fn (decoder: *const FLAC__StreamDecoder, status: FLAC__StreamDecoderErrorStatus, client_data: ?*anyopaque) callconv(.c) void;

pub extern fn FLAC__stream_decoder_new() ?*FLAC__StreamDecoder;
pub extern fn FLAC__stream_decoder_delete(decoder: ?*FLAC__StreamDecoder) void;
pub extern fn FLAC__stream_decoder_set_ogg_serial_number(decoder: *FLAC__StreamDecoder, serial_number: c_long) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_decode_chained_stream(decoder: *FLAC__StreamDecoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_md5_checking(decoder: *FLAC__StreamDecoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_metadata_respond(decoder: *FLAC__StreamDecoder, @"type": FLAC__MetadataType) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_metadata_respond_application(decoder: *FLAC__StreamDecoder, id: *const [4]FLAC__byte) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_metadata_respond_all(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_metadata_ignore(decoder: *FLAC__StreamDecoder, @"type": FLAC__MetadataType) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_metadata_ignore_application(decoder: *FLAC__StreamDecoder, id: *const [4]FLAC__byte) FLAC__bool;
pub extern fn FLAC__stream_decoder_set_metadata_ignore_all(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_get_state(decoder: *const FLAC__StreamDecoder) FLAC__StreamDecoderState;
pub extern fn FLAC__stream_decoder_get_resolved_state_string(decoder: *const FLAC__StreamDecoder) [*:0]const u8;
pub extern fn FLAC__stream_decoder_get_decode_chained_stream(decoder: *const FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_get_md5_checking(decoder: *const FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_get_total_samples(decoder: *const FLAC__StreamDecoder) u64;
pub extern fn FLAC__stream_decoder_find_total_samples(decoder: *FLAC__StreamDecoder) u64;
pub extern fn FLAC__stream_decoder_get_channels(decoder: *const FLAC__StreamDecoder) u32;
pub extern fn FLAC__stream_decoder_get_channel_assignment(decoder: *const FLAC__StreamDecoder) FLAC__ChannelAssignment;
pub extern fn FLAC__stream_decoder_get_bits_per_sample(decoder: *const FLAC__StreamDecoder) u32;
pub extern fn FLAC__stream_decoder_get_sample_rate(decoder: *const FLAC__StreamDecoder) u32;
pub extern fn FLAC__stream_decoder_get_blocksize(decoder: *const FLAC__StreamDecoder) u32;
pub extern fn FLAC__stream_decoder_get_decode_position(decoder: *const FLAC__StreamDecoder, position: *u64) FLAC__bool;
pub extern fn FLAC__stream_decoder_get_client_data(decoder: *FLAC__StreamDecoder) ?*const anyopaque;
pub extern fn FLAC__stream_decoder_get_link_lengths(decoder: *FLAC__StreamDecoder, link_lengths: ?*?[*]u64) i32;
pub extern fn FLAC__stream_decoder_init_stream(
    decoder: *FLAC__StreamDecoder,
    read_callback: ?FLAC__StreamDecoderReadCallback,
    seek_callback: ?FLAC__StreamDecoderSeekCallback,
    tell_callback: ?FLAC__StreamDecoderTellCallback,
    length_callback: ?FLAC__StreamDecoderLengthCallback,
    eof_callback: ?FLAC__StreamDecoderEofCallback,
    write_callback: ?FLAC__StreamDecoderWriteCallback,
    metadata_callback: ?FLAC__StreamDecoderMetadataCallback,
    error_callback: ?FLAC__StreamDecoderErrorCallback,
    client_data: ?*anyopaque,
) FLAC__StreamDecoderInitStatus;
pub extern fn FLAC__stream_decoder_init_ogg_stream(
    decoder: *FLAC__StreamDecoder,
    read_callback: ?FLAC__StreamDecoderReadCallback,
    seek_callback: ?FLAC__StreamDecoderSeekCallback,
    tell_callback: ?FLAC__StreamDecoderTellCallback,
    length_callback: ?FLAC__StreamDecoderLengthCallback,
    eof_callback: ?FLAC__StreamDecoderEofCallback,
    write_callback: ?FLAC__StreamDecoderWriteCallback,
    metadata_callback: ?FLAC__StreamDecoderMetadataCallback,
    error_callback: ?FLAC__StreamDecoderErrorCallback,
    client_data: ?*anyopaque,
) FLAC__StreamDecoderInitStatus;
pub extern fn FLAC__stream_decoder_init_FILE(decoder: *FLAC__StreamDecoder, file: *FILE, write_callback: ?FLAC__StreamDecoderWriteCallback, metadata_callback: ?FLAC__StreamDecoderMetadataCallback, error_callback: ?FLAC__StreamDecoderErrorCallback, client_data: ?*anyopaque) FLAC__StreamDecoderInitStatus;
pub extern fn FLAC__stream_decoder_init_ogg_FILE(decoder: *FLAC__StreamDecoder, file: *FILE, write_callback: ?FLAC__StreamDecoderWriteCallback, metadata_callback: ?FLAC__StreamDecoderMetadataCallback, error_callback: ?FLAC__StreamDecoderErrorCallback, client_data: ?*anyopaque) FLAC__StreamDecoderInitStatus;
pub extern fn FLAC__stream_decoder_init_file(decoder: *FLAC__StreamDecoder, filename: ?[*:0]const u8, write_callback: ?FLAC__StreamDecoderWriteCallback, metadata_callback: ?FLAC__StreamDecoderMetadataCallback, error_callback: ?FLAC__StreamDecoderErrorCallback, client_data: ?*anyopaque) FLAC__StreamDecoderInitStatus;
pub extern fn FLAC__stream_decoder_init_ogg_file(decoder: *FLAC__StreamDecoder, filename: ?[*:0]const u8, write_callback: ?FLAC__StreamDecoderWriteCallback, metadata_callback: ?FLAC__StreamDecoderMetadataCallback, error_callback: ?FLAC__StreamDecoderErrorCallback, client_data: ?*anyopaque) FLAC__StreamDecoderInitStatus;
pub extern fn FLAC__stream_decoder_finish(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_finish_link(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_flush(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_reset(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_process_single(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_process_until_end_of_metadata(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_process_until_end_of_link(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_process_until_end_of_stream(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_skip_single_frame(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_skip_single_link(decoder: *FLAC__StreamDecoder) FLAC__bool;
pub extern fn FLAC__stream_decoder_seek_absolute(decoder: *FLAC__StreamDecoder, sample: u64) FLAC__bool;

// stream_encoder.h

pub const FLAC__StreamEncoderState = c_uint;
pub const FLAC__STREAM_ENCODER_OK: FLAC__StreamEncoderState = 0;
pub const FLAC__STREAM_ENCODER_UNINITIALIZED: FLAC__StreamEncoderState = 1;
pub const FLAC__STREAM_ENCODER_OGG_ERROR: FLAC__StreamEncoderState = 2;
pub const FLAC__STREAM_ENCODER_VERIFY_DECODER_ERROR: FLAC__StreamEncoderState = 3;
pub const FLAC__STREAM_ENCODER_VERIFY_MISMATCH_IN_AUDIO_DATA: FLAC__StreamEncoderState = 4;
pub const FLAC__STREAM_ENCODER_CLIENT_ERROR: FLAC__StreamEncoderState = 5;
pub const FLAC__STREAM_ENCODER_IO_ERROR: FLAC__StreamEncoderState = 6;
pub const FLAC__STREAM_ENCODER_FRAMING_ERROR: FLAC__StreamEncoderState = 7;
pub const FLAC__STREAM_ENCODER_MEMORY_ALLOCATION_ERROR: FLAC__StreamEncoderState = 8;
pub extern const FLAC__StreamEncoderStateString: [9][*:0]const u8;

pub const FLAC__StreamEncoderInitStatus = c_uint;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_OK: FLAC__StreamEncoderInitStatus = 0;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_ENCODER_ERROR: FLAC__StreamEncoderInitStatus = 1;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_UNSUPPORTED_CONTAINER: FLAC__StreamEncoderInitStatus = 2;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_CALLBACKS: FLAC__StreamEncoderInitStatus = 3;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_NUMBER_OF_CHANNELS: FLAC__StreamEncoderInitStatus = 4;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_BITS_PER_SAMPLE: FLAC__StreamEncoderInitStatus = 5;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_SAMPLE_RATE: FLAC__StreamEncoderInitStatus = 6;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_BLOCK_SIZE: FLAC__StreamEncoderInitStatus = 7;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_MAX_LPC_ORDER: FLAC__StreamEncoderInitStatus = 8;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_QLP_COEFF_PRECISION: FLAC__StreamEncoderInitStatus = 9;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_BLOCK_SIZE_TOO_SMALL_FOR_LPC_ORDER: FLAC__StreamEncoderInitStatus = 10;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_NOT_STREAMABLE: FLAC__StreamEncoderInitStatus = 11;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_INVALID_METADATA: FLAC__StreamEncoderInitStatus = 12;
pub const FLAC__STREAM_ENCODER_INIT_STATUS_ALREADY_INITIALIZED: FLAC__StreamEncoderInitStatus = 13;
pub extern const FLAC__StreamEncoderInitStatusString: [14][*:0]const u8;

pub const FLAC__StreamEncoderReadStatus = c_uint;
pub const FLAC__STREAM_ENCODER_READ_STATUS_CONTINUE: FLAC__StreamEncoderReadStatus = 0;
pub const FLAC__STREAM_ENCODER_READ_STATUS_END_OF_STREAM: FLAC__StreamEncoderReadStatus = 1;
pub const FLAC__STREAM_ENCODER_READ_STATUS_ABORT: FLAC__StreamEncoderReadStatus = 2;
pub const FLAC__STREAM_ENCODER_READ_STATUS_UNSUPPORTED: FLAC__StreamEncoderReadStatus = 3;
pub extern const FLAC__StreamEncoderReadStatusString: [4][*:0]const u8;

pub const FLAC__StreamEncoderWriteStatus = c_uint;
pub const FLAC__STREAM_ENCODER_WRITE_STATUS_OK: FLAC__StreamEncoderWriteStatus = 0;
pub const FLAC__STREAM_ENCODER_WRITE_STATUS_FATAL_ERROR: FLAC__StreamEncoderWriteStatus = 1;
pub extern const FLAC__StreamEncoderWriteStatusString: [2][*:0]const u8;

pub const FLAC__StreamEncoderSeekStatus = c_uint;
pub const FLAC__STREAM_ENCODER_SEEK_STATUS_OK: FLAC__StreamEncoderSeekStatus = 0;
pub const FLAC__STREAM_ENCODER_SEEK_STATUS_ERROR: FLAC__StreamEncoderSeekStatus = 1;
pub const FLAC__STREAM_ENCODER_SEEK_STATUS_UNSUPPORTED: FLAC__StreamEncoderSeekStatus = 2;
pub extern const FLAC__StreamEncoderSeekStatusString: [3][*:0]const u8;

pub const FLAC__StreamEncoderTellStatus = c_uint;
pub const FLAC__STREAM_ENCODER_TELL_STATUS_OK: FLAC__StreamEncoderTellStatus = 0;
pub const FLAC__STREAM_ENCODER_TELL_STATUS_ERROR: FLAC__StreamEncoderTellStatus = 1;
pub const FLAC__STREAM_ENCODER_TELL_STATUS_UNSUPPORTED: FLAC__StreamEncoderTellStatus = 2;
pub extern const FLAC__StreamEncoderTellStatusString: [3][*:0]const u8;

pub const FLAC__StreamEncoderProtected = opaque {};
pub const FLAC__StreamEncoderPrivate = opaque {};

pub const FLAC__StreamEncoder = extern struct {
    protected_: ?*FLAC__StreamEncoderProtected,
    private_: ?*FLAC__StreamEncoderPrivate,
};

pub const FLAC__StreamEncoderReadCallback = *const fn (encoder: *const FLAC__StreamEncoder, buffer: [*]FLAC__byte, bytes: *usize, client_data: ?*anyopaque) callconv(.c) FLAC__StreamEncoderReadStatus;
pub const FLAC__StreamEncoderWriteCallback = *const fn (encoder: *const FLAC__StreamEncoder, buffer: [*]const FLAC__byte, bytes: usize, samples: u32, current_frame: u32, client_data: ?*anyopaque) callconv(.c) FLAC__StreamEncoderWriteStatus;
pub const FLAC__StreamEncoderSeekCallback = *const fn (encoder: *const FLAC__StreamEncoder, absolute_byte_offset: u64, client_data: ?*anyopaque) callconv(.c) FLAC__StreamEncoderSeekStatus;
pub const FLAC__StreamEncoderTellCallback = *const fn (encoder: *const FLAC__StreamEncoder, absolute_byte_offset: *u64, client_data: ?*anyopaque) callconv(.c) FLAC__StreamEncoderTellStatus;
pub const FLAC__StreamEncoderMetadataCallback = *const fn (encoder: *const FLAC__StreamEncoder, metadata: *const FLAC__StreamMetadata, client_data: ?*anyopaque) callconv(.c) void;
pub const FLAC__StreamEncoderProgressCallback = *const fn (encoder: *const FLAC__StreamEncoder, bytes_written: u64, samples_written: u64, frames_written: u32, total_frames_estimate: u32, client_data: ?*anyopaque) callconv(.c) void;

pub extern fn FLAC__stream_encoder_new() ?*FLAC__StreamEncoder;
pub extern fn FLAC__stream_encoder_delete(encoder: ?*FLAC__StreamEncoder) void;
pub extern fn FLAC__stream_encoder_set_ogg_serial_number(encoder: *FLAC__StreamEncoder, serial_number: c_long) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_verify(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_streamable_subset(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_channels(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_bits_per_sample(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_sample_rate(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_compression_level(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_blocksize(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_do_mid_side_stereo(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_loose_mid_side_stereo(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_apodization(encoder: *FLAC__StreamEncoder, specification: [*:0]const u8) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_max_lpc_order(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_qlp_coeff_precision(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_do_qlp_coeff_prec_search(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_do_escape_coding(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_do_exhaustive_model_search(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_min_residual_partition_order(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_max_residual_partition_order(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_num_threads(encoder: *FLAC__StreamEncoder, value: u32) u32;
pub extern fn FLAC__stream_encoder_set_rice_parameter_search_dist(encoder: *FLAC__StreamEncoder, value: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_total_samples_estimate(encoder: *FLAC__StreamEncoder, value: u64) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_metadata(encoder: *FLAC__StreamEncoder, metadata: ?[*]*FLAC__StreamMetadata, num_blocks: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_set_limit_min_bitrate(encoder: *FLAC__StreamEncoder, value: FLAC__bool) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_state(encoder: *const FLAC__StreamEncoder) FLAC__StreamEncoderState;
pub extern fn FLAC__stream_encoder_get_verify_decoder_state(encoder: *const FLAC__StreamEncoder) FLAC__StreamDecoderState;
pub extern fn FLAC__stream_encoder_get_resolved_state_string(encoder: *const FLAC__StreamEncoder) [*:0]const u8;
pub extern fn FLAC__stream_encoder_get_verify_decoder_error_stats(encoder: *const FLAC__StreamEncoder, absolute_sample: ?*u64, frame_number: ?*u32, channel: ?*u32, sample: ?*u32, expected: ?*i32, got: ?*i32) void;
pub extern fn FLAC__stream_encoder_get_verify(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_streamable_subset(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_channels(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_bits_per_sample(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_sample_rate(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_blocksize(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_do_mid_side_stereo(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_loose_mid_side_stereo(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_max_lpc_order(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_qlp_coeff_precision(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_do_qlp_coeff_prec_search(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_do_escape_coding(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_do_exhaustive_model_search(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_get_min_residual_partition_order(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_max_residual_partition_order(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_num_threads(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_rice_parameter_search_dist(encoder: *const FLAC__StreamEncoder) u32;
pub extern fn FLAC__stream_encoder_get_total_samples_estimate(encoder: *const FLAC__StreamEncoder) u64;
pub extern fn FLAC__stream_encoder_get_limit_min_bitrate(encoder: *const FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_init_stream(encoder: *FLAC__StreamEncoder, write_callback: ?FLAC__StreamEncoderWriteCallback, seek_callback: ?FLAC__StreamEncoderSeekCallback, tell_callback: ?FLAC__StreamEncoderTellCallback, metadata_callback: ?FLAC__StreamEncoderMetadataCallback, client_data: ?*anyopaque) FLAC__StreamEncoderInitStatus;
pub extern fn FLAC__stream_encoder_init_ogg_stream(encoder: *FLAC__StreamEncoder, read_callback: ?FLAC__StreamEncoderReadCallback, write_callback: ?FLAC__StreamEncoderWriteCallback, seek_callback: ?FLAC__StreamEncoderSeekCallback, tell_callback: ?FLAC__StreamEncoderTellCallback, metadata_callback: ?FLAC__StreamEncoderMetadataCallback, client_data: ?*anyopaque) FLAC__StreamEncoderInitStatus;
pub extern fn FLAC__stream_encoder_init_FILE(encoder: *FLAC__StreamEncoder, file: *FILE, progress_callback: ?FLAC__StreamEncoderProgressCallback, client_data: ?*anyopaque) FLAC__StreamEncoderInitStatus;
pub extern fn FLAC__stream_encoder_init_ogg_FILE(encoder: *FLAC__StreamEncoder, file: *FILE, progress_callback: ?FLAC__StreamEncoderProgressCallback, client_data: ?*anyopaque) FLAC__StreamEncoderInitStatus;
pub extern fn FLAC__stream_encoder_init_file(encoder: *FLAC__StreamEncoder, filename: ?[*:0]const u8, progress_callback: ?FLAC__StreamEncoderProgressCallback, client_data: ?*anyopaque) FLAC__StreamEncoderInitStatus;
pub extern fn FLAC__stream_encoder_init_ogg_file(encoder: *FLAC__StreamEncoder, filename: ?[*:0]const u8, progress_callback: ?FLAC__StreamEncoderProgressCallback, client_data: ?*anyopaque) FLAC__StreamEncoderInitStatus;
pub extern fn FLAC__stream_encoder_finish(encoder: *FLAC__StreamEncoder) FLAC__bool;
pub extern fn FLAC__stream_encoder_process(encoder: *FLAC__StreamEncoder, buffer: [*]const [*]const i32, samples: u32) FLAC__bool;
pub extern fn FLAC__stream_encoder_process_interleaved(encoder: *FLAC__StreamEncoder, buffer: [*]const i32, samples: u32) FLAC__bool;

// metadata.h

pub extern fn FLAC__metadata_get_streaminfo(filename: [*:0]const u8, streaminfo: *FLAC__StreamMetadata) FLAC__bool;
pub extern fn FLAC__metadata_get_tags(filename: [*:0]const u8, tags: *?*FLAC__StreamMetadata) FLAC__bool;
pub extern fn FLAC__metadata_get_cuesheet(filename: [*:0]const u8, cuesheet: *?*FLAC__StreamMetadata) FLAC__bool;
pub extern fn FLAC__metadata_get_picture(filename: [*:0]const u8, picture: *?*FLAC__StreamMetadata, @"type": FLAC__StreamMetadata_Picture_Type, mime_type: ?[*:0]const u8, description: ?[*:0]const FLAC__byte, max_width: u32, max_height: u32, max_depth: u32, max_colors: u32) FLAC__bool;

pub const FLAC__Metadata_SimpleIterator = opaque {};

pub const FLAC__Metadata_SimpleIteratorStatus = c_uint;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_OK: FLAC__Metadata_SimpleIteratorStatus = 0;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_ILLEGAL_INPUT: FLAC__Metadata_SimpleIteratorStatus = 1;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_ERROR_OPENING_FILE: FLAC__Metadata_SimpleIteratorStatus = 2;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_NOT_A_FLAC_FILE: FLAC__Metadata_SimpleIteratorStatus = 3;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_NOT_WRITABLE: FLAC__Metadata_SimpleIteratorStatus = 4;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_BAD_METADATA: FLAC__Metadata_SimpleIteratorStatus = 5;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_READ_ERROR: FLAC__Metadata_SimpleIteratorStatus = 6;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_SEEK_ERROR: FLAC__Metadata_SimpleIteratorStatus = 7;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_WRITE_ERROR: FLAC__Metadata_SimpleIteratorStatus = 8;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_RENAME_ERROR: FLAC__Metadata_SimpleIteratorStatus = 9;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_UNLINK_ERROR: FLAC__Metadata_SimpleIteratorStatus = 10;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_MEMORY_ALLOCATION_ERROR: FLAC__Metadata_SimpleIteratorStatus = 11;
pub const FLAC__METADATA_SIMPLE_ITERATOR_STATUS_INTERNAL_ERROR: FLAC__Metadata_SimpleIteratorStatus = 12;
pub extern const FLAC__Metadata_SimpleIteratorStatusString: [13][*:0]const u8;

pub extern fn FLAC__metadata_simple_iterator_new() ?*FLAC__Metadata_SimpleIterator;
pub extern fn FLAC__metadata_simple_iterator_delete(iterator: *FLAC__Metadata_SimpleIterator) void;
pub extern fn FLAC__metadata_simple_iterator_status(iterator: *FLAC__Metadata_SimpleIterator) FLAC__Metadata_SimpleIteratorStatus;
pub extern fn FLAC__metadata_simple_iterator_init(iterator: *FLAC__Metadata_SimpleIterator, filename: [*:0]const u8, read_only: FLAC__bool, preserve_file_stats: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_is_writable(iterator: *const FLAC__Metadata_SimpleIterator) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_next(iterator: *FLAC__Metadata_SimpleIterator) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_prev(iterator: *FLAC__Metadata_SimpleIterator) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_is_last(iterator: *const FLAC__Metadata_SimpleIterator) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_get_block_offset(iterator: *const FLAC__Metadata_SimpleIterator) i64;
pub extern fn FLAC__metadata_simple_iterator_get_block_type(iterator: *const FLAC__Metadata_SimpleIterator) FLAC__MetadataType;
pub extern fn FLAC__metadata_simple_iterator_get_block_length(iterator: *const FLAC__Metadata_SimpleIterator) u32;
pub extern fn FLAC__metadata_simple_iterator_get_application_id(iterator: *FLAC__Metadata_SimpleIterator, id: *[4]FLAC__byte) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_get_block(iterator: *FLAC__Metadata_SimpleIterator) ?*FLAC__StreamMetadata;
pub extern fn FLAC__metadata_simple_iterator_set_block(iterator: *FLAC__Metadata_SimpleIterator, block: *FLAC__StreamMetadata, use_padding: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_insert_block_after(iterator: *FLAC__Metadata_SimpleIterator, block: *FLAC__StreamMetadata, use_padding: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_simple_iterator_delete_block(iterator: *FLAC__Metadata_SimpleIterator, use_padding: FLAC__bool) FLAC__bool;

pub const FLAC__Metadata_Chain = opaque {};
pub const FLAC__Metadata_Iterator = opaque {};

pub const FLAC__Metadata_ChainStatus = c_uint;
pub const FLAC__METADATA_CHAIN_STATUS_OK: FLAC__Metadata_ChainStatus = 0;
pub const FLAC__METADATA_CHAIN_STATUS_ILLEGAL_INPUT: FLAC__Metadata_ChainStatus = 1;
pub const FLAC__METADATA_CHAIN_STATUS_ERROR_OPENING_FILE: FLAC__Metadata_ChainStatus = 2;
pub const FLAC__METADATA_CHAIN_STATUS_NOT_A_FLAC_FILE: FLAC__Metadata_ChainStatus = 3;
pub const FLAC__METADATA_CHAIN_STATUS_NOT_WRITABLE: FLAC__Metadata_ChainStatus = 4;
pub const FLAC__METADATA_CHAIN_STATUS_BAD_METADATA: FLAC__Metadata_ChainStatus = 5;
pub const FLAC__METADATA_CHAIN_STATUS_READ_ERROR: FLAC__Metadata_ChainStatus = 6;
pub const FLAC__METADATA_CHAIN_STATUS_SEEK_ERROR: FLAC__Metadata_ChainStatus = 7;
pub const FLAC__METADATA_CHAIN_STATUS_WRITE_ERROR: FLAC__Metadata_ChainStatus = 8;
pub const FLAC__METADATA_CHAIN_STATUS_RENAME_ERROR: FLAC__Metadata_ChainStatus = 9;
pub const FLAC__METADATA_CHAIN_STATUS_UNLINK_ERROR: FLAC__Metadata_ChainStatus = 10;
pub const FLAC__METADATA_CHAIN_STATUS_MEMORY_ALLOCATION_ERROR: FLAC__Metadata_ChainStatus = 11;
pub const FLAC__METADATA_CHAIN_STATUS_INTERNAL_ERROR: FLAC__Metadata_ChainStatus = 12;
pub const FLAC__METADATA_CHAIN_STATUS_INVALID_CALLBACKS: FLAC__Metadata_ChainStatus = 13;
pub const FLAC__METADATA_CHAIN_STATUS_READ_WRITE_MISMATCH: FLAC__Metadata_ChainStatus = 14;
pub const FLAC__METADATA_CHAIN_STATUS_WRONG_WRITE_CALL: FLAC__Metadata_ChainStatus = 15;
pub extern const FLAC__Metadata_ChainStatusString: [16][*:0]const u8;

pub extern fn FLAC__metadata_chain_new() ?*FLAC__Metadata_Chain;
pub extern fn FLAC__metadata_chain_delete(chain: *FLAC__Metadata_Chain) void;
pub extern fn FLAC__metadata_chain_status(chain: *FLAC__Metadata_Chain) FLAC__Metadata_ChainStatus;
pub extern fn FLAC__metadata_chain_read(chain: *FLAC__Metadata_Chain, filename: [*:0]const u8) FLAC__bool;
pub extern fn FLAC__metadata_chain_read_ogg(chain: *FLAC__Metadata_Chain, filename: [*:0]const u8) FLAC__bool;
pub extern fn FLAC__metadata_chain_read_with_callbacks(chain: *FLAC__Metadata_Chain, handle: FLAC__IOHandle, callbacks: FLAC__IOCallbacks) FLAC__bool;
pub extern fn FLAC__metadata_chain_read_ogg_with_callbacks(chain: *FLAC__Metadata_Chain, handle: FLAC__IOHandle, callbacks: FLAC__IOCallbacks) FLAC__bool;
pub extern fn FLAC__metadata_chain_check_if_tempfile_needed(chain: *FLAC__Metadata_Chain, use_padding: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_chain_write(chain: *FLAC__Metadata_Chain, use_padding: FLAC__bool, preserve_file_stats: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_chain_write_new_file(chain: *FLAC__Metadata_Chain, filename: [*:0]const u8, use_padding: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_chain_write_with_callbacks(chain: *FLAC__Metadata_Chain, use_padding: FLAC__bool, handle: FLAC__IOHandle, callbacks: FLAC__IOCallbacks) FLAC__bool;
pub extern fn FLAC__metadata_chain_write_with_callbacks_and_tempfile(chain: *FLAC__Metadata_Chain, use_padding: FLAC__bool, handle: FLAC__IOHandle, callbacks: FLAC__IOCallbacks, temp_handle: FLAC__IOHandle, temp_callbacks: FLAC__IOCallbacks) FLAC__bool;
pub extern fn FLAC__metadata_chain_merge_padding(chain: *FLAC__Metadata_Chain) void;
pub extern fn FLAC__metadata_chain_sort_padding(chain: *FLAC__Metadata_Chain) void;

pub extern fn FLAC__metadata_iterator_new() ?*FLAC__Metadata_Iterator;
pub extern fn FLAC__metadata_iterator_delete(iterator: *FLAC__Metadata_Iterator) void;
pub extern fn FLAC__metadata_iterator_init(iterator: *FLAC__Metadata_Iterator, chain: *FLAC__Metadata_Chain) void;
pub extern fn FLAC__metadata_iterator_next(iterator: *FLAC__Metadata_Iterator) FLAC__bool;
pub extern fn FLAC__metadata_iterator_prev(iterator: *FLAC__Metadata_Iterator) FLAC__bool;
pub extern fn FLAC__metadata_iterator_get_block_type(iterator: *const FLAC__Metadata_Iterator) FLAC__MetadataType;
pub extern fn FLAC__metadata_iterator_get_block(iterator: *FLAC__Metadata_Iterator) ?*FLAC__StreamMetadata;
pub extern fn FLAC__metadata_iterator_set_block(iterator: *FLAC__Metadata_Iterator, block: *FLAC__StreamMetadata) FLAC__bool;
pub extern fn FLAC__metadata_iterator_delete_block(iterator: *FLAC__Metadata_Iterator, replace_with_padding: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_iterator_insert_block_before(iterator: *FLAC__Metadata_Iterator, block: *FLAC__StreamMetadata) FLAC__bool;
pub extern fn FLAC__metadata_iterator_insert_block_after(iterator: *FLAC__Metadata_Iterator, block: *FLAC__StreamMetadata) FLAC__bool;

pub extern fn FLAC__metadata_object_new(@"type": FLAC__MetadataType) ?*FLAC__StreamMetadata;
pub extern fn FLAC__metadata_object_clone(object: *const FLAC__StreamMetadata) ?*FLAC__StreamMetadata;
pub extern fn FLAC__metadata_object_delete(object: *FLAC__StreamMetadata) void;
pub extern fn FLAC__metadata_object_is_equal(block1: *const FLAC__StreamMetadata, block2: *const FLAC__StreamMetadata) FLAC__bool;
pub extern fn FLAC__metadata_object_application_set_data(object: *FLAC__StreamMetadata, data: ?[*]FLAC__byte, length: u32, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_resize_points(object: *FLAC__StreamMetadata, new_num_points: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_set_point(object: *FLAC__StreamMetadata, point_num: u32, point: FLAC__StreamMetadata_SeekPoint) void;
pub extern fn FLAC__metadata_object_seektable_insert_point(object: *FLAC__StreamMetadata, point_num: u32, point: FLAC__StreamMetadata_SeekPoint) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_delete_point(object: *FLAC__StreamMetadata, point_num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_is_legal(object: *const FLAC__StreamMetadata) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_template_append_placeholders(object: *FLAC__StreamMetadata, num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_template_append_point(object: *FLAC__StreamMetadata, sample_number: u64) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_template_append_points(object: *FLAC__StreamMetadata, sample_numbers: [*]u64, num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_template_append_spaced_points(object: *FLAC__StreamMetadata, num: u32, total_samples: u64) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_template_append_spaced_points_by_samples(object: *FLAC__StreamMetadata, samples: u32, total_samples: u64) FLAC__bool;
pub extern fn FLAC__metadata_object_seektable_template_sort(object: *FLAC__StreamMetadata, compact: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_set_vendor_string(object: *FLAC__StreamMetadata, entry: FLAC__StreamMetadata_VorbisComment_Entry, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_resize_comments(object: *FLAC__StreamMetadata, new_num_comments: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_set_comment(object: *FLAC__StreamMetadata, comment_num: u32, entry: FLAC__StreamMetadata_VorbisComment_Entry, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_insert_comment(object: *FLAC__StreamMetadata, comment_num: u32, entry: FLAC__StreamMetadata_VorbisComment_Entry, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_append_comment(object: *FLAC__StreamMetadata, entry: FLAC__StreamMetadata_VorbisComment_Entry, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_replace_comment(object: *FLAC__StreamMetadata, entry: FLAC__StreamMetadata_VorbisComment_Entry, all: FLAC__bool, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_delete_comment(object: *FLAC__StreamMetadata, comment_num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_entry_from_name_value_pair(entry: *FLAC__StreamMetadata_VorbisComment_Entry, field_name: [*:0]const u8, field_value: [*:0]const u8) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_entry_to_name_value_pair(entry: FLAC__StreamMetadata_VorbisComment_Entry, field_name: *?[*:0]u8, field_value: *?[*:0]u8) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_entry_matches(entry: FLAC__StreamMetadata_VorbisComment_Entry, field_name: [*]const u8, field_name_length: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_vorbiscomment_find_entry_from(object: *const FLAC__StreamMetadata, offset: u32, field_name: [*:0]const u8) c_int;
pub extern fn FLAC__metadata_object_vorbiscomment_remove_entry_matching(object: *FLAC__StreamMetadata, field_name: [*:0]const u8) c_int;
pub extern fn FLAC__metadata_object_vorbiscomment_remove_entries_matching(object: *FLAC__StreamMetadata, field_name: [*:0]const u8) c_int;
pub extern fn FLAC__metadata_object_cuesheet_track_new() ?*FLAC__StreamMetadata_CueSheet_Track;
pub extern fn FLAC__metadata_object_cuesheet_track_clone(object: *const FLAC__StreamMetadata_CueSheet_Track) ?*FLAC__StreamMetadata_CueSheet_Track;
pub extern fn FLAC__metadata_object_cuesheet_track_delete(object: *FLAC__StreamMetadata_CueSheet_Track) void;
pub extern fn FLAC__metadata_object_cuesheet_track_resize_indices(object: *FLAC__StreamMetadata, track_num: u32, new_num_indices: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_track_insert_index(object: *FLAC__StreamMetadata, track_num: u32, index_num: u32, index: FLAC__StreamMetadata_CueSheet_Index) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_track_insert_blank_index(object: *FLAC__StreamMetadata, track_num: u32, index_num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_track_delete_index(object: *FLAC__StreamMetadata, track_num: u32, index_num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_resize_tracks(object: *FLAC__StreamMetadata, new_num_tracks: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_set_track(object: *FLAC__StreamMetadata, track_num: u32, track: *FLAC__StreamMetadata_CueSheet_Track, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_insert_track(object: *FLAC__StreamMetadata, track_num: u32, track: *FLAC__StreamMetadata_CueSheet_Track, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_insert_blank_track(object: *FLAC__StreamMetadata, track_num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_delete_track(object: *FLAC__StreamMetadata, track_num: u32) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_is_legal(object: *const FLAC__StreamMetadata, check_cd_da_subset: FLAC__bool, violation: ?*[*:0]const u8) FLAC__bool;
pub extern fn FLAC__metadata_object_cuesheet_calculate_cddb_id(object: *const FLAC__StreamMetadata) u32;
pub extern fn FLAC__metadata_object_picture_set_mime_type(object: *FLAC__StreamMetadata, mime_type: [*:0]u8, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_picture_set_description(object: *FLAC__StreamMetadata, description: [*:0]FLAC__byte, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_picture_set_data(object: *FLAC__StreamMetadata, data: ?[*]FLAC__byte, length: u32, copy: FLAC__bool) FLAC__bool;
pub extern fn FLAC__metadata_object_picture_is_legal(object: *const FLAC__StreamMetadata, violation: ?*[*:0]const u8) FLAC__bool;
pub extern fn FLAC__metadata_object_get_raw(object: *const FLAC__StreamMetadata) ?[*]FLAC__byte;
pub extern fn FLAC__metadata_object_set_raw(buffer: [*]FLAC__byte, length: u32) ?*FLAC__StreamMetadata;
