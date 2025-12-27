const std = @import("std");
const testing = std.testing;
const Interpreter = @import("forthic").Interpreter;
const Value = @import("forthic").Value;
const CoreModule = @import("forthic").modules.standard.CoreModule;
const MathModule = @import("forthic").modules.standard.MathModule;

const TestContext = struct {
    interp: *Interpreter,
    core_mod: *CoreModule,
    math_mod: *MathModule,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TestContext) void {
        self.core_mod.deinit();
        self.math_mod.deinit();
        self.interp.deinit();
        self.allocator.destroy(self.interp);
    }
};

fn setupCoreInterpreter(allocator: std.mem.Allocator) !TestContext {
    const interp = try allocator.create(Interpreter);
    interp.* = try Interpreter.init(allocator);
    try interp.fixupAfterMove();  // Fix module_stack pointer after copy

    const core_mod = try CoreModule.init(allocator);
    const math_mod = try MathModule.init(allocator);

    try interp.registerModule(&core_mod.module);
    try interp.registerModule(&math_mod.module);

    try interp.curModule().importModule("", &core_mod.module, interp);
    try interp.curModule().importModule("", &math_mod.module, interp);

    return TestContext{
        .interp = interp,
        .core_mod = core_mod,
        .math_mod = math_mod,
        .allocator = allocator,
    };
}

// ========================================
// Stack Operations
// ========================================

test "Core: POP" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("1 2 3 POP");

    const stack = ctx.interp.getStack();
    try testing.expectEqual(@as(usize, 2), stack.length());

    var top = try ctx.interp.stackPop();
    defer top.deinit(allocator);
    try testing.expectEqual(@as(i64, 2), top.int_value);
}

test "Core: DUP" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("42 DUP");

    const stack = ctx.interp.getStack();
    try testing.expectEqual(@as(usize, 2), stack.length());

    var top1 = try ctx.interp.stackPop();
    defer top1.deinit(allocator);
    var top2 = try ctx.interp.stackPop();
    defer top2.deinit(allocator);

    try testing.expectEqual(@as(i64, 42), top1.int_value);
    try testing.expectEqual(@as(i64, 42), top2.int_value);
}

test "Core: SWAP" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("1 2 SWAP");

    const stack = ctx.interp.getStack();
    try testing.expectEqual(@as(usize, 2), stack.length());

    var top = try ctx.interp.stackPop();
    defer top.deinit(allocator);
    var bottom = try ctx.interp.stackPop();
    defer bottom.deinit(allocator);

    try testing.expectEqual(@as(i64, 1), top.int_value);
    try testing.expectEqual(@as(i64, 2), bottom.int_value);
}

// ========================================
// Variable Operations
// ========================================

test "Core: VARIABLES" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("[\"x\" \"y\"] VARIABLES");

    const app_module = ctx.interp.getAppModule();
    const x_var = app_module.getVariable("x");
    const y_var = app_module.getVariable("y");

    try testing.expect(x_var != null);
    try testing.expect(y_var != null);
}

test "Core: Invalid Variable Name" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    const result = ctx.interp.run("[\"__test\"] VARIABLES");
    try testing.expectError(error.InvalidVariableName, result);
}

test "Core: Set and Get Variables" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("[\"x\"] VARIABLES 24 \"x\" ! \"x\" @");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 24), result.int_value);
}

test "Core: BangAt (!@)" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("[\"x\"] VARIABLES 42 \"x\" !@");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 42), result.int_value);

    // Verify variable was also set
    const app_module = ctx.interp.getAppModule();
    const x_var = app_module.getVariable("x").?;
    const value = x_var.getValue();
    try testing.expectEqual(@as(i64, 42), value.int_value);
}

test "Core: Auto-Create Variables with !" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("\"hello\" \"autovar1\" !");
    try ctx.interp.run("\"autovar1\" @");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqualStrings("hello", result.string_value);

    // Verify variable was created
    const app_module = ctx.interp.getAppModule();
    const autovar1 = app_module.getVariable("autovar1");
    try testing.expect(autovar1 != null);
}

test "Core: Auto-Create Variables with @" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("\"autovar2\" @");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expect(result == .null_value);
}

test "Core: Auto-Create Variables with !@" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("\"world\" \"autovar3\" !@");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqualStrings("world", result.string_value);
}

test "Core: Auto-Create Variables Validation" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    // Test that __ prefix variables are rejected for !
    const result1 = ctx.interp.run("\"value\" \"__invalid\" !");
    try testing.expectError(error.InvalidVariableName, result1);

    // Test that validation works for @
    const result2 = ctx.interp.run("\"__invalid2\" @");
    try testing.expectError(error.InvalidVariableName, result2);

    // Test that validation works for !@
    const result3 = ctx.interp.run("\"value\" \"__invalid3\" !@");
    try testing.expectError(error.InvalidVariableName, result3);
}

// ========================================
// Module Operations
// ========================================

test "Core: EXPORT" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("[\"POP\" \"DUP\"] EXPORT");
    // This is a basic smoke test - full test would verify exportable list
}

test "Core: INTERPRET" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("\"5 10 +\" INTERPRET");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 15), result.int_value);
}

// ========================================
// Control Flow
// ========================================

test "Core: IDENTITY" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("42 IDENTITY");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 42), result.int_value);
}

test "Core: NOP" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("NOP");

    const stack = ctx.interp.getStack();
    try testing.expectEqual(@as(usize, 0), stack.length());
}

test "Core: NULL" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("NULL");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expect(result == .null_value);
}

test "Core: ARRAY?" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("[1 2 3] ARRAY?");

    var result1 = try ctx.interp.stackPop();
    defer result1.deinit(allocator);
    try testing.expectEqual(true, result1.bool_value);

    try ctx.interp.run("42 ARRAY?");

    var result2 = try ctx.interp.stackPop();
    defer result2.deinit(allocator);
    try testing.expectEqual(false, result2.bool_value);
}

test "Core: DEFAULT with null" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("NULL 42 DEFAULT");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 42), result.int_value);
}

test "Core: DEFAULT with non-null" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("10 42 DEFAULT");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 10), result.int_value);
}

test "Core: DEFAULT with empty string" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("\"\" 42 DEFAULT");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 42), result.int_value);
}

test "Core: *DEFAULT with null" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("NULL \"10 20 +\" *DEFAULT");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 30), result.int_value);
}

test "Core: *DEFAULT with non-null" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("42 \"10 20 +\" *DEFAULT");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 42), result.int_value);
}

// ========================================
// String Operations
// ========================================

test "Core: INTERPOLATE Basic" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("5 \"count\" ! \"Count: .count\" INTERPOLATE");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqualStrings("Count: 5", result.string_value);
}

test "Core: INTERPOLATE Escaped Dots" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("\"Test \\. escaped\" INTERPOLATE");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expect(std.mem.indexOf(u8, result.string_value, ".") != null);
}

// ========================================
// Profiling (Placeholder tests)
// ========================================

test "Core: Profiling" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("PROFILE-START PROFILE-END");
    try ctx.interp.run("\"test\" PROFILE-TIMESTAMP");
    try ctx.interp.run("PROFILE-DATA");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expect(result == .record_value);
}

// ========================================
// Logging (Placeholder tests)
// ========================================

test "Core: Logging" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("START-LOG END-LOG");
}

// ========================================
// Integration Tests
// ========================================

test "Core: Variable Integration" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run(
        \\["x" "y"] VARIABLES
        \\10 "x" !
        \\20 "y" !
        \\"x" @ "y" @ +
    );

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 30), result.int_value);
}

test "Core: Stack Manipulation" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run(
        \\1 2 3
        \\DUP
        \\POP
        \\SWAP
    );

    const stack = ctx.interp.getStack();
    try testing.expectEqual(@as(usize, 3), stack.length());

    var top = try ctx.interp.stackPop();
    defer top.deinit(allocator);
    var mid = try ctx.interp.stackPop();
    defer mid.deinit(allocator);
    var bot = try ctx.interp.stackPop();
    defer bot.deinit(allocator);

    try testing.expectEqual(@as(i64, 2), top.int_value);
    try testing.expectEqual(@as(i64, 3), mid.int_value);
    try testing.expectEqual(@as(i64, 1), bot.int_value);
}

test "Core: NULL and DEFAULT Chain" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run("NULL NULL 0 DEFAULT DEFAULT");

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 0), result.int_value);
}

test "Core: Complex Variable Operations" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run(
        \\["counter"] VARIABLES
        \\0 "counter" !
        \\"counter" @ 1 + "counter" !
        \\"counter" @ 1 + "counter" !
        \\"counter" @
    );

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 2), result.int_value);
}

test "Core: INTERPRET with Variables" {
    const allocator = testing.allocator;
    var ctx = try setupCoreInterpreter(allocator);
    defer ctx.deinit();

    try ctx.interp.run(
        \\["result"] VARIABLES
        \\"'10 20 +' INTERPRET 'result' !" INTERPRET
        \\"result" @
    );

    var result = try ctx.interp.stackPop();
    defer result.deinit(allocator);
    try testing.expectEqual(@as(i64, 30), result.int_value);
}
