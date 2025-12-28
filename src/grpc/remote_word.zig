const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Word = @import("../forthic/word.zig").Word;
const Value = @import("../forthic/value.zig").Value;
const Interpreter = @import("../forthic/interpreter.zig").Interpreter;
const GrpcClient = @import("client.zig").GrpcClient;

/// Word that executes in a remote Forthic runtime via gRPC
pub const RemoteWord = struct {
    allocator: Allocator,
    name: []const u8,
    client: *GrpcClient,
    runtime_name: []const u8,
    module_name: []const u8,
    stack_effect: []const u8,
    description: []const u8,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        name: []const u8,
        client: *GrpcClient,
        runtime_name: []const u8,
        module_name: []const u8,
        stack_effect: []const u8,
        description: []const u8,
    ) !Self {
        return Self{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .client = client,
            .runtime_name = try allocator.dupe(u8, runtime_name),
            .module_name = try allocator.dupe(u8, module_name),
            .stack_effect = try allocator.dupe(u8, stack_effect),
            .description = try allocator.dupe(u8, description),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.runtime_name);
        self.allocator.free(self.module_name);
        self.allocator.free(self.stack_effect);
        self.allocator.free(self.description);
    }

    pub fn execute(self: *Self, interp: *Interpreter) !void {
        // Get current stack items
        const stack_items = interp.stack.items();

        // Execute remotely
        var result = try self.client.executeWord(self.name, stack_items);
        defer result.deinit(self.allocator);

        // Check for remote error
        if (result.remote_error) |err| {
            return error.RemoteExecutionFailed;
        }

        // Clear local stack
        interp.stack.clear();

        // Push result values
        for (result.values.items) |value| {
            const value_clone = try value.clone(self.allocator);
            try interp.stack.push(value_clone);
        }
    }

    pub fn getName(self: *const Self) []const u8 {
        return self.name;
    }

    pub fn getStackEffect(self: *const Self) []const u8 {
        return self.stack_effect;
    }

    pub fn getDescription(self: *const Self) []const u8 {
        return self.description;
    }
};
