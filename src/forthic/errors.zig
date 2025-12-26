const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// ============================================================================
/// Error Set
/// ============================================================================

pub const ForthicErrorType = error{
    UnknownWord,
    UnknownModule,
    StackUnderflow,
    WordExecution,
    MissingSemicolon,
    ExtraSemicolon,
    ModuleError,
    IntentionalStop,
    InvalidVariableName,
    OutOfMemory,
    InvalidFormat,
};

/// ============================================================================
/// Code Location
/// ============================================================================

pub const CodeLocation = struct {
    file: []const u8,
    line: usize,
    column: usize,

    pub fn init(file: []const u8, line: usize, column: usize) CodeLocation {
        return .{
            .file = file,
            .line = line,
            .column = column,
        };
    }

    pub fn format(
        self: CodeLocation,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (self.file.len == 0) {
            try writer.print("line {d}, col {d}", .{ self.line, self.column });
        } else {
            try writer.print("{s}:{d}:{d}", .{ self.file, self.line, self.column });
        }
    }
};

/// ============================================================================
/// Forthic Error
/// ============================================================================

pub const ForthicError = struct {
    message: []const u8,
    forthic: ?[]const u8,
    location: ?CodeLocation,
    cause: ?[]const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, message: []const u8) !ForthicError {
        const msg_copy = try allocator.dupe(u8, message);
        return ForthicError{
            .message = msg_copy,
            .forthic = null,
            .location = null,
            .cause = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ForthicError) void {
        self.allocator.free(self.message);
        if (self.forthic) |f| {
            self.allocator.free(f);
        }
        if (self.cause) |c| {
            self.allocator.free(c);
        }
    }

    pub fn withLocation(self: *ForthicError, location: CodeLocation) !void {
        self.location = location;
    }

    pub fn withForthic(self: *ForthicError, forthic: []const u8) !void {
        if (self.forthic) |f| {
            self.allocator.free(f);
        }
        self.forthic = try self.allocator.dupe(u8, forthic);
    }

    pub fn withCause(self: *ForthicError, cause: []const u8) !void {
        if (self.cause) |c| {
            self.allocator.free(c);
        }
        self.cause = try self.allocator.dupe(u8, cause);
    }

    pub fn format(
        self: ForthicError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(self.message);

        if (self.location) |loc| {
            try writer.print("\n  at {}", .{loc});
        }

        if (self.forthic) |f| {
            try writer.print("\n  in: {s}", .{f});
        }

        if (self.cause) |c| {
            try writer.print("\n  caused by: {s}", .{c});
        }
    }
};

/// ============================================================================
/// Specific Error Types
/// ============================================================================

pub const UnknownWordError = struct {
    base: ForthicError,
    word: []const u8,

    pub fn init(allocator: Allocator, word: []const u8) !UnknownWordError {
        const message = try std.fmt.allocPrint(allocator, "Unknown word: {s}", .{word});
        defer allocator.free(message);

        const word_copy = try allocator.dupe(u8, word);
        return UnknownWordError{
            .base = try ForthicError.init(allocator, message),
            .word = word_copy,
        };
    }

    pub fn deinit(self: *UnknownWordError) void {
        self.base.deinit();
        self.base.allocator.free(self.word);
    }
};

pub const UnknownModuleError = struct {
    base: ForthicError,
    module: []const u8,

    pub fn init(allocator: Allocator, module: []const u8) !UnknownModuleError {
        const message = try std.fmt.allocPrint(allocator, "Unknown module: {s}", .{module});
        defer allocator.free(message);

        const module_copy = try allocator.dupe(u8, module);
        return UnknownModuleError{
            .base = try ForthicError.init(allocator, message),
            .module = module_copy,
        };
    }

    pub fn deinit(self: *UnknownModuleError) void {
        self.base.deinit();
        self.base.allocator.free(self.module);
    }
};

pub const StackUnderflowError = struct {
    base: ForthicError,

    pub fn init(allocator: Allocator) !StackUnderflowError {
        return StackUnderflowError{
            .base = try ForthicError.init(allocator, "Stack underflow"),
        };
    }

    pub fn deinit(self: *StackUnderflowError) void {
        self.base.deinit();
    }
};

pub const WordExecutionError = struct {
    base: ForthicError,
    word: []const u8,

    pub fn init(allocator: Allocator, word: []const u8, cause: []const u8) !WordExecutionError {
        const message = try std.fmt.allocPrint(allocator, "Error executing word: {s}", .{word});
        defer allocator.free(message);

        const word_copy = try allocator.dupe(u8, word);
        var err = WordExecutionError{
            .base = try ForthicError.init(allocator, message),
            .word = word_copy,
        };
        try err.base.withCause(cause);
        return err;
    }

    pub fn deinit(self: *WordExecutionError) void {
        self.base.deinit();
        self.base.allocator.free(self.word);
    }
};

pub const MissingSemicolonError = struct {
    base: ForthicError,

    pub fn init(allocator: Allocator) !MissingSemicolonError {
        return MissingSemicolonError{
            .base = try ForthicError.init(allocator, "Missing semicolon (;) to end definition"),
        };
    }

    pub fn deinit(self: *MissingSemicolonError) void {
        self.base.deinit();
    }
};

pub const ExtraSemicolonError = struct {
    base: ForthicError,

    pub fn init(allocator: Allocator) !ExtraSemicolonError {
        return ExtraSemicolonError{
            .base = try ForthicError.init(allocator, "Extra semicolon (;) outside of definition"),
        };
    }

    pub fn deinit(self: *ExtraSemicolonError) void {
        self.base.deinit();
    }
};

pub const ModuleError = struct {
    base: ForthicError,
    module: []const u8,

    pub fn init(allocator: Allocator, module: []const u8, err_message: []const u8) !ModuleError {
        const message = try std.fmt.allocPrint(allocator, "Module error in {s}: {s}", .{ module, err_message });
        defer allocator.free(message);

        const module_copy = try allocator.dupe(u8, module);
        return ModuleError{
            .base = try ForthicError.init(allocator, message),
            .module = module_copy,
        };
    }

    pub fn deinit(self: *ModuleError) void {
        self.base.deinit();
        self.base.allocator.free(self.module);
    }
};

pub const IntentionalStopError = struct {
    base: ForthicError,

    pub fn init(allocator: Allocator, message: []const u8) !IntentionalStopError {
        return IntentionalStopError{
            .base = try ForthicError.init(allocator, message),
        };
    }

    pub fn deinit(self: *IntentionalStopError) void {
        self.base.deinit();
    }
};

pub const InvalidVariableNameError = struct {
    base: ForthicError,
    var_name: []const u8,

    pub fn init(allocator: Allocator, var_name: []const u8) !InvalidVariableNameError {
        const message = try std.fmt.allocPrint(allocator, "Invalid variable name: {s}", .{var_name});
        defer allocator.free(message);

        const var_name_copy = try allocator.dupe(u8, var_name);
        return InvalidVariableNameError{
            .base = try ForthicError.init(allocator, message),
            .var_name = var_name_copy,
        };
    }

    pub fn deinit(self: *InvalidVariableNameError) void {
        self.base.deinit();
        self.base.allocator.free(self.var_name);
    }
};
