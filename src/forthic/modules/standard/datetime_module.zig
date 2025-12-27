const std = @import("std");
const Allocator = std.mem.Allocator;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;
const Value = @import("../../value.zig").Value;
const utils = @import("../../utils.zig");
const DateTime = utils.DateTime;

pub const DateTimeModule = struct {
    module: Module,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*DateTimeModule {
        const self = try allocator.create(DateTimeModule);
        self.* = .{
            .module = try Module.init(allocator, "datetime", ""),
            .allocator = allocator,
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *DateTimeModule) void {
        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn registerWords(self: *DateTimeModule) !void {
        try self.module.addWord(">DATE", toDate);
        try self.module.addWord(">DATETIME", toDateTime);
        try self.module.addWord("DATE>STR", dateToStr);
        try self.module.addWord("DATETIME>STR", dateTimeToStr);
        try self.module.addWord("ADD-DAYS", addDays);
        try self.module.addWord("ADD-HOURS", addHours);
        try self.module.addWord("ADD-MINUTES", addMinutes);
        try self.module.addWord("ADD-SECONDS", addSeconds);
        try self.module.addWord("DIFF-DAYS", diffDays);
        try self.module.addWord("DIFF-HOURS", diffHours);
        try self.module.addWord("DIFF-MINUTES", diffMinutes);
        try self.module.addWord("DIFF-SECONDS", diffSeconds);
        try self.module.addWord("NOW", now);
        try self.module.addWord("TODAY", today);
        try self.module.addWord("YEAR", year);
        try self.module.addWord("MONTH", month);
        try self.module.addWord("DAY", day);
        try self.module.addWord("HOUR", hour);
        try self.module.addWord("MINUTE", minute);
        try self.module.addWord("SECOND", second);
    }

    fn toDate(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = switch (val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const dt = utils.parseDate(str) catch {
            try interp.stackPush(Value.initNull());
            return;
        };

        try interp.stackPush(Value.initDateTime(dt));
    }

    fn toDateTime(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = switch (val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        // Try to parse as "YYYY-MM-DD HH:MM:SS" format
        const dt = if (std.mem.indexOf(u8, str, " ")) |space_idx|
            blk: {
                const date_part = str[0..space_idx];
                const time_part = str[space_idx + 1 ..];

                const date = utils.parseDate(date_part) catch break :blk null;
                const time = utils.parseTime(time_part) catch break :blk null;

                if (date == null or time == null) break :blk null;

                break :blk DateTime{
                    .year = date.?.year,
                    .month = date.?.month,
                    .day = date.?.day,
                    .hour = time.?.hour,
                    .minute = time.?.minute,
                    .second = time.?.second,
                };
            }
        else
            utils.parseDateTime(str) catch null;

        if (dt) |datetime| {
            try interp.stackPush(Value.initDateTime(datetime));
        } else {
            try interp.stackPush(Value.initNull());
        }
    }

    fn dateToStr(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                const empty_str = try interp.allocator.dupe(u8, "");
                try interp.stackPush(Value.initString(empty_str));
                return;
            },
        };

        const str = try utils.formatDate(interp.allocator, dt);
        try interp.stackPush(Value.initString(str));
    }

    fn dateTimeToStr(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                const empty_str = try interp.allocator.dupe(u8, "");
                try interp.stackPush(Value.initString(empty_str));
                return;
            },
        };

        const str = try std.fmt.allocPrint(interp.allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second,
        });
        try interp.stackPush(Value.initString(str));
    }

    fn addDays(interp: *Interpreter) !void {
        const days_val = try interp.stackPop();
        const dt_val = try interp.stackPop();

        const dt = switch (dt_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const days = days_val.toInt() orelse 0;
        const result = addDaysToDateTime(dt, @intCast(days));
        try interp.stackPush(Value.initDateTime(result));
    }

    fn addHours(interp: *Interpreter) !void {
        const hours_val = try interp.stackPop();
        const dt_val = try interp.stackPop();

        const dt = switch (dt_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const hours = hours_val.toInt() orelse 0;
        var result = dt;
        result.hour = @intCast(@mod(result.hour + hours, 24));
        if (hours >= 24 or hours < 0) {
            result = addDaysToDateTime(result, @intCast(@divFloor(hours, 24)));
        }
        try interp.stackPush(Value.initDateTime(result));
    }

    fn addMinutes(interp: *Interpreter) !void {
        const minutes_val = try interp.stackPop();
        const dt_val = try interp.stackPop();

        const dt = switch (dt_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const minutes = minutes_val.toInt() orelse 0;
        var result = dt;
        result.minute = @intCast(@mod(result.minute + minutes, 60));
        if (minutes >= 60 or minutes < 0) {
            const hours = @divFloor(minutes, 60);
            result.hour = @intCast(@mod(result.hour + hours, 24));
            if (hours >= 24 or hours < 0) {
                result = addDaysToDateTime(result, @intCast(@divFloor(hours, 24)));
            }
        }
        try interp.stackPush(Value.initDateTime(result));
    }

    fn addSeconds(interp: *Interpreter) !void {
        const seconds_val = try interp.stackPop();
        const dt_val = try interp.stackPop();

        const dt = switch (dt_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const seconds = seconds_val.toInt() orelse 0;
        var result = dt;
        result.second = @intCast(@mod(result.second + seconds, 60));
        if (seconds >= 60 or seconds < 0) {
            const minutes = @divFloor(seconds, 60);
            result.minute = @intCast(@mod(result.minute + minutes, 60));
            if (minutes >= 60 or minutes < 0) {
                const hours = @divFloor(minutes, 60);
                result.hour = @intCast(@mod(result.hour + hours, 24));
                if (hours >= 24 or hours < 0) {
                    result = addDaysToDateTime(result, @intCast(@divFloor(hours, 24)));
                }
            }
        }
        try interp.stackPush(Value.initDateTime(result));
    }

    fn addDaysToDateTime(dt: DateTime, days: i32) DateTime {
        var result = dt;
        result.day = @intCast(@as(i32, result.day) + days);

        // Simplified: doesn't handle month/year overflow properly
        // This is a basic implementation
        while (result.day > 31) {
            result.day -= 30;
            result.month += 1;
            if (result.month > 12) {
                result.month = 1;
                result.year += 1;
            }
        }
        while (result.day < 1) {
            result.day += 30;
            result.month -= 1;
            if (result.month < 1) {
                result.month = 12;
                result.year -= 1;
            }
        }

        return result;
    }

    fn diffDays(interp: *Interpreter) !void {
        const end_val = try interp.stackPop();
        const start_val = try interp.stackPop();

        const end_dt = switch (end_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const start_dt = switch (start_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        // Simplified day difference (doesn't account for varying month lengths)
        const days = (@as(i64, end_dt.year) - start_dt.year) * 365 +
            (@as(i64, end_dt.month) - start_dt.month) * 30 +
            (@as(i64, end_dt.day) - start_dt.day);

        try interp.stackPush(Value.initInt(days));
    }

    fn diffHours(interp: *Interpreter) !void {
        const end_val = try interp.stackPop();
        const start_val = try interp.stackPop();

        const end_dt = switch (end_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const start_dt = switch (start_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const days = (@as(i64, end_dt.year) - start_dt.year) * 365 +
            (@as(i64, end_dt.month) - start_dt.month) * 30 +
            (@as(i64, end_dt.day) - start_dt.day);
        const hours = days * 24 + (@as(i64, end_dt.hour) - start_dt.hour);

        try interp.stackPush(Value.initInt(hours));
    }

    fn diffMinutes(interp: *Interpreter) !void {
        const end_val = try interp.stackPop();
        const start_val = try interp.stackPop();

        const end_dt = switch (end_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const start_dt = switch (start_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const days = (@as(i64, end_dt.year) - start_dt.year) * 365 +
            (@as(i64, end_dt.month) - start_dt.month) * 30 +
            (@as(i64, end_dt.day) - start_dt.day);
        const hours = days * 24 + (@as(i64, end_dt.hour) - start_dt.hour);
        const minutes = hours * 60 + (@as(i64, end_dt.minute) - start_dt.minute);

        try interp.stackPush(Value.initInt(minutes));
    }

    fn diffSeconds(interp: *Interpreter) !void {
        const end_val = try interp.stackPop();
        const start_val = try interp.stackPop();

        const end_dt = switch (end_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const start_dt = switch (start_val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        const days = (@as(i64, end_dt.year) - start_dt.year) * 365 +
            (@as(i64, end_dt.month) - start_dt.month) * 30 +
            (@as(i64, end_dt.day) - start_dt.day);
        const hours = days * 24 + (@as(i64, end_dt.hour) - start_dt.hour);
        const minutes = hours * 60 + (@as(i64, end_dt.minute) - start_dt.minute);
        const seconds = minutes * 60 + (@as(i64, end_dt.second) - start_dt.second);

        try interp.stackPush(Value.initInt(seconds));
    }

    fn now(interp: *Interpreter) !void {
        // Returns current Unix timestamp as integer
        const timestamp = std.time.timestamp();
        try interp.stackPush(Value.initInt(timestamp));
    }

    fn today(interp: *Interpreter) !void {
        // Returns midnight of current day as Unix timestamp
        const timestamp = std.time.timestamp();
        const day_start = @divFloor(timestamp, 86400) * 86400;
        try interp.stackPush(Value.initInt(day_start));
    }

    fn year(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        try interp.stackPush(Value.initInt(dt.year));
    }

    fn month(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        try interp.stackPush(Value.initInt(dt.month));
    }

    fn day(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        try interp.stackPush(Value.initInt(dt.day));
    }

    fn hour(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        try interp.stackPush(Value.initInt(dt.hour));
    }

    fn minute(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        try interp.stackPush(Value.initInt(dt.minute));
    }

    fn second(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const dt = switch (val) {
            .datetime_value => |d| d,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        try interp.stackPush(Value.initInt(dt.second));
    }
};
