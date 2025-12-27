const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;
const Value = @import("../../value.zig").Value;

pub const ArrayModule = struct {
    module: Module,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*ArrayModule {
        const self = try allocator.create(ArrayModule);
        self.* = .{
            .module = try Module.init(allocator, "array", ""),
            .allocator = allocator,
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *ArrayModule) void {
        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn registerWords(self: *ArrayModule) !void {
        // Construction
        try self.module.addWord("APPEND", append);
        try self.module.addWord("REVERSE", reverse);
        try self.module.addWord("UNIQUE", unique);
        // Access
        try self.module.addWord("LENGTH", length);
        try self.module.addWord("NTH", nth);
        try self.module.addWord("LAST", last);
        try self.module.addWord("SLICE", slice);
        try self.module.addWord("TAKE", take);
        try self.module.addWord("DROP", drop);
        // Set operations
        try self.module.addWord("DIFFERENCE", difference);
        try self.module.addWord("INTERSECTION", intersection);
        try self.module.addWord("UNION", union_op);
        // Sort
        try self.module.addWord("SORT", sort);
        try self.module.addWord("SHUFFLE", shuffle);
        try self.module.addWord("ROTATE", rotate);
        // Combine
        try self.module.addWord("ZIP", zip);
        try self.module.addWord("ZIP-WITH", zipWith);
        try self.module.addWord("FLATTEN", flatten);
        // Transform
        try self.module.addWord("MAP", map);
        try self.module.addWord("SELECT", select);
        try self.module.addWord("REDUCE", reduce);
        // Group
        try self.module.addWord("INDEX", index);
        try self.module.addWord("BY-FIELD", byField);
        try self.module.addWord("GROUP-BY-FIELD", groupByField);
        try self.module.addWord("GROUP-BY", groupBy);
        try self.module.addWord("GROUPS-OF", groupsOf);
        // Utility
        try self.module.addWord("FOREACH", forEach);
        try self.module.addWord("<REPEAT", repeat);
        try self.module.addWord("UNPACK", unpack);
        try self.module.addWord("KEY-OF", keyOf);
    }

    // Implement stub functions for all words
    fn append(interp: *Interpreter) !void {
        const item = try interp.stackPop();
        var container = try interp.stackPop();

        switch (container) {
            .array_value => |*arr| {
                try arr.append(interp.allocator, item);
                try interp.stackPush(container);
            },
            .null_value => {
                var new_arr = Value.initArray(interp.allocator);
                try new_arr.array_value.append(interp.allocator, item);
                try interp.stackPush(new_arr);
            },
            else => {
                var new_arr = Value.initArray(interp.allocator);
                try new_arr.array_value.append(interp.allocator, container);
                try new_arr.array_value.append(interp.allocator, item);
                try interp.stackPush(new_arr);
            },
        }
    }

    fn reverse(interp: *Interpreter) !void {
        const arr_val = try interp.stackPop();

        switch (arr_val) {
            .array_value => |arr| {
                var result = Value.initArray(interp.allocator);
                try result.array_value.ensureTotalCapacity(interp.allocator, arr.items.len);

                var i = arr.items.len;
                while (i > 0) {
                    i -= 1;
                    try result.array_value.append(interp.allocator, try arr.items[i].clone(interp.allocator));
                }

                try interp.stackPush(result);
            },
            else => try interp.stackPush(arr_val),
        }
    }

    fn unique(interp: *Interpreter) !void {
        const arr_val = try interp.stackPop();

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(arr_val);
                return;
            },
        };

        var result = Value.initArray(interp.allocator);

        for (arr.items) |item| {
            var found = false;
            for (result.array_value.items) |res_item| {
                if (item.equals(&res_item)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
            }
        }

        try interp.stackPush(result);
    }

    fn length(interp: *Interpreter) !void {
        const val = try interp.stackPop();

        const len: i64 = switch (val) {
            .array_value => |arr| @intCast(arr.items.len),
            .string_value => |s| @intCast(s.len),
            .record_value => |rec| @intCast(rec.count()),
            else => 0,
        };

        try interp.stackPush(Value.initInt(len));
    }

    fn nth(interp: *Interpreter) !void {
        const index_val = try interp.stackPop();
        const container = try interp.stackPop();

        const idx = index_val.toInt() orelse {
            try interp.stackPush(Value.initNull());
            return;
        };

        switch (container) {
            .array_value => |arr| {
                const array_idx = if (idx < 0) @as(usize, @intCast(arr.items.len)) - @as(usize, @intCast(-idx)) else @as(usize, @intCast(idx));
                if (array_idx < arr.items.len) {
                    try interp.stackPush(try arr.items[array_idx].clone(interp.allocator));
                } else {
                    try interp.stackPush(Value.initNull());
                }
            },
            .string_value => |s| {
                const str_idx = if (idx < 0) @as(usize, @intCast(s.len)) - @as(usize, @intCast(-idx)) else @as(usize, @intCast(idx));
                if (str_idx < s.len) {
                    const char_str = try interp.allocator.alloc(u8, 1);
                    char_str[0] = s[str_idx];
                    try interp.stackPush(Value.initString(char_str));
                } else {
                    try interp.stackPush(Value.initNull());
                }
            },
            else => try interp.stackPush(Value.initNull()),
        }
    }

    fn last(interp: *Interpreter) !void {
        const container = try interp.stackPop();

        switch (container) {
            .array_value => |arr| {
                if (arr.items.len > 0) {
                    try interp.stackPush(try arr.items[arr.items.len - 1].clone(interp.allocator));
                } else {
                    try interp.stackPush(Value.initNull());
                }
            },
            else => try interp.stackPush(Value.initNull()),
        }
    }

    fn slice(interp: *Interpreter) !void {
        const end_val = try interp.stackPop();
        const start_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const start_raw = start_val.toInt() orelse 0;
        const end_raw = end_val.toInt() orelse @as(i64, @intCast(arr.items.len));

        const start = if (start_raw < 0) @max(0, @as(i64, @intCast(arr.items.len)) + start_raw) else start_raw;
        const end = if (end_raw < 0) @max(0, @as(i64, @intCast(arr.items.len)) + end_raw) else end_raw;

        const start_idx: usize = @intCast(@max(0, @min(start, @as(i64, @intCast(arr.items.len)))));
        const end_idx: usize = @intCast(@max(start, @min(end, @as(i64, @intCast(arr.items.len)))));

        var result = Value.initArray(interp.allocator);
        if (start_idx < end_idx) {
            try result.array_value.ensureTotalCapacity(interp.allocator, end_idx - start_idx);
            for (start_idx..end_idx) |i| {
                try result.array_value.append(interp.allocator, try arr.items[i].clone(interp.allocator));
            }
        }

        try interp.stackPush(result);
    }

    fn take(interp: *Interpreter) !void {
        const n_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const n = n_val.toInt() orelse 0;

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        if (n <= 0) {
            try interp.stackPush(Value.initArray(interp.allocator));
            return;
        }

        const count: usize = @intCast(@min(n, @as(i64, @intCast(arr.items.len))));
        var result = Value.initArray(interp.allocator);
        try result.array_value.ensureTotalCapacity(interp.allocator, count);

        for (0..count) |i| {
            try result.array_value.append(interp.allocator, try arr.items[i].clone(interp.allocator));
        }

        try interp.stackPush(result);
    }

    fn drop(interp: *Interpreter) !void {
        const n_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const n = n_val.toInt() orelse 0;

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        if (n <= 0) {
            var result = Value.initArray(interp.allocator);
            for (arr.items) |item| {
                try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
            }
            try interp.stackPush(result);
            return;
        }

        const count: usize = @intCast(@min(n, @as(i64, @intCast(arr.items.len))));

        if (count >= arr.items.len) {
            try interp.stackPush(Value.initArray(interp.allocator));
            return;
        }

        var result = Value.initArray(interp.allocator);
        try result.array_value.ensureTotalCapacity(interp.allocator, arr.items.len - count);

        for (count..arr.items.len) |i| {
            try result.array_value.append(interp.allocator, try arr.items[i].clone(interp.allocator));
        }

        try interp.stackPush(result);
    }

    fn difference(interp: *Interpreter) !void {
        const arr2_val = try interp.stackPop();
        const arr1_val = try interp.stackPop();

        const arr1 = switch (arr1_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const arr2 = switch (arr2_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        var result = Value.initArray(interp.allocator);

        for (arr1.items) |item| {
            var found = false;
            for (arr2.items) |item2| {
                if (item.equals(&item2)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
            }
        }

        try interp.stackPush(result);
    }

    fn intersection(interp: *Interpreter) !void {
        const arr2_val = try interp.stackPop();
        const arr1_val = try interp.stackPop();

        const arr1 = switch (arr1_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const arr2 = switch (arr2_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        var result = Value.initArray(interp.allocator);

        for (arr1.items) |item| {
            // Check if in arr2
            var found_in_arr2 = false;
            for (arr2.items) |item2| {
                if (item.equals(&item2)) {
                    found_in_arr2 = true;
                    break;
                }
            }

            if (found_in_arr2) {
                // Check if already in result to avoid duplicates
                var already_in_result = false;
                for (result.array_value.items) |res_item| {
                    if (item.equals(&res_item)) {
                        already_in_result = true;
                        break;
                    }
                }

                if (!already_in_result) {
                    try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
                }
            }
        }

        try interp.stackPush(result);
    }

    fn union_op(interp: *Interpreter) !void {
        const arr2_val = try interp.stackPop();
        const arr1_val = try interp.stackPop();

        const arr1 = switch (arr1_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const arr2 = switch (arr2_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        var result = Value.initArray(interp.allocator);

        // Add all unique items from arr1
        for (arr1.items) |item| {
            var found = false;
            for (result.array_value.items) |res_item| {
                if (item.equals(&res_item)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
            }
        }

        // Add all unique items from arr2
        for (arr2.items) |item| {
            var found = false;
            for (result.array_value.items) |res_item| {
                if (item.equals(&res_item)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
            }
        }

        try interp.stackPush(result);
    }

    fn sort(interp: *Interpreter) !void {
        const arr_val = try interp.stackPop();

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(arr_val);
                return;
            },
        };

        // Create a copy to sort
        var result = Value.initArray(interp.allocator);
        try result.array_value.ensureTotalCapacity(interp.allocator, arr.items.len);
        for (arr.items) |item| {
            try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
        }

        // Simple bubble sort for now
        const n = result.array_value.items.len;
        if (n <= 1) {
            try interp.stackPush(result);
            return;
        }

        var i: usize = 0;
        while (i < n - 1) : (i += 1) {
            var j: usize = 0;
            while (j < n - i - 1) : (j += 1) {
                if (compareValues(&result.array_value.items[j], &result.array_value.items[j + 1])) {
                    const temp = result.array_value.items[j];
                    result.array_value.items[j] = result.array_value.items[j + 1];
                    result.array_value.items[j + 1] = temp;
                }
            }
        }

        try interp.stackPush(result);
    }

    fn compareValues(a: *const Value, b: *const Value) bool {
        // Returns true if a > b (for ascending sort)
        const a_num = a.toNumber();
        const b_num = b.toNumber();

        if (a_num != null and b_num != null) {
            return a_num.? > b_num.?;
        }

        // Fall back to string comparison
        const a_str = switch (a.*) {
            .string_value => |s| s,
            else => return false,
        };
        const b_str = switch (b.*) {
            .string_value => |s| s,
            else => return true,
        };

        return std.mem.order(u8, a_str, b_str) == .gt;
    }

    fn shuffle(interp: *Interpreter) !void {
        const arr_val = try interp.stackPop();
        // TODO: Implement with proper random number generation
        try interp.stackPush(arr_val);
    }

    fn rotate(interp: *Interpreter) !void {
        const n_val = try interp.stackPop();
        const arr_val = try interp.stackPop();
        // TODO: Implement array rotation
        _ = n_val;
        try interp.stackPush(arr_val);
    }

    fn zip(interp: *Interpreter) !void {
        const arr2_val = try interp.stackPop();
        const arr1_val = try interp.stackPop();

        const arr1 = switch (arr1_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const arr2 = switch (arr2_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const min_len = @min(arr1.items.len, arr2.items.len);
        var result = Value.initArray(interp.allocator);
        try result.array_value.ensureTotalCapacity(interp.allocator, min_len);

        for (0..min_len) |i| {
            var pair = Value.initArray(interp.allocator);
            try pair.array_value.append(interp.allocator, try arr1.items[i].clone(interp.allocator));
            try pair.array_value.append(interp.allocator, try arr2.items[i].clone(interp.allocator));
            try result.array_value.append(interp.allocator, pair);
        }

        try interp.stackPush(result);
    }

    fn zipWith(interp: *Interpreter) !void {
        const code_val = try interp.stackPop();
        const arr2_val = try interp.stackPop();
        const arr1_val = try interp.stackPop();

        const code = switch (code_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const arr1 = switch (arr1_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const arr2 = switch (arr2_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        var result = Value.initArray(interp.allocator);
        try result.array_value.ensureTotalCapacity(interp.allocator, arr1.items.len);

        for (0..arr1.items.len) |i| {
            const value2 = if (i < arr2.items.len) try arr2.items[i].clone(interp.allocator) else Value.initNull();
            try interp.stackPush(try arr1.items[i].clone(interp.allocator));
            try interp.stackPush(value2);
            try interp.run(code);
            const zipped = try interp.stackPop();
            try result.array_value.append(interp.allocator, zipped);
        }

        try interp.stackPush(result);
    }

    fn flatten(interp: *Interpreter) !void {
        const arr_val = try interp.stackPop();

        switch (arr_val) {
            .array_value => |arr| {
                var result = Value.initArray(interp.allocator);
                try flattenHelper(interp.allocator, &arr, &result.array_value);
                try interp.stackPush(result);
            },
            else => try interp.stackPush(arr_val),
        }
    }

    fn flattenHelper(allocator: Allocator, arr: *const ArrayList(Value), result: *ArrayList(Value)) !void {
        for (arr.items) |*item| {
            switch (item.*) {
                .array_value => |sub_arr| {
                    try flattenHelper(allocator, &sub_arr, result);
                },
                else => try result.append(allocator, try item.clone(allocator)),
            }
        }
    }

    fn map(interp: *Interpreter) !void {
        const code_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        // Get code string
        const code = switch (code_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        // Get array
        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        // Map over array
        var result = Value.initArray(interp.allocator);
        try result.array_value.ensureTotalCapacity(interp.allocator, arr.items.len);

        for (arr.items) |item| {
            try interp.stackPush(try item.clone(interp.allocator));
            try interp.run(code);
            const mapped = try interp.stackPop();
            try result.array_value.append(interp.allocator, mapped);
        }

        try interp.stackPush(result);
    }

    fn select(interp: *Interpreter) !void {
        const code_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        // Get code string
        const code = switch (code_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        // Get array
        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        // Filter array
        var result = Value.initArray(interp.allocator);

        for (arr.items) |item| {
            try interp.stackPush(try item.clone(interp.allocator));
            try interp.run(code);
            const keep_val = try interp.stackPop();
            if (keep_val.isTruthy()) {
                try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
            }
        }

        try interp.stackPush(result);
    }

    fn reduce(interp: *Interpreter) !void {
        const code_val = try interp.stackPop();
        const initial = try interp.stackPop();
        const arr_val = try interp.stackPop();

        // Get code string
        const code = switch (code_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(initial);
                return;
            },
        };

        // Get array
        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(initial);
                return;
            },
        };

        // Reduce array
        var accumulator = initial;
        for (arr.items) |item| {
            try interp.stackPush(try accumulator.clone(interp.allocator));
            try interp.stackPush(try item.clone(interp.allocator));
            try interp.run(code);
            accumulator = try interp.stackPop();
        }

        try interp.stackPush(accumulator);
    }

    fn index(interp: *Interpreter) !void {
        const code_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const code = switch (code_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        var result = Value.initRecord(interp.allocator);

        for (arr.items) |item| {
            try interp.stackPush(try item.clone(interp.allocator));
            try interp.run(code);
            const keys_val = try interp.stackPop();

            switch (keys_val) {
                .array_value => |keys_arr| {
                    for (keys_arr.items) |key_val| {
                        const key_str = try key_val.toString(interp.allocator);
                        defer interp.allocator.free(key_str);

                        const key_lower = try toLowerCaseAlloc(interp.allocator, key_str);

                        if (result.record_value.get(key_lower)) |existing_val| {
                            switch (existing_val) {
                                .array_value => |*existing_arr| {
                                    try existing_arr.append(interp.allocator, try item.clone(interp.allocator));
                                },
                                else => {},
                            }
                        } else {
                            var new_arr = Value.initArray(interp.allocator);
                            try new_arr.array_value.append(interp.allocator, try item.clone(interp.allocator));
                            try result.record_value.put(key_lower, new_arr);
                        }
                    }
                },
                else => {},
            }
        }

        try interp.stackPush(result);
    }

    fn toLowerCaseAlloc(allocator: Allocator, s: []const u8) ![]const u8 {
        const lower = try allocator.alloc(u8, s.len);
        for (s, 0..) |c, i| {
            lower[i] = std.ascii.toLower(c);
        }
        return lower;
    }

    fn byField(interp: *Interpreter) !void {
        const field_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const field_str = switch (field_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        var result = Value.initRecord(interp.allocator);

        for (arr.items) |item| {
            switch (item) {
                .record_value => |rec| {
                    if (rec.get(field_str)) |field_value| {
                        const key_str = try field_value.toString(interp.allocator);
                        defer interp.allocator.free(key_str);

                        const key_lower = try toLowerCaseAlloc(interp.allocator, key_str);

                        try result.record_value.put(key_lower, try item.clone(interp.allocator));
                    }
                },
                else => {},
            }
        }

        try interp.stackPush(result);
    }

    fn groupByField(interp: *Interpreter) !void {
        const field_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const field_str = switch (field_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        var result = Value.initRecord(interp.allocator);

        for (arr.items) |item| {
            switch (item) {
                .record_value => |rec| {
                    if (rec.get(field_str)) |field_value| {
                        const key_str = try field_value.toString(interp.allocator);
                        defer interp.allocator.free(key_str);

                        const key_lower = try toLowerCaseAlloc(interp.allocator, key_str);

                        if (result.record_value.getPtr(key_lower)) |existing_ptr| {
                            switch (existing_ptr.*) {
                                .array_value => |*existing_arr| {
                                    try existing_arr.append(interp.allocator, try item.clone(interp.allocator));
                                },
                                else => {},
                            }
                        } else {
                            var new_arr = Value.initArray(interp.allocator);
                            try new_arr.array_value.append(interp.allocator, try item.clone(interp.allocator));
                            try result.record_value.put(key_lower, new_arr);
                        }
                    }
                },
                else => {},
            }
        }

        try interp.stackPush(result);
    }

    fn groupBy(interp: *Interpreter) !void {
        const code_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const code = switch (code_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        var result = Value.initRecord(interp.allocator);

        for (arr.items) |item| {
            try interp.stackPush(try item.clone(interp.allocator));
            try interp.run(code);
            const key_val = try interp.stackPop();

            const key_str = try key_val.toString(interp.allocator);
            defer interp.allocator.free(key_str);

            const key_lower = try toLowerCaseAlloc(interp.allocator, key_str);

            if (result.record_value.getPtr(key_lower)) |existing_ptr| {
                switch (existing_ptr.*) {
                    .array_value => |*existing_arr| {
                        try existing_arr.append(interp.allocator, try item.clone(interp.allocator));
                    },
                    else => {},
                }
            } else {
                var new_arr = Value.initArray(interp.allocator);
                try new_arr.array_value.append(interp.allocator, try item.clone(interp.allocator));
                try result.record_value.put(key_lower, new_arr);
            }
        }

        try interp.stackPush(result);
    }

    fn groupsOf(interp: *Interpreter) !void {
        const n_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        const n = n_val.toInt() orelse 0;
        if (n <= 0) {
            try interp.stackPush(Value.initArray(interp.allocator));
            return;
        }

        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const chunk_size: usize = @intCast(n);
        var result = Value.initArray(interp.allocator);

        var i: usize = 0;
        while (i < arr.items.len) {
            var chunk = Value.initArray(interp.allocator);
            const end = @min(i + chunk_size, arr.items.len);

            for (i..end) |j| {
                try chunk.array_value.append(interp.allocator, try arr.items[j].clone(interp.allocator));
            }

            try result.array_value.append(interp.allocator, chunk);
            i = end;
        }

        try interp.stackPush(result);
    }

    fn forEach(interp: *Interpreter) !void {
        const code_val = try interp.stackPop();
        const arr_val = try interp.stackPop();

        // Get code string
        const code = switch (code_val) {
            .string_value => |s| s,
            else => return,
        };

        // Get array
        const arr = switch (arr_val) {
            .array_value => |a| a,
            else => return,
        };

        // Execute code for each item (discard results)
        for (arr.items) |item| {
            try interp.stackPush(try item.clone(interp.allocator));
            try interp.run(code);
            // Discard result if any
            if (interp.stack.length() > 0) {
                _ = try interp.stackPop();
            }
        }
    }

    fn repeat(interp: *Interpreter) !void {
        const n_val = try interp.stackPop();
        const item = try interp.stackPop();

        const n = n_val.toInt() orelse 0;
        if (n <= 0) {
            try interp.stackPush(Value.initArray(interp.allocator));
            return;
        }

        var result = Value.initArray(interp.allocator);
        try result.array_value.ensureTotalCapacity(interp.allocator, @intCast(n));

        var i: i64 = 0;
        while (i < n) : (i += 1) {
            try result.array_value.append(interp.allocator, try item.clone(interp.allocator));
        }

        try interp.stackPush(result);
    }

    fn unpack(interp: *Interpreter) !void {
        const container = try interp.stackPop();

        switch (container) {
            .array_value => |arr| {
                for (arr.items) |item| {
                    try interp.stackPush(try item.clone(interp.allocator));
                }
            },
            .record_value => |rec| {
                // Get sorted keys for consistent order
                var keys = try std.ArrayList([]const u8).initCapacity(interp.allocator, rec.count());
                defer keys.deinit();

                var iter = rec.keyIterator();
                while (iter.next()) |key| {
                    try keys.append(key.*);
                }

                std.mem.sort([]const u8, keys.items, {}, struct {
                    fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                        return std.mem.lessThan(u8, a, b);
                    }
                }.lessThan);

                for (keys.items) |key| {
                    if (rec.get(key)) |val| {
                        try interp.stackPush(try val.clone(interp.allocator));
                    }
                }
            },
            else => {},
        }
    }

    fn keyOf(interp: *Interpreter) !void {
        const value = try interp.stackPop();
        const container = try interp.stackPop();

        switch (container) {
            .array_value => |arr| {
                for (arr.items, 0..) |item, i| {
                    if (item.equals(&value)) {
                        try interp.stackPush(Value.initInt(@intCast(i)));
                        return;
                    }
                }
                try interp.stackPush(Value.initNull());
            },
            .record_value => |rec| {
                var iter = rec.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.equals(&value)) {
                        const key_copy = try interp.allocator.dupe(u8, entry.key_ptr.*);
                        try interp.stackPush(Value.initString(key_copy));
                        return;
                    }
                }
                try interp.stackPush(Value.initNull());
            },
            else => try interp.stackPush(Value.initNull()),
        }
    }
};
