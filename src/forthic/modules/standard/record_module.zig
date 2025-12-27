const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;
const Value = @import("../../value.zig").Value;

pub const RecordModule = struct {
    module: Module,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*RecordModule {
        const self = try allocator.create(RecordModule);
        self.* = .{
            .module = try Module.init(allocator, "record", ""),
            .allocator = allocator,
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *RecordModule) void {
        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn registerWords(self: *RecordModule) !void {
        try self.module.addWord("REC", createRecord);
        try self.module.addWord("<REC!", setRecordValue);
        try self.module.addWord("REC@", getRecordValue);
        try self.module.addWord("|REC@", pipeRecAt);
        try self.module.addWord("KEYS", keys);
        try self.module.addWord("VALUES", values);
        try self.module.addWord("RELABEL", relabel);
        try self.module.addWord("INVERT-KEYS", invertKeys);
        try self.module.addWord("REC-DEFAULTS", recDefaults);
        try self.module.addWord("<DEL", del);
    }

    fn createRecord(interp: *Interpreter) !void {
        const pairs_val = try interp.stackPop();

        const pairs = switch (pairs_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        var result = Value.initRecord(interp.allocator);

        for (pairs.items) |pair| {
            switch (pair) {
                .array_value => |pair_arr| {
                    if (pair_arr.items.len >= 2) {
                        const key_str = try pair_arr.items[0].toString(interp.allocator);
                        defer interp.allocator.free(key_str);

                        const key_copy = try interp.allocator.dupe(u8, key_str);
                        const val_copy = try pair_arr.items[1].clone(interp.allocator);
                        try result.record_value.put(key_copy, val_copy);
                    }
                },
                else => {},
            }
        }

        try interp.stackPush(result);
    }

    fn setRecordValue(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const key_val = try interp.stackPop();
        var rec_val = try interp.stackPop();

        const key_str = switch (key_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(rec_val);
                return;
            },
        };

        switch (rec_val) {
            .record_value => |*rec| {
                const key_copy = try interp.allocator.dupe(u8, key_str);
                try rec.put(key_copy, try val.clone(interp.allocator));
                try interp.stackPush(rec_val);
            },
            else => try interp.stackPush(rec_val),
        }
    }

    fn getRecordValue(interp: *Interpreter) !void {
        const key_val = try interp.stackPop();
        const rec_val = try interp.stackPop();

        const key_str = switch (key_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(Value.initNull());
                return;
            },
        };

        switch (rec_val) {
            .record_value => |rec| {
                if (rec.get(key_str)) |value| {
                    try interp.stackPush(try value.clone(interp.allocator));
                } else {
                    try interp.stackPush(Value.initNull());
                }
            },
            else => try interp.stackPush(Value.initNull()),
        }
    }

    fn pipeRecAt(interp: *Interpreter) !void {
        const keys_val = try interp.stackPop();
        const rec_val = try interp.stackPop();

        const keys_array = switch (keys_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        const rec = switch (rec_val) {
            .record_value => |r| r,
            else => {
                try interp.stackPush(Value.initArray(interp.allocator));
                return;
            },
        };

        var result = Value.initArray(interp.allocator);

        for (keys_array.items) |key_val| {
            const key_str = try key_val.toString(interp.allocator);
            defer interp.allocator.free(key_str);

            if (rec.get(key_str)) |value| {
                try result.array_value.append(interp.allocator, try value.clone(interp.allocator));
            } else {
                try result.array_value.append(interp.allocator, Value.initNull());
            }
        }

        try interp.stackPush(result);
    }

    fn keys(interp: *Interpreter) !void {
        const rec_val = try interp.stackPop();

        switch (rec_val) {
            .record_value => |rec| {
                var result = Value.initArray(interp.allocator);

                var iter = rec.keyIterator();
                while (iter.next()) |key| {
                    const key_copy = try interp.allocator.dupe(u8, key.*);
                    try result.array_value.append(interp.allocator, Value.initString(key_copy));
                }

                try interp.stackPush(result);
            },
            else => try interp.stackPush(Value.initArray(interp.allocator)),
        }
    }

    fn values(interp: *Interpreter) !void {
        const rec_val = try interp.stackPop();

        switch (rec_val) {
            .record_value => |rec| {
                var result = Value.initArray(interp.allocator);

                var iter = rec.valueIterator();
                while (iter.next()) |value| {
                    try result.array_value.append(interp.allocator, try value.clone(interp.allocator));
                }

                try interp.stackPush(result);
            },
            else => try interp.stackPush(Value.initArray(interp.allocator)),
        }
    }

    fn relabel(interp: *Interpreter) !void {
        const new_keys_val = try interp.stackPop();
        const old_keys_val = try interp.stackPop();
        const rec_val = try interp.stackPop();

        const old_keys = switch (old_keys_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(rec_val);
                return;
            },
        };

        const new_keys = switch (new_keys_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(rec_val);
                return;
            },
        };

        var result = switch (rec_val) {
            .record_value => |rec| blk: {
                var new_rec = Value.initRecord(interp.allocator);

                // Copy all existing keys
                var iter = rec.iterator();
                while (iter.next()) |entry| {
                    const key_copy = try interp.allocator.dupe(u8, entry.key_ptr.*);
                    try new_rec.record_value.put(key_copy, try entry.value_ptr.clone(interp.allocator));
                }

                break :blk new_rec;
            },
            else => {
                try interp.stackPush(rec_val);
                return;
            },
        };

        // Rename keys
        for (old_keys.items, 0..) |old_key_val, i| {
            if (i >= new_keys.items.len) break;

            const old_key_str = try old_key_val.toString(interp.allocator);
            defer interp.allocator.free(old_key_str);

            const new_key_str = try new_keys.items[i].toString(interp.allocator);
            defer interp.allocator.free(new_key_str);

            if (result.record_value.fetchRemove(old_key_str)) |entry| {
                const new_key_copy = try interp.allocator.dupe(u8, new_key_str);
                try result.record_value.put(new_key_copy, entry.value);
                interp.allocator.free(entry.key);
            }
        }

        try interp.stackPush(result);
    }

    fn invertKeys(interp: *Interpreter) !void {
        const rec_val = try interp.stackPop();

        const rec = switch (rec_val) {
            .record_value => |r| r,
            else => {
                try interp.stackPush(Value.initRecord(interp.allocator));
                return;
            },
        };

        var result = Value.initRecord(interp.allocator);

        // Iterate through outer keys
        var outer_iter = rec.iterator();
        while (outer_iter.next()) |outer_entry| {
            const outer_key = outer_entry.key_ptr.*;

            // Check if value is a record
            switch (outer_entry.value_ptr.*) {
                .record_value => |inner_rec| {
                    // Iterate through inner keys
                    var inner_iter = inner_rec.iterator();
                    while (inner_iter.next()) |inner_entry| {
                        const inner_key = inner_entry.key_ptr.*;

                        // Get or create the inverted record for this inner key
                        if (result.record_value.getPtr(inner_key)) |inverted_rec_ptr| {
                            // Add this outer_key -> value mapping
                            switch (inverted_rec_ptr.*) {
                                .record_value => |*inverted_rec| {
                                    const outer_key_copy = try interp.allocator.dupe(u8, outer_key);
                                    try inverted_rec.put(outer_key_copy, try inner_entry.value_ptr.clone(interp.allocator));
                                },
                                else => {},
                            }
                        } else {
                            // Create new inverted record for this inner key
                            var new_inverted = Value.initRecord(interp.allocator);
                            const outer_key_copy = try interp.allocator.dupe(u8, outer_key);
                            try new_inverted.record_value.put(outer_key_copy, try inner_entry.value_ptr.clone(interp.allocator));

                            const inner_key_copy = try interp.allocator.dupe(u8, inner_key);
                            try result.record_value.put(inner_key_copy, new_inverted);
                        }
                    }
                },
                else => {},
            }
        }

        try interp.stackPush(result);
    }

    fn recDefaults(interp: *Interpreter) !void {
        const defaults_val = try interp.stackPop();
        var rec_val = try interp.stackPop();

        const defaults = switch (defaults_val) {
            .array_value => |a| a,
            else => {
                try interp.stackPush(rec_val);
                return;
            },
        };

        switch (rec_val) {
            .record_value => |*rec| {
                // Apply each default if key doesn't exist
                for (defaults.items) |default_pair| {
                    switch (default_pair) {
                        .array_value => |pair_arr| {
                            if (pair_arr.items.len >= 2) {
                                const key_str = try pair_arr.items[0].toString(interp.allocator);
                                defer interp.allocator.free(key_str);

                                if (!rec.contains(key_str)) {
                                    const key_copy = try interp.allocator.dupe(u8, key_str);
                                    const val_copy = try pair_arr.items[1].clone(interp.allocator);
                                    try rec.put(key_copy, val_copy);
                                }
                            }
                        },
                        else => {},
                    }
                }

                try interp.stackPush(rec_val);
            },
            else => try interp.stackPush(rec_val),
        }
    }

    fn del(interp: *Interpreter) !void {
        const key_val = try interp.stackPop();
        var rec_val = try interp.stackPop();

        const key_str = switch (key_val) {
            .string_value => |s| s,
            else => {
                try interp.stackPush(rec_val);
                return;
            },
        };

        switch (rec_val) {
            .record_value => |*rec| {
                if (rec.fetchRemove(key_str)) |entry| {
                    interp.allocator.free(entry.key);
                    entry.value.deinit(interp.allocator);
                }
                try interp.stackPush(rec_val);
            },
            else => try interp.stackPush(rec_val),
        }
    }
};
