const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const errors = @import("errors.zig");
const Value = @import("value.zig").Value;

/// ============================================================================
/// Stack - LIFO data stack for interpreter
/// ============================================================================

pub const Stack = struct {
    items: ArrayList(Value),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Stack {
        const items = ArrayList(Value){};
        return Stack{
            .items = items,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Stack) void {
        // Free all values on stack
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
    }

    /// Push value onto stack (takes ownership)
    pub fn push(self: *Stack, value: Value) !void {
        try self.items.append(self.allocator, value);
    }

    /// Pop value from stack (transfers ownership)
    pub fn pop(self: *Stack) !Value {
        if (self.items.items.len == 0) {
            return errors.ForthicErrorType.StackUnderflow;
        }
        return self.items.pop() orelse return errors.ForthicErrorType.StackUnderflow;
    }

    /// Peek at top value without removing (returns reference)
    pub fn peek(self: *const Stack) !*const Value {
        if (self.items.items.len == 0) {
            return errors.ForthicErrorType.StackUnderflow;
        }
        return &self.items.items[self.items.items.len - 1];
    }

    /// Get stack length
    pub fn length(self: *const Stack) usize {
        return self.items.items.len;
    }

    /// Clear all items
    pub fn clear(self: *Stack) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();
    }

    /// Get item at index (0 = bottom, length-1 = top)
    pub fn at(self: *const Stack, index: usize) !*const Value {
        if (index >= self.items.items.len) {
            return error.OutOfMemory; // Using this as index out of bounds
        }
        return &self.items.items[index];
    }

    /// Set item at index (takes ownership of new value, frees old)
    pub fn set(self: *Stack, index: usize, value: Value) !void {
        if (index >= self.items.items.len) {
            return error.OutOfMemory;
        }
        self.items.items[index].deinit(self.allocator);
        self.items.items[index] = value;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Stack: push and pop" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit();

    const val1 = Value.initInt(42);
    try stack.push(val1);
    try std.testing.expectEqual(@as(usize, 1), stack.length());

    const popped = try stack.pop();
    try std.testing.expectEqual(@as(i64, 42), popped.int_value);
    try std.testing.expectEqual(@as(usize, 0), stack.length());
}

test "Stack: underflow" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit();

    const result = stack.pop();
    try std.testing.expectError(errors.ForthicErrorType.StackUnderflow, result);
}

test "Stack: peek" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit();

    try stack.push(Value.initInt(42));

    const peeked = try stack.peek();
    try std.testing.expectEqual(@as(i64, 42), peeked.int_value);
    try std.testing.expectEqual(@as(usize, 1), stack.length()); // Still on stack
}

test "Stack: multiple items" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit();

    try stack.push(Value.initInt(1));
    try stack.push(Value.initInt(2));
    try stack.push(Value.initInt(3));

    try std.testing.expectEqual(@as(usize, 3), stack.length());

    const pop3 = try stack.pop();
    const pop2 = try stack.pop();
    const pop1 = try stack.pop();

    try std.testing.expectEqual(@as(i64, 3), pop3.int_value);
    try std.testing.expectEqual(@as(i64, 2), pop2.int_value);
    try std.testing.expectEqual(@as(i64, 1), pop1.int_value);
}

test "Stack: clear" {
    const allocator = std.testing.allocator;
    var stack = Stack.init(allocator);
    defer stack.deinit();

    try stack.push(Value.initInt(42));
    try stack.push(Value.initBool(true));
    try stack.push(Value.initFloat(3.14));

    stack.clear();
    try std.testing.expectEqual(@as(usize, 0), stack.length());
}
