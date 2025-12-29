const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("../../value.zig").Value;

/// Common helper functions shared across standard modules
pub const Helpers = struct {
    pub fn isTruthy(val: Value) bool {
        return switch (val) {
            .null_value => false,
            .bool_value => |b| b,
            .int_value => |i| i != 0,
            .float_value => |f| f != 0.0,
            .string_value => |s| s.len > 0,
            .array_value => |a| a.items.len > 0,
            .record_value => |r| r.count() > 0,
            .datetime_value => true,
        };
    }

    pub fn areEqual(a: Value, b: Value) bool {
        // Simple equality check - can be expanded
        return std.meta.eql(a, b);
    }

    pub fn toNumber(val: Value) ?f64 {
        return switch (val) {
            .null_value => null,
            .bool_value => |b| if (b) 1.0 else 0.0,
            .int_value => |i| @floatFromInt(i),
            .float_value => |f| f,
            .string_value => |s| std.fmt.parseFloat(f64, s) catch null,
            else => null,
        };
    }

    pub fn toString(allocator: Allocator, val: Value) ![]const u8 {
        return switch (val) {
            .null_value => try allocator.dupe(u8, ""),
            .bool_value => |b| if (b) try allocator.dupe(u8, "TRUE") else try allocator.dupe(u8, "FALSE"),
            .int_value => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float_value => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
            .string_value => |s| try allocator.dupe(u8, s),
            else => try allocator.dupe(u8, ""),
        };
    }

    pub fn toInt(val: Value) i64 {
        return switch (val) {
            .null_value => 0,
            .bool_value => |b| if (b) 1 else 0,
            .int_value => |i| i,
            .float_value => |f| @intFromFloat(f),
            .string_value => |s| std.fmt.parseInt(i64, s, 10) catch 0,
            else => 0,
        };
    }

    pub fn toLowerCase(allocator: Allocator, val: Value) ![]const u8 {
        const str = try toString(allocator, val);
        defer allocator.free(str);
        const result = try allocator.alloc(u8, str.len);
        for (str, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return result;
    }
};
