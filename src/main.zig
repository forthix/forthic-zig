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
pub const value = @import("forthic/value.zig");

// Re-export commonly used types
pub const Value = value.Value;
pub const Interpreter = interpreter.Interpreter;
pub const Module = module.Module;
pub const Variable = variable.Variable;
pub const WordOptions = word_options.WordOptions;

// Standard modules
pub const modules = struct {
    pub const standard = struct {
        pub const CoreModule = @import("forthic/modules/standard/core_module.zig").CoreModule;
        pub const MathModule = @import("forthic/modules/standard/math_module.zig").MathModule;
        pub const ArrayModule = @import("forthic/modules/standard/array_module.zig").ArrayModule;
        pub const BooleanModule = @import("forthic/modules/standard/boolean_module.zig").BooleanModule;
        pub const StringModule = @import("forthic/modules/standard/string_module.zig").StringModule;
        pub const RecordModule = @import("forthic/modules/standard/record_module.zig").RecordModule;
        pub const DatetimeModule = @import("forthic/modules/standard/datetime_module.zig").DatetimeModule;
        pub const JsonModule = @import("forthic/modules/standard/json_module.zig").JsonModule;
    };
};

test {
    @import("std").testing.refAllDecls(@This());
}
