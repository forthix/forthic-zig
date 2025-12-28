const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ==========================================================================
    // gRPC C++ Source Files Configuration
    // ==========================================================================

    // Common C++ compiler flags
    const cpp_flags = &[_][]const u8{
        "-std=c++17",
        "-fno-exceptions", // Disable exceptions for smaller binary
    };

    // C++ source files that will be added to each test
    const grpc_cpp_files = &[_][]const u8{
        "gen/protos/forthic_runtime.pb.cc",
        "gen/protos/forthic_runtime.grpc.pb.cc",
        "src/grpc/grpc_c_wrapper.cpp",
    };

    // ==========================================================================
    // Forthic Module with gRPC Support
    // ==========================================================================

    // Create forthic module that tests can import
    const forthic_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Helper function to configure gRPC for a compile step
    const addGrpcSupport = struct {
        fn call(step: *std.Build.Step.Compile, builder: *std.Build, files: []const []const u8, flags: []const []const u8) void {
            // Add C++ source files
            for (files) |file| {
                step.addCSourceFile(.{
                    .file = builder.path(file),
                    .flags = flags,
                });
            }

            // Link C++ standard library
            step.linkLibCpp();

            // Link gRPC and protobuf libraries
            step.linkSystemLibrary("protobuf");
            step.linkSystemLibrary("grpc++");
            step.linkSystemLibrary("grpc");

            // Add include paths
            step.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            step.addIncludePath(.{ .cwd_relative = "gen" }); // For generated proto headers
            step.addIncludePath(.{ .cwd_relative = "src/grpc" }); // For wrapper header
            step.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        }
    }.call;

    // ==========================================================================
    // Tests
    // ==========================================================================

    // Main library tests (for module integration)
    const lib_tests = b.addTest(.{
        .root_module = forthic_module,
    });
    addGrpcSupport(lib_tests, b, grpc_cpp_files, cpp_flags);

    // Tokenizer tests
    const tokenizer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tokenizer_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tokenizer_tests.root_module.addImport("forthic", forthic_module);
    addGrpcSupport(tokenizer_tests, b, grpc_cpp_files, cpp_flags);

    // Literals tests
    const literals_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/literals_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    literals_tests.root_module.addImport("forthic", forthic_module);
    addGrpcSupport(literals_tests, b, grpc_cpp_files, cpp_flags);

    // Core module tests
    const core_module_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/core_module_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    core_module_tests.root_module.addImport("forthic", forthic_module);
    addGrpcSupport(core_module_tests, b, grpc_cpp_files, cpp_flags);

    // gRPC tests
    const grpc_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/grpc_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    grpc_tests.root_module.addImport("forthic", forthic_module);
    addGrpcSupport(grpc_tests, b, grpc_cpp_files, cpp_flags);

    // Add all test runs
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_tokenizer_tests = b.addRunArtifact(tokenizer_tests);
    const run_literals_tests = b.addRunArtifact(literals_tests);
    const run_core_module_tests = b.addRunArtifact(core_module_tests);
    const run_grpc_tests = b.addRunArtifact(grpc_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_tokenizer_tests.step);
    test_step.dependOn(&run_literals_tests.step);
    test_step.dependOn(&run_core_module_tests.step);
    test_step.dependOn(&run_grpc_tests.step);
}
