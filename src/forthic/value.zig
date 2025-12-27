const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const utils = @import("utils.zig");

/// Runtime value type for Forthic - idiomatic Zig tagged union
/// Similar to std.json.Value
pub const Value = union(enum) {
    null_value,
    bool_value: bool,
    int_value: i64,
    float_value: f64,
    string_value: []const u8,
    array_value: ArrayList(Value),
    record_value: StringHashMap(Value),
    datetime_value: utils.DateTime,

    /// Create null value
    pub fn initNull() Value {
        return .null_value;
    }

    /// Create bool value
    pub fn initBool(b: bool) Value {
        return .{ .bool_value = b };
    }

    /// Create int value
    pub fn initInt(i: i64) Value {
        return .{ .int_value = i };
    }

    /// Create float value
    pub fn initFloat(f: f64) Value {
        return .{ .float_value = f };
    }

    /// Create string value (takes ownership)
    pub fn initString(s: []const u8) Value {
        return .{ .string_value = s };
    }

    /// Create empty array
    pub fn initArray(allocator: Allocator) Value {
        _ = allocator;
        return .{ .array_value = std.ArrayList(Value){} };
    }

    /// Create empty record
    pub fn initRecord(allocator: Allocator) Value {
        return .{ .record_value = StringHashMap(Value).init(allocator) };
    }

    /// Create datetime value
    pub fn initDateTime(dt: utils.DateTime) Value {
        return .{ .datetime_value = dt };
    }

    /// Deep copy a value
    pub fn clone(self: *const Value, allocator: Allocator) !Value {
        return switch (self.*) {
            .null_value => .null_value,
            .bool_value => |b| .{ .bool_value = b },
            .int_value => |i| .{ .int_value = i },
            .float_value => |f| .{ .float_value = f },
            .string_value => |s| .{ .string_value = try allocator.dupe(u8, s) },
            .datetime_value => |dt| .{ .datetime_value = dt },
            .array_value => |arr| {
                var new_arr: std.ArrayList(Value) = .{};
                try new_arr.ensureTotalCapacity(allocator, arr.items.len);
                for (arr.items) |item| {
                    try new_arr.append(allocator, try item.clone(allocator));
                }
                return .{ .array_value = new_arr };
            },
            .record_value => |rec| {
                var new_rec = StringHashMap(Value).init(allocator);
                try new_rec.ensureTotalCapacity(rec.count());
                var iter = rec.iterator();
                while (iter.next()) |entry| {
                    const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                    const val_copy = try entry.value_ptr.clone(allocator);
                    try new_rec.put(key_copy, val_copy);
                }
                return .{ .record_value = new_rec };
            },
        };
    }

    /// Free memory associated with value
    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self.*) {
            .string_value => |s| allocator.free(s),
            .array_value => |*arr| {
                for (arr.items) |*item| {
                    item.deinit(allocator);
                }
                arr.deinit(allocator);
            },
            .record_value => |*rec| {
                var iter = rec.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                rec.deinit();
            },
            else => {},
        }
    }

    /// Check if value is truthy (for boolean operations)
    pub fn isTruthy(self: *const Value) bool {
        return switch (self.*) {
            .null_value => false,
            .bool_value => |b| b,
            .int_value => |i| i != 0,
            .float_value => |f| f != 0.0,
            .string_value => |s| s.len > 0,
            .array_value => |arr| arr.items.len > 0,
            .record_value => |rec| rec.count() > 0,
            .datetime_value => true,
        };
    }

    /// Convert to number if possible
    pub fn toNumber(self: *const Value) ?f64 {
        return switch (self.*) {
            .int_value => |i| @floatFromInt(i),
            .float_value => |f| f,
            .bool_value => |b| if (b) 1.0 else 0.0,
            .string_value => |s| std.fmt.parseFloat(f64, s) catch null,
            else => null,
        };
    }

    /// Convert to integer if possible
    pub fn toInt(self: *const Value) ?i64 {
        return switch (self.*) {
            .int_value => |i| i,
            .float_value => |f| @intFromFloat(f),
            .bool_value => |b| if (b) @as(i64, 1) else @as(i64, 0),
            .string_value => |s| std.fmt.parseInt(i64, s, 10) catch null,
            else => null,
        };
    }

    /// Convert to string (allocates new string)
    pub fn toString(self: *const Value, allocator: Allocator) ![]const u8 {
        return switch (self.*) {
            .null_value => try allocator.dupe(u8, ""),
            .bool_value => |b| try allocator.dupe(u8, if (b) "true" else "false"),
            .int_value => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float_value => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
            .string_value => |s| try allocator.dupe(u8, s),
            .array_value => try allocator.dupe(u8, "[Array]"),
            .record_value => try allocator.dupe(u8, "{Record}"),
            .datetime_value => |dt| try std.fmt.allocPrint(
                allocator,
                "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
                .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second },
            ),
        };
    }

    /// Compare two values for equality
    pub fn equals(self: *const Value, other: *const Value) bool {
        // Different types are never equal (except numeric coercion)
        const self_tag = @as(std.meta.Tag(Value), self.*);
        const other_tag = @as(std.meta.Tag(Value), other.*);

        // Numeric coercion: int and float can be compared
        if ((self_tag == .int_value or self_tag == .float_value) and
            (other_tag == .int_value or other_tag == .float_value))
        {
            const a = self.toNumber() orelse return false;
            const b = other.toNumber() orelse return false;
            return @abs(a - b) < std.math.floatEps(f64);
        }

        // Same tag comparison
        if (self_tag != other_tag) return false;

        return switch (self.*) {
            .null_value => true,
            .bool_value => |a| a == other.bool_value,
            .int_value => |a| a == other.int_value,
            .float_value => |a| @abs(a - other.float_value) < std.math.floatEps(f64),
            .string_value => |a| std.mem.eql(u8, a, other.string_value),
            .datetime_value => |a| {
                const b = other.datetime_value;
                return a.year == b.year and a.month == b.month and
                    a.day == b.day and a.hour == b.hour and
                    a.minute == b.minute and a.second == b.second;
            },
            .array_value => |a| {
                const b = other.array_value;
                if (a.items.len != b.items.len) return false;
                for (a.items, b.items) |*item_a, *item_b| {
                    if (!item_a.equals(item_b)) return false;
                }
                return true;
            },
            .record_value => {
                // Simplified record comparison
                return false; // Full implementation would compare all keys
            },
        };
    }
};
