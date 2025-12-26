const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// ============================================================================
/// Type Checking Utilities
/// ============================================================================

pub const ValueType = enum {
    int,
    float,
    string,
    bool,
    array,
    record,
    null_value,
    unknown,
};

pub fn getValueType(value: anytype) ValueType {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    return switch (info) {
        .Int => .int,
        .Float => .float,
        .Bool => .bool,
        .Pointer => |ptr| {
            if (ptr.size == .Slice) {
                if (ptr.child == u8) {
                    return .string;
                }
                return .array;
            }
            return .unknown;
        },
        .Struct => .record,
        .Null => .null_value,
        .Optional => |opt| {
            if (@typeInfo(opt.child) == .Null) {
                return .null_value;
            }
            return .unknown;
        },
        else => .unknown,
    };
}

pub fn isInt(value: anytype) bool {
    return getValueType(value) == .int;
}

pub fn isFloat(value: anytype) bool {
    return getValueType(value) == .float;
}

pub fn isString(value: anytype) bool {
    return getValueType(value) == .string;
}

pub fn isBool(value: anytype) bool {
    return getValueType(value) == .bool;
}

pub fn isArray(value: anytype) bool {
    return getValueType(value) == .array;
}

pub fn isRecord(value: anytype) bool {
    return getValueType(value) == .record;
}

/// ============================================================================
/// Type Conversion Utilities
/// ============================================================================

pub fn toInt(allocator: Allocator, value: anytype) !i64 {
    _ = allocator;
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    return switch (info) {
        .Int => @intCast(value),
        .Float => @intFromFloat(value),
        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                // String to int
                return std.fmt.parseInt(i64, value, 10);
            }
            return error.InvalidFormat;
        },
        else => error.InvalidFormat,
    };
}

pub fn toFloat(allocator: Allocator, value: anytype) !f64 {
    _ = allocator;
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    return switch (info) {
        .Float => @floatCast(value),
        .Int => @floatFromInt(value),
        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                // String to float
                return std.fmt.parseFloat(f64, value);
            }
            return error.InvalidFormat;
        },
        else => error.InvalidFormat,
    };
}

pub fn toString(allocator: Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    return switch (info) {
        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return allocator.dupe(u8, value);
            }
            return try std.fmt.allocPrint(allocator, "{any}", .{value});
        },
        .Bool => if (value) try allocator.dupe(u8, "true") else try allocator.dupe(u8, "false"),
        .Int => try std.fmt.allocPrint(allocator, "{d}", .{value}),
        .Float => try std.fmt.allocPrint(allocator, "{d}", .{value}),
        .Null => try allocator.dupe(u8, "null"),
        .Optional => {
            if (value) |v| {
                return toString(allocator, v);
            } else {
                return try allocator.dupe(u8, "null");
            }
        },
        else => try std.fmt.allocPrint(allocator, "{any}", .{value}),
    };
}

/// ============================================================================
/// String Utilities
/// ============================================================================

pub fn trim(allocator: Allocator, s: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, s, &std.ascii.whitespace);
    return allocator.dupe(u8, trimmed);
}

pub fn split(allocator: Allocator, s: []const u8, sep: []const u8) !ArrayList([]const u8) {
    var result = ArrayList([]const u8).init(allocator);

    if (sep.len == 0) {
        // Split into individual characters
        for (s) |c| {
            const char_slice = try allocator.alloc(u8, 1);
            char_slice[0] = c;
            try result.append(char_slice);
        }
        return result;
    }

    var iter = std.mem.split(u8, s, sep);
    while (iter.next()) |part| {
        const part_copy = try allocator.dupe(u8, part);
        try result.append(part_copy);
    }

    return result;
}

pub fn join(allocator: Allocator, parts: []const []const u8, sep: []const u8) ![]const u8 {
    if (parts.len == 0) {
        return try allocator.dupe(u8, "");
    }

    // Calculate total length
    var total_len: usize = 0;
    for (parts, 0..) |part, i| {
        total_len += part.len;
        if (i < parts.len - 1) {
            total_len += sep.len;
        }
    }

    // Allocate and build result
    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (parts, 0..) |part, i| {
        @memcpy(result[pos .. pos + part.len], part);
        pos += part.len;
        if (i < parts.len - 1) {
            @memcpy(result[pos .. pos + sep.len], sep);
            pos += sep.len;
        }
    }

    return result;
}

pub fn replace(allocator: Allocator, s: []const u8, old: []const u8, new: []const u8) ![]const u8 {
    if (old.len == 0) {
        return allocator.dupe(u8, s);
    }

    // Count occurrences
    var count: usize = 0;
    var pos: usize = 0;
    while (pos + old.len <= s.len) {
        if (std.mem.eql(u8, s[pos .. pos + old.len], old)) {
            count += 1;
            pos += old.len;
        } else {
            pos += 1;
        }
    }

    if (count == 0) {
        return allocator.dupe(u8, s);
    }

    // Calculate new length and allocate
    const new_len = s.len - (count * old.len) + (count * new.len);
    var result = try allocator.alloc(u8, new_len);

    // Build result
    var src_pos: usize = 0;
    var dst_pos: usize = 0;
    while (src_pos < s.len) {
        if (src_pos + old.len <= s.len and std.mem.eql(u8, s[src_pos .. src_pos + old.len], old)) {
            @memcpy(result[dst_pos .. dst_pos + new.len], new);
            src_pos += old.len;
            dst_pos += new.len;
        } else {
            result[dst_pos] = s[src_pos];
            src_pos += 1;
            dst_pos += 1;
        }
    }

    return result;
}

/// ============================================================================
/// Date/Time Utilities
/// ============================================================================

pub const DateTime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

/// Parse date in YYYY-MM-DD format
/// Supports wildcards: YYYY-**-**, ****-MM-**, ****-**-DD
pub fn parseDate(s: []const u8) !DateTime {
    if (std.mem.indexOf(u8, s, "*")) |_| {
        return parseDateWithWildcards(s);
    }

    // Standard parsing
    var iter = std.mem.split(u8, s, "-");
    const year_str = iter.next() orelse return error.InvalidFormat;
    const month_str = iter.next() orelse return error.InvalidFormat;
    const day_str = iter.next() orelse return error.InvalidFormat;

    const year = try std.fmt.parseInt(i32, year_str, 10);
    const month = try std.fmt.parseInt(u8, month_str, 10);
    const day = try std.fmt.parseInt(u8, day_str, 10);

    return DateTime{
        .year = year,
        .month = month,
        .day = day,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
}

fn parseDateWithWildcards(s: []const u8) !DateTime {
    const now = std.time.timestamp();
    const epoch_day = @divFloor(now, 86400);
    const days_since_epoch: i32 = @intCast(epoch_day);

    // Simplified: assume 2024-01-01 as baseline
    const now_year: i32 = 2024 + @divFloor(days_since_epoch, 365);
    const now_month: u8 = @intCast(@mod(@divFloor(days_since_epoch, 30), 12) + 1);
    const now_day: u8 = @intCast(@mod(days_since_epoch, 30) + 1);

    var iter = std.mem.split(u8, s, "-");
    const year_str = iter.next() orelse return error.InvalidFormat;
    const month_str = iter.next() orelse return error.InvalidFormat;
    const day_str = iter.next() orelse return error.InvalidFormat;

    const year = if (std.mem.eql(u8, year_str, "****"))
        now_year
    else
        try std.fmt.parseInt(i32, year_str, 10);

    const month = if (std.mem.eql(u8, month_str, "**"))
        now_month
    else
        try std.fmt.parseInt(u8, month_str, 10);

    const day = if (std.mem.eql(u8, day_str, "**"))
        now_day
    else
        try std.fmt.parseInt(u8, day_str, 10);

    return DateTime{
        .year = year,
        .month = month,
        .day = day,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
}

/// Parse time in HH:MM or HH:MM:SS format
/// Also supports 12-hour format with AM/PM (e.g., "2:30 PM")
pub fn parseTime(s: []const u8) !DateTime {
    const trimmed = std.mem.trim(u8, s, &std.ascii.whitespace);

    // Check for AM/PM format
    if (std.mem.indexOf(u8, trimmed, "AM") != null or std.mem.indexOf(u8, trimmed, "PM") != null) {
        return parseTime12Hour(trimmed);
    }

    // Parse 24-hour format
    var iter = std.mem.split(u8, trimmed, ":");
    const hour_str = iter.next() orelse return error.InvalidFormat;
    const minute_str = iter.next() orelse return error.InvalidFormat;
    const second_str = iter.next();

    const hour = try std.fmt.parseInt(u8, hour_str, 10);
    const minute = try std.fmt.parseInt(u8, minute_str, 10);
    const second = if (second_str) |s_str| try std.fmt.parseInt(u8, s_str, 10) else 0;

    return DateTime{
        .year = 0,
        .month = 1,
        .day = 1,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

fn parseTime12Hour(s: []const u8) !DateTime {
    const is_pm = std.mem.indexOf(u8, s, "PM") != null;

    // Extract time part (before AM/PM)
    const time_end = std.mem.indexOf(u8, s, " ") orelse s.len;
    const time_part = s[0..time_end];

    var iter = std.mem.split(u8, time_part, ":");
    const hour_str = iter.next() orelse return error.InvalidFormat;
    const minute_str = iter.next() orelse return error.InvalidFormat;

    var hour = try std.fmt.parseInt(u8, hour_str, 10);
    const minute = try std.fmt.parseInt(u8, minute_str, 10);

    // Convert to 24-hour format
    if (is_pm and hour < 12) {
        hour += 12;
    } else if (!is_pm and hour == 12) {
        hour = 0;
    }

    return DateTime{
        .year = 0,
        .month = 1,
        .day = 1,
        .hour = hour,
        .minute = minute,
        .second = 0,
    };
}

/// Format date as YYYY-MM-DD
pub fn formatDate(allocator: Allocator, dt: DateTime) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ dt.year, dt.month, dt.day });
}

/// Format time as HH:MM
pub fn formatTime(allocator: Allocator, dt: DateTime) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}", .{ dt.hour, dt.minute });
}

/// Format datetime as RFC3339
pub fn formatDateTime(allocator: Allocator, dt: DateTime) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second,
    });
}

/// Parse RFC3339 datetime string
pub fn parseDateTime(s: []const u8) !DateTime {
    // Simple RFC3339 parsing (YYYY-MM-DDTHH:MM:SSZ)
    if (s.len < 19) return error.InvalidFormat;

    const year = try std.fmt.parseInt(i32, s[0..4], 10);
    const month = try std.fmt.parseInt(u8, s[5..7], 10);
    const day = try std.fmt.parseInt(u8, s[8..10], 10);
    const hour = try std.fmt.parseInt(u8, s[11..13], 10);
    const minute = try std.fmt.parseInt(u8, s[14..16], 10);
    const second = try std.fmt.parseInt(u8, s[17..19], 10);

    return DateTime{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

/// Convert date to YYYYMMDD integer format
pub fn dateToInt(dt: DateTime) i64 {
    return @as(i64, dt.year) * 10000 + @as(i64, dt.month) * 100 + @as(i64, dt.day);
}

/// Convert YYYYMMDD integer to date
pub fn intToDate(n: i64) DateTime {
    const year: i32 = @intCast(@divFloor(n, 10000));
    const month: u8 = @intCast(@mod(@divFloor(n, 100), 100));
    const day: u8 = @intCast(@mod(n, 100));

    return DateTime{
        .year = year,
        .month = month,
        .day = day,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
}
