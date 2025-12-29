const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;
const Value = @import("../../value.zig").Value;
const Variable = @import("../../variable.zig").Variable;
const WordOptions = @import("../../word_options.zig").WordOptions;
const errors = @import("../../errors.zig");
const word_mod = @import("../../word.zig");
const ModuleWord = word_mod.ModuleWord;

pub const CoreModule = struct {
    module: Module,
    allocator: Allocator,
    word_ptrs: ArrayList(*ModuleWord),

    pub fn init(allocator: Allocator) !*CoreModule {
        const self = try allocator.create(CoreModule);
        self.* = .{
            .module = Module.init(allocator, "core", ""),
            .allocator = allocator,
            .word_ptrs = ArrayList(*ModuleWord){},
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *CoreModule) void {
        // Free word pointers
        for (self.word_ptrs.items) |word_ptr| {
            word_ptr.asWord().deinit(self.allocator);
            self.allocator.destroy(word_ptr);
        }
        self.word_ptrs.deinit(self.allocator);

        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn addModuleWord(self: *CoreModule, name: []const u8, handler: word_mod.HandlerFn) !void {
        const word_ptr = try self.allocator.create(ModuleWord);
        word_ptr.* = ModuleWord.init(self.allocator, name, handler);
        try self.word_ptrs.append(self.allocator, word_ptr);  // Track for cleanup
        try self.module.addExportableWord(word_ptr.asWord());
    }

    fn registerWords(self: *CoreModule) !void {
        // Stack operations
        try self.addModuleWord("POP", pop);
        try self.addModuleWord("DUP", dup);
        try self.addModuleWord("SWAP", swap);

        // Variable operations
        try self.addModuleWord("VARIABLES", variables);
        try self.addModuleWord("!", set);
        try self.addModuleWord("@", get);
        try self.addModuleWord("!@", setGet);

        // Module operations
        try self.addModuleWord("EXPORT", exportWord);
        try self.addModuleWord("USE-MODULES", useModules);

        // Execution
        try self.addModuleWord("INTERPRET", interpret);

        // Control flow
        try self.addModuleWord("IDENTITY", identity);
        try self.addModuleWord("NOP", nop);
        try self.addModuleWord("NULL", null_word);
        try self.addModuleWord("ARRAY?", arrayCheck);
        try self.addModuleWord("DEFAULT", default_word);
        try self.addModuleWord("*DEFAULT", defaultStar);

        // Options
        try self.addModuleWord("~>", toOptions);

        // Profiling (placeholder)
        try self.addModuleWord("PROFILE-START", profileStart);
        try self.addModuleWord("PROFILE-END", profileEnd);
        try self.addModuleWord("PROFILE-TIMESTAMP", profileTimestamp);
        try self.addModuleWord("PROFILE-DATA", profileData);

        // Logging (placeholder)
        try self.addModuleWord("START-LOG", startLog);
        try self.addModuleWord("END-LOG", endLog);

        // String operations
        try self.addModuleWord("INTERPOLATE", interpolate);
        try self.addModuleWord("PRINT", print);

        // Debug
        try self.addModuleWord("PEEK!", peek);
        try self.addModuleWord("STACK!", stackDebug);
    }

    // ========================================
    // Helper Functions
    // ========================================

    fn getOrCreateVariable(interp: *Interpreter, name: []const u8) !Variable {
        // Validate variable name - no __ prefix allowed
        if (std.mem.startsWith(u8, name, "__")) {
            return errors.ForthicErrorType.InvalidVariableName;
        }

        const cur_module = interp.curModule();

        // Check if variable already exists
        if (cur_module.getVariable(name)) |variable| {
            return variable;
        }

        // Create it if it doesn't exist
        try cur_module.addVariable(name, Value.initNull());
        return cur_module.getVariable(name).?;
    }

    // ========================================
    // Stack Operations
    // ========================================

    fn pop(interp: *Interpreter) !void {
        var value = try interp.stackPop();
        value.deinit(interp.allocator);
    }

    fn dup(interp: *Interpreter) !void {
        var a = try interp.stackPop();
        defer a.deinit(interp.allocator);
        try interp.stackPush(try a.clone(interp.allocator));
        try interp.stackPush(try a.clone(interp.allocator));
    }

    fn swap(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        try interp.stackPush(b);
        try interp.stackPush(a);
    }

    // ========================================
    // Variable Operations
    // ========================================

    fn variables(interp: *Interpreter) !void {
        var varnames = try interp.stackPop();
        defer varnames.deinit(interp.allocator);

        switch (varnames) {
            .array_value => |arr| {
                const cur_module = interp.curModule();
                for (arr.items) |item| {
                    switch (item) {
                        .string_value => |var_name| {
                            // Validate variable name
                            if (std.mem.startsWith(u8, var_name, "__")) {
                                return errors.ForthicErrorType.InvalidVariableName;
                            }
                            try cur_module.addVariable(var_name, Value.initNull());
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    fn set(interp: *Interpreter) !void {
        var variable = try interp.stackPop();
        defer variable.deinit(interp.allocator);
        var value = try interp.stackPop();
        defer value.deinit(interp.allocator);

        // Handle both string names (auto-create) and Variable objects
        switch (variable) {
            .string_value => |var_name| {
                // Validate and ensure variable exists (validates no __ prefix)
                _ = try getOrCreateVariable(interp, var_name);

                // Clone the value and update in the module
                const cloned_value = try value.clone(interp.allocator);
                const cur_module = interp.curModule();
                try cur_module.setVariable(var_name, cloned_value);
            },
            else => {
                // Assume it's a Variable pointer stored as opaque pointer
                // For now, just handle string case
                return error.InvalidVariableType;
            },
        }
    }

    fn get(interp: *Interpreter) !void {
        var variable = try interp.stackPop();
        defer variable.deinit(interp.allocator);

        switch (variable) {
            .string_value => |var_name| {
                // Auto-create variable if string name
                const var_obj = try getOrCreateVariable(interp, var_name);
                const val = var_obj.getValue();
                try interp.stackPush(try val.clone(interp.allocator));
            },
            else => {
                return error.InvalidVariableType;
            },
        }
    }

    fn setGet(interp: *Interpreter) !void {
        var variable = try interp.stackPop();
        defer variable.deinit(interp.allocator);
        var value = try interp.stackPop();
        defer value.deinit(interp.allocator);

        switch (variable) {
            .string_value => |var_name| {
                // Validate and ensure variable exists (validates no __ prefix)
                _ = try getOrCreateVariable(interp, var_name);

                // Clone the value and update in the module
                const cloned_value = try value.clone(interp.allocator);
                const cur_module = interp.curModule();
                try cur_module.setVariable(var_name, cloned_value);

                // Push the value back on the stack
                try interp.stackPush(try value.clone(interp.allocator));
            },
            else => {
                return error.InvalidVariableType;
            },
        }
    }

    // ========================================
    // Module Operations
    // ========================================

    fn exportWord(interp: *Interpreter) !void {
        var names = try interp.stackPop();
        defer names.deinit(interp.allocator);

        switch (names) {
            .array_value => |arr| {
                var str_names = ArrayList([]const u8){};
                defer str_names.deinit(interp.allocator);

                for (arr.items) |item| {
                    switch (item) {
                        .string_value => |name| {
                            try str_names.append(interp.allocator, name);
                        },
                        else => {},
                    }
                }

                try interp.curModule().addExportable(str_names.items);
            },
            else => {},
        }
    }

    fn useModules(interp: *Interpreter) !void {
        var names = try interp.stackPop();
        defer names.deinit(interp.allocator);

        switch (names) {
            .null_value => {},
            .array_value => |arr| {
                for (arr.items) |item| {
                    switch (item) {
                        .string_value => |module_name| {
                            const module = try interp.findModule(module_name);
                            try interp.curModule().importModule("", module, interp);
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    // ========================================
    // Execution
    // ========================================

    fn interpret(interp: *Interpreter) !void {
        var str = try interp.stackPop();
        defer str.deinit(interp.allocator);

        switch (str) {
            .null_value => {},
            .string_value => |code| {
                try interp.run(code);
            },
            else => {},
        }
    }

    // ========================================
    // Control Flow
    // ========================================

    fn identity(interp: *Interpreter) !void {
        _ = interp;
        // No-op
    }

    fn nop(interp: *Interpreter) !void {
        _ = interp;
        // No-op
    }

    fn null_word(interp: *Interpreter) !void {
        try interp.stackPush(Value.initNull());
    }

    fn arrayCheck(interp: *Interpreter) !void {
        var value = try interp.stackPop();
        defer value.deinit(interp.allocator);

        const is_array = switch (value) {
            .array_value => true,
            else => false,
        };

        try interp.stackPush(Value.initBool(is_array));
    }

    fn default_word(interp: *Interpreter) !void {
        var default_value = try interp.stackPop();
        defer default_value.deinit(interp.allocator);
        var value = try interp.stackPop();
        defer value.deinit(interp.allocator);

        // Check if value is null or empty string
        const use_default = switch (value) {
            .null_value => true,
            .string_value => |s| s.len == 0,
            else => false,
        };

        if (use_default) {
            try interp.stackPush(try default_value.clone(interp.allocator));
        } else {
            try interp.stackPush(try value.clone(interp.allocator));
        }
    }

    fn defaultStar(interp: *Interpreter) !void {
        var default_forthic = try interp.stackPop();
        defer default_forthic.deinit(interp.allocator);
        var value = try interp.stackPop();
        defer value.deinit(interp.allocator);

        // Check if value is null or empty string
        const use_default = switch (value) {
            .null_value => true,
            .string_value => |s| s.len == 0,
            else => false,
        };

        if (use_default) {
            switch (default_forthic) {
                .string_value => |code| {
                    try interp.run(code);
                    const result = try interp.stackPop();
                    try interp.stackPush(result);
                },
                else => {
                    try interp.stackPush(try value.clone(interp.allocator));
                },
            }
        } else {
            try interp.stackPush(try value.clone(interp.allocator));
        }
    }

    // ========================================
    // Options
    // ========================================

    fn toOptions(interp: *Interpreter) !void {
        const array = try interp.stackPop();

        switch (array) {
            .array_value => |arr| {
                // Convert array to WordOptions
                // For now, create empty options (full implementation would parse array)
                const opts = WordOptions.init(interp.allocator);
                const opts_ptr = try interp.allocator.create(WordOptions);
                opts_ptr.* = opts;

                // Parse array: [.key1 val1 .key2 val2 ...]
                var i: usize = 0;
                while (i + 1 < arr.items.len) : (i += 2) {
                    // Keys should be strings (dot symbols)
                    const key_val = arr.items[i];
                    const val = arr.items[i + 1];

                    switch (key_val) {
                        .string_value => |key_str| {
                            // Store value
                            const val_ptr = try interp.allocator.create(Value);
                            val_ptr.* = try val.clone(interp.allocator);
                            try opts_ptr.options.put(key_str, val_ptr);
                        },
                        else => {},
                    }
                }

                // Create a Value to hold the WordOptions pointer
                // For now, we'll store it as an opaque pointer in a special wrapper
                // This is a simplification - full implementation would have a dedicated Value type
                try interp.stackPush(Value.initNull()); // Placeholder
            },
            else => {
                try interp.stackPush(Value.initNull());
            },
        }
    }

    // ========================================
    // Profiling (Placeholder implementations)
    // ========================================

    fn profileStart(interp: *Interpreter) !void {
        _ = interp;
        // TODO: Implement profiling in interpreter
    }

    fn profileEnd(interp: *Interpreter) !void {
        _ = interp;
        // TODO: Implement profiling in interpreter
    }

    fn profileTimestamp(interp: *Interpreter) !void {
        var label = try interp.stackPop();
        label.deinit(interp.allocator);
        // TODO: Implement profiling
    }

    fn profileData(interp: *Interpreter) !void {
        // TODO: Implement profiling
        var result = Value.initRecord(interp.allocator);
        const word_counts = Value.initArray(interp.allocator);
        const timestamps = Value.initArray(interp.allocator);

        // Duplicate keys for record - they will be freed in Value.deinit()
        const word_counts_key = try interp.allocator.dupe(u8, "word_counts");
        const timestamps_key = try interp.allocator.dupe(u8, "timestamps");

        try result.record_value.put(word_counts_key, word_counts);
        try result.record_value.put(timestamps_key, timestamps);

        try interp.stackPush(result);
    }

    // ========================================
    // Logging (Placeholder implementations)
    // ========================================

    fn startLog(interp: *Interpreter) !void {
        _ = interp;
        // TODO: Implement logging in interpreter
    }

    fn endLog(interp: *Interpreter) !void {
        _ = interp;
        // TODO: Implement logging in interpreter
    }

    // ========================================
    // String Operations
    // ========================================

    fn interpolate(interp: *Interpreter) !void {
        // Pop top value - could be string or options
        var top_val = try interp.stackPop();
        defer top_val.deinit(interp.allocator);

        var str: []const u8 = undefined;
        const separator: []const u8 = ", ";
        const null_text: []const u8 = "null";
        const use_json: bool = false;

        // Check if we have options (simplified - full impl would check WordOptions type)
        var needs_str_val_deinit = false;
        var str_val: Value = undefined;
        defer if (needs_str_val_deinit) str_val.deinit(interp.allocator);

        switch (top_val) {
            .string_value => |s| {
                str = s;
            },
            else => {
                // Assume options were passed, pop string
                str_val = try interp.stackPop();
                needs_str_val_deinit = true;
                str = switch (str_val) {
                    .string_value => |s| s,
                    else => "",
                };
            },
        }

        const result = try interpolateString(interp, str, separator, null_text, use_json);
        try interp.stackPush(Value.initString(result));
    }

    fn print(interp: *Interpreter) !void {
        const top_val = try interp.stackPop();

        var value: Value = undefined;
        const separator: []const u8 = ", ";
        const null_text: []const u8 = "null";
        const use_json: bool = false;

        // Check if we have options (simplified)
        value = top_val;

        var result: []const u8 = undefined;
        switch (value) {
            .string_value => |s| {
                // String: interpolate variables
                result = try interpolateString(interp, s, separator, null_text, use_json);
            },
            else => {
                // Non-string: format directly
                result = try valueToString(interp.allocator, value, separator, null_text, use_json);
            },
        }

        std.debug.print("{s}\n", .{result});
    }

    fn interpolateString(interp: *Interpreter, str: []const u8, separator: []const u8, null_text: []const u8, use_json: bool) ![]const u8 {
        if (str.len == 0) {
            return try interp.allocator.dupe(u8, "");
        }

        // Simple implementation: replace .varname with variable values
        // Full implementation would use regex or more sophisticated parsing

        var result = ArrayList(u8){};
        defer result.deinit(interp.allocator);

        var i: usize = 0;
        while (i < str.len) {
            // Check for escaped dot
            if (i + 1 < str.len and str[i] == '\\' and str[i + 1] == '.') {
                try result.append(interp.allocator, '.');
                i += 2;
                continue;
            }

            // Check for variable reference: .varname
            if (str[i] == '.' and (i == 0 or std.ascii.isWhitespace(str[i - 1]))) {
                // Extract variable name
                const start = i + 1;
                var end = start;
                while (end < str.len and (std.ascii.isAlphanumeric(str[end]) or str[end] == '_' or str[end] == '-')) {
                    end += 1;
                }

                if (end > start) {
                    const var_name = str[start..end];

                    // Get variable value
                    if (getOrCreateVariable(interp, var_name)) |var_obj| {
                        const val = var_obj.getValue();
                        const val_str = try valueToString(interp.allocator, val, separator, null_text, use_json);
                        try result.appendSlice(interp.allocator, val_str);
                        interp.allocator.free(val_str);
                    } else |_| {
                        // If variable doesn't exist, keep the original text
                        try result.append(interp.allocator, '.');
                        try result.appendSlice(interp.allocator, var_name);
                    }

                    i = end;
                    continue;
                }
            }

            try result.append(interp.allocator, str[i]);
            i += 1;
        }

        return result.toOwnedSlice(interp.allocator);
    }

    fn valueToString(allocator: Allocator, value: Value, separator: []const u8, null_text: []const u8, use_json: bool) ![]const u8 {
        _ = use_json; // TODO: implement JSON formatting

        switch (value) {
            .null_value => return try allocator.dupe(u8, null_text),
            .bool_value => |b| return try allocator.dupe(u8, if (b) "true" else "false"),
            .int_value => |i| return try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float_value => |f| return try std.fmt.allocPrint(allocator, "{d}", .{f}),
            .string_value => |s| return try allocator.dupe(u8, s),
            .array_value => |arr| {
                var result = ArrayList(u8){};
                defer result.deinit(allocator);

                for (arr.items, 0..) |item, idx| {
                    if (idx > 0) {
                        try result.appendSlice(allocator, separator);
                    }
                    const item_str = try valueToString(allocator, item, separator, null_text, false);
                    defer allocator.free(item_str);
                    try result.appendSlice(allocator, item_str);
                }

                return result.toOwnedSlice(allocator);
            },
            .record_value => {
                // Simple record formatting (full impl would use JSON)
                return try allocator.dupe(u8, "{Record}");
            },
            .datetime_value => |dt| {
                return try std.fmt.allocPrint(
                    allocator,
                    "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
                    .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second },
                );
            },
        }
    }

    // ========================================
    // Debug Operations
    // ========================================

    fn peek(interp: *Interpreter) !void {
        const stack = interp.getStack();
        const items = stack.items.items;

        if (items.len > 0) {
            const top = items[items.len - 1];
            const str = try top.toString(interp.allocator);
            defer interp.allocator.free(str);
            std.debug.print("{s}\n", .{str});
        } else {
            std.debug.print("<STACK EMPTY>\n", .{});
        }

        return errors.ForthicErrorType.IntentionalStop;
    }

    fn stackDebug(interp: *Interpreter) !void {
        const stack = interp.getStack();
        const items = stack.items.items;

        // Print stack from top to bottom (reversed)
        std.debug.print("[\n", .{});
        var i = items.len;
        while (i > 0) {
            i -= 1;
            const item = items[i];
            const str = try item.toString(interp.allocator);
            defer interp.allocator.free(str);
            std.debug.print("  {s}\n", .{str});
        }
        std.debug.print("]\n", .{});

        return errors.ForthicErrorType.IntentionalStop;
    }
};
