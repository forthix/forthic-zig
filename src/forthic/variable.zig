const std = @import("std");
const Allocator = std.mem.Allocator;

/// ============================================================================
/// Variable - Named mutable value container
/// ============================================================================

pub const Variable = struct {
    name: []const u8,
    value: ?*anyopaque,

    pub fn init(name: []const u8, value: ?*anyopaque) Variable {
        return Variable{
            .name = name,
            .value = value,
        };
    }

    pub fn getName(self: *const Variable) []const u8 {
        return self.name;
    }

    pub fn setValue(self: *Variable, value: ?*anyopaque) void {
        self.value = value;
    }

    pub fn getValue(self: *const Variable) ?*anyopaque {
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

    const val1: i32 = 42;
    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    var variable = Variable.init("my_var", val1_ptr);

    try std.testing.expectEqualStrings("my_var", variable.getName());
    try std.testing.expectEqual(@as(?*anyopaque, val1_ptr), variable.getValue());
}

test "Variable: set value" {
    const allocator = std.testing.allocator;

    const val1: i32 = 42;
    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    const val2: i32 = 99;
    const val2_ptr = try allocator.create(i32);
    defer allocator.destroy(val2_ptr);
    val2_ptr.* = val2;

    var variable = Variable.init("my_var", val1_ptr);
    variable.setValue(val2_ptr);

    try std.testing.expectEqual(@as(?*anyopaque, val2_ptr), variable.getValue());
}

test "Variable: duplicate" {
    const allocator = std.testing.allocator;

    const val1: i32 = 42;
    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    const variable = Variable.init("my_var", val1_ptr);
    const dup_var = variable.dup();

    try std.testing.expectEqualStrings(variable.getName(), dup_var.getName());
    try std.testing.expectEqual(variable.getValue(), dup_var.getValue());
}
