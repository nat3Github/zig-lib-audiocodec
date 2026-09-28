pub const c = @import("c.zig");
pub const alac = @import("alac.zig");
pub const c_allocator = @import("c_allocator.zig");

comptime {
    _ = @import("libc.zig");
}
