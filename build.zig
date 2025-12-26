const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create forthic module that tests can import
    const forthic_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main library tests (for module integration)
    const lib_tests = b.addTest(.{
        .root_module = forthic_module,
    });

    // Tokenizer tests
    const tokenizer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tokenizer_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tokenizer_tests.root_module.addImport("forthic", forthic_module);

    // Literals tests
    const literals_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/literals_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    literals_tests.root_module.addImport("forthic", forthic_module);

    // Add all test runs
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_tokenizer_tests = b.addRunArtifact(tokenizer_tests);
    const run_literals_tests = b.addRunArtifact(literals_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_tokenizer_tests.step);
    test_step.dependOn(&run_literals_tests.step);
}
