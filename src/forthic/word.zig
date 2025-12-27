const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const errors = @import("errors.zig");

// Forward declaration
pub const Interpreter = @import("interpreter.zig").Interpreter;

/// ============================================================================
/// Error Handler
/// ============================================================================

pub const ErrorHandler = *const fn (err: anyerror, word: *Word, interp: *Interpreter) anyerror!void;

/// ============================================================================
/// RuntimeInfo
/// ============================================================================

pub const RuntimeInfo = struct {
    runtime: []const u8 = "local",
    is_remote: bool = false,
    is_standard: bool = false,
    available_in: []const []const u8,

    pub fn init(allocator: Allocator) !RuntimeInfo {
        var available = try allocator.alloc([]const u8, 1);
        available[0] = "zig";
        return RuntimeInfo{
            .available_in = available,
        };
    }

    pub fn deinit(self: *RuntimeInfo, allocator: Allocator) void {
        allocator.free(self.available_in);
    }
};

/// ============================================================================
/// Word Interface (via VTable)
/// ============================================================================

pub const Word = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        execute: *const fn (ptr: *anyopaque, interp: *Interpreter) anyerror!void,
        getName: *const fn (ptr: *anyopaque) []const u8,
        getLocation: *const fn (ptr: *anyopaque) ?errors.CodeLocation,
        setLocation: *const fn (ptr: *anyopaque, loc: ?errors.CodeLocation) void,
        deinit: *const fn (ptr: *anyopaque, allocator: Allocator) void,
    };

    pub fn execute(self: Word, interp: *Interpreter) !void {
        return self.vtable.execute(self.ptr, interp);
    }

    pub fn getName(self: Word) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    pub fn getLocation(self: Word) ?errors.CodeLocation {
        return self.vtable.getLocation(self.ptr);
    }

    pub fn setLocation(self: Word, loc: ?errors.CodeLocation) void {
        self.vtable.setLocation(self.ptr, loc);
    }

    pub fn deinit(self: Word, allocator: Allocator) void {
        self.vtable.deinit(self.ptr, allocator);
    }
};

/// ============================================================================
/// PushValueWord - Pushes a value onto the stack
/// ============================================================================

pub const PushValueWord = struct {
    name: []const u8,
    value: ?*anyopaque,
    location: ?errors.CodeLocation,

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn init(name: []const u8, value: ?*anyopaque) PushValueWord {
        return PushValueWord{
            .name = name,
            .value = value,
            .location = null,
        };
    }

    pub fn asWord(self: *PushValueWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *PushValueWord = @ptrCast(@alignCast(ptr));
        try interp.stackPush(self.value);
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *PushValueWord = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *PushValueWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *PushValueWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        _ = allocator;
        _ = ptr;
        // Value ownership is not managed by the word
    }
};

/// ============================================================================
/// ModuleWord - Word with handler function and error handler support
/// ============================================================================

pub const HandlerFn = *const fn (interp: *Interpreter) anyerror!void;

pub const ModuleWord = struct {
    name: []const u8,
    handler: HandlerFn,
    location: ?errors.CodeLocation,
    error_handlers: ArrayList(ErrorHandler),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, handler: HandlerFn) ModuleWord {
        return ModuleWord{
            .name = name,
            .handler = handler,
            .location = null,
            .error_handlers = ArrayList(ErrorHandler){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleWord) void {
        self.error_handlers.deinit(self.allocator);
    }

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn asWord(self: *ModuleWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *ModuleWord = @ptrCast(@alignCast(ptr));
        self.handler(interp) catch |err| {
            // Try error handlers
            for (self.error_handlers.items) |handler| {
                handler(err, self.asWord(), interp) catch continue;
                return; // Handler succeeded
            }
            return err; // No handler succeeded, propagate error
        };
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *ModuleWord = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *ModuleWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *ModuleWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        const self: *ModuleWord = @ptrCast(@alignCast(ptr));
        _ = allocator;
        self.deinit();
    }

    pub fn addErrorHandler(self: *ModuleWord, handler: ErrorHandler) !void {
        try self.error_handlers.append(self.allocator, handler);
    }
};

/// ============================================================================
/// DefinitionWord - Sequence of words
/// ============================================================================

pub const DefinitionWord = struct {
    name: []const u8,
    words: ArrayList(Word),
    location: ?errors.CodeLocation,
    error_handlers: ArrayList(ErrorHandler),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) DefinitionWord {
        return DefinitionWord{
            .name = name,
            .words = ArrayList(Word){},
            .location = null,
            .error_handlers = ArrayList(ErrorHandler){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DefinitionWord) void {
        self.words.deinit(self.allocator);
        self.error_handlers.deinit(self.allocator);
    }

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn asWord(self: *DefinitionWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn addWord(self: *DefinitionWord, word: Word) !void {
        try self.words.append(self.allocator, word);
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *DefinitionWord = @ptrCast(@alignCast(ptr));
        for (self.words.items) |word| {
            word.execute(interp) catch |err| {
                // Try error handlers
                for (self.error_handlers.items) |handler| {
                    handler(err, self.asWord(), interp) catch continue;
                    continue; // Handler succeeded, continue with next word
                }
                return err; // No handler succeeded, propagate error
            };
        }
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *DefinitionWord = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *DefinitionWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *DefinitionWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        const self: *DefinitionWord = @ptrCast(@alignCast(ptr));
        _ = allocator;
        self.deinit();
    }
};
