// Main entry point for the Forthic Zig library
pub const tokenizer = @import("forthic/tokenizer.zig");
pub const literals = @import("forthic/literals.zig");
pub const errors = @import("forthic/errors.zig");
pub const utils = @import("forthic/utils.zig");
pub const word_options = @import("forthic/word_options.zig");
pub const stack = @import("forthic/stack.zig");
pub const word = @import("forthic/word.zig");
pub const variable = @import("forthic/variable.zig");
pub const module = @import("forthic/module.zig");
pub const interpreter = @import("forthic/interpreter.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
