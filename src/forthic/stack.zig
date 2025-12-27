const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const errors = @import("errors.zig");

/// ============================================================================
/// Stack - LIFO data stack for interpreter
/// ============================================================================

pub const Stack = struct {
    items: ArrayList(?*anyopaque),

    pub fn init(allocator: Allocator) Stack {
        _ = allocator;
        return Stack{
            .items = ArrayList(?*anyopaque){},
        };
    }

    pub fn deinit(self: *Stack, allocator: Allocator) void {
        self.items.deinit(allocator);
    }

    /// Push value onto stack
    pub fn push(self: *Stack, allocator: Allocator, value: ?*anyopaque) !void {
        try self.items.append(allocator, value);
    }

    /// Pop value from stack
    pub fn pop(self: *Stack) !?*anyopaque {
        if (self.items.items.len == 0) {
            return errors.ForthicErrorType.StackUnderflow;
        }
        return self.items.pop().?;
    }

    /// Peek at top value without removing
    pub fn peek(self: *const Stack) !?*anyopaque {
        if (self.items.items.len == 0) {
            return errors.ForthicErrorType.StackUnderflow;
        }
        return self.items.items[self.items.items.len - 1];
    }

    /// Get stack length
    pub fn length(self: *const Stack) usize {
        return self.items.items.len;
    }

    /// Clear all items
    pub fn clear(self: *Stack, allocator: Allocator) void {
        _ = allocator;
        self.items.clearRetainingCapacity();
    }

    /// Get item at index (0 = bottom, length-1 = top)
    pub fn at(self: *const Stack, index: usize) !?*anyopaque {
        if (index >= self.items.items.len) {
            return error.OutOfMemory; // Using this as index out of bounds
        }
        return self.items.items[index];
    }

    /// Set item at index
    pub fn set(self: *Stack, index: usize, value: ?*anyopaque) !void {
        if (index >= self.items.items.len) {
            return error.OutOfMemory;
        }
        self.items.items[index] = value;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Stack: push and pop" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const val1: i32 = 42;
    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    try stack.push(allocator, val1_ptr);
    try std.testing.expectEqual(@as(usize, 1), stack.length());

    const popped = try stack.pop();
    try std.testing.expectEqual(@as(?*anyopaque, val1_ptr), popped);
    try std.testing.expectEqual(@as(usize, 0), stack.length());
}

test "Stack: underflow" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const result = stack.pop();
    try std.testing.expectError(errors.ForthicErrorType.StackUnderflow, result);
}

test "Stack: peek" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const val1: i32 = 42;
    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    try stack.push(allocator, val1_ptr);

    const peeked = try stack.peek();
    try std.testing.expectEqual(@as(?*anyopaque, val1_ptr), peeked);
    try std.testing.expectEqual(@as(usize, 1), stack.length()); // Still on stack
}

test "Stack: multiple items" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const val1: i32 = 1;
    const val2: i32 = 2;
    const val3: i32 = 3;

    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    const val2_ptr = try allocator.create(i32);
    defer allocator.destroy(val2_ptr);
    val2_ptr.* = val2;

    const val3_ptr = try allocator.create(i32);
    defer allocator.destroy(val3_ptr);
    val3_ptr.* = val3;

    try stack.push(allocator, val1_ptr);
    try stack.push(allocator, val2_ptr);
    try stack.push(allocator, val3_ptr);

    try std.testing.expectEqual(@as(usize, 3), stack.length());

    const pop3 = try stack.pop();
    const pop2 = try stack.pop();
    const pop1 = try stack.pop();

    try std.testing.expectEqual(@as(?*anyopaque, val3_ptr), pop3);
    try std.testing.expectEqual(@as(?*anyopaque, val2_ptr), pop2);
    try std.testing.expectEqual(@as(?*anyopaque, val1_ptr), pop1);
}

test "Stack: clear" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const val1: i32 = 42;
    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    try stack.push(allocator, val1_ptr);
    try stack.push(allocator, val1_ptr);
    try stack.push(allocator, val1_ptr);

    stack.clear(allocator);
    try std.testing.expectEqual(@as(usize, 0), stack.length());
}
