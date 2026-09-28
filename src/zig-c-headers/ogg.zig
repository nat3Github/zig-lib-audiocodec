//! Hand-written bindings for libogg (include/ogg/ogg.h).

pub const ogg_iovec_t = extern struct {
    iov_base: ?*anyopaque,
    iov_len: usize,
};

pub const oggpack_buffer = extern struct {
    endbyte: c_long,
    endbit: c_int,
    buffer: ?[*]u8,
    ptr: ?[*]u8,
    storage: c_long,
};

pub const ogg_page = extern struct {
    header: ?[*]u8,
    header_len: c_long,
    body: ?[*]u8,
    body_len: c_long,
};

pub const ogg_stream_state = extern struct {
    body_data: ?[*]u8,
    body_storage: c_long,
    body_fill: c_long,
    body_returned: c_long,
    lacing_vals: ?[*]c_int,
    granule_vals: ?[*]i64,
    lacing_storage: c_long,
    lacing_fill: c_long,
    lacing_packet: c_long,
    lacing_returned: c_long,
    header: [282]u8,
    header_fill: c_int,
    e_o_s: c_int,
    b_o_s: c_int,
    serialno: c_long,
    pageno: c_long,
    packetno: i64,
    granulepos: i64,
};

pub const ogg_packet = extern struct {
    packet: ?[*]u8,
    bytes: c_long,
    b_o_s: c_long,
    e_o_s: c_long,
    granulepos: i64,
    packetno: i64,
};

pub const ogg_sync_state = extern struct {
    data: ?[*]u8,
    storage: c_int,
    fill: c_int,
    returned: c_int,
    unsynced: c_int,
    headerbytes: c_int,
    bodybytes: c_int,
};

// bitpacking, LSb first
pub extern fn oggpack_writeinit(b: *oggpack_buffer) void;
pub extern fn oggpack_writecheck(b: *oggpack_buffer) c_int;
pub extern fn oggpack_writetrunc(b: *oggpack_buffer, bits: c_long) void;
pub extern fn oggpack_writealign(b: *oggpack_buffer) void;
pub extern fn oggpack_writecopy(b: *oggpack_buffer, source: ?*anyopaque, bits: c_long) void;
pub extern fn oggpack_reset(b: *oggpack_buffer) void;
pub extern fn oggpack_writeclear(b: *oggpack_buffer) void;
pub extern fn oggpack_readinit(b: *oggpack_buffer, buf: [*]u8, bytes: c_int) void;
pub extern fn oggpack_write(b: *oggpack_buffer, value: c_ulong, bits: c_int) void;
pub extern fn oggpack_look(b: *oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpack_look1(b: *oggpack_buffer) c_long;
pub extern fn oggpack_adv(b: *oggpack_buffer, bits: c_int) void;
pub extern fn oggpack_adv1(b: *oggpack_buffer) void;
pub extern fn oggpack_read(b: *oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpack_read1(b: *oggpack_buffer) c_long;
pub extern fn oggpack_bytes(b: *oggpack_buffer) c_long;
pub extern fn oggpack_bits(b: *oggpack_buffer) c_long;
pub extern fn oggpack_get_buffer(b: *oggpack_buffer) ?[*]u8;

// bitpacking, MSb first
pub extern fn oggpackB_writeinit(b: *oggpack_buffer) void;
pub extern fn oggpackB_writecheck(b: *oggpack_buffer) c_int;
pub extern fn oggpackB_writetrunc(b: *oggpack_buffer, bits: c_long) void;
pub extern fn oggpackB_writealign(b: *oggpack_buffer) void;
pub extern fn oggpackB_writecopy(b: *oggpack_buffer, source: ?*anyopaque, bits: c_long) void;
pub extern fn oggpackB_reset(b: *oggpack_buffer) void;
pub extern fn oggpackB_writeclear(b: *oggpack_buffer) void;
pub extern fn oggpackB_readinit(b: *oggpack_buffer, buf: [*]u8, bytes: c_int) void;
pub extern fn oggpackB_write(b: *oggpack_buffer, value: c_ulong, bits: c_int) void;
pub extern fn oggpackB_look(b: *oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpackB_look1(b: *oggpack_buffer) c_long;
pub extern fn oggpackB_adv(b: *oggpack_buffer, bits: c_int) void;
pub extern fn oggpackB_adv1(b: *oggpack_buffer) void;
pub extern fn oggpackB_read(b: *oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpackB_read1(b: *oggpack_buffer) c_long;
pub extern fn oggpackB_bytes(b: *oggpack_buffer) c_long;
pub extern fn oggpackB_bits(b: *oggpack_buffer) c_long;
pub extern fn oggpackB_get_buffer(b: *oggpack_buffer) ?[*]u8;

// encoding
pub extern fn ogg_stream_packetin(os: *ogg_stream_state, op: *ogg_packet) c_int;
pub extern fn ogg_stream_iovecin(os: *ogg_stream_state, iov: [*]ogg_iovec_t, count: c_int, e_o_s: c_long, granulepos: i64) c_int;
pub extern fn ogg_stream_pageout(os: *ogg_stream_state, og: *ogg_page) c_int;
pub extern fn ogg_stream_pageout_fill(os: *ogg_stream_state, og: *ogg_page, nfill: c_int) c_int;
pub extern fn ogg_stream_flush(os: *ogg_stream_state, og: *ogg_page) c_int;
pub extern fn ogg_stream_flush_fill(os: *ogg_stream_state, og: *ogg_page, nfill: c_int) c_int;

// decoding
pub extern fn ogg_sync_init(oy: *ogg_sync_state) c_int;
pub extern fn ogg_sync_clear(oy: *ogg_sync_state) c_int;
pub extern fn ogg_sync_reset(oy: *ogg_sync_state) c_int;
pub extern fn ogg_sync_destroy(oy: *ogg_sync_state) c_int;
pub extern fn ogg_sync_check(oy: *ogg_sync_state) c_int;
pub extern fn ogg_sync_buffer(oy: *ogg_sync_state, size: c_long) ?[*]u8;
pub extern fn ogg_sync_wrote(oy: *ogg_sync_state, bytes: c_long) c_int;
pub extern fn ogg_sync_pageseek(oy: *ogg_sync_state, og: *ogg_page) c_long;
pub extern fn ogg_sync_pageout(oy: *ogg_sync_state, og: *ogg_page) c_int;
pub extern fn ogg_stream_pagein(os: *ogg_stream_state, og: *ogg_page) c_int;
pub extern fn ogg_stream_packetout(os: *ogg_stream_state, op: *ogg_packet) c_int;
pub extern fn ogg_stream_packetpeek(os: *ogg_stream_state, op: ?*ogg_packet) c_int;

// general
pub extern fn ogg_stream_init(os: *ogg_stream_state, serialno: c_int) c_int;
pub extern fn ogg_stream_clear(os: *ogg_stream_state) c_int;
pub extern fn ogg_stream_reset(os: *ogg_stream_state) c_int;
pub extern fn ogg_stream_reset_serialno(os: *ogg_stream_state, serialno: c_int) c_int;
pub extern fn ogg_stream_destroy(os: *ogg_stream_state) c_int;
pub extern fn ogg_stream_check(os: *ogg_stream_state) c_int;
pub extern fn ogg_stream_eos(os: *ogg_stream_state) c_int;

pub extern fn ogg_page_checksum_set(og: *ogg_page) void;
pub extern fn ogg_page_version(og: *const ogg_page) c_int;
pub extern fn ogg_page_continued(og: *const ogg_page) c_int;
pub extern fn ogg_page_bos(og: *const ogg_page) c_int;
pub extern fn ogg_page_eos(og: *const ogg_page) c_int;
pub extern fn ogg_page_granulepos(og: *const ogg_page) i64;
pub extern fn ogg_page_serialno(og: *const ogg_page) c_int;
pub extern fn ogg_page_pageno(og: *const ogg_page) c_long;
pub extern fn ogg_page_packets(og: *const ogg_page) c_int;
pub extern fn ogg_packet_clear(op: *ogg_packet) void;
