const std = @import("std");
const Allocator = std.mem.Allocator;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;
const helpers = @import("helpers.zig");

pub const BooleanModule = struct {
    module: Module,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*BooleanModule {
        const self = try allocator.create(BooleanModule);
        self.* = .{
            .module = try Module.init(allocator, "boolean", ""),
            .allocator = allocator,
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *BooleanModule) void {
        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn registerWords(self: *BooleanModule) !void {
        try self.module.addWord("==", equal);
        try self.module.addWord("!=", notEqual);
        try self.module.addWord("<", lessThan);
        try self.module.addWord(">", greaterThan);
        try self.module.addWord("<=", lessThanOrEqual);
        try self.module.addWord(">=", greaterThanOrEqual);
        try self.module.addWord("AND", andOp);
        try self.module.addWord("OR", orOp);
        try self.module.addWord("NOT", notOp);
        try self.module.addWord("TRUE", trueOp);
        try self.module.addWord("FALSE", falseOp);
        try self.module.addWord("NULL", nullOp);
        try self.module.addWord("IN", inOp);
    }

    fn equal(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        try interp.stackPush(helpers.Helpers.areEqual(a, b));
    }

    fn notEqual(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        try interp.stackPush(!helpers.Helpers.areEqual(a, b));
    }

    fn lessThan(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);
        const result = if (numA != null and numB != null) numA.? < numB.? else false;
        try interp.stackPush(result);
    }

    fn greaterThan(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);
        const result = if (numA != null and numB != null) numA.? > numB.? else false;
        try interp.stackPush(result);
    }

    fn lessThanOrEqual(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);
        const result = if (numA != null and numB != null) numA.? <= numB.? else false;
        try interp.stackPush(result);
    }

    fn greaterThanOrEqual(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        const numA = helpers.Helpers.toNumber(a);
        const numB = helpers.Helpers.toNumber(b);
        const result = if (numA != null and numB != null) numA.? >= numB.? else false;
        try interp.stackPush(result);
    }

    fn andOp(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        try interp.stackPush(helpers.Helpers.isTruthy(a) and helpers.Helpers.isTruthy(b));
    }

    fn orOp(interp: *Interpreter) !void {
        const b = try interp.stackPop();
        const a = try interp.stackPop();
        try interp.stackPush(helpers.Helpers.isTruthy(a) or helpers.Helpers.isTruthy(b));
    }

    fn notOp(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        try interp.stackPush(!helpers.Helpers.isTruthy(val));
    }

    fn trueOp(interp: *Interpreter) !void {
        try interp.stackPush(true);
    }

    fn falseOp(interp: *Interpreter) !void {
        try interp.stackPush(false);
    }

    fn nullOp(interp: *Interpreter) !void {
        try interp.stackPush(null);
    }

    fn inOp(interp: *Interpreter) !void {
        const container = try interp.stackPop();
        const item = try interp.stackPop();
        _ = container;
        _ = item;
        // TODO: Check if item in container (array or map)
        try interp.stackPush(false);
    }
};
