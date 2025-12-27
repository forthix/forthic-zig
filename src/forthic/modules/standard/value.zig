const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const utils = @import("../../utils.zig");
const DateTime = utils.DateTime;

/// Runtime value type for Forthic standard library
/// This provides type-safe value discrimination for module operations
pub const Value = union(enum) {
    null_value,
    bool_value: bool,
    int_value: i64,
    float_value: f64,
    string_value: []const u8,
    array_value: ArrayList(*Value),
    record_value: StringHashMap(*Value),
    datetime_value: DateTime,

    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self.*) {
            .array_value => |*arr| {
                for (arr.items) |item| {
                    item.deinit(allocator);
                    allocator.destroy(item);
                }
                arr.deinit();
            },
            .record_value => |*rec| {
                var iter = rec.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.*.deinit(allocator);
                    allocator.destroy(entry.value_ptr.*);
                }
                rec.deinit();
            },
            .string_value => |str| {
                allocator.free(str);
            },
            else => {},
        }
    }

    /// Convert anyopaque pointer to Value (best effort)
    pub fn fromAnyopaque(ptr: ?*anyopaque) ?*Value {
        if (ptr == null) return null;
        // This is unsafe but necessary for the current architecture
        return @ptrCast(@alignCast(ptr));
    }

    /// Convert Value to anyopaque pointer
    pub fn toAnyopaque(self: *Value) ?*anyopaque {
        return @ptrCast(self);
    }

    /// Check if value is truthy
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
            else => null,
        };
    }

    /// Convert to integer if possible
    pub fn toInt(self: *const Value) ?i64 {
        return switch (self.*) {
            .int_value => |i| i,
            .float_value => |f| @intFromFloat(f),
            .bool_value => |b| if (b) 1 else 0,
            else => null,
        };
    }

    /// Convert to string (allocates)
    pub fn toString(self: *const Value, allocator: Allocator) ![]const u8 {
        return switch (self.*) {
            .null_value => try allocator.dupe(u8, ""),
            .bool_value => |b| try allocator.dupe(u8, if (b) "true" else "false"),
            .int_value => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float_value => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
            .string_value => |s| try allocator.dupe(u8, s),
            .array_value => try allocator.dupe(u8, "[array]"),
            .record_value => try allocator.dupe(u8, "{record}"),
            .datetime_value => |dt| try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second }),
        };
    }
};
