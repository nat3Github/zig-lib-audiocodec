//! Hand-written bindings for fdk-aac (aacdecoder_lib.h, aacenc_lib.h, and the parts of FDK_audio.h /
//! machine_type.h that the public API uses). Omitted from FDK_audio.h: bitstream-internal
//! CODER_CONFIG, element/extension-payload IDs, AC_*/CC_* flags, and the static inline FDKlibInfo_* helpers.

// machine_type.h

pub const INT = c_int;
pub const UINT = c_uint;
pub const SHORT = c_short;
pub const UCHAR = u8;
pub const SCHAR = i8;
pub const INT64 = i64;
pub const INT_PCM = SHORT;

// FDK_audio.h

pub const TRANSPORT_TYPE = c_int;
pub const TT_UNKNOWN: TRANSPORT_TYPE = -1;
pub const TT_MP4_RAW: TRANSPORT_TYPE = 0;
pub const TT_MP4_ADIF: TRANSPORT_TYPE = 1;
pub const TT_MP4_ADTS: TRANSPORT_TYPE = 2;
pub const TT_MP4_LATM_MCP1: TRANSPORT_TYPE = 6;
pub const TT_MP4_LATM_MCP0: TRANSPORT_TYPE = 7;
pub const TT_MP4_LOAS: TRANSPORT_TYPE = 10;
pub const TT_DRM: TRANSPORT_TYPE = 12;

pub const AUDIO_OBJECT_TYPE = c_int;
pub const AOT_NONE: AUDIO_OBJECT_TYPE = -1;
pub const AOT_NULL_OBJECT: AUDIO_OBJECT_TYPE = 0;
pub const AOT_AAC_MAIN: AUDIO_OBJECT_TYPE = 1;
pub const AOT_AAC_LC: AUDIO_OBJECT_TYPE = 2;
pub const AOT_AAC_SSR: AUDIO_OBJECT_TYPE = 3;
pub const AOT_AAC_LTP: AUDIO_OBJECT_TYPE = 4;
pub const AOT_SBR: AUDIO_OBJECT_TYPE = 5;
pub const AOT_AAC_SCAL: AUDIO_OBJECT_TYPE = 6;
pub const AOT_TWIN_VQ: AUDIO_OBJECT_TYPE = 7;
pub const AOT_CELP: AUDIO_OBJECT_TYPE = 8;
pub const AOT_HVXC: AUDIO_OBJECT_TYPE = 9;
pub const AOT_RSVD_10: AUDIO_OBJECT_TYPE = 10;
pub const AOT_RSVD_11: AUDIO_OBJECT_TYPE = 11;
pub const AOT_TTSI: AUDIO_OBJECT_TYPE = 12;
pub const AOT_MAIN_SYNTH: AUDIO_OBJECT_TYPE = 13;
pub const AOT_WAV_TAB_SYNTH: AUDIO_OBJECT_TYPE = 14;
pub const AOT_GEN_MIDI: AUDIO_OBJECT_TYPE = 15;
pub const AOT_ALG_SYNTH_AUD_FX: AUDIO_OBJECT_TYPE = 16;
pub const AOT_ER_AAC_LC: AUDIO_OBJECT_TYPE = 17;
pub const AOT_RSVD_18: AUDIO_OBJECT_TYPE = 18;
pub const AOT_ER_AAC_LTP: AUDIO_OBJECT_TYPE = 19;
pub const AOT_ER_AAC_SCAL: AUDIO_OBJECT_TYPE = 20;
pub const AOT_ER_TWIN_VQ: AUDIO_OBJECT_TYPE = 21;
pub const AOT_ER_BSAC: AUDIO_OBJECT_TYPE = 22;
pub const AOT_ER_AAC_LD: AUDIO_OBJECT_TYPE = 23;
pub const AOT_ER_CELP: AUDIO_OBJECT_TYPE = 24;
pub const AOT_ER_HVXC: AUDIO_OBJECT_TYPE = 25;
pub const AOT_ER_HILN: AUDIO_OBJECT_TYPE = 26;
pub const AOT_ER_PARA: AUDIO_OBJECT_TYPE = 27;
pub const AOT_RSVD_28: AUDIO_OBJECT_TYPE = 28;
pub const AOT_PS: AUDIO_OBJECT_TYPE = 29;
pub const AOT_MPEGS: AUDIO_OBJECT_TYPE = 30;
pub const AOT_ESCAPE: AUDIO_OBJECT_TYPE = 31;
pub const AOT_MP3ONMP4_L1: AUDIO_OBJECT_TYPE = 32;
pub const AOT_MP3ONMP4_L2: AUDIO_OBJECT_TYPE = 33;
pub const AOT_MP3ONMP4_L3: AUDIO_OBJECT_TYPE = 34;
pub const AOT_RSVD_35: AUDIO_OBJECT_TYPE = 35;
pub const AOT_RSVD_36: AUDIO_OBJECT_TYPE = 36;
pub const AOT_AAC_SLS: AUDIO_OBJECT_TYPE = 37;
pub const AOT_SLS: AUDIO_OBJECT_TYPE = 38;
pub const AOT_ER_AAC_ELD: AUDIO_OBJECT_TYPE = 39;
pub const AOT_USAC: AUDIO_OBJECT_TYPE = 42;
pub const AOT_SAOC: AUDIO_OBJECT_TYPE = 43;
pub const AOT_LD_MPEGS: AUDIO_OBJECT_TYPE = 44;
pub const AOT_MP2_AAC_LC: AUDIO_OBJECT_TYPE = 129;
pub const AOT_MP2_SBR: AUDIO_OBJECT_TYPE = 132;
pub const AOT_DRM_AAC: AUDIO_OBJECT_TYPE = 143;
pub const AOT_DRM_SBR: AUDIO_OBJECT_TYPE = 144;
pub const AOT_DRM_MPEG_PS: AUDIO_OBJECT_TYPE = 145;
pub const AOT_DRM_SURROUND: AUDIO_OBJECT_TYPE = 146;
pub const AOT_DRM_USAC: AUDIO_OBJECT_TYPE = 147;

pub const CHANNEL_MODE = c_int;
pub const MODE_INVALID: CHANNEL_MODE = -1;
pub const MODE_UNKNOWN: CHANNEL_MODE = 0;
pub const MODE_1: CHANNEL_MODE = 1;
pub const MODE_2: CHANNEL_MODE = 2;
pub const MODE_1_2: CHANNEL_MODE = 3;
pub const MODE_1_2_1: CHANNEL_MODE = 4;
pub const MODE_1_2_2: CHANNEL_MODE = 5;
pub const MODE_1_2_2_1: CHANNEL_MODE = 6;
pub const MODE_1_2_2_2_1: CHANNEL_MODE = 7;
pub const MODE_6_1: CHANNEL_MODE = 11;
pub const MODE_7_1_BACK: CHANNEL_MODE = 12;
pub const MODE_7_1_TOP_FRONT: CHANNEL_MODE = 14;
pub const MODE_7_1_REAR_SURROUND: CHANNEL_MODE = 33;
pub const MODE_7_1_FRONT_CENTER: CHANNEL_MODE = 34;
pub const MODE_212: CHANNEL_MODE = 128;

pub const AUDIO_CHANNEL_TYPE = c_uint;
pub const ACT_NONE: AUDIO_CHANNEL_TYPE = 0x00;
pub const ACT_FRONT: AUDIO_CHANNEL_TYPE = 0x01;
pub const ACT_SIDE: AUDIO_CHANNEL_TYPE = 0x02;
pub const ACT_BACK: AUDIO_CHANNEL_TYPE = 0x03;
pub const ACT_LFE: AUDIO_CHANNEL_TYPE = 0x04;
pub const ACT_TOP: AUDIO_CHANNEL_TYPE = 0x10;
pub const ACT_FRONT_TOP: AUDIO_CHANNEL_TYPE = 0x11;
pub const ACT_SIDE_TOP: AUDIO_CHANNEL_TYPE = 0x12;
pub const ACT_BACK_TOP: AUDIO_CHANNEL_TYPE = 0x13;
pub const ACT_BOTTOM: AUDIO_CHANNEL_TYPE = 0x20;
pub const ACT_FRONT_BOTTOM: AUDIO_CHANNEL_TYPE = 0x21;
pub const ACT_SIDE_BOTTOM: AUDIO_CHANNEL_TYPE = 0x22;
pub const ACT_BACK_BOTTOM: AUDIO_CHANNEL_TYPE = 0x23;

pub const SBR_PS_SIGNALING = c_int;
pub const SIG_UNKNOWN: SBR_PS_SIGNALING = -1;
pub const SIG_IMPLICIT: SBR_PS_SIGNALING = 0;
pub const SIG_EXPLICIT_BW_COMPATIBLE: SBR_PS_SIGNALING = 1;
pub const SIG_EXPLICIT_HIERARCHICAL: SBR_PS_SIGNALING = 2;

pub const FDK_MODULE_ID = c_uint;
pub const FDK_NONE: FDK_MODULE_ID = 0;
pub const FDK_TOOLS: FDK_MODULE_ID = 1;
pub const FDK_SYSLIB: FDK_MODULE_ID = 2;
pub const FDK_AACDEC: FDK_MODULE_ID = 3;
pub const FDK_AACENC: FDK_MODULE_ID = 4;
pub const FDK_SBRDEC: FDK_MODULE_ID = 5;
pub const FDK_SBRENC: FDK_MODULE_ID = 6;
pub const FDK_TPDEC: FDK_MODULE_ID = 7;
pub const FDK_TPENC: FDK_MODULE_ID = 8;
pub const FDK_MPSDEC: FDK_MODULE_ID = 9;
pub const FDK_MPEGFILEREAD: FDK_MODULE_ID = 10;
pub const FDK_MPEGFILEWRITE: FDK_MODULE_ID = 11;
pub const FDK_PCMDMX: FDK_MODULE_ID = 31;
pub const FDK_MPSENC: FDK_MODULE_ID = 34;
pub const FDK_TDLIMIT: FDK_MODULE_ID = 35;
pub const FDK_UNIDRCDEC: FDK_MODULE_ID = 38;
/// Size of the LIB_INFO array passed to *GetLibInfo.
pub const FDK_MODULE_LAST: FDK_MODULE_ID = 39;

pub const LIB_INFO = extern struct {
    title: ?[*:0]const u8,
    build_date: ?[*:0]const u8,
    build_time: ?[*:0]const u8,
    module_id: FDK_MODULE_ID,
    version: INT,
    flags: UINT,
    versionStr: [32]u8,
};

// LIB_INFO.flags capability bits
pub const CAPF_AAC_LC = 0x00000001;
pub const CAPF_ER_AAC_LD = 0x00000002;
pub const CAPF_ER_AAC_SCAL = 0x00000004;
pub const CAPF_ER_AAC_LC = 0x00000008;
pub const CAPF_AAC_480 = 0x00000010;
pub const CAPF_AAC_512 = 0x00000020;
pub const CAPF_AAC_960 = 0x00000040;
pub const CAPF_AAC_1024 = 0x00000080;
pub const CAPF_AAC_HCR = 0x00000100;
pub const CAPF_AAC_VCB11 = 0x00000200;
pub const CAPF_AAC_RVLC = 0x00000400;
pub const CAPF_AAC_MPEG4 = 0x00000800;
pub const CAPF_AAC_DRC = 0x00001000;
pub const CAPF_AAC_CONCEALMENT = 0x00002000;
pub const CAPF_AAC_DRM_BSFORMAT = 0x00004000;
pub const CAPF_ER_AAC_ELD = 0x00008000;
pub const CAPF_ER_AAC_BSAC = 0x00010000;
pub const CAPF_AAC_ELD_DOWNSCALE = 0x00040000;
pub const CAPF_AAC_USAC_LP = 0x00100000;
pub const CAPF_AAC_USAC = 0x00200000;
pub const CAPF_ER_AAC_ELDV2 = 0x00800000;
pub const CAPF_AAC_UNIDRC = 0x01000000;
pub const CAPF_ADTS = 0x00000001;
pub const CAPF_ADIF = 0x00000002;
pub const CAPF_LATM = 0x00000004;
pub const CAPF_LOAS = 0x00000008;
pub const CAPF_RAWPACKETS = 0x00000010;
pub const CAPF_DRM = 0x00000020;
pub const CAPF_RSVD50 = 0x00000040;
pub const CAPF_SBR_LP = 0x00000001;
pub const CAPF_SBR_HQ = 0x00000002;
pub const CAPF_SBR_DRM_BS = 0x00000004;
pub const CAPF_SBR_CONCEALMENT = 0x00000008;
pub const CAPF_SBR_DRC = 0x00000010;
pub const CAPF_SBR_PS_MPEG = 0x00000020;
pub const CAPF_SBR_PS_DRM = 0x00000040;
pub const CAPF_SBR_ELD_DOWNSCALE = 0x00000080;
pub const CAPF_SBR_HBEHQ = 0x00000100;
pub const CAPF_DMX_BLIND = 0x00000001;
pub const CAPF_DMX_PCE = 0x00000002;
pub const CAPF_DMX_ARIB = 0x00000004;
pub const CAPF_DMX_DVB = 0x00000008;
pub const CAPF_DMX_CH_EXP = 0x00000010;
pub const CAPF_DMX_6_CH = 0x00000020;
pub const CAPF_DMX_8_CH = 0x00000040;
pub const CAPF_DMX_24_CH = 0x00000080;
pub const CAPF_LIMITER = 0x00002000;
pub const CAPF_MPS_STD = 0x00000001;
pub const CAPF_MPS_LD = 0x00000002;
pub const CAPF_MPS_USAC = 0x00000004;
pub const CAPF_MPS_HQ = 0x00000010;
pub const CAPF_MPS_LP = 0x00000020;
pub const CAPF_MPS_BLIND = 0x00000040;
pub const CAPF_MPS_BINAURAL = 0x00000080;
pub const CAPF_MPS_2CH_OUT = 0x00000100;
pub const CAPF_MPS_6CH_OUT = 0x00000200;
pub const CAPF_MPS_8CH_OUT = 0x00000400;
pub const CAPF_MPS_1CH_IN = 0x00001000;
pub const CAPF_MPS_2CH_IN = 0x00002000;
pub const CAPF_MPS_6CH_IN = 0x00004000;

// aacdecoder_lib.h

pub const AACDECODER_LIB_VL0 = 3;
pub const AACDECODER_LIB_VL1 = 2;
pub const AACDECODER_LIB_VL2 = 0;

pub const AAC_DECODER_ERROR = c_uint;
pub const AAC_DEC_OK: AAC_DECODER_ERROR = 0x0000;
pub const AAC_DEC_OUT_OF_MEMORY: AAC_DECODER_ERROR = 0x0002;
pub const AAC_DEC_UNKNOWN: AAC_DECODER_ERROR = 0x0005;
pub const aac_dec_sync_error_start: AAC_DECODER_ERROR = 0x1000;
pub const AAC_DEC_TRANSPORT_SYNC_ERROR: AAC_DECODER_ERROR = 0x1001;
pub const AAC_DEC_NOT_ENOUGH_BITS: AAC_DECODER_ERROR = 0x1002;
pub const aac_dec_sync_error_end: AAC_DECODER_ERROR = 0x1FFF;
pub const aac_dec_init_error_start: AAC_DECODER_ERROR = 0x2000;
pub const AAC_DEC_INVALID_HANDLE: AAC_DECODER_ERROR = 0x2001;
pub const AAC_DEC_UNSUPPORTED_AOT: AAC_DECODER_ERROR = 0x2002;
pub const AAC_DEC_UNSUPPORTED_FORMAT: AAC_DECODER_ERROR = 0x2003;
pub const AAC_DEC_UNSUPPORTED_ER_FORMAT: AAC_DECODER_ERROR = 0x2004;
pub const AAC_DEC_UNSUPPORTED_EPCONFIG: AAC_DECODER_ERROR = 0x2005;
pub const AAC_DEC_UNSUPPORTED_MULTILAYER: AAC_DECODER_ERROR = 0x2006;
pub const AAC_DEC_UNSUPPORTED_CHANNELCONFIG: AAC_DECODER_ERROR = 0x2007;
pub const AAC_DEC_UNSUPPORTED_SAMPLINGRATE: AAC_DECODER_ERROR = 0x2008;
pub const AAC_DEC_INVALID_SBR_CONFIG: AAC_DECODER_ERROR = 0x2009;
pub const AAC_DEC_SET_PARAM_FAIL: AAC_DECODER_ERROR = 0x200A;
pub const AAC_DEC_NEED_TO_RESTART: AAC_DECODER_ERROR = 0x200B;
pub const AAC_DEC_OUTPUT_BUFFER_TOO_SMALL: AAC_DECODER_ERROR = 0x200C;
pub const aac_dec_init_error_end: AAC_DECODER_ERROR = 0x2FFF;
pub const aac_dec_decode_error_start: AAC_DECODER_ERROR = 0x4000;
pub const AAC_DEC_TRANSPORT_ERROR: AAC_DECODER_ERROR = 0x4001;
pub const AAC_DEC_PARSE_ERROR: AAC_DECODER_ERROR = 0x4002;
pub const AAC_DEC_UNSUPPORTED_EXTENSION_PAYLOAD: AAC_DECODER_ERROR = 0x4003;
pub const AAC_DEC_DECODE_FRAME_ERROR: AAC_DECODER_ERROR = 0x4004;
pub const AAC_DEC_CRC_ERROR: AAC_DECODER_ERROR = 0x4005;
pub const AAC_DEC_INVALID_CODE_BOOK: AAC_DECODER_ERROR = 0x4006;
pub const AAC_DEC_UNSUPPORTED_PREDICTION: AAC_DECODER_ERROR = 0x4007;
pub const AAC_DEC_UNSUPPORTED_CCE: AAC_DECODER_ERROR = 0x4008;
pub const AAC_DEC_UNSUPPORTED_LFE: AAC_DECODER_ERROR = 0x4009;
pub const AAC_DEC_UNSUPPORTED_GAIN_CONTROL_DATA: AAC_DECODER_ERROR = 0x400A;
pub const AAC_DEC_UNSUPPORTED_SBA: AAC_DECODER_ERROR = 0x400B;
pub const AAC_DEC_TNS_READ_ERROR: AAC_DECODER_ERROR = 0x400C;
pub const AAC_DEC_RVLC_ERROR: AAC_DECODER_ERROR = 0x400D;
pub const aac_dec_decode_error_end: AAC_DECODER_ERROR = 0x4FFF;
pub const aac_dec_anc_data_error_start: AAC_DECODER_ERROR = 0x8000;
pub const AAC_DEC_ANC_DATA_ERROR: AAC_DECODER_ERROR = 0x8001;
pub const AAC_DEC_TOO_SMALL_ANC_BUFFER: AAC_DECODER_ERROR = 0x8002;
pub const AAC_DEC_TOO_MANY_ANC_ELEMENTS: AAC_DECODER_ERROR = 0x8003;
pub const aac_dec_anc_data_error_end: AAC_DECODER_ERROR = 0x8FFF;

pub const AAC_MD_PROFILE = c_uint;
pub const AAC_MD_PROFILE_MPEG_STANDARD: AAC_MD_PROFILE = 0;
pub const AAC_MD_PROFILE_MPEG_LEGACY: AAC_MD_PROFILE = 1;
pub const AAC_MD_PROFILE_MPEG_LEGACY_PRIO: AAC_MD_PROFILE = 2;
pub const AAC_MD_PROFILE_ARIB_JAPAN: AAC_MD_PROFILE = 3;

pub const AAC_DRC_DEFAULT_PRESENTATION_MODE_OPTIONS = c_int;
pub const AAC_DRC_PARAMETER_HANDLING_DISABLED: AAC_DRC_DEFAULT_PRESENTATION_MODE_OPTIONS = -1;
pub const AAC_DRC_PARAMETER_HANDLING_ENABLED: AAC_DRC_DEFAULT_PRESENTATION_MODE_OPTIONS = 0;
pub const AAC_DRC_PRESENTATION_MODE_1_DEFAULT: AAC_DRC_DEFAULT_PRESENTATION_MODE_OPTIONS = 1;
pub const AAC_DRC_PRESENTATION_MODE_2_DEFAULT: AAC_DRC_DEFAULT_PRESENTATION_MODE_OPTIONS = 2;

pub const AACDEC_PARAM = c_uint;
pub const AAC_PCM_DUAL_CHANNEL_OUTPUT_MODE: AACDEC_PARAM = 0x0002;
pub const AAC_PCM_OUTPUT_CHANNEL_MAPPING: AACDEC_PARAM = 0x0003;
pub const AAC_PCM_LIMITER_ENABLE: AACDEC_PARAM = 0x0004;
pub const AAC_PCM_LIMITER_ATTACK_TIME: AACDEC_PARAM = 0x0005;
pub const AAC_PCM_LIMITER_RELEAS_TIME: AACDEC_PARAM = 0x0006;
pub const AAC_PCM_MIN_OUTPUT_CHANNELS: AACDEC_PARAM = 0x0011;
pub const AAC_PCM_MAX_OUTPUT_CHANNELS: AACDEC_PARAM = 0x0012;
pub const AAC_METADATA_PROFILE: AACDEC_PARAM = 0x0020;
pub const AAC_METADATA_EXPIRY_TIME: AACDEC_PARAM = 0x0021;
pub const AAC_CONCEAL_METHOD: AACDEC_PARAM = 0x0100;
pub const AAC_DRC_BOOST_FACTOR: AACDEC_PARAM = 0x0200;
pub const AAC_DRC_ATTENUATION_FACTOR: AACDEC_PARAM = 0x0201;
pub const AAC_DRC_REFERENCE_LEVEL: AACDEC_PARAM = 0x0202;
pub const AAC_DRC_HEAVY_COMPRESSION: AACDEC_PARAM = 0x0203;
pub const AAC_DRC_DEFAULT_PRESENTATION_MODE: AACDEC_PARAM = 0x0204;
pub const AAC_DRC_ENC_TARGET_LEVEL: AACDEC_PARAM = 0x0205;
pub const AAC_UNIDRC_SET_EFFECT: AACDEC_PARAM = 0x0206;
pub const AAC_UNIDRC_ALBUM_MODE: AACDEC_PARAM = 0x0207;
pub const AAC_QMF_LOWPOWER: AACDEC_PARAM = 0x0300;
pub const AAC_TPDEC_CLEAR_BUFFER: AACDEC_PARAM = 0x0603;

pub const CStreamInfo = extern struct {
    sampleRate: INT,
    frameSize: INT,
    numChannels: INT,
    pChannelType: ?[*]AUDIO_CHANNEL_TYPE,
    pChannelIndices: ?[*]UCHAR,
    aacSampleRate: INT,
    profile: INT,
    aot: AUDIO_OBJECT_TYPE,
    channelConfig: INT,
    bitRate: INT,
    aacSamplesPerFrame: INT,
    aacNumChannels: INT,
    extAot: AUDIO_OBJECT_TYPE,
    extSamplingRate: INT,
    outputDelay: UINT,
    flags: UINT,
    epConfig: SCHAR,
    numLostAccessUnits: INT,
    numTotalBytes: INT64,
    numBadBytes: INT64,
    numTotalAccessUnits: INT64,
    numBadAccessUnits: INT64,
    drcProgRefLev: SCHAR,
    drcPresMode: SCHAR,
    outputLoudness: INT,
};

pub const AAC_DECODER_INSTANCE = opaque {};
pub const HANDLE_AACDECODER = *AAC_DECODER_INSTANCE;

pub const AACDEC_CONCEAL = 1;
pub const AACDEC_FLUSH = 2;
pub const AACDEC_INTR = 4;
pub const AACDEC_CLRHIST = 8;

pub extern fn aacDecoder_AncDataInit(self: HANDLE_AACDECODER, buffer: ?[*]UCHAR, size: c_int) AAC_DECODER_ERROR;
pub extern fn aacDecoder_AncDataGet(self: HANDLE_AACDECODER, index: c_int, ptr: *?[*]UCHAR, size: *c_int) AAC_DECODER_ERROR;
pub extern fn aacDecoder_SetParam(self: HANDLE_AACDECODER, param: AACDEC_PARAM, value: INT) AAC_DECODER_ERROR;
pub extern fn aacDecoder_GetFreeBytes(self: HANDLE_AACDECODER, pFreeBytes: *UINT) AAC_DECODER_ERROR;
pub extern fn aacDecoder_Open(transportFmt: TRANSPORT_TYPE, nrOfLayers: UINT) ?HANDLE_AACDECODER;
pub extern fn aacDecoder_ConfigRaw(self: HANDLE_AACDECODER, conf: [*]const [*]UCHAR, length: [*]const UINT) AAC_DECODER_ERROR;
pub extern fn aacDecoder_RawISOBMFFData(self: HANDLE_AACDECODER, buffer: [*]UCHAR, length: UINT) AAC_DECODER_ERROR;
pub extern fn aacDecoder_Fill(self: HANDLE_AACDECODER, pBuffer: [*]const [*]UCHAR, bufferSize: [*]const UINT, bytesValid: *UINT) AAC_DECODER_ERROR;
pub extern fn aacDecoder_DecodeFrame(self: HANDLE_AACDECODER, pTimeData: [*]INT_PCM, timeDataSize: INT, flags: UINT) AAC_DECODER_ERROR;
pub extern fn aacDecoder_Close(self: ?HANDLE_AACDECODER) void;
pub extern fn aacDecoder_GetStreamInfo(self: HANDLE_AACDECODER) ?*CStreamInfo;
pub extern fn aacDecoder_GetLibInfo(info: *[FDK_MODULE_LAST]LIB_INFO) INT;

// aacenc_lib.h

pub const AACENCODER_LIB_VL0 = 4;
pub const AACENCODER_LIB_VL1 = 0;
pub const AACENCODER_LIB_VL2 = 1;

pub const AACENC_ERROR = c_uint;
pub const AACENC_OK: AACENC_ERROR = 0x0000;
pub const AACENC_INVALID_HANDLE: AACENC_ERROR = 0x0020;
pub const AACENC_MEMORY_ERROR: AACENC_ERROR = 0x0021;
pub const AACENC_UNSUPPORTED_PARAMETER: AACENC_ERROR = 0x0022;
pub const AACENC_INVALID_CONFIG: AACENC_ERROR = 0x0023;
pub const AACENC_INIT_ERROR: AACENC_ERROR = 0x0040;
pub const AACENC_INIT_AAC_ERROR: AACENC_ERROR = 0x0041;
pub const AACENC_INIT_SBR_ERROR: AACENC_ERROR = 0x0042;
pub const AACENC_INIT_TP_ERROR: AACENC_ERROR = 0x0043;
pub const AACENC_INIT_META_ERROR: AACENC_ERROR = 0x0044;
pub const AACENC_INIT_MPS_ERROR: AACENC_ERROR = 0x0045;
pub const AACENC_ENCODE_ERROR: AACENC_ERROR = 0x0060;
pub const AACENC_ENCODE_EOF: AACENC_ERROR = 0x0080;

pub const AACENC_BufferIdentifier = c_uint;
pub const IN_AUDIO_DATA: AACENC_BufferIdentifier = 0;
pub const IN_ANCILLRY_DATA: AACENC_BufferIdentifier = 1;
pub const IN_METADATA_SETUP: AACENC_BufferIdentifier = 2;
pub const OUT_BITSTREAM_DATA: AACENC_BufferIdentifier = 3;
pub const OUT_AU_SIZES: AACENC_BufferIdentifier = 4;

pub const AACENCODER = opaque {};
pub const HANDLE_AACENCODER = *AACENCODER;

pub const AACENC_InfoStruct = extern struct {
    maxOutBufBytes: UINT,
    maxAncBytes: UINT,
    inBufFillLevel: UINT,
    inputChannels: UINT,
    frameLength: UINT,
    nDelay: UINT,
    nDelayCore: UINT,
    confBuf: [64]UCHAR,
    confSize: UINT,
};

pub const AACENC_BufDesc = extern struct {
    numBufs: INT,
    bufs: ?[*]?*anyopaque,
    bufferIdentifiers: ?[*]INT,
    bufSizes: ?[*]INT,
    bufElSizes: ?[*]INT,
};

pub const AACENC_InArgs = extern struct {
    numInSamples: INT,
    numAncBytes: INT,
};

pub const AACENC_OutArgs = extern struct {
    numOutBytes: INT,
    numInSamples: INT,
    numAncBytes: INT,
    bitResState: INT,
};

pub const AACENC_METADATA_DRC_PROFILE = c_uint;
pub const AACENC_METADATA_DRC_NONE: AACENC_METADATA_DRC_PROFILE = 0;
pub const AACENC_METADATA_DRC_FILMSTANDARD: AACENC_METADATA_DRC_PROFILE = 1;
pub const AACENC_METADATA_DRC_FILMLIGHT: AACENC_METADATA_DRC_PROFILE = 2;
pub const AACENC_METADATA_DRC_MUSICSTANDARD: AACENC_METADATA_DRC_PROFILE = 3;
pub const AACENC_METADATA_DRC_MUSICLIGHT: AACENC_METADATA_DRC_PROFILE = 4;
pub const AACENC_METADATA_DRC_SPEECH: AACENC_METADATA_DRC_PROFILE = 5;
pub const AACENC_METADATA_DRC_NOT_PRESENT: AACENC_METADATA_DRC_PROFILE = 256;

pub const AACENC_MetaData = extern struct {
    drc_profile: AACENC_METADATA_DRC_PROFILE,
    comp_profile: AACENC_METADATA_DRC_PROFILE,
    drc_TargetRefLevel: INT,
    comp_TargetRefLevel: INT,
    prog_ref_level_present: INT,
    prog_ref_level: INT,
    PCE_mixdown_idx_present: UCHAR,
    ETSI_DmxLvl_present: UCHAR,
    centerMixLevel: SCHAR,
    surroundMixLevel: SCHAR,
    dolbySurroundMode: UCHAR,
    drcPresentationMode: UCHAR,
    ExtMetaData: extern struct {
        extAncDataEnable: UCHAR,
        extDownmixLevelEnable: UCHAR,
        extDownmixLevel_A: UCHAR,
        extDownmixLevel_B: UCHAR,
        dmxGainEnable: UCHAR,
        dmxGain5: INT,
        dmxGain2: INT,
        lfeDmxEnable: UCHAR,
        lfeDmxLevel: UCHAR,
    },
};

pub const AACENC_CTRLFLAGS = c_uint;
pub const AACENC_INIT_NONE: AACENC_CTRLFLAGS = 0x0000;
pub const AACENC_INIT_CONFIG: AACENC_CTRLFLAGS = 0x0001;
pub const AACENC_INIT_STATES: AACENC_CTRLFLAGS = 0x0002;
pub const AACENC_INIT_TRANSPORT: AACENC_CTRLFLAGS = 0x1000;
pub const AACENC_RESET_INBUFFER: AACENC_CTRLFLAGS = 0x2000;
pub const AACENC_INIT_ALL: AACENC_CTRLFLAGS = 0xFFFF;

pub const AACENC_PARAM = c_uint;
pub const AACENC_AOT: AACENC_PARAM = 0x0100;
pub const AACENC_BITRATE: AACENC_PARAM = 0x0101;
pub const AACENC_BITRATEMODE: AACENC_PARAM = 0x0102;
pub const AACENC_SAMPLERATE: AACENC_PARAM = 0x0103;
pub const AACENC_SBR_MODE: AACENC_PARAM = 0x0104;
pub const AACENC_GRANULE_LENGTH: AACENC_PARAM = 0x0105;
pub const AACENC_CHANNELMODE: AACENC_PARAM = 0x0106;
pub const AACENC_CHANNELORDER: AACENC_PARAM = 0x0107;
pub const AACENC_SBR_RATIO: AACENC_PARAM = 0x0108;
pub const AACENC_AFTERBURNER: AACENC_PARAM = 0x0200;
pub const AACENC_BANDWIDTH: AACENC_PARAM = 0x0203;
pub const AACENC_PEAK_BITRATE: AACENC_PARAM = 0x0207;
pub const AACENC_TRANSMUX: AACENC_PARAM = 0x0300;
pub const AACENC_HEADER_PERIOD: AACENC_PARAM = 0x0301;
pub const AACENC_SIGNALING_MODE: AACENC_PARAM = 0x0302;
pub const AACENC_TPSUBFRAMES: AACENC_PARAM = 0x0303;
pub const AACENC_AUDIOMUXVER: AACENC_PARAM = 0x0304;
pub const AACENC_PROTECTION: AACENC_PARAM = 0x0306;
pub const AACENC_ANCILLARY_BITRATE: AACENC_PARAM = 0x0500;
pub const AACENC_METADATA_MODE: AACENC_PARAM = 0x0600;
pub const AACENC_CONTROL_STATE: AACENC_PARAM = 0xFF00;
pub const AACENC_NONE: AACENC_PARAM = 0xFFFF;

pub extern fn aacEncOpen(phAacEncoder: *?HANDLE_AACENCODER, encModules: UINT, maxChannels: UINT) AACENC_ERROR;
pub extern fn aacEncClose(phAacEncoder: *?HANDLE_AACENCODER) AACENC_ERROR;
pub extern fn aacEncEncode(hAacEncoder: HANDLE_AACENCODER, inBufDesc: ?*const AACENC_BufDesc, outBufDesc: ?*const AACENC_BufDesc, inargs: ?*const AACENC_InArgs, outargs: ?*AACENC_OutArgs) AACENC_ERROR;
pub extern fn aacEncInfo(hAacEncoder: HANDLE_AACENCODER, pInfo: *AACENC_InfoStruct) AACENC_ERROR;
pub extern fn aacEncoder_SetParam(hAacEncoder: HANDLE_AACENCODER, param: AACENC_PARAM, value: UINT) AACENC_ERROR;
pub extern fn aacEncoder_GetParam(hAacEncoder: HANDLE_AACENCODER, param: AACENC_PARAM) UINT;
pub extern fn aacEncGetLibInfo(info: *[FDK_MODULE_LAST]LIB_INFO) AACENC_ERROR;
