const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Value = @import("../forthic/value.zig").Value;
const c_bindings = @import("c_bindings.zig");
const serializer = @import("serializer.zig");

// =============================================================================
// Error Types
// =============================================================================

pub const ClientError = error{
    ConnectionFailed,
    ExecutionFailed,
    InvalidAddress,
    SerializationError,
    DeserializationError,
} || c_bindings.GrpcError || Allocator.Error;

/// Remote execution error with context
pub const RemoteError = struct {
    message: []const u8,
    runtime: []const u8,
    error_type: []const u8,

    pub fn deinit(self: *RemoteError, allocator: Allocator) void {
        allocator.free(self.message);
        allocator.free(self.runtime);
        allocator.free(self.error_type);
    }
};

// =============================================================================
// GrpcClient
// =============================================================================

/// High-level gRPC client for executing words in remote Forthic runtimes
pub const GrpcClient = struct {
    allocator: Allocator,
    c_client: *c_bindings.GrpcClient,
    address: []const u8,

    const Self = @This();

    /// Create a new gRPC client connected to the specified address
    /// Address format: "host:port" (e.g., "localhost:50051")
    pub fn init(allocator: Allocator, address: []const u8) ClientError!Self {
        // Create null-terminated address for C
        const c_address = allocator.dupeZ(u8, address) catch return error.InvalidAddress;
        defer allocator.free(c_address);

        const c_client = c_bindings.grpcClientCreate(c_address.ptr) catch |err| {
            return switch (err) {
                error.InvalidArgument => error.InvalidAddress,
                error.Unavailable => error.ConnectionFailed,
                else => error.ConnectionFailed,
            };
        };

        const address_copy = try allocator.dupe(u8, address);

        return Self{
            .allocator = allocator,
            .c_client = c_client,
            .address = address_copy,
        };
    }

    /// Close the client and free resources
    pub fn deinit(self: *Self) void {
        c_bindings.grpcClientDestroy(self.c_client);
        self.allocator.free(self.address);
    }

    /// Execute a word in the remote runtime
    ///
    /// Args:
    ///   - word_name: Name of the word to execute
    ///   - stack: Current stack values to pass to the word
    ///
    /// Returns:
    ///   - ArrayList of result values (caller owns and must deinit)
    ///
    /// Errors:
    ///   - Returns ClientError if the gRPC call fails
    ///   - Returns RemoteError if the remote execution fails
    pub fn executeWord(
        self: *Self,
        word_name: []const u8,
        stack: []const Value,
    ) ClientError!ExecuteWordResult {
        // Serialize input stack
        var stack_values = serializer.serializeValueSlice(self.allocator, stack) catch {
            return error.SerializationError;
        };
        defer serializer.freeStackValueArray(self.allocator, stack_values);

        // Convert to const slice for C API
        var const_stack = try self.allocator.alloc(*const c_bindings.StackValue, stack_values.len);
        defer self.allocator.free(const_stack);

        for (stack_values, 0..) |sv, i| {
            const_stack[i] = sv orelse return error.SerializationError;
        }

        // Create C string for word name
        const c_word_name = try self.allocator.dupeZ(u8, word_name);
        defer self.allocator.free(c_word_name);

        // Execute the word via gRPC
        var result = try c_bindings.grpcClientExecuteWord(
            self.c_client,
            c_word_name.ptr,
            const_stack,
        );

        // Check for remote execution error
        if (result.error_info) |err_info| {
            defer c_bindings.errorInfoDestroy(err_info);

            const message = try self.allocator.dupe(u8, std.mem.span(c_bindings.errorInfoGetMessage(err_info)));
            const runtime = try self.allocator.dupe(u8, std.mem.span(c_bindings.errorInfoGetRuntime(err_info)));
            const error_type = try self.allocator.dupe(u8, std.mem.span(c_bindings.errorInfoGetErrorType(err_info)));

            // Clean up result stack if present
            if (result.result_stack.len > 0) {
                result.deinit();
            }

            return ExecuteWordResult{
                .values = ArrayList(Value).init(self.allocator),
                .remote_error = RemoteError{
                    .message = message,
                    .runtime = runtime,
                    .error_type = error_type,
                },
            };
        }

        // Deserialize result stack
        var values = ArrayList(Value).init(self.allocator);
        errdefer {
            for (values.items) |*val| {
                val.deinit(self.allocator);
            }
            values.deinit();
        }

        for (result.result_stack) |stack_value| {
            const value = serializer.deserializeValue(self.allocator, stack_value) catch {
                // Clean up partial results
                result.deinit();
                return error.DeserializationError;
            };
            try values.append(self.allocator, value);
        }

        // Clean up C result
        result.deinit();

        return ExecuteWordResult{
            .values = values,
            .remote_error = null,
        };
    }

    /// Execute a word and expect a single result value
    /// Convenience wrapper around executeWord for common case
    pub fn executeWordSingle(
        self: *Self,
        word_name: []const u8,
        stack: []const Value,
    ) ClientError!Value {
        var result = try self.executeWord(word_name, stack);
        defer result.deinit(self.allocator);

        if (result.remote_error) |_| {
            return error.ExecutionFailed;
        }

        if (result.values.items.len == 0) {
            return Value.initNull();
        }

        if (result.values.items.len > 1) {
            return error.ExecutionFailed;
        }

        return try result.values.items[0].clone(self.allocator);
    }

    /// Execute a word with empty stack
    /// Convenience wrapper for words that don't take arguments
    pub fn executeWordNoArgs(
        self: *Self,
        word_name: []const u8,
    ) ClientError!ExecuteWordResult {
        const empty_stack = [_]Value{};
        return self.executeWord(word_name, &empty_stack);
    }
};

// =============================================================================
// Result Types
// =============================================================================

pub const ExecuteWordResult = struct {
    values: ArrayList(Value),
    remote_error: ?RemoteError,

    pub fn deinit(self: *ExecuteWordResult, allocator: Allocator) void {
        for (self.values.items) |*val| {
            val.deinit(allocator);
        }
        self.values.deinit();

        if (self.remote_error) |*err| {
            err.deinit(allocator);
        }
    }

    pub fn isError(self: *const ExecuteWordResult) bool {
        return self.remote_error != null;
    }

    pub fn getError(self: *const ExecuteWordResult) ?RemoteError {
        return self.remote_error;
    }

    pub fn getValues(self: *const ExecuteWordResult) []const Value {
        return self.values.items;
    }
};

// =============================================================================
// Helper Functions
// =============================================================================

/// Create a GrpcClient for localhost with default port
pub fn initLocalhost(allocator: Allocator) ClientError!GrpcClient {
    return GrpcClient.init(allocator, "localhost:50051");
}

/// Create a GrpcClient for localhost with custom port
pub fn initLocalhostPort(allocator: Allocator, port: u16) ClientError!GrpcClient {
    var buf: [32]u8 = undefined;
    const address = std.fmt.bufPrint(&buf, "localhost:{d}", .{port}) catch {
        return error.InvalidAddress;
    };
    return GrpcClient.init(allocator, address);
}
