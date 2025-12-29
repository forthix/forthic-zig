const std = @import("std");
const testing = std.testing;
const forthic = @import("forthic");
const c_bindings = forthic.grpc.c_bindings;

// =============================================================================
// C Bindings Tests
// =============================================================================

test "c_bindings: create and destroy null stack value" {
    const value = c_bindings.stackValueCreateNull();
    try testing.expect(value != null);

    const stack_type = c_bindings.stackValueGetType(value.?);
    try testing.expectEqual(c_bindings.STACK_VALUE_NULL, stack_type);

    c_bindings.stackValueDestroy(value.?);
}

test "c_bindings: create and read int stack value" {
    const value = c_bindings.stackValueCreateInt(42);
    try testing.expect(value != null);

    const stack_type = c_bindings.stackValueGetType(value.?);
    try testing.expectEqual(c_bindings.STACK_VALUE_INT, stack_type);

    const int_val = c_bindings.stackValueGetInt(value.?);
    try testing.expectEqual(@as(i64, 42), int_val);

    c_bindings.stackValueDestroy(value.?);
}

test "c_bindings: create and read string stack value" {
    const value = c_bindings.stackValueCreateString("hello");
    try testing.expect(value != null);

    const stack_type = c_bindings.stackValueGetType(value.?);
    try testing.expectEqual(c_bindings.STACK_VALUE_STRING, stack_type);

    const str_val = c_bindings.stackValueGetString(value.?);
    try testing.expect(std.mem.eql(u8, std.mem.span(str_val), "hello"));

    c_bindings.stackValueDestroy(value.?);
}

test "c_bindings: create and read bool stack value" {
    const value = c_bindings.stackValueCreateBool(true);
    try testing.expect(value != null);

    const stack_type = c_bindings.stackValueGetType(value.?);
    try testing.expectEqual(c_bindings.STACK_VALUE_BOOL, stack_type);

    const bool_val = c_bindings.stackValueGetBool(value.?);
    try testing.expect(bool_val);

    c_bindings.stackValueDestroy(value.?);
}

test "c_bindings: create and read float stack value" {
    const value = c_bindings.stackValueCreateFloat(3.14);
    try testing.expect(value != null);

    const stack_type = c_bindings.stackValueGetType(value.?);
    try testing.expectEqual(c_bindings.STACK_VALUE_FLOAT, stack_type);

    const float_val = c_bindings.stackValueGetFloat(value.?);
    try testing.expectApproxEqAbs(@as(f64, 3.14), float_val, 0.001);

    c_bindings.stackValueDestroy(value.?);
}

test "c_bindings: create and destroy array stack value" {
    const item1 = c_bindings.stackValueCreateInt(1);
    const item2 = c_bindings.stackValueCreateInt(2);
    const item3 = c_bindings.stackValueCreateInt(3);

    const items = [_]*const c_bindings.StackValue{ item1.?, item2.?, item3.? };
    const array = c_bindings.stackValueCreateArray(&items, items.len);
    try testing.expect(array != null);

    const stack_type = c_bindings.stackValueGetType(array.?);
    try testing.expectEqual(c_bindings.STACK_VALUE_ARRAY, stack_type);

    // Clean up
    c_bindings.stackValueDestroy(array.?);
    c_bindings.stackValueDestroy(item1.?);
    c_bindings.stackValueDestroy(item2.?);
    c_bindings.stackValueDestroy(item3.?);
}

// =============================================================================
// Serializer Tests
// =============================================================================

const serializer = forthic.grpc.serializer;
const Value = forthic.Value;

test "serializer: serialize and deserialize null" {
    const allocator = testing.allocator;

    const value = Value.initNull();
    const stack_value = try serializer.serializeValue(allocator, value);
    defer if (stack_value) |sv| c_bindings.stackValueDestroy(sv);

    try testing.expect(stack_value != null);

    const deserialized = try serializer.deserializeValue(allocator, stack_value.?);
    defer {
        var mut_val = deserialized;
        mut_val.deinit(allocator);
    }

    try testing.expect(deserialized == .null_value);
}

test "serializer: serialize and deserialize int" {
    const allocator = testing.allocator;

    const value = Value.initInt(42);
    const stack_value = try serializer.serializeValue(allocator, value);
    defer if (stack_value) |sv| c_bindings.stackValueDestroy(sv);

    try testing.expect(stack_value != null);

    const deserialized = try serializer.deserializeValue(allocator, stack_value.?);
    defer {
        var mut_val = deserialized;
        mut_val.deinit(allocator);
    }

    try testing.expectEqual(@as(i64, 42), deserialized.int_value);
}

test "serializer: serialize and deserialize string" {
    const allocator = testing.allocator;

    const str = try allocator.dupe(u8, "hello world");
    const value = Value.initString(str);
    defer {
        var mut_val = value;
        mut_val.deinit(allocator);
    }

    const stack_value = try serializer.serializeValue(allocator, value);
    defer if (stack_value) |sv| c_bindings.stackValueDestroy(sv);

    try testing.expect(stack_value != null);

    const deserialized = try serializer.deserializeValue(allocator, stack_value.?);
    defer {
        var mut_val = deserialized;
        mut_val.deinit(allocator);
    }

    try testing.expect(std.mem.eql(u8, "hello world", deserialized.string_value));
}

test "serializer: serialize and deserialize bool" {
    const allocator = testing.allocator;

    const value = Value.initBool(true);
    const stack_value = try serializer.serializeValue(allocator, value);
    defer if (stack_value) |sv| c_bindings.stackValueDestroy(sv);

    try testing.expect(stack_value != null);

    const deserialized = try serializer.deserializeValue(allocator, stack_value.?);
    defer {
        var mut_val = deserialized;
        mut_val.deinit(allocator);
    }

    try testing.expect(deserialized.bool_value);
}

test "serializer: serialize and deserialize float" {
    const allocator = testing.allocator;

    const value = Value.initFloat(3.14);
    const stack_value = try serializer.serializeValue(allocator, value);
    defer if (stack_value) |sv| c_bindings.stackValueDestroy(sv);

    try testing.expect(stack_value != null);

    const deserialized = try serializer.deserializeValue(allocator, stack_value.?);
    defer {
        var mut_val = deserialized;
        mut_val.deinit(allocator);
    }

    try testing.expectApproxEqAbs(@as(f64, 3.14), deserialized.float_value, 0.001);
}

test "serializer: serialize and deserialize array" {
    const allocator = testing.allocator;

    var arr = std.ArrayList(Value).init(allocator);
    try arr.append(allocator, Value.initInt(1));
    try arr.append(allocator, Value.initInt(2));
    try arr.append(allocator, Value.initInt(3));

    const value = Value{ .array_value = arr };
    defer {
        var mut_val = value;
        mut_val.deinit(allocator);
    }

    const stack_value = try serializer.serializeValue(allocator, value);
    defer if (stack_value) |sv| c_bindings.stackValueDestroy(sv);

    try testing.expect(stack_value != null);

    const deserialized = try serializer.deserializeValue(allocator, stack_value.?);
    defer {
        var mut_val = deserialized;
        mut_val.deinit(allocator);
    }

    try testing.expectEqual(@as(usize, 3), deserialized.array_value.items.len);
    try testing.expectEqual(@as(i64, 1), deserialized.array_value.items[0].int_value);
    try testing.expectEqual(@as(i64, 2), deserialized.array_value.items[1].int_value);
    try testing.expectEqual(@as(i64, 3), deserialized.array_value.items[2].int_value);
}

// =============================================================================
// Client Tests
// =============================================================================

const GrpcClient = forthic.grpc.GrpcClient;

test "client: init and deinit" {
    const allocator = testing.allocator;

    // Note: This will fail to connect since there's no server
    // but we can test that the API works
    const result = GrpcClient.init(allocator, "localhost:50051");

    // We expect this to either succeed (if a server is running) or fail with ConnectionFailed
    if (result) |*client| {
        defer client.deinit();
        // If we got a client, that's fine (server is running)
    } else |err| {
        // Connection failed is expected when no server is running
        try testing.expect(err == error.ConnectionFailed or err == error.Unavailable);
    }
}

test "client: helper constructors" {
    const allocator = testing.allocator;

    // Test localhost helper
    const result1 = forthic.grpc.client.initLocalhost(allocator);
    if (result1) |*client| {
        defer client.deinit();
    } else |_| {
        // Expected to fail without server
    }

    // Test localhost with port helper
    const result2 = forthic.grpc.client.initLocalhostPort(allocator, 50051);
    if (result2) |*client| {
        defer client.deinit();
    } else |_| {
        // Expected to fail without server
    }
}
