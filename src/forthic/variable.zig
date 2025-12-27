const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;

/// ============================================================================
/// Variable - Named mutable value container
/// ============================================================================

pub const Variable = struct {
    name: []const u8,
    value: Value,

    pub fn init(name: []const u8, value: Value) Variable {
        return Variable{
            .name = name,
            .value = value,
        };
    }

    pub fn deinit(self: *Variable, allocator: Allocator) void {
        self.value.deinit(allocator);
        // Don't free self.name - it's owned by the HashMap key
    }

    pub fn getName(self: *const Variable) []const u8 {
        return self.name;
    }

    pub fn setValue(self: *Variable, value: Value) void {
        self.value = value;
    }

    pub fn getValue(self: *const Variable) Value {
        return self.value;
    }

    pub fn dup(self: *const Variable) Variable {
        return Variable{
            .name = self.name,
            .value = self.value,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Variable: basic operations" {
    const allocator = std.testing.allocator;
    _ = allocator;

    const value = Value.initInt(42);
    var variable = Variable.init("my_var", value);

    try std.testing.expectEqualStrings("my_var", variable.getName());
    try std.testing.expectEqual(value, variable.getValue());
}

test "Variable: set value" {
    const allocator = std.testing.allocator;
    _ = allocator;

    const val1 = Value.initInt(42);
    const val2 = Value.initInt(99);

    var variable = Variable.init("my_var", val1);
    variable.setValue(val2);

    try std.testing.expectEqual(val2, variable.getValue());
}

test "Variable: duplicate" {
    const allocator = std.testing.allocator;
    _ = allocator;

    const value = Value.initInt(42);
    const variable = Variable.init("my_var", value);
    const dup_var = variable.dup();

    try std.testing.expectEqualStrings(variable.getName(), dup_var.getName());
    try std.testing.expectEqual(variable.getValue(), dup_var.getValue());
}
