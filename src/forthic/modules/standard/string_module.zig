const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;
const Value = @import("../../value.zig").Value;

pub const StringModule = struct {
    module: Module,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*StringModule {
        const self = try allocator.create(StringModule);
        self.* = .{
            .module = try Module.init(allocator, "string", ""),
            .allocator = allocator,
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *StringModule) void {
        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn registerWords(self: *StringModule) !void {
        try self.module.addWord(">STR", toStr);
        try self.module.addWord("CONCAT", concat);
        try self.module.addWord("SPLIT", split);
        try self.module.addWord("JOIN", join);
        try self.module.addWord("/N", slashN);
        try self.module.addWord("/R", slashR);
        try self.module.addWord("/T", slashT);
        try self.module.addWord("LOWERCASE", lowercase);
        try self.module.addWord("UPPERCASE", uppercase);
        try self.module.addWord("ASCII", ascii);
        try self.module.addWord("STRIP", strip);
        try self.module.addWord("REPLACE", replace);
        try self.module.addWord("RE-MATCH", reMatch);
        try self.module.addWord("RE-MATCH-ALL", reMatchAll);
        try self.module.addWord("RE-MATCH-GROUP", reMatchGroup);
        try self.module.addWord("URL-ENCODE", urlEncode);
        try self.module.addWord("URL-DECODE", urlDecode);
    }

    fn toStr(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const str = try val.toString(interp.allocator);
        try interp.stackPush(Value.initString(str));
    }

    fn concat(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();

        const strA = try a.toString(interp.allocator);
        defer interp.allocator.free(strA);
        const strB = try b.toString(interp.allocator);
        defer interp.allocator.free(strB);

        const result = try std.fmt.allocPrint(interp.allocator, "{s}{s}", .{ strA, strB });
        try interp.stackPush(Value.initString(result));
    }

    fn split(interp: *Interpreter) !void {
        const delimiter_val = try interp.stackPop();
        const str_val = try interp.stackPop();

        const str = switch (str_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const delimiter = switch (delimiter_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        var result = Value.initArray(interp.allocator);

        var iter = std.mem.split(u8, str, delimiter);
        while (iter.next()) |part| {
            const part_copy = try interp.allocator.dupe(u8, part);
            try result.array_value.append(interp.allocator, Value.initString(part_copy));
        }

        try interp.stackPush(result);
    }

    fn join(interp: *Interpreter) !void {
        const delimiter_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                const empty_str = try interp.allocator.dupe(u8, "");
                try interp.stackPush(Value.initString(empty_str));
                return;
            },
        };

        const delimiter = switch (delimiter_val) {
            .string_value => |s| s,
            else => {
                const empty_str = try interp.allocator.dupe(u8, "");
                try interp.stackPush(Value.initString(empty_str));
                return;
            },
        };

        var parts = std.ArrayList([]const u8).init(interp.allocator);
        defer {
            for (parts.items) |part| {
                interp.allocator.free(part);
            }
            parts.deinit();
        }

        for (arr.items) |item| {
            const str = try item.toString(interp.allocator);
            try parts.append(str);
        }

        const result = try std.mem.join(interp.allocator, delimiter, parts.items);
        try interp.stackPush(Value.initString(result));
    }

    fn slashN(interp: *Interpreter) !void {
        const newline = try interp.allocator.dupe(u8, "\n");
        try interp.stackPush(Value.initString(newline));
    }

    fn slashR(interp: *Interpreter) !void {
        const carriage_return = try interp.allocator.dupe(u8, "\r");
        try interp.stackPush(Value.initString(carriage_return));
    }

    fn slashT(interp: *Interpreter) !void {
        const tab = try interp.allocator.dupe(u8, "\t");
        try interp.stackPush(Value.initString(tab));
    }

    fn lowercase(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = try val.toString(interp.allocator);
        defer interp.allocator.free(str);

        const result = try interp.allocator.alloc(u8, str.len);
        for (str, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }

        try interp.stackPush(Value.initString(result));
    }

    fn uppercase(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = try val.toString(interp.allocator);
        defer interp.allocator.free(str);

        const result = try interp.allocator.alloc(u8, str.len);
        for (str, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }

        try interp.stackPush(Value.initString(result));
    }

    fn ascii(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = try val.toString(interp.allocator);
        defer interp.allocator.free(str);

        if (str.len > 0) {
            try interp.stackPush(Value.initInt(@as(i64, str[0])));
        } else {
            try interp.stackPush(Value.initInt(0));
        }
    }

    fn strip(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = try val.toString(interp.allocator);
        defer interp.allocator.free(str);

        const trimmed = std.mem.trim(u8, str, " \t\n\r");
        const result = try interp.allocator.dupe(u8, trimmed);

        try interp.stackPush(Value.initString(result));
    }

    fn replace(interp: *Interpreter) !void {
        const replacement_val = try interp.stackPop();
        const pattern_val = try interp.stackPop();
        const str_val = try interp.stackPop();

        const str = switch (str_val) {
            .string_value => |s| s,
            else => {
                const empty_str = try interp.allocator.dupe(u8, "");
                try interp.stackPush(Value.initString(empty_str));
                return;
            },
        };

        const pattern = switch (pattern_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(try str_val.clone(interp.allocator));
                return;
            },
        };

        const replacement = switch (replacement_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(try str_val.clone(interp.allocator));
                return;
            },
        };

        // Simple string replacement (not regex)
        const result = try replaceAll(interp.allocator, str, pattern, replacement);
        try interp.stackPush(Value.initString(result));
    }

    fn replaceAll(allocator: Allocator, s: []const u8, old: []const u8, new: []const u8) ![]const u8 {
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
        const result = try allocator.alloc(u8, new_len);

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

    fn reMatch(interp: *Interpreter) !void {
        _ = try interp.stackPop(); // pattern
        _ = try interp.stackPop(); // string
        // TODO: Implement regex matching (requires regex library)
        try interp.stackPush(Value.initNull());
    }

    fn reMatchAll(interp: *Interpreter) !void {
        _ = try interp.stackPop(); // pattern
        _ = try interp.stackPop(); // string
        // TODO: Implement global regex matching (requires regex library)
        try interp.stackPush(Value.initArray(interp.allocator));
    }

    fn reMatchGroup(interp: *Interpreter) !void {
        _ = try interp.stackPop(); // group index
        _ = try interp.stackPop(); // pattern
        _ = try interp.stackPop(); // string
        // TODO: Implement regex group capture (requires regex library)
        try interp.stackPush(Value.initNull());
    }

    fn urlEncode(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = try val.toString(interp.allocator);
        defer interp.allocator.free(str);

        // TODO: Implement proper URL percent encoding
        // For now, just return the string as-is
        const result = try interp.allocator.dupe(u8, str);
        try interp.stackPush(Value.initString(result));
    }

    fn urlDecode(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const str = try val.toString(interp.allocator);
        defer interp.allocator.free(str);

        // TODO: Implement proper URL percent decoding
        // For now, just return the string as-is
        const result = try interp.allocator.dupe(u8, str);
        try interp.stackPush(Value.initString(result));
    }
};
