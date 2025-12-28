const std = @import("std");

// Import the C wrapper header
const c = @cImport({
    @cInclude("grpc_c_wrapper.h");
});

// =============================================================================
// Error Types
// =============================================================================

pub const GrpcError = error{
    InvalidArgument,
    NotFound,
    AlreadyExists,
    PermissionDenied,
    ResourceExhausted,
    FailedPrecondition,
    Aborted,
    OutOfRange,
    Unimplemented,
    Internal,
    Unavailable,
    DataLoss,
    Unauthenticated,
    Unknown,
};

fn grpcErrorFromCode(code: c.GrpcErrorCode) GrpcError!void {
    return switch (code) {
        c.GRPC_OK => {},
        c.GRPC_ERROR_INVALID_ARGUMENT => error.InvalidArgument,
        c.GRPC_ERROR_NOT_FOUND => error.NotFound,
        c.GRPC_ERROR_ALREADY_EXISTS => error.AlreadyExists,
        c.GRPC_ERROR_PERMISSION_DENIED => error.PermissionDenied,
        c.GRPC_ERROR_RESOURCE_EXHAUSTED => error.ResourceExhausted,
        c.GRPC_ERROR_FAILED_PRECONDITION => error.FailedPrecondition,
        c.GRPC_ERROR_ABORTED => error.Aborted,
        c.GRPC_ERROR_OUT_OF_RANGE => error.OutOfRange,
        c.GRPC_ERROR_UNIMPLEMENTED => error.Unimplemented,
        c.GRPC_ERROR_INTERNAL => error.Internal,
        c.GRPC_ERROR_UNAVAILABLE => error.Unavailable,
        c.GRPC_ERROR_DATA_LOSS => error.DataLoss,
        c.GRPC_ERROR_UNAUTHENTICATED => error.Unauthenticated,
        else => error.Unknown,
    };
}

// =============================================================================
// Type Aliases
// =============================================================================

pub const StackValue = c.StackValue;
pub const StackValueType = c.StackValueType;
pub const GrpcClient = c.GrpcClient;
pub const GrpcServer = c.GrpcServer;
pub const ErrorInfo = c.ErrorInfo;

// Stack value types
pub const STACK_VALUE_NULL = c.STACK_VALUE_NULL;
pub const STACK_VALUE_INT = c.STACK_VALUE_INT;
pub const STACK_VALUE_STRING = c.STACK_VALUE_STRING;
pub const STACK_VALUE_BOOL = c.STACK_VALUE_BOOL;
pub const STACK_VALUE_FLOAT = c.STACK_VALUE_FLOAT;
pub const STACK_VALUE_ARRAY = c.STACK_VALUE_ARRAY;
pub const STACK_VALUE_RECORD = c.STACK_VALUE_RECORD;
pub const STACK_VALUE_INSTANT = c.STACK_VALUE_INSTANT;
pub const STACK_VALUE_PLAIN_DATE = c.STACK_VALUE_PLAIN_DATE;
pub const STACK_VALUE_ZONED_DATETIME = c.STACK_VALUE_ZONED_DATETIME;

// =============================================================================
// StackValue API
// =============================================================================

pub fn stackValueCreateNull() ?*StackValue {
    return c.stack_value_create_null();
}

pub fn stackValueCreateInt(value: i64) ?*StackValue {
    return c.stack_value_create_int(value);
}

pub fn stackValueCreateString(value: [*:0]const u8) ?*StackValue {
    return c.stack_value_create_string(value);
}

pub fn stackValueCreateBool(value: bool) ?*StackValue {
    return c.stack_value_create_bool(value);
}

pub fn stackValueCreateFloat(value: f64) ?*StackValue {
    return c.stack_value_create_float(value);
}

pub fn stackValueCreateArray(items: []*const StackValue, len: usize) ?*StackValue {
    return c.stack_value_create_array(@ptrCast(items.ptr), len);
}

pub fn stackValueGetType(value: *const StackValue) StackValueType {
    return c.stack_value_get_type(value);
}

pub fn stackValueGetInt(value: *const StackValue) i64 {
    return c.stack_value_get_int(value);
}

pub fn stackValueGetString(value: *const StackValue) [*:0]const u8 {
    return c.stack_value_get_string(value);
}

pub fn stackValueGetBool(value: *const StackValue) bool {
    return c.stack_value_get_bool(value);
}

pub fn stackValueGetFloat(value: *const StackValue) f64 {
    return c.stack_value_get_float(value);
}

pub const ArrayItems = struct {
    items: []*const StackValue,
    len: usize,

    pub fn deinit(self: *ArrayItems) void {
        // Free the items array (items themselves owned by caller)
        if (self.len > 0) {
            // Cast away const for free
            const items_mut = @constCast(self.items);
            for (items_mut) |item| {
                stackValueDestroy(@constCast(item));
            }
        }
    }
};

pub fn stackValueGetArray(value: *const StackValue) ArrayItems {
    var items: [*c][*c]const StackValue = null;
    var len: usize = 0;
    c.stack_value_get_array(value, &items, &len);

    if (len == 0 or items == null) {
        return ArrayItems{ .items = &[_]*const StackValue{}, .len = 0 };
    }

    const slice = @as([*]*const StackValue, @ptrCast(items))[0..len];
    return ArrayItems{ .items = slice, .len = len };
}

pub fn stackValueDestroy(value: *StackValue) void {
    c.stack_value_destroy(value);
}

pub fn stackValueArrayDestroy(array: []*StackValue, len: usize) void {
    c.stack_value_array_destroy(@ptrCast(array.ptr), len);
}

// =============================================================================
// Client API
// =============================================================================

pub fn grpcClientCreate(address: [*:0]const u8) GrpcError!*GrpcClient {
    var client: ?*GrpcClient = null;
    const err_code = c.grpc_client_create(address, &client);
    try grpcErrorFromCode(err_code);
    return client orelse return error.Internal;
}

pub const ExecuteWordResult = struct {
    result_stack: []*StackValue,
    error_info: ?*ErrorInfo,

    pub fn deinit(self: *ExecuteWordResult) void {
        if (self.result_stack.len > 0) {
            stackValueArrayDestroy(self.result_stack, self.result_stack.len);
        }
        if (self.error_info) |err_info| {
            errorInfoDestroy(err_info);
        }
    }
};

pub fn grpcClientExecuteWord(
    client: *GrpcClient,
    word_name: [*:0]const u8,
    stack: []*const StackValue,
) GrpcError!ExecuteWordResult {
    var result_stack: [*c][*c]StackValue = null;
    var result_len: usize = 0;
    var error_info: ?*ErrorInfo = null;

    const err_code = c.grpc_client_execute_word(
        client,
        word_name,
        @ptrCast(stack.ptr),
        stack.len,
        &result_stack,
        &result_len,
        &error_info,
    );

    try grpcErrorFromCode(err_code);

    // Convert C array to Zig slice
    const result_slice = if (result_len > 0)
        @as([*]*StackValue, @ptrCast(result_stack))[0..result_len]
    else
        &[_]*StackValue{};

    return ExecuteWordResult{
        .result_stack = result_slice,
        .error_info = error_info,
    };
}

pub fn grpcClientDestroy(client: *GrpcClient) void {
    c.grpc_client_destroy(client);
}

// =============================================================================
// ErrorInfo API
// =============================================================================

pub fn errorInfoGetMessage(error_info: *const ErrorInfo) [*:0]const u8 {
    return c.error_info_get_message(error_info);
}

pub fn errorInfoGetRuntime(error_info: *const ErrorInfo) [*:0]const u8 {
    return c.error_info_get_runtime(error_info);
}

pub fn errorInfoGetErrorType(error_info: *const ErrorInfo) [*:0]const u8 {
    return c.error_info_get_error_type(error_info);
}

pub fn errorInfoDestroy(error_info: *ErrorInfo) void {
    c.error_info_destroy(error_info);
}

// =============================================================================
// Server API (Stubs)
// =============================================================================

pub fn grpcServerCreate(port: u16) GrpcError!*GrpcServer {
    var server: ?*GrpcServer = null;
    const err_code = c.forthic_grpc_server_create(port, &server);
    try grpcErrorFromCode(err_code);
    return server orelse return error.Internal;
}

pub fn grpcServerStart(server: *GrpcServer) GrpcError!void {
    const err_code = c.forthic_grpc_server_start(server);
    try grpcErrorFromCode(err_code);
}

pub fn grpcServerStop(server: *GrpcServer) GrpcError!void {
    const err_code = c.forthic_grpc_server_stop(server);
    try grpcErrorFromCode(err_code);
}

pub fn grpcServerDestroy(server: *GrpcServer) void {
    c.forthic_grpc_server_destroy(server);
}
