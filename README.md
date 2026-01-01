# Forthic Zig Runtime

A Zig implementation of the Forthic stack-based concatenative programming language.

## Overview

Forthic is a stack-based, concatenative language designed for composable transformations. This is the official Zig runtime implementation, providing full compatibility with other Forthic runtimes while leveraging Zig's comptime metaprogramming and performance.

**[Learn more at forthix.com →](https://forthix.com)**

## Features

- ✅ Complete Forthic language implementation
- ✅ All 8 standard library modules
- ✅ Comptime decorators for zero-overhead abstractions
- ✅ Manual memory management for maximum performance
- ✅ gRPC support for multi-runtime execution
- ✅ CLI with REPL, script execution, and eval modes
- ✅ Comprehensive test suite

## Installation

```bash
zig build
```

## Usage

### As a Library

```zig
const forthic = @import("forthic");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interp = try forthic.StandardInterpreter.init(allocator);
    defer interp.deinit();

    try interp.run("[1 2 3] \"2 *\" MAP");

    const result = try interp.stackPop();
    defer result.deinit(allocator);
    // result is [2, 4, 6]
}
```

### CLI

```bash
# REPL mode
./zig-out/bin/forthic-zig repl

# Execute a script
./zig-out/bin/forthic-zig run script.forthic

# Eval mode (one-liner)
./zig-out/bin/forthic-zig eval "[1 2 3] LENGTH"
```

## Development

```bash
# Build
zig build

# Run tests
zig build test

# Run specific test
zig test src/forthic/interpreter.zig

# Build with optimizations
zig build -Doptimize=ReleaseFast
```

## Project Structure

```
forthic-zig/
├── src/
│   ├── main.zig              # Entry point
│   └── forthic/
│       ├── interpreter.zig   # Core interpreter
│       ├── tokenizer.zig     # Lexical analysis
│       ├── module.zig        # Module system
│       └── modules/standard/ # Standard library (8 modules)
├── tests/                    # Test suites
└── build.zig                 # Build configuration
```

## Standard Library Modules

- **core**: Stack operations, variables, control flow
- **array**: Data transformation (MAP, SELECT, SORT, etc.)
- **record**: Dictionary operations
- **string**: Text processing
- **math**: Arithmetic operations
- **boolean**: Logical operations
- **datetime**: Date/time manipulation
- **json**: JSON serialization

## Comptime Features

Zig's comptime enables zero-overhead word registration:

```zig
const words = .{
    .{ .name = "SWAP", .meta = Word.init("( a b -- b a )", "Swap"), .func = swap },
    .{ .name = "DUP", .meta = Word.init("( a -- a a )", "Duplicate"), .func = dup },
};

// Compile-time registration
pub fn registerWords(module: *Module) void {
    inline for (words) |word| {
        module.addWord(word.name, word.meta, word.func);
    }
}
```

## Multi-Runtime Execution

This runtime supports calling words from other Forthic runtimes via gRPC:

```zig
// Call a TypeScript word from Zig
const result = try interp.executeRemoteWord("typescript-runtime", "MY-WORD", args);
```

## Performance

Zig's manual memory management and comptime features provide excellent performance:
- Zero-cost abstractions
- No garbage collection pauses
- Predictable memory usage
- Optimal code generation

## License

BSD 2-CLAUSE

## Links

- **[forthix.com](https://forthix.com)** - Learn about Forthic and Categorical Coding
- **[Category Theory for Coders](https://forthix.com/blog/category-theory-for-the-rest-of-us-coders)** - Understand the foundations
- [Forthic Language Specification](https://github.com/forthix/forthic)
- [TypeScript Runtime](https://github.com/forthix/forthic-ts) (reference implementation)
- [Documentation](https://forthix.github.io/forthic-zig)
