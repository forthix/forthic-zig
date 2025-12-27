const std = @import("std");
const Allocator = std.mem.Allocator;
const Module = @import("../../module.zig").Module;
const Interpreter = @import("../../interpreter.zig").Interpreter;

pub const JSONModule = struct {
    module: Module,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*JSONModule {
        const self = try allocator.create(JSONModule);
        self.* = .{
            .module = try Module.init(allocator, "json", ""),
            .allocator = allocator,
        };
        try self.registerWords();
        return self;
    }

    pub fn deinit(self: *JSONModule) void {
        self.module.deinit();
        self.allocator.destroy(self);
    }

    fn registerWords(self: *JSONModule) !void {
        try self.module.addWord(">JSON", toJson);
        try self.module.addWord("JSON>", fromJson);
        try self.module.addWord("JSON-PRETTIFY", jsonPrettify);
    }

    fn toJson(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        _ = val;
        // TODO: Serialize to JSON using std.json
        try interp.stackPush("null");
    }

    fn fromJson(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        _ = val;
        // TODO: Parse JSON using std.json
        try interp.stackPush(null);
    }

    fn jsonPrettify(interp: *Interpreter) !void {
        const val = try interp.stackPop();
        _ = val;
        // TODO: Serialize to JSON with indentation
        try interp.stackPush("null");
    }
};
