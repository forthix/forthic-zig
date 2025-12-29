const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const Value = @import("../forthic/value.zig").Value;
const c_bindings = @import("c_bindings.zig");

// =============================================================================
// Serialization: Forthic Value -> C StackValue
// =============================================================================

/// Serialize a Forthic Value to a C StackValue for gRPC transmission
/// Caller must call c_bindings.stackValueDestroy() on the returned value
pub fn serializeValue(allocator: Allocator, value: Value) !?*c_bindings.StackValue {
    return switch (value) {
        .null_value => c_bindings.stackValueCreateNull(),
        .bool_value => |b| c_bindings.stackValueCreateBool(b),
        .int_value => |i| c_bindings.stackValueCreateInt(i),
        .float_value => |f| c_bindings.stackValueCreateFloat(f),
        .string_value => |s| blk: {
            // Need null-terminated string for C
            const c_str = try allocator.dupeZ(u8, s);
            defer allocator.free(c_str);
            break :blk c_bindings.stackValueCreateString(c_str.ptr);
        },
        .array_value => |arr| try serializeArray(allocator, arr),
        .record_value => |rec| try serializeRecord(allocator, rec),
        .datetime_value => |dt| try serializeDateTime(allocator, dt),
    };
}

fn serializeArray(allocator: Allocator, arr: ArrayList(Value)) !?*c_bindings.StackValue {
    // Serialize each item
    var items = try allocator.alloc(?*c_bindings.StackValue, arr.items.len);
    defer allocator.free(items);

    var serialized_count: usize = 0;
    errdefer {
        // Clean up on error
        for (items[0..serialized_count]) |item| {
            if (item) |sv| c_bindings.stackValueDestroy(sv);
        }
    }

    for (arr.items, 0..) |item, i| {
        items[i] = try serializeValue(allocator, item);
        serialized_count += 1;
    }

    // Create array (cast to non-optional for C API)
    const items_const = try allocator.alloc(*const c_bindings.StackValue, arr.items.len);
    defer allocator.free(items_const);

    for (items, 0..) |item, i| {
        items_const[i] = item orelse return error.SerializationFailed;
    }

    const result = c_bindings.stackValueCreateArray(items_const, arr.items.len);

    // Clean up intermediate items (array has copied them)
    for (items) |item| {
        if (item) |sv| c_bindings.stackValueDestroy(sv);
    }

    return result;
}

fn serializeRecord(allocator: Allocator, rec: StringHashMap(Value)) !?*c_bindings.StackValue {
    // For now, serialize record as an array of [key, value] pairs
    // This matches the pattern from other Forthic implementations

    // Create array to hold key-value pairs
    var pairs = ArrayList(?*c_bindings.StackValue).init(allocator);
    defer pairs.deinit();

    var iter = rec.iterator();
    errdefer {
        // Clean up on error
        for (pairs.items) |pair| {
            if (pair) |sv| c_bindings.stackValueDestroy(sv);
        }
    }

    while (iter.next()) |entry| {
        // Create key-value pair as a 2-element array
        const key_str = try allocator.dupeZ(u8, entry.key_ptr.*);
        defer allocator.free(key_str);

        const key_sv = c_bindings.stackValueCreateString(key_str.ptr) orelse return error.SerializationFailed;
        const value_sv = try serializeValue(allocator, entry.value_ptr.*) orelse return error.SerializationFailed;

        const pair_items = [_]*const c_bindings.StackValue{ key_sv, value_sv };
        const pair_sv = c_bindings.stackValueCreateArray(&pair_items, 2);

        // Clean up intermediate values
        c_bindings.stackValueDestroy(key_sv);
        c_bindings.stackValueDestroy(value_sv);

        try pairs.append(pair_sv);
    }

    // Convert to const slice for C API
    const pairs_const = try allocator.alloc(*const c_bindings.StackValue, pairs.items.len);
    defer allocator.free(pairs_const);

    for (pairs.items, 0..) |pair, i| {
        pairs_const[i] = pair orelse return error.SerializationFailed;
    }

    const result = c_bindings.stackValueCreateArray(pairs_const, pairs.items.len);

    // Clean up intermediate pairs
    for (pairs.items) |pair| {
        if (pair) |sv| c_bindings.stackValueDestroy(sv);
    }

    return result;
}

fn serializeDateTime(allocator: Allocator, dt: anytype) !?*c_bindings.StackValue {
    // For now, serialize datetime as ISO8601 string
    // TODO: Use proper instant_value once protobuf support is added
    _ = allocator;
    _ = dt;
    // Placeholder: return null for now
    return c_bindings.stackValueCreateNull();
}

// =============================================================================
// Deserialization: C StackValue -> Forthic Value
// =============================================================================

/// Deserialize a C StackValue to a Forthic Value
/// Caller owns the returned Value and must call deinit() on it
pub fn deserializeValue(allocator: Allocator, stack_value: *const c_bindings.StackValue) !Value {
    const value_type = c_bindings.stackValueGetType(stack_value);

    return switch (value_type) {
        c_bindings.STACK_VALUE_NULL => Value.initNull(),
        c_bindings.STACK_VALUE_BOOL => Value.initBool(c_bindings.stackValueGetBool(stack_value)),
        c_bindings.STACK_VALUE_INT => Value.initInt(c_bindings.stackValueGetInt(stack_value)),
        c_bindings.STACK_VALUE_FLOAT => Value.initFloat(c_bindings.stackValueGetFloat(stack_value)),
        c_bindings.STACK_VALUE_STRING => blk: {
            const c_str = c_bindings.stackValueGetString(stack_value);
            const str = try allocator.dupe(u8, std.mem.span(c_str));
            break :blk Value.initString(str);
        },
        c_bindings.STACK_VALUE_ARRAY => try deserializeArray(allocator, stack_value),
        c_bindings.STACK_VALUE_RECORD => try deserializeRecord(allocator, stack_value),
        c_bindings.STACK_VALUE_INSTANT,
        c_bindings.STACK_VALUE_PLAIN_DATE,
        c_bindings.STACK_VALUE_ZONED_DATETIME,
        => {
            // TODO: Implement proper datetime deserialization
            return Value.initNull();
        },
        else => error.UnknownStackValueType,
    };
}

fn deserializeArray(allocator: Allocator, stack_value: *const c_bindings.StackValue) !Value {
    var array_items = c_bindings.stackValueGetArray(stack_value);
    defer array_items.deinit();

    var arr = ArrayList(Value).init(allocator);
    errdefer {
        for (arr.items) |*item| {
            item.deinit(allocator);
        }
        arr.deinit();
    }

    try arr.ensureTotalCapacity(allocator, array_items.len);

    for (array_items.items) |item| {
        const value = try deserializeValue(allocator, item);
        try arr.append(allocator, value);
    }

    return Value{ .array_value = arr };
}

fn deserializeRecord(allocator: Allocator, stack_value: *const c_bindings.StackValue) !Value {
    // Record is serialized as an array of [key, value] pairs
    var array_items = c_bindings.stackValueGetArray(stack_value);
    defer array_items.deinit();

    var rec = StringHashMap(Value).init(allocator);
    errdefer {
        var iter = rec.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        rec.deinit();
    }

    for (array_items.items) |pair_sv| {
        // Each pair should be a 2-element array [key, value]
        var pair_items = c_bindings.stackValueGetArray(pair_sv);
        defer pair_items.deinit();

        if (pair_items.len != 2) {
            return error.InvalidRecordFormat;
        }

        // Get key (should be string)
        const key_type = c_bindings.stackValueGetType(pair_items.items[0]);
        if (key_type != c_bindings.STACK_VALUE_STRING) {
            return error.InvalidRecordKeyType;
        }

        const c_key = c_bindings.stackValueGetString(pair_items.items[0]);
        const key = try allocator.dupe(u8, std.mem.span(c_key));
        errdefer allocator.free(key);

        // Get value
        const value = try deserializeValue(allocator, pair_items.items[1]);
        errdefer value.deinit(allocator);

        try rec.put(key, value);
    }

    return Value{ .record_value = rec };
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Serialize a slice of Values to a slice of StackValues
/// Caller must call freeStackValueArray() on the returned slice
pub fn serializeValueSlice(allocator: Allocator, values: []const Value) ![]?*c_bindings.StackValue {
    var stack_values = try allocator.alloc(?*c_bindings.StackValue, values.len);
    errdefer allocator.free(stack_values);

    var serialized_count: usize = 0;
    errdefer {
        for (stack_values[0..serialized_count]) |sv| {
            if (sv) |val| c_bindings.stackValueDestroy(val);
        }
    }

    for (values, 0..) |value, i| {
        stack_values[i] = try serializeValue(allocator, value);
        serialized_count += 1;
    }

    return stack_values;
}

/// Deserialize a slice of StackValues to a slice of Values
/// Caller owns the returned Values and must call deinit() on each
pub fn deserializeValueSlice(allocator: Allocator, stack_values: []const *c_bindings.StackValue) ![]Value {
    var values = try allocator.alloc(Value, stack_values.len);
    errdefer allocator.free(values);

    var deserialized_count: usize = 0;
    errdefer {
        for (values[0..deserialized_count]) |*val| {
            val.deinit(allocator);
        }
    }

    for (stack_values, 0..) |stack_value, i| {
        values[i] = try deserializeValue(allocator, stack_value);
        deserialized_count += 1;
    }

    return values;
}

/// Free an array of StackValues
pub fn freeStackValueArray(allocator: Allocator, stack_values: []?*c_bindings.StackValue) void {
    for (stack_values) |sv| {
        if (sv) |val| c_bindings.stackValueDestroy(val);
    }
    allocator.free(stack_values);
}
