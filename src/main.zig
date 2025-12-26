// Main entry point for the Forthic Zig library
pub const tokenizer = @import("forthic/tokenizer.zig");
pub const literals = @import("forthic/literals.zig");
pub const errors = @import("forthic/errors.zig");
pub const utils = @import("forthic/utils.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
