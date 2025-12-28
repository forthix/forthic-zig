/**
 * C Wrapper for C++ gRPC - Bridge for Zig FFI
 *
 * This header provides a pure C interface to the C++ gRPC implementation,
 * allowing Zig to easily call gRPC functions through its excellent C interop.
 */

#ifndef FORTHIC_GRPC_C_WRAPPER_H
#define FORTHIC_GRPC_C_WRAPPER_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Opaque Types (hide C++ implementation details)
// =============================================================================

typedef struct GrpcServer GrpcServer;
typedef struct GrpcClient GrpcClient;
typedef struct StackValue StackValue;
typedef struct ErrorInfo ErrorInfo;

// =============================================================================
// Error Codes
// =============================================================================

typedef enum {
    GRPC_OK = 0,
    GRPC_ERROR_INVALID_ARGUMENT = 1,
    GRPC_ERROR_NOT_FOUND = 2,
    GRPC_ERROR_ALREADY_EXISTS = 3,
    GRPC_ERROR_PERMISSION_DENIED = 4,
    GRPC_ERROR_RESOURCE_EXHAUSTED = 5,
    GRPC_ERROR_FAILED_PRECONDITION = 6,
    GRPC_ERROR_ABORTED = 7,
    GRPC_ERROR_OUT_OF_RANGE = 8,
    GRPC_ERROR_UNIMPLEMENTED = 9,
    GRPC_ERROR_INTERNAL = 10,
    GRPC_ERROR_UNAVAILABLE = 11,
    GRPC_ERROR_DATA_LOSS = 12,
    GRPC_ERROR_UNAUTHENTICATED = 13,
    GRPC_ERROR_UNKNOWN = 99
} GrpcErrorCode;

// =============================================================================
// StackValue Type Tags
// =============================================================================

typedef enum {
    STACK_VALUE_NULL = 0,
    STACK_VALUE_INT = 1,
    STACK_VALUE_STRING = 2,
    STACK_VALUE_BOOL = 3,
    STACK_VALUE_FLOAT = 4,
    STACK_VALUE_ARRAY = 5,
    STACK_VALUE_RECORD = 6,
    STACK_VALUE_INSTANT = 7,
    STACK_VALUE_PLAIN_DATE = 8,
    STACK_VALUE_ZONED_DATETIME = 9
} StackValueType;

// =============================================================================
// Server API
// =============================================================================

/**
 * Create a new gRPC server
 * @param port Port to listen on
 * @param out_server Pointer to receive created server handle
 * @return Error code
 */
GrpcErrorCode forthic_grpc_server_create(uint16_t port, GrpcServer** out_server);

/**
 * Start the server (non-blocking)
 * @param server Server handle
 * @return Error code
 */
GrpcErrorCode forthic_grpc_server_start(GrpcServer* server);

/**
 * Stop the server and wait for completion
 * @param server Server handle
 * @return Error code
 */
GrpcErrorCode forthic_grpc_server_stop(GrpcServer* server);

/**
 * Destroy server and free resources
 * @param server Server handle
 */
void forthic_grpc_server_destroy(GrpcServer* server);

// =============================================================================
// Client API
// =============================================================================

/**
 * Create a new gRPC client
 * @param address Server address (e.g., "localhost:50051")
 * @param out_client Pointer to receive created client handle
 * @return Error code
 */
GrpcErrorCode grpc_client_create(const char* address, GrpcClient** out_client);

/**
 * Execute a word in the remote runtime
 * @param client Client handle
 * @param word_name Name of word to execute
 * @param stack Array of stack values
 * @param stack_len Length of stack array
 * @param out_result_stack Pointer to receive result stack array
 * @param out_result_len Pointer to receive result stack length
 * @param out_error Pointer to receive error info (NULL if no error)
 * @return Error code
 */
GrpcErrorCode grpc_client_execute_word(
    GrpcClient* client,
    const char* word_name,
    const StackValue* const* stack,
    size_t stack_len,
    StackValue*** out_result_stack,
    size_t* out_result_len,
    ErrorInfo** out_error
);

/**
 * Execute a sequence of words in one batch
 * @param client Client handle
 * @param word_names Array of word names
 * @param word_names_len Length of word names array
 * @param stack Array of stack values
 * @param stack_len Length of stack array
 * @param out_result_stack Pointer to receive result stack array
 * @param out_result_len Pointer to receive result stack length
 * @param out_error Pointer to receive error info (NULL if no error)
 * @return Error code
 */
GrpcErrorCode grpc_client_execute_sequence(
    GrpcClient* client,
    const char* const* word_names,
    size_t word_names_len,
    const StackValue* const* stack,
    size_t stack_len,
    StackValue*** out_result_stack,
    size_t* out_result_len,
    ErrorInfo** out_error
);

/**
 * Close the client and free resources
 * @param client Client handle
 */
void grpc_client_destroy(GrpcClient* client);

// =============================================================================
// StackValue API
// =============================================================================

/**
 * Create a null stack value
 */
StackValue* stack_value_create_null(void);

/**
 * Create an integer stack value
 */
StackValue* stack_value_create_int(int64_t value);

/**
 * Create a string stack value
 */
StackValue* stack_value_create_string(const char* value);

/**
 * Create a boolean stack value
 */
StackValue* stack_value_create_bool(bool value);

/**
 * Create a float stack value
 */
StackValue* stack_value_create_float(double value);

/**
 * Create an array stack value
 */
StackValue* stack_value_create_array(const StackValue* const* items, size_t len);

/**
 * Get the type of a stack value
 */
StackValueType stack_value_get_type(const StackValue* value);

/**
 * Get integer value (must be STACK_VALUE_INT type)
 */
int64_t stack_value_get_int(const StackValue* value);

/**
 * Get string value (must be STACK_VALUE_STRING type)
 * Returns pointer to internal string - do not free
 */
const char* stack_value_get_string(const StackValue* value);

/**
 * Get boolean value (must be STACK_VALUE_BOOL type)
 */
bool stack_value_get_bool(const StackValue* value);

/**
 * Get float value (must be STACK_VALUE_FLOAT type)
 */
double stack_value_get_float(const StackValue* value);

/**
 * Get array items (must be STACK_VALUE_ARRAY type)
 * @param value Stack value
 * @param out_items Pointer to receive array of items
 * @param out_len Pointer to receive array length
 */
void stack_value_get_array(const StackValue* value, const StackValue*** out_items, size_t* out_len);

/**
 * Destroy a stack value and free resources
 */
void stack_value_destroy(StackValue* value);

/**
 * Destroy an array of stack values
 */
void stack_value_array_destroy(StackValue** array, size_t len);

// =============================================================================
// ErrorInfo API
// =============================================================================

/**
 * Get error message
 */
const char* error_info_get_message(const ErrorInfo* error);

/**
 * Get runtime name
 */
const char* error_info_get_runtime(const ErrorInfo* error);

/**
 * Get error type
 */
const char* error_info_get_error_type(const ErrorInfo* error);

/**
 * Destroy error info
 */
void error_info_destroy(ErrorInfo* error);

#ifdef __cplusplus
}
#endif

#endif // FORTHIC_GRPC_C_WRAPPER_H
