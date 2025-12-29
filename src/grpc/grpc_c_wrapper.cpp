/**
 * C++ Implementation of C Wrapper for gRPC
 *
 * This file wraps the C++ gRPC generated code (forthic_runtime.pb.h/forthic_runtime.grpc.pb.h)
 * and exposes a pure C API that Zig can easily call.
 */

#include "grpc_c_wrapper.h"
#include "../../gen/protos/forthic_runtime.pb.h"
#include "../../gen/protos/forthic_runtime.grpc.pb.h"

#include <grpcpp/grpcpp.h>
#include <memory>
#include <string>
#include <vector>

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using grpc::Channel;
using grpc::ClientContext;

using forthic::ForthicRuntime;
using ProtoStackValue = forthic::StackValue;
using forthic::ExecuteWordRequest;
using forthic::ExecuteWordResponse;
using forthic::ExecuteSequenceRequest;
using forthic::ExecuteSequenceResponse;
using ProtoErrorInfo = forthic::ErrorInfo;

// =============================================================================
// Internal C++ Structures
// =============================================================================

struct GrpcServer {
    std::unique_ptr<Server> server;
    uint16_t port;
};

struct GrpcClient {
    std::shared_ptr<Channel> channel;
    std::unique_ptr<ForthicRuntime::Stub> stub;
};

struct StackValue {
    ProtoStackValue proto_value;
};

struct ErrorInfo {
    std::string message;
    std::string runtime;
    std::string error_type;
};

// =============================================================================
// Helper Functions
// =============================================================================

static GrpcErrorCode status_to_error_code(const Status& status) {
    if (status.ok()) return GRPC_OK;

    switch (status.error_code()) {
        case grpc::StatusCode::INVALID_ARGUMENT:
            return GRPC_ERROR_INVALID_ARGUMENT;
        case grpc::StatusCode::NOT_FOUND:
            return GRPC_ERROR_NOT_FOUND;
        case grpc::StatusCode::ALREADY_EXISTS:
            return GRPC_ERROR_ALREADY_EXISTS;
        case grpc::StatusCode::PERMISSION_DENIED:
            return GRPC_ERROR_PERMISSION_DENIED;
        case grpc::StatusCode::RESOURCE_EXHAUSTED:
            return GRPC_ERROR_RESOURCE_EXHAUSTED;
        case grpc::StatusCode::FAILED_PRECONDITION:
            return GRPC_ERROR_FAILED_PRECONDITION;
        case grpc::StatusCode::ABORTED:
            return GRPC_ERROR_ABORTED;
        case grpc::StatusCode::OUT_OF_RANGE:
            return GRPC_ERROR_OUT_OF_RANGE;
        case grpc::StatusCode::UNIMPLEMENTED:
            return GRPC_ERROR_UNIMPLEMENTED;
        case grpc::StatusCode::INTERNAL:
            return GRPC_ERROR_INTERNAL;
        case grpc::StatusCode::UNAVAILABLE:
            return GRPC_ERROR_UNAVAILABLE;
        case grpc::StatusCode::DATA_LOSS:
            return GRPC_ERROR_DATA_LOSS;
        case grpc::StatusCode::UNAUTHENTICATED:
            return GRPC_ERROR_UNAUTHENTICATED;
        default:
            return GRPC_ERROR_UNKNOWN;
    }
}

// =============================================================================
// StackValue API Implementation
// =============================================================================

extern "C" StackValue* stack_value_create_null(void) {
    auto* value = new StackValue();
    value->proto_value.mutable_null_value();
    return value;
}

extern "C" StackValue* stack_value_create_int(int64_t val) {
    auto* value = new StackValue();
    value->proto_value.set_int_value(val);
    return value;
}

extern "C" StackValue* stack_value_create_string(const char* val) {
    auto* value = new StackValue();
    value->proto_value.set_string_value(val);
    return value;
}

extern "C" StackValue* stack_value_create_bool(bool val) {
    auto* value = new StackValue();
    value->proto_value.set_bool_value(val);
    return value;
}

extern "C" StackValue* stack_value_create_float(double val) {
    auto* value = new StackValue();
    value->proto_value.set_float_value(val);
    return value;
}

extern "C" StackValue* stack_value_create_array(const StackValue* const* items, size_t len) {
    auto* value = new StackValue();
    auto* array = value->proto_value.mutable_array_value();

    for (size_t i = 0; i < len; i++) {
        *array->add_items() = items[i]->proto_value;
    }

    return value;
}

extern "C" StackValueType stack_value_get_type(const StackValue* value) {
    if (!value) return STACK_VALUE_NULL;

    const auto& proto = value->proto_value;

    if (proto.has_null_value()) return STACK_VALUE_NULL;
    if (proto.has_int_value()) return STACK_VALUE_INT;
    if (proto.has_string_value()) return STACK_VALUE_STRING;
    if (proto.has_bool_value()) return STACK_VALUE_BOOL;
    if (proto.has_float_value()) return STACK_VALUE_FLOAT;
    if (proto.has_array_value()) return STACK_VALUE_ARRAY;
    if (proto.has_record_value()) return STACK_VALUE_RECORD;
    if (proto.has_instant_value()) return STACK_VALUE_INSTANT;
    if (proto.has_plain_date_value()) return STACK_VALUE_PLAIN_DATE;
    if (proto.has_zoned_datetime_value()) return STACK_VALUE_ZONED_DATETIME;

    return STACK_VALUE_NULL;
}

extern "C" int64_t stack_value_get_int(const StackValue* value) {
    return value ? value->proto_value.int_value() : 0;
}

extern "C" const char* stack_value_get_string(const StackValue* value) {
    return value ? value->proto_value.string_value().c_str() : "";
}

extern "C" bool stack_value_get_bool(const StackValue* value) {
    return value ? value->proto_value.bool_value() : false;
}

extern "C" double stack_value_get_float(const StackValue* value) {
    return value ? value->proto_value.float_value() : 0.0;
}

extern "C" void stack_value_get_array(const StackValue* value, const StackValue*** out_items, size_t* out_len) {
    if (!value || !out_items || !out_len) return;

    if (!value->proto_value.has_array_value()) {
        *out_items = nullptr;
        *out_len = 0;
        return;
    }

    const auto& array = value->proto_value.array_value();
    size_t len = array.items_size();

    // Allocate array of pointers to StackValue
    auto** items = (const StackValue**)malloc(sizeof(StackValue*) * len);

    for (size_t i = 0; i < len; i++) {
        auto* item = new StackValue();
        item->proto_value = array.items(i);
        items[i] = item;
    }

    *out_items = items;
    *out_len = len;
}

extern "C" void stack_value_destroy(StackValue* value) {
    delete value;
}

extern "C" void stack_value_array_destroy(StackValue** array, size_t len) {
    if (!array) return;
    for (size_t i = 0; i < len; i++) {
        delete array[i];
    }
    free(array);
}

// =============================================================================
// Client API Implementation
// =============================================================================

extern "C" GrpcErrorCode grpc_client_create(const char* address, GrpcClient** out_client) {
    if (!address || !out_client) {
        return GRPC_ERROR_INVALID_ARGUMENT;
    }

    auto* client = new GrpcClient();
    client->channel = grpc::CreateChannel(address, grpc::InsecureChannelCredentials());
    client->stub = ForthicRuntime::NewStub(client->channel);

    *out_client = client;
    return GRPC_OK;
}

extern "C" GrpcErrorCode grpc_client_execute_word(
    GrpcClient* client,
    const char* word_name,
    const StackValue* const* stack,
    size_t stack_len,
    StackValue*** out_result_stack,
    size_t* out_result_len,
    ErrorInfo** out_error
) {
    if (!client || !word_name || !out_result_stack || !out_result_len) {
        return GRPC_ERROR_INVALID_ARGUMENT;
    }

    // Build request
    ExecuteWordRequest request;
    request.set_word_name(word_name);

    for (size_t i = 0; i < stack_len; i++) {
        *request.add_stack() = stack[i]->proto_value;
    }

    // Make RPC call
    ExecuteWordResponse response;
    ClientContext context;
    Status status = client->stub->ExecuteWord(&context, request, &response);

    if (!status.ok()) {
        return status_to_error_code(status);
    }

    // Check for application-level error
    if (response.has_error()) {
        auto* error = new ErrorInfo();
        error->message = response.error().message();
        error->runtime = response.error().runtime();
        error->error_type = response.error().error_type();
        *out_error = error;
        *out_result_len = 0;
        *out_result_stack = nullptr;
        return GRPC_OK;  // gRPC succeeded, but execution failed
    }

    // Convert result stack
    size_t result_len = response.result_stack_size();
    auto** result_array = (StackValue**)malloc(sizeof(StackValue*) * result_len);

    for (size_t i = 0; i < result_len; i++) {
        result_array[i] = new StackValue();
        result_array[i]->proto_value = response.result_stack(i);
    }

    *out_result_stack = result_array;
    *out_result_len = result_len;
    *out_error = nullptr;

    return GRPC_OK;
}

extern "C" void grpc_client_destroy(GrpcClient* client) {
    delete client;
}

// =============================================================================
// ErrorInfo API Implementation
// =============================================================================

extern "C" const char* error_info_get_message(const ErrorInfo* error) {
    return error ? error->message.c_str() : "";
}

extern "C" const char* error_info_get_runtime(const ErrorInfo* error) {
    return error ? error->runtime.c_str() : "";
}

extern "C" const char* error_info_get_error_type(const ErrorInfo* error) {
    return error ? error->error_type.c_str() : "";
}

extern "C" void error_info_destroy(ErrorInfo* error) {
    delete error;
}

// =============================================================================
// Server API - Stub Implementation (requires Forthic interpreter integration)
// =============================================================================

extern "C" GrpcErrorCode forthic_grpc_server_create(uint16_t port, GrpcServer** out_server) {
    // Server implementation requires integrating with Zig Forthic interpreter
    // This would be implemented after the client side is working
    return GRPC_ERROR_UNIMPLEMENTED;
}

extern "C" GrpcErrorCode forthic_grpc_server_start(GrpcServer* server) {
    return GRPC_ERROR_UNIMPLEMENTED;
}

extern "C" GrpcErrorCode forthic_grpc_server_stop(GrpcServer* server) {
    return GRPC_ERROR_UNIMPLEMENTED;
}

extern "C" void forthic_grpc_server_destroy(GrpcServer* server) {
    delete server;
}
