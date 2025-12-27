const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const errors = @import("errors.zig");
const stack_mod = @import("stack.zig");
const Stack = stack_mod.Stack;
const Value = @import("value.zig").Value;
const module_mod = @import("module.zig");
const Module = module_mod.Module;
const word_mod = @import("word.zig");
const Word = word_mod.Word;
const PushValueWord = word_mod.PushValueWord;
const DefinitionWord = word_mod.DefinitionWord;
const tokenizer_mod = @import("tokenizer.zig");
const Tokenizer = tokenizer_mod.Tokenizer;
const Token = tokenizer_mod.Token;
const TokenType = tokenizer_mod.TokenType;
const literals = @import("literals.zig");
const LiteralValue = literals.LiteralValue;

/// ============================================================================
/// Literal Handler
/// ============================================================================

pub const LiteralHandler = *const fn (allocator: Allocator, str: []const u8) anyerror!?LiteralValue;

/// ============================================================================
/// Interpreter - Core Forthic interpreter
/// ============================================================================

pub const Interpreter = struct {
    stack: Stack,
    app_module: Module,
    module_stack: ArrayList(*Module),
    registered_modules: StringHashMap(*Module),
    tokenizer_stack: ArrayList(*Tokenizer),
    literal_handlers: ArrayList(LiteralHandler),
    is_compiling: bool,
    is_memo_definition: bool,
    cur_definition: ?*DefinitionWord,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Interpreter {
        const app_module = Module.init(allocator, "", "");

        var interp = Interpreter{
            .stack = Stack.init(allocator),
            .app_module = app_module,
            .module_stack = ArrayList(*Module){},  // Initialize empty - will be fixed after copy
            .registered_modules = StringHashMap(*Module).init(allocator),
            .tokenizer_stack = ArrayList(*Tokenizer){},
            .literal_handlers = ArrayList(LiteralHandler){},
            .is_compiling = false,
            .is_memo_definition = false,
            .cur_definition = null,
            .allocator = allocator,
        };

        try interp.registerStandardLiterals();

        return interp;
    }

    /// Must be called after init() if the Interpreter is moved/copied
    /// This fixes the module_stack to point to the app_module at its new location
    pub fn fixupAfterMove(self: *Interpreter) !void {
        // Clear and rebuild module_stack to point to the correct app_module location
        self.module_stack.clearRetainingCapacity();
        try self.module_stack.append(self.allocator, &self.app_module);
    }

    pub fn deinit(self: *Interpreter) void {
        self.stack.deinit();
        self.app_module.deinit();
        self.module_stack.deinit(self.allocator);
        self.registered_modules.deinit();
        self.tokenizer_stack.deinit(self.allocator);
        self.literal_handlers.deinit(self.allocator);
    }

    // ========================================================================
    // Stack Operations
    // ========================================================================

    pub fn stackPush(self: *Interpreter, value: Value) !void {
        try self.stack.push(value);
    }

    pub fn stackPop(self: *Interpreter) !Value {
        return try self.stack.pop();
    }

    pub fn stackPeek(self: *const Interpreter) !*const Value {
        return try self.stack.peek();
    }

    pub fn getStack(self: *Interpreter) *Stack {
        return &self.stack;
    }

    // ========================================================================
    // Module Operations
    // ========================================================================

    pub fn getAppModule(self: *Interpreter) *Module {
        return &self.app_module;
    }

    pub fn curModule(self: *Interpreter) *Module {
        return self.module_stack.items[self.module_stack.items.len - 1];
    }

    pub fn moduleStackPush(self: *Interpreter, module: *Module) !void {
        try self.module_stack.append(self.allocator, module);
    }

    pub fn moduleStackPop(self: *Interpreter) !*Module {
        if (self.module_stack.items.len <= 1) {
            return errors.ForthicErrorType.ModuleError;
        }
        return self.module_stack.pop() orelse return errors.ForthicErrorType.ModuleError;
    }

    pub fn registerModule(self: *Interpreter, module: *Module) !void {
        try self.registered_modules.put(module.name, module);
        module.setInterp(self);
    }

    pub fn findModule(self: *const Interpreter, name: []const u8) !*Module {
        return self.registered_modules.get(name) orelse error.UnknownModule;
    }

    // ========================================================================
    // Literal Handlers
    // ========================================================================

    fn registerStandardLiterals(self: *Interpreter) !void {
        try self.literal_handlers.append(self.allocator, literals.toBool);
        try self.literal_handlers.append(self.allocator, literals.toFloat);
        try self.literal_handlers.append(self.allocator, literals.toInt);
    }

    fn findLiteralWord(self: *Interpreter, name: []const u8) !?Word {
        for (self.literal_handlers.items) |handler| {
            if (try handler(self.allocator, name)) |lit_value| {
                // Convert LiteralValue to Value
                const value = switch (lit_value) {
                    .bool_value => |b| Value.initBool(b),
                    .int_value => |i| Value.initInt(i),
                    .float_value => |f| Value.initFloat(f),
                    .time_value, .date_value, .datetime_value => |dt| Value.initDateTime(dt),
                };

                const push_word = PushValueWord.init("<literal>", value);
                var word_ptr = try self.allocator.create(PushValueWord);
                word_ptr.* = push_word;
                return word_ptr.asWord();
            }
        }
        return null;
    }

    // ========================================================================
    // Find Word
    // ========================================================================

    pub fn findWord(self: *Interpreter, name: []const u8) !Word {
        // 1. Check module stack (from top to bottom)
        var i: usize = self.module_stack.items.len;
        while (i > 0) {
            i -= 1;
            const module = self.module_stack.items[i];
            if (module.findWord(name)) |w| {
                return w;
            }
        }

        // 2. Check literal handlers
        if (try self.findLiteralWord(name)) |w| {
            return w;
        }

        // 3. Not found
        return errors.ForthicErrorType.UnknownWord;
    }

    // ========================================================================
    // Main Execution
    // ========================================================================

    pub fn run(self: *Interpreter, code: []const u8) !void {
        const tokenizer = try Tokenizer.init(self.allocator, code, null, false);
        // Note: Don't deinit tokenizer here - we copy it to heap and deinit the heap copy

        const tokenizer_ptr = try self.allocator.create(Tokenizer);
        tokenizer_ptr.* = tokenizer;
        try self.tokenizer_stack.append(self.allocator, tokenizer_ptr);
        defer {
            _ = self.tokenizer_stack.pop();
            tokenizer_ptr.deinit();  // Free internal token_string buffer
            self.allocator.destroy(tokenizer_ptr);
        }

        try self.runWithTokenizer(tokenizer_ptr);
    }

    fn runWithTokenizer(self: *Interpreter, tokenizer: *Tokenizer) !void {
        while (true) {
            const maybe_token = try tokenizer.nextToken();
            if (maybe_token == null) break;

            var token = maybe_token.?;
            defer token.deinit(self.allocator);

            try self.handleToken(token);

            if (token.type == TokenType.eos) {
                break;
            }
        }
    }

    // ========================================================================
    // Token Handling
    // ========================================================================

    fn handleToken(self: *Interpreter, token: Token) !void {
        switch (token.type) {
            .string => try self.handleStringToken(token),
            .comment => {}, // No-op
            .start_array => try self.handleStartArrayToken(token),
            .end_array => try self.handleEndArrayToken(token),
            .start_module => try self.handleStartModuleToken(token),
            .end_module => try self.handleEndModuleToken(token),
            .start_def => try self.handleStartDefinitionToken(token),
            .start_memo => try self.handleStartMemoToken(token),
            .end_def => try self.handleEndDefinitionToken(token),
            .dot_symbol => try self.handleDotSymbolToken(token),
            .word => try self.handleWordToken(token),
            .eos => {
                if (self.is_compiling) {
                    return errors.ForthicErrorType.MissingSemicolon;
                }
            },
        }
    }

    fn handleStringToken(self: *Interpreter, token: Token) !void {
        const str_copy = try self.allocator.dupe(u8, token.string);
        errdefer self.allocator.free(str_copy);

        const value = Value.initString(str_copy);

        const push_word = PushValueWord.init("<string>", value);
        var word_ptr = try self.allocator.create(PushValueWord);
        errdefer self.allocator.destroy(word_ptr);
        word_ptr.* = push_word;

        const word = word_ptr.asWord();
        try self.handleWord(word, token.location);

        // Clean up temporary word if not compiling into definition
        if (!self.is_compiling) {
            word.deinit(self.allocator);
            self.allocator.destroy(word_ptr);
        }
    }

    fn handleDotSymbolToken(self: *Interpreter, token: Token) !void {
        const str_copy = try self.allocator.dupe(u8, token.string);
        errdefer self.allocator.free(str_copy);

        const value = Value.initString(str_copy);

        const push_word = PushValueWord.init("<dot-symbol>", value);
        var word_ptr = try self.allocator.create(PushValueWord);
        errdefer self.allocator.destroy(word_ptr);
        word_ptr.* = push_word;

        const word = word_ptr.asWord();
        try self.handleWord(word, token.location);

        // Clean up temporary word if not compiling into definition
        if (!self.is_compiling) {
            word.deinit(self.allocator);
            self.allocator.destroy(word_ptr);
        }
    }

    fn handleStartArrayToken(self: *Interpreter, token: Token) !void {
        // Push a marker value onto the stack to indicate start of array
        // TODO: Use a proper marker type instead of null
        const value = Value.initNull();

        const push_word = PushValueWord.init("<start_array_token>", value);
        var word_ptr = try self.allocator.create(PushValueWord);
        errdefer self.allocator.destroy(word_ptr);
        word_ptr.* = push_word;

        const word = word_ptr.asWord();
        try self.handleWord(word, token.location);

        // Clean up temporary word if not compiling into definition
        if (!self.is_compiling) {
            word.deinit(self.allocator);
            self.allocator.destroy(word_ptr);
        }
    }

    fn handleEndArrayToken(self: *Interpreter, token: Token) !void {
        _ = token;
        var items: std.ArrayList(Value) = .{};

        while (true) {
            const item = try self.stackPop();

            // Check if it's a START_ARRAY marker (null value)
            // TODO: Use a proper marker type instead of relying on null
            if (item == .null_value) {
                break;
            }

            try items.append(self.allocator, item);
        }

        // Reverse the items
        std.mem.reverse(Value, items.items);

        // Create array value
        const array_value = Value{ .array_value = items };
        try self.stackPush(array_value);
    }

    fn handleStartModuleToken(self: *Interpreter, token: Token) !void {
        const module_name = token.string;

        if (module_name.len == 0) {
            // Empty name refers to app module
            try self.moduleStackPush(&self.app_module);
            return;
        }

        // Check if module exists in current module
        var module = self.curModule().findModule(module_name);
        if (module == null) {
            // Create new module
            const new_module_ptr = try self.allocator.create(Module);
            new_module_ptr.* = Module.init(self.allocator, module_name, "");
            try self.curModule().registerModule(module_name, module_name, new_module_ptr);

            // If we're at app module, also register with interpreter
            if (self.curModule().name.len == 0) {
                try self.registerModule(new_module_ptr);
            }

            module = new_module_ptr;
        }

        try self.moduleStackPush(module.?);
    }

    fn handleEndModuleToken(self: *Interpreter, token: Token) !void {
        _ = token;
        _ = try self.moduleStackPop();
    }

    fn handleStartDefinitionToken(self: *Interpreter, token: Token) !void {
        if (self.is_compiling) {
            return errors.ForthicErrorType.MissingSemicolon;
        }

        const def_ptr = try self.allocator.create(DefinitionWord);
        def_ptr.* = DefinitionWord.init(self.allocator, token.string);

        self.cur_definition = def_ptr;
        self.is_compiling = true;
        self.is_memo_definition = false;
    }

    fn handleStartMemoToken(self: *Interpreter, token: Token) !void {
        if (self.is_compiling) {
            return errors.ForthicErrorType.MissingSemicolon;
        }

        const def_ptr = try self.allocator.create(DefinitionWord);
        def_ptr.* = DefinitionWord.init(self.allocator, token.string);

        self.cur_definition = def_ptr;
        self.is_compiling = true;
        self.is_memo_definition = true;
    }

    fn handleEndDefinitionToken(self: *Interpreter, token: Token) !void {
        _ = token;
        if (!self.is_compiling or self.cur_definition == null) {
            return errors.ForthicErrorType.ExtraSemicolon;
        }

        if (self.is_memo_definition) {
            // Add memo words
            const def_word = self.cur_definition.?.asWord();
            var memo_word_ptr = try self.allocator.create(module_mod.ModuleMemoWord);
            memo_word_ptr.* = module_mod.ModuleMemoWord.init(def_word);

            try self.curModule().addWord(memo_word_ptr.asWord());

            // Create refresh variants
            const name = self.cur_definition.?.name;
            const bang_name = try std.fmt.allocPrint(self.allocator, "{s}!", .{name});
            const bangat_name = try std.fmt.allocPrint(self.allocator, "{s}!@", .{name});

            var bang_word_ptr = try self.allocator.create(module_mod.ModuleMemoBangWord);
            bang_word_ptr.* = module_mod.ModuleMemoBangWord.init(memo_word_ptr, bang_name);

            var bangat_word_ptr = try self.allocator.create(module_mod.ModuleMemoBangAtWord);
            bangat_word_ptr.* = module_mod.ModuleMemoBangAtWord.init(memo_word_ptr, bangat_name);

            try self.curModule().addWord(bang_word_ptr.asWord());
            try self.curModule().addWord(bangat_word_ptr.asWord());
        } else {
            try self.curModule().addWord(self.cur_definition.?.asWord());
        }

        self.is_compiling = false;
        self.cur_definition = null;
    }

    fn handleWordToken(self: *Interpreter, token: Token) !void {
        const w = try self.findWord(token.string);

        // Check if this is a literal word (created in findLiteralWord)
        const is_literal = std.mem.eql(u8, w.getName(), "<literal>");

        try self.handleWord(w, token.location);

        // Clean up literal words if not compiling
        if (is_literal and !self.is_compiling) {
            const word_ptr: *PushValueWord = @ptrCast(@alignCast(w.ptr));
            w.deinit(self.allocator);
            self.allocator.destroy(word_ptr);
        }
    }

    fn handleWord(self: *Interpreter, w: Word, location: tokenizer_mod.CodeLocation) !void {
        _ = location;
        if (self.is_compiling and self.cur_definition != null) {
            try self.cur_definition.?.addWord(w);
        } else {
            try w.execute(self);
        }
    }
};

/// ============================================================================
/// Special Word Types
/// ============================================================================

pub const StartModuleWord = struct {
    name: []const u8,
    location: ?errors.CodeLocation,

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn init(name: []const u8) StartModuleWord {
        return StartModuleWord{
            .name = name,
            .location = null,
        };
    }

    pub fn asWord(self: *StartModuleWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *StartModuleWord = @ptrCast(@alignCast(ptr));
        _ = self;
        _ = interp;
        // Implementation in handleStartModuleToken
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *StartModuleWord = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *StartModuleWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *StartModuleWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        _ = allocator;
        _ = ptr;
    }
};

pub const EndModuleWord = struct {
    location: ?errors.CodeLocation,

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn init() EndModuleWord {
        return EndModuleWord{
            .location = null,
        };
    }

    pub fn asWord(self: *EndModuleWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        _ = ptr;
        _ = try interp.moduleStackPop();
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "}";
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *EndModuleWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *EndModuleWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        _ = allocator;
        _ = ptr;
    }
};
