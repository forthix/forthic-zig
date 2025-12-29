const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;
const Value = @import("../../value.zig").Value;
const helpers = @import("helpers.zig");
const word_mod = @import("../../word.zig");
const ModuleWord = word_mod.ModuleWord;

pub const MathModule = struct {
    module: Module,
    allocator: Allocator,
    word_ptrs: ArrayList(*ModuleWord),

    pub fn init(allocator: Allocator) !*MathModule {
        const self = try allocator.create(MathModule);
        self.* = .{
            .module = Module.init(allocator, "math", ""),
            .allocator = allocator,
            .word_ptrs = ArrayList(*ModuleWord){},
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *MathModule) void {
        // Free word pointers
        for (self.word_ptrs.items) |word_ptr| {
            word_ptr.asWord().deinit(self.allocator);
            self.allocator.destroy(word_ptr);
        }
        self.word_ptrs.deinit(self.allocator);

        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn addModuleWord(self: *MathModule, name: []const u8, handler: word_mod.HandlerFn) !void {
        const word_ptr = try self.allocator.create(ModuleWord);
        word_ptr.* = ModuleWord.init(self.allocator, name, handler);
        try self.word_ptrs.append(self.allocator, word_ptr);  // Track for cleanup
        try self.module.addExportableWord(word_ptr.asWord());
    }

    fn registerWords(self: *MathModule) !void {
        // Arithmetic
        try self.addModuleWord("+", plus);
        try self.addModuleWord("ADD", plus);
        try self.addModuleWord("-", minus);
        try self.addModuleWord("SUBTRACT", minus);
        try self.addModuleWord("*", times);
        try self.addModuleWord("MULTIPLY", times);
        try self.addModuleWord("/", divide);
        try self.addModuleWord("DIVIDE", divide);
        try self.addModuleWord("MOD", mod);

        // Aggregates
        try self.addModuleWord("SUM", sum);
        try self.addModuleWord("MEAN", mean);
        try self.addModuleWord("MAX", max);
        try self.addModuleWord("MIN", min);

        // Conversions
        try self.addModuleWord(">INT", toInt);
        try self.addModuleWord(">FLOAT", toFloat);
        try self.addModuleWord("ROUND", round);
        try self.addModuleWord(">FIXED", toFixed);

        // Functions
        try self.addModuleWord("ABS", abs);
        try self.addModuleWord("SQRT", sqrt);
        try self.addModuleWord("FLOOR", floor);
        try self.addModuleWord("CEIL", ceil);
        try self.addModuleWord("CLAMP", clamp);

        // Special
        try self.addModuleWord("INFINITY", infinity);
        try self.addModuleWord("UNIFORM-RANDOM", uniformRandom);
    }

    fn plus(interp: *Interpreter) !void {
        const b = try interp.stackPop();

        // TODO: Case 1: Array on stack - sum all elements

        // Case 2: Two numbers
        const a = try interp.stackPop();

        // Preserve integer types when both are integers
        if (a == .int_value and b == .int_value) {
            const result = a.int_value + b.int_value;
            try interp.stackPush(Value.initInt(result));
            return;
        }

        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);

        if (numA == null or numB == null) {
            try interp.stackPush(Value.initNull());
            return;
        }

        const result = numA.? + numB.?;
        try interp.stackPush(Value.initFloat(result));
    }

    fn minus(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();

        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);

        if (numA == null or numB == null) {
            try interp.stackPush(Value.initNull());
            return;
        }

        try interp.stackPush(Value.initFloat(numA.? - numB.?));
    }

    fn times(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();

        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);

        if (numA == null or numB == null) {
            try interp.stackPush(Value.initNull());
            return;
        }

        try interp.stackPush(Value.initFloat(numA.? * numB.?));
    }

    fn divide(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();

        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);

        if (numA == null or numB == null or numB.? == 0) {
            try interp.stackPush(Value.initNull());
            return;
        }

        try interp.stackPush(Value.initFloat(numA.? / numB.?));
    }

    fn mod(interp: *Interpreter) !void {
        const n = try interp.stackPop();
        const m = try interp.stackPop();

        const numM = helpers.Helpers.toNumber(m);
        const numN = helpers.Helpers.toNumber(n);

        if (numM == null or numN == null) {
            try interp.stackPush(Value.initNull());
            return;
        }

        const result = @mod(@as(i64, @intFromFloat(numM.?)), @as(i64, @intFromFloat(numN.?)));
        try interp.stackPush(Value.initInt(result));
    }

    fn sum(interp: *Interpreter) !void {
        const items = try interp.stackPop();
        _ = items; // TODO: Implement array sum
        try interp.stackPush(Value.initFloat(0.0));
    }

    fn mean(interp: *Interpreter) !void {
        const items = try interp.stackPop();
        _ = items; // TODO: Implement array mean
        try interp.stackPush(Value.initFloat(0.0));
    }

    fn max(interp: *Interpreter) !void {
        const items = try interp.stackPop();
        _ = items; // TODO: Implement array max
        try interp.stackPush(Value.initNull());
    }

    fn min(interp: *Interpreter) !void {
        const items = try interp.stackPop();
        _ = items; // TODO: Implement array min
        try interp.stackPush(Value.initNull());
    }

    fn toInt(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const num = helpers.Helpers.toNumber(val);
        const result = if (num) |n| @as(i64, @intFromFloat(n)) else 0;
        try interp.stackPush(Value.initInt(result));
    }

    fn toFloat(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const num = helpers.Helpers.toNumber(val);
        try interp.stackPush(Value.initFloat(num orelse 0.0));
    }

    fn round(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const num = helpers.Helpers.toNumber(val);
        try interp.stackPush(Value.initFloat(if (num) |n| @round(n) else 0.0));
    }

    fn toFixed(interp: *Interpreter) !void {
        const decimals = try interp.stackPop();
        const val = try interp.stackPop();
        _ = decimals;
        _ = val;
        // TODO: Format number to fixed decimals
        const empty_str = try interp.allocator.dupe(u8, "");
        try interp.stackPush(Value.initString(empty_str));
    }

    fn abs(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const num = helpers.Helpers.toNumber(val);
        try interp.stackPush(Value.initFloat(if (num) |n| @abs(n) else 0.0));
    }

    fn sqrt(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const num = helpers.Helpers.toNumber(val);
        try interp.stackPush(Value.initFloat(if (num) |n| @sqrt(n) else 0.0));
    }

    fn floor(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const num = helpers.Helpers.toNumber(val);
        try interp.stackPush(Value.initFloat(if (num) |n| @floor(n) else 0.0));
    }

    fn ceil(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        const num = helpers.Helpers.toNumber(val);
        try interp.stackPush(Value.initFloat(if (num) |n| @ceil(n) else 0.0));
    }

    fn clamp(interp: *Interpreter) !void {
        const max_val = try interp.stackPop();
        const min_val = try interp.stackPop();
        const val = try interp.stackPop();

        const num = helpers.Helpers.toNumber(val);
        const min_num = helpers.Helpers.toNumber(min_val);
        const max_num = helpers.Helpers.toNumber(max_val);

        if (num == null or min_num == null or max_num == null) {
            try interp.stackPush(Value.initNull());
            return;
        }

        const result = @max(min_num.?, @min(max_num.?, num.?));
        try interp.stackPush(Value.initFloat(result));
    }

    fn infinity(interp: *Interpreter) !void {
        try interp.stackPush(Value.initFloat(std.math.inf(f64)));
    }

    fn uniformRandom(interp: *Interpreter) !void {
        const max_val = try interp.stackPop();
        const min_val = try interp.stackPop();

        const min_num = helpers.Helpers.toNumber(min_val) orelse 0.0;
        const max_num = helpers.Helpers.toNumber(max_val) orelse 1.0;

        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();
        const result = min_num + (random.float(f64) * (max_num - min_num));

        try interp.stackPush(Value.initFloat(result));
    }
};
