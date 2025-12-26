const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");

/// ============================================================================
/// Literal Handler Type
/// ============================================================================

/// Literal handler: takes string, returns parsed value or null if can't parse
pub const LiteralHandler = *const fn (allocator: Allocator, str: []const u8) anyerror!?LiteralValue;

/// Value types that can be returned by literal handlers
pub const LiteralValue = union(enum) {
    bool_value: bool,
    int_value: i64,
    float_value: f64,
    time_value: utils.DateTime,
    date_value: utils.DateTime,
    datetime_value: utils.DateTime,
};

/// ============================================================================
/// Boolean Literals
/// ============================================================================

/// Parse boolean literals: TRUE, FALSE
pub fn toBool(allocator: Allocator, str: []const u8) !?LiteralValue {
    _ = allocator;
    if (std.mem.eql(u8, str, "TRUE")) {
        return LiteralValue{ .bool_value = true };
    }
    if (std.mem.eql(u8, str, "FALSE")) {
        return LiteralValue{ .bool_value = false };
    }
    return null;
}

/// ============================================================================
/// Numeric Literals
/// ============================================================================

/// Parse float literals: 3.14, -2.5, 0.0
/// Must contain a decimal point
pub fn toFloat(allocator: Allocator, str: []const u8) !?LiteralValue {
    _ = allocator;
    if (std.mem.indexOf(u8, str, ".") == null) {
        return null;
    }
    const result = std.fmt.parseFloat(f64, str) catch return null;
    return LiteralValue{ .float_value = result };
}

/// Parse integer literals: 42, -10, 0
/// Must not contain a decimal point
pub fn toInt(allocator: Allocator, str: []const u8) !?LiteralValue {
    if (std.mem.indexOf(u8, str, ".") != null) {
        return null;
    }
    const result = std.fmt.parseInt(i64, str, 10) catch return null;

    // Verify it's actually an integer string (not "42abc")
    var buf: [32]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, "{d}", .{result});
    if (!std.mem.eql(u8, formatted, str)) {
        return null;
    }

    _ = allocator;
    return LiteralValue{ .int_value = result };
}

/// ============================================================================
/// Time Literals
/// ============================================================================

/// Parse time literals: 9:00, 11:30 PM, 22:15
pub fn toTime(allocator: Allocator, str: []const u8) !?LiteralValue {
    _ = allocator;

    // Try to parse HH:MM AM/PM format
    if (std.mem.indexOf(u8, str, "AM") != null or std.mem.indexOf(u8, str, "PM") != null) {
        return parseTime12Hour(str);
    }

    // Try to parse HH:MM format
    return parseTime24Hour(str);
}

fn parseTime24Hour(str: []const u8) !?LiteralValue {
    var iter = std.mem.splitScalar(u8, str, ':');
    const hour_str = iter.next() orelse return null;
    const minute_str = iter.next() orelse return null;

    const hours = std.fmt.parseInt(u8, hour_str, 10) catch return null;
    const minutes = std.fmt.parseInt(u8, minute_str, 10) catch return null;

    if (hours > 23 or minutes >= 60) {
        return null;
    }

    return LiteralValue{
        .time_value = utils.DateTime{
            .year = 0,
            .month = 1,
            .day = 1,
            .hour = hours,
            .minute = minutes,
            .second = 0,
        },
    };
}

fn parseTime12Hour(str: []const u8) !?LiteralValue {
    const is_pm = std.mem.indexOf(u8, str, "PM") != null;

    // Find the space before AM/PM
    const space_pos = std.mem.indexOf(u8, str, " ") orelse str.len;
    const time_part = str[0..space_pos];

    var iter = std.mem.splitScalar(u8, time_part, ':');
    const hour_str = iter.next() orelse return null;
    const minute_str = iter.next() orelse return null;

    var hours = std.fmt.parseInt(u8, hour_str, 10) catch return null;
    const minutes = std.fmt.parseInt(u8, minute_str, 10) catch return null;

    // Convert to 24-hour format
    if (is_pm and hours < 12) {
        hours += 12;
    } else if (!is_pm and hours == 12) {
        hours = 0;
    }

    if (hours > 23 or minutes >= 60) {
        return null;
    }

    return LiteralValue{
        .time_value = utils.DateTime{
            .year = 0,
            .month = 1,
            .day = 1,
            .hour = hours,
            .minute = minutes,
            .second = 0,
        },
    };
}

/// ============================================================================
/// Date Literals
/// ============================================================================

/// Parse date literals: 2020-06-05, YYYY-MM-DD (with wildcards)
pub fn toLiteralDate(allocator: Allocator, str: []const u8) !?LiteralValue {
    _ = allocator;

    // Check if it matches YYYY-MM-DD format
    if (str.len != 10) return null;
    if (str[4] != '-' or str[7] != '-') return null;

    // Get current date for wildcards
    const now = std.time.timestamp();
    const epoch_day = @divFloor(now, 86400);
    const days_since_epoch: i32 = @intCast(epoch_day);

    // Simplified: assume 2024-01-01 as baseline
    const now_year: i32 = 2024 + @divFloor(days_since_epoch, 365);
    const now_month: u8 = @intCast(@mod(@divFloor(days_since_epoch, 30), 12) + 1);
    const now_day: u8 = @intCast(@mod(days_since_epoch, 30) + 1);

    const year_str = str[0..4];
    const month_str = str[5..7];
    const day_str = str[8..10];

    const year = if (std.mem.eql(u8, year_str, "YYYY"))
        now_year
    else
        std.fmt.parseInt(i32, year_str, 10) catch return null;

    const month = if (std.mem.eql(u8, month_str, "MM"))
        now_month
    else
        std.fmt.parseInt(u8, month_str, 10) catch return null;

    const day = if (std.mem.eql(u8, day_str, "DD"))
        now_day
    else
        std.fmt.parseInt(u8, day_str, 10) catch return null;

    return LiteralValue{
        .date_value = utils.DateTime{
            .year = year,
            .month = month,
            .day = day,
            .hour = 0,
            .minute = 0,
            .second = 0,
        },
    };
}

/// ============================================================================
/// ZonedDateTime Literals
/// ============================================================================

/// Parse zoned datetime literals
/// - 2025-05-24T10:15:00[America/Los_Angeles] (IANA named timezone, RFC 9557)
/// - 2025-05-24T10:15:00Z (UTC)
/// - 2025-05-24T10:15:00-05:00 (offset timezone)
/// - 2025-05-24T10:15:00 (uses default timezone)
pub fn toZonedDateTime(allocator: Allocator, str: []const u8) !?LiteralValue {
    _ = allocator;

    if (std.mem.indexOf(u8, str, "T") == null) {
        return null;
    }

    // Handle IANA named timezone in bracket notation (RFC 9557)
    if (std.mem.indexOf(u8, str, "[") != null and std.mem.endsWith(u8, str, "]")) {
        return parseDateTimeWithBracket(str);
    }

    // Handle explicit UTC (Z suffix)
    if (std.mem.endsWith(u8, str, "Z")) {
        return parseDateTimeUTC(str);
    }

    // Handle explicit timezone offset or no timezone
    if (hasTimezoneOffset(str)) {
        return parseDateTimeWithOffset(str);
    }

    // No timezone specified, parse as plain datetime
    return parsePlainDateTime(str);
}

fn parseDateTimeWithBracket(str: []const u8) !?LiteralValue {
    const bracket_start = std.mem.indexOf(u8, str, "[") orelse return null;
    const dt_str = str[0..bracket_start];

    // Try parsing datetime part (could have offset)
    if (hasTimezoneOffset(dt_str)) {
        return parseIso8601DateTime(dt_str);
    }

    // No offset, parse as plain datetime
    return parseIso8601DateTime(dt_str);
}

fn parseDateTimeUTC(str: []const u8) !?LiteralValue {
    const dt_str = str[0 .. str.len - 1]; // Remove 'Z'
    return parseIso8601DateTime(dt_str);
}

fn parseDateTimeWithOffset(str: []const u8) !?LiteralValue {
    return parseIso8601DateTime(str);
}

fn parsePlainDateTime(str: []const u8) !?LiteralValue {
    return parseIso8601DateTime(str);
}

fn parseIso8601DateTime(str: []const u8) !?LiteralValue {
    // Simple ISO 8601 parsing: YYYY-MM-DDTHH:MM:SS
    // Minimum length: "2025-01-01T00:00:00" = 19 chars
    if (str.len < 19) return null;

    // Remove timezone offset if present for basic parsing
    var clean_str = str;
    const plus_pos = std.mem.indexOf(u8, str, "+");
    const dash_pos = std.mem.lastIndexOf(u8, str, "-");

    if (plus_pos) |pos| {
        if (pos > 10) { // After the date part
            clean_str = str[0..pos];
        }
    } else if (dash_pos) |pos| {
        if (pos > 10) { // After the date part
            clean_str = str[0..pos];
        }
    }

    // Parse: YYYY-MM-DDTHH:MM:SS
    if (clean_str.len < 19) return null;

    const year = std.fmt.parseInt(i32, clean_str[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, clean_str[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, clean_str[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, clean_str[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u8, clean_str[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u8, clean_str[17..19], 10) catch return null;

    return LiteralValue{
        .datetime_value = utils.DateTime{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
        },
    };
}

fn hasTimezoneOffset(str: []const u8) bool {
    // Check for +HH:MM or -HH:MM at the end
    if (str.len < 6) return false;

    const last_6 = str[str.len - 6 ..];
    if (last_6[0] == '+' or last_6[0] == '-') {
        if (last_6[3] == ':') {
            return true;
        }
    }
    return false;
}
