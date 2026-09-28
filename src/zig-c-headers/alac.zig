//! Hand-written bindings for the ALAC C DSP core (codec/{aglib,dplib,matrixlib,ALACBitUtilities,
//! EndianPortable,ALACAudioTypes}.h). ALACDecoder/ALACEncoder (C++) are not built; see src/alac.zig.

// ALACAudioTypes.h

pub const kChannelAtomSize = 12;

pub const kALAC_UnimplementedError = -4;
pub const kALAC_FileNotFoundError = -43;
pub const kALAC_ParamError = -50;
pub const kALAC_MemFullError = -108;

pub const kALACFormatAppleLossless: u32 = 'a' << 24 | 'l' << 16 | 'a' << 8 | 'c';
pub const kALACFormatLinearPCM: u32 = 'l' << 24 | 'p' << 16 | 'c' << 8 | 'm';

pub const kALACMaxChannels = 8;
pub const kALACMaxEscapeHeaderBytes = 8;
pub const kALACMaxSearches = 16;
pub const kALACMaxCoefs = 16;
pub const kALACDefaultFramesPerPacket = 4096;

pub const ALACChannelLayoutTag = u32;

pub const kALACFormatFlagIsFloat = 1 << 0;
pub const kALACFormatFlagIsBigEndian = 1 << 1;
pub const kALACFormatFlagIsSignedInteger = 1 << 2;
pub const kALACFormatFlagIsPacked = 1 << 3;
pub const kALACFormatFlagIsAlignedHigh = 1 << 4;

pub const kALACChannelLayoutTag_Mono: ALACChannelLayoutTag = (100 << 16) | 1;
pub const kALACChannelLayoutTag_Stereo: ALACChannelLayoutTag = (101 << 16) | 2;
pub const kALACChannelLayoutTag_MPEG_3_0_B: ALACChannelLayoutTag = (113 << 16) | 3;
pub const kALACChannelLayoutTag_MPEG_4_0_B: ALACChannelLayoutTag = (116 << 16) | 4;
pub const kALACChannelLayoutTag_MPEG_5_0_D: ALACChannelLayoutTag = (120 << 16) | 5;
pub const kALACChannelLayoutTag_MPEG_5_1_D: ALACChannelLayoutTag = (124 << 16) | 6;
pub const kALACChannelLayoutTag_AAC_6_1: ALACChannelLayoutTag = (142 << 16) | 7;
pub const kALACChannelLayoutTag_MPEG_7_1_B: ALACChannelLayoutTag = (127 << 16) | 8;

/// `static const` in the header, so not a linkable symbol.
pub const ALACChannelLayoutTags = [kALACMaxChannels]ALACChannelLayoutTag{
    kALACChannelLayoutTag_Mono,
    kALACChannelLayoutTag_Stereo,
    kALACChannelLayoutTag_MPEG_3_0_B,
    kALACChannelLayoutTag_MPEG_4_0_B,
    kALACChannelLayoutTag_MPEG_5_0_D,
    kALACChannelLayoutTag_MPEG_5_1_D,
    kALACChannelLayoutTag_AAC_6_1,
    kALACChannelLayoutTag_MPEG_7_1_B,
};

pub const ALACAudioChannelLayout = extern struct {
    mChannelLayoutTag: ALACChannelLayoutTag,
    mChannelBitmap: u32,
    mNumberChannelDescriptions: u32,
};

pub const AudioFormatDescription = extern struct {
    mSampleRate: f64,
    mFormatID: u32,
    mFormatFlags: u32,
    mBytesPerPacket: u32,
    mFramesPerPacket: u32,
    mBytesPerFrame: u32,
    mChannelsPerFrame: u32,
    mBitsPerChannel: u32,
    mReserved: u32,
};

pub const kALACCodecFormat = kALACFormatAppleLossless;
pub const kALACVersion = 0;
pub const kALACCompatibleVersion = kALACVersion;
pub const kALACDefaultFrameSize = 4096;

/// On-disk "magic cookie" layout; multi-byte fields are big-endian there.
pub const ALACSpecificConfig = extern struct {
    frameLength: u32,
    compatibleVersion: u8,
    bitDepth: u8,
    pb: u8,
    mb: u8,
    kb: u8,
    numChannels: u8,
    maxRun: u16,
    maxFrameBytes: u32,
    avgBitRate: u32,
    sampleRate: u32,
};

pub const AudioChannelLayoutAID: u32 = 'c' << 24 | 'h' << 16 | 'a' << 8 | 'n';

// ALACBitUtilities.h

pub const ALAC_noErr = 0;

pub const ELEMENT_TYPE = c_uint;
pub const ID_SCE: ELEMENT_TYPE = 0;
pub const ID_CPE: ELEMENT_TYPE = 1;
pub const ID_CCE: ELEMENT_TYPE = 2;
pub const ID_LFE: ELEMENT_TYPE = 3;
pub const ID_DSE: ELEMENT_TYPE = 4;
pub const ID_PCE: ELEMENT_TYPE = 5;
pub const ID_FIL: ELEMENT_TYPE = 6;
pub const ID_END: ELEMENT_TYPE = 7;

pub const BitBuffer = extern struct {
    cur: [*]u8,
    end: [*]u8,
    bitIndex: u32,
    byteSize: u32,
};

pub extern fn BitBufferInit(bits: *BitBuffer, buffer: [*]u8, byteSize: u32) void;
pub extern fn BitBufferRead(bits: *BitBuffer, numBits: u8) u32;
pub extern fn BitBufferReadSmall(bits: *BitBuffer, numBits: u8) u8;
pub extern fn BitBufferReadOne(bits: *BitBuffer) u8;
pub extern fn BitBufferPeek(bits: *BitBuffer, numBits: u8) u32;
pub extern fn BitBufferPeekOne(bits: *BitBuffer) u32;
pub extern fn BitBufferUnpackBERSize(bits: *BitBuffer) u32;
pub extern fn BitBufferGetPosition(bits: *BitBuffer) u32;
pub extern fn BitBufferByteAlign(bits: *BitBuffer, addZeros: i32) void;
pub extern fn BitBufferAdvance(bits: *BitBuffer, numBits: u32) void;
pub extern fn BitBufferRewind(bits: *BitBuffer, numBits: u32) void;
pub extern fn BitBufferWrite(bits: *BitBuffer, value: u32, numBits: u32) void;
pub extern fn BitBufferReset(bits: *BitBuffer) void;

// EndianPortable.h

pub extern fn Swap16NtoB(inUInt16: u16) u16;
pub extern fn Swap16BtoN(inUInt16: u16) u16;
pub extern fn Swap32NtoB(inUInt32: u32) u32;
pub extern fn Swap32BtoN(inUInt32: u32) u32;
pub extern fn Swap64BtoN(inUInt64: u64) u64;
pub extern fn Swap64NtoB(inUInt64: u64) u64;
pub extern fn SwapFloat32BtoN(in: f32) f32;
pub extern fn SwapFloat32NtoB(in: f32) f32;
pub extern fn SwapFloat64BtoN(in: f64) f64;
pub extern fn SwapFloat64NtoB(in: f64) f64;
pub extern fn Swap16(inUInt16: *u16) void;
pub extern fn Swap24(inUInt24: *[3]u8) void;
pub extern fn Swap32(inUInt32: *u32) void;

// aglib.h

pub const QBSHIFT = 9;
pub const QB = 1 << QBSHIFT;
pub const PB0 = 40;
pub const MB0 = 10;
pub const KB0 = 14;
pub const MAX_RUN_DEFAULT = 255;
pub const MMULSHIFT = 2;
pub const MDENSHIFT = QBSHIFT - MMULSHIFT - 1;
pub const MOFF = 1 << (MDENSHIFT - 2);
pub const BITOFF = 24;
pub const MAX_PREFIX_16 = 9;
pub const MAX_PREFIX_TOLONG_16 = 15;
pub const MAX_PREFIX_32 = 9;
pub const MAX_DATATYPE_BITS_16 = 16;

pub const AGParamRec = extern struct {
    mb: u32,
    mb0: u32,
    pb: u32,
    kb: u32,
    wb: u32,
    qb: u32,
    fw: u32,
    sw: u32,
    maxrun: u32,
};

pub extern fn set_standard_ag_params(params: *AGParamRec, fullwidth: u32, sectorwidth: u32) void;
pub extern fn set_ag_params(params: *AGParamRec, m: u32, p: u32, k: u32, f: u32, s: u32, maxrun: u32) void;
pub extern fn dyn_comp(params: *AGParamRec, pc: [*]i32, bitstream: *BitBuffer, numSamples: i32, bitSize: i32, outNumBits: *u32) i32;
pub extern fn dyn_decomp(params: *AGParamRec, bitstream: *BitBuffer, pc: [*]i32, numSamples: i32, maxSize: i32, outNumBits: *u32) i32;

// dplib.h

pub const DENSHIFT_MAX = 15;
pub const DENSHIFT_DEFAULT = 9;
pub const AINIT = 38;
pub const BINIT = -29;
pub const CINIT = -2;
pub const NUMCOEPAIRS = 16;

pub extern fn init_coefs(coefs: [*]i16, denshift: u32, numPairs: i32) void;
pub extern fn copy_coefs(srcCoefs: [*]const i16, dstCoefs: [*]i16, numPairs: i32) void;
/// coefs may be NULL when numactive == 31 (first-order pass-through mode).
pub extern fn pc_block(in: [*]i32, pc: [*]i32, num: i32, coefs: ?[*]i16, numactive: i32, chanbits: u32, denshift: u32) void;
pub extern fn unpc_block(pc: [*]i32, out: [*]i32, num: i32, coefs: ?[*]i16, numactive: i32, chanbits: u32, denshift: u32) void;

// matrixlib.h

pub extern fn mix16(in: [*]i16, stride: u32, u: [*]i32, v: [*]i32, numSamples: i32, mixbits: i32, mixres: i32) void;
pub extern fn unmix16(u: [*]i32, v: [*]i32, out: [*]i16, stride: u32, numSamples: i32, mixbits: i32, mixres: i32) void;
pub extern fn mix20(in: [*]u8, stride: u32, u: [*]i32, v: [*]i32, numSamples: i32, mixbits: i32, mixres: i32) void;
pub extern fn unmix20(u: [*]i32, v: [*]i32, out: [*]u8, stride: u32, numSamples: i32, mixbits: i32, mixres: i32) void;
pub extern fn mix24(in: [*]u8, stride: u32, u: [*]i32, v: [*]i32, numSamples: i32, mixbits: i32, mixres: i32, shiftUV: [*]u16, bytesShifted: i32) void;
pub extern fn unmix24(u: [*]i32, v: [*]i32, out: [*]u8, stride: u32, numSamples: i32, mixbits: i32, mixres: i32, shiftUV: [*]u16, bytesShifted: i32) void;
pub extern fn mix32(in: [*]i32, stride: u32, u: [*]i32, v: [*]i32, numSamples: i32, mixbits: i32, mixres: i32, shiftUV: [*]u16, bytesShifted: i32) void;
pub extern fn unmix32(u: [*]i32, v: [*]i32, out: [*]i32, stride: u32, numSamples: i32, mixbits: i32, mixres: i32, shiftUV: [*]u16, bytesShifted: i32) void;
pub extern fn copy20ToPredictor(in: [*]u8, stride: u32, out: [*]i32, numSamples: i32) void;
pub extern fn copy24ToPredictor(in: [*]u8, stride: u32, out: [*]i32, numSamples: i32) void;
pub extern fn copyPredictorTo24(in: [*]i32, out: [*]u8, stride: u32, numSamples: i32) void;
pub extern fn copyPredictorTo24Shift(in: [*]i32, shift: [*]u16, out: [*]u8, stride: u32, numSamples: i32, bytesShifted: i32) void;
pub extern fn copyPredictorTo20(in: [*]i32, out: [*]u8, stride: u32, numSamples: i32) void;
pub extern fn copyPredictorTo32(in: [*]i32, out: [*]i32, stride: u32, numSamples: i32) void;
pub extern fn copyPredictorTo32Shift(in: [*]i32, shift: [*]u16, out: [*]i32, stride: u32, numSamples: i32, bytesShifted: i32) void;
