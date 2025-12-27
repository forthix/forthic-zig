const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const word_mod = @import("word.zig");
const Word = word_mod.Word;
const variable_mod = @import("variable.zig");
const Variable = variable_mod.Variable;
const errors = @import("errors.zig");
const Value = @import("value.zig").Value;

// Forward declaration
pub const Interpreter = @import("interpreter.zig").Interpreter;

/// ============================================================================
/// Module - Container for words, variables, and imported modules
/// ============================================================================

pub const Module = struct {
    name: []const u8,
    forthic_code: []const u8,
    words: ArrayList(Word),
    exportable: ArrayList([]const u8),
    variables: StringHashMap(Variable),
    modules: StringHashMap(*Module),
    module_prefixes: StringHashMap(ArrayList([]const u8)),
    interp: ?*Interpreter,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, forthic_code: []const u8) Module {
        return Module{
            .name = name,
            .forthic_code = forthic_code,
            .words = ArrayList(Word){},
            .exportable = ArrayList([]const u8){},
            .variables = StringHashMap(Variable).init(allocator),
            .modules = StringHashMap(*Module).init(allocator),
            .module_prefixes = StringHashMap(ArrayList([]const u8)).init(allocator),
            .interp = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Module) void {
        // Note: Don't call word.deinit() here - words may be imported from other modules
        // Only the module that created the words should free them
        self.words.deinit(self.allocator);
        self.exportable.deinit(self.allocator);

        // Clean up variables - free both keys and values
        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);  // Free name
            entry.value_ptr.deinit(self.allocator);  // Free value
        }
        self.variables.deinit();

        self.modules.deinit();

        var it = self.module_prefixes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.module_prefixes.deinit();
    }

    pub fn getName(self: *const Module) []const u8 {
        return self.name;
    }

    pub fn setInterp(self: *Module, interp: *Interpreter) void {
        self.interp = interp;
    }

    pub fn getInterp(self: *const Module) !*Interpreter {
        if (self.interp) |interp| {
            return interp;
        }
        return errors.ForthicErrorType.ModuleError;
    }

    // ========================================================================
    // Module Management
    // ========================================================================

    pub fn findModule(self: *const Module, name: []const u8) ?*Module {
        return self.modules.get(name);
    }

    pub fn registerModule(self: *Module, module_name: []const u8, prefix: []const u8, module: *Module) !void {
        try self.modules.put(module_name, module);

        if (!self.module_prefixes.contains(module_name)) {
            const prefixes = ArrayList([]const u8){};
            try self.module_prefixes.put(module_name, prefixes);
        }

        const prefixes = self.module_prefixes.getPtr(module_name).?;
        try prefixes.append(self.allocator, prefix);
    }

    pub fn importModule(self: *Module, prefix: []const u8, module: *Module, interp: *Interpreter) !void {
        _ = interp; // Will be needed for creating ExecuteWords

        const exported_words = try module.exportableWords();
        defer module.allocator.free(exported_words);

        for (exported_words) |exported_word| {
            if (prefix.len == 0) {
                try self.addWord(exported_word);
            } else {
                // For now, just add unprefixed - prefixed import needs ExecuteWord
                try self.addWord(exported_word);
            }
        }

        try self.registerModule(module.name, prefix, module);
    }

    // ========================================================================
    // Word Management
    // ========================================================================

    pub fn addWord(self: *Module, new_word: Word) !void {
        try self.words.append(self.allocator, new_word);
    }

    pub fn addExportable(self: *Module, names: []const []const u8) !void {
        for (names) |name| {
            try self.exportable.append(self.allocator, name);
        }
    }

    pub fn addExportableWord(self: *Module, new_word: Word) !void {
        try self.addWord(new_word);
        try self.exportable.append(self.allocator, new_word.getName());
    }

    pub fn exportableWords(self: *const Module) ![]Word {
        var result = ArrayList(Word){};
        errdefer result.deinit(self.allocator);

        var exportable_set = StringHashMap(void).init(self.allocator);
        defer exportable_set.deinit();

        for (self.exportable.items) |name| {
            try exportable_set.put(name, {});
        }

        for (self.words.items) |w| {
            if (exportable_set.contains(w.getName())) {
                try result.append(self.allocator, w);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    pub fn findWord(self: *const Module, name: []const u8) ?Word {
        // Check dictionary words first
        if (self.findDictionaryWord(name)) |w| {
            return w;
        }

        // Check variables
        if (self.findVariable(name)) |w| {
            return w;
        }

        return null;
    }

    pub fn findDictionaryWord(self: *const Module, word_name: []const u8) ?Word {
        // Search from end to beginning (last added word wins)
        var i: usize = self.words.items.len;
        while (i > 0) {
            i -= 1;
            const w = self.words.items[i];
            if (std.mem.eql(u8, w.getName(), word_name)) {
                return w;
            }
        }
        return null;
    }

    pub fn findVariable(self: *const Module, var_name: []const u8) ?Word {
        if (self.variables.get(var_name)) |variable| {
            // Create a PushValueWord for the variable
            // Note: This creates a word on the stack, caller must handle ownership
            var push_word = word_mod.PushValueWord.init(var_name, variable.value);
            return push_word.asWord();
        }
        return null;
    }

    // ========================================================================
    // Variable Management
    // ========================================================================

    pub fn addVariable(self: *Module, name: []const u8, value: Value) !void {
        if (!self.variables.contains(name)) {
            const name_copy = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(name_copy);

            const variable = Variable.init(name_copy, value);
            try self.variables.put(name_copy, variable);
        }
    }

    pub fn setVariable(self: *Module, name: []const u8, value: Value) !void {
        // If variable exists, free old value and update
        if (self.variables.getPtr(name)) |var_ptr| {
            var_ptr.value.deinit(self.allocator);
            var_ptr.value = value;
        } else {
            // New variable - duplicate name
            const name_copy = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(name_copy);

            const variable = Variable.init(name_copy, value);
            try self.variables.put(name_copy, variable);
        }
    }

    pub fn getVariable(self: *const Module, name: []const u8) ?Variable {
        return self.variables.get(name);
    }
};

/// ============================================================================
/// ExecuteWord - Wrapper word that executes another word
/// ============================================================================

pub const ExecuteWord = struct {
    name: []const u8,
    target_word: Word,
    location: ?errors.CodeLocation,

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn init(name: []const u8, target_word: Word) ExecuteWord {
        return ExecuteWord{
            .name = name,
            .target_word = target_word,
            .location = null,
        };
    }

    pub fn asWord(self: *ExecuteWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *ExecuteWord = @ptrCast(@alignCast(ptr));
        try self.target_word.execute(interp);
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *ExecuteWord = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *ExecuteWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *ExecuteWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        _ = allocator;
        _ = ptr;
    }
};

/// ============================================================================
/// ModuleMemoWord - Memoized word that caches its result
/// ============================================================================

pub const ModuleMemoWord = struct {
    word: Word,
    has_value: bool,
    value: Value,
    location: ?errors.CodeLocation,

    pub fn init(w: Word) ModuleMemoWord {
        return ModuleMemoWord{
            .word = w,
            .has_value = false,
            .value = Value.initNull(),
            .location = null,
        };
    }

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn asWord(self: *ModuleMemoWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn refresh(self: *ModuleMemoWord, interp: *Interpreter) !void {
        try self.word.execute(interp);
        self.value = try interp.stackPop();
        self.has_value = true;
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *ModuleMemoWord = @ptrCast(@alignCast(ptr));
        if (!self.has_value) {
            try self.refresh(interp);
        }
        const cloned = try self.value.clone(interp.allocator);
        try interp.stackPush(cloned);
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *ModuleMemoWord = @ptrCast(@alignCast(ptr));
        return self.word.getName();
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *ModuleMemoWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *ModuleMemoWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        var self: *ModuleMemoWord = @ptrCast(@alignCast(ptr));
        if (self.has_value) {
            self.value.deinit(allocator);
        }
    }
};

/// ============================================================================
/// ModuleMemoBangWord - Forces refresh of a memoized word
/// ============================================================================

pub const ModuleMemoBangWord = struct {
    memo_word: *ModuleMemoWord,
    name: []const u8,
    location: ?errors.CodeLocation,

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn init(memo_word: *ModuleMemoWord, name: []const u8) ModuleMemoBangWord {
        return ModuleMemoBangWord{
            .memo_word = memo_word,
            .name = name,
            .location = null,
        };
    }

    pub fn asWord(self: *ModuleMemoBangWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *ModuleMemoBangWord = @ptrCast(@alignCast(ptr));
        try self.memo_word.refresh(interp);
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *ModuleMemoBangWord = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *ModuleMemoBangWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *ModuleMemoBangWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        _ = allocator;
        _ = ptr;
    }
};

/// ============================================================================
/// ModuleMemoBangAtWord - Refreshes a memoized word and returns its value
/// ============================================================================

pub const ModuleMemoBangAtWord = struct {
    memo_word: *ModuleMemoWord,
    name: []const u8,
    location: ?errors.CodeLocation,

    const vtable = Word.VTable{
        .execute = execute,
        .getName = getName,
        .getLocation = getLocation,
        .setLocation = setLocation,
        .deinit = deinitImpl,
    };

    pub fn init(memo_word: *ModuleMemoWord, name: []const u8) ModuleMemoBangAtWord {
        return ModuleMemoBangAtWord{
            .memo_word = memo_word,
            .name = name,
            .location = null,
        };
    }

    pub fn asWord(self: *ModuleMemoBangAtWord) Word {
        return Word{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn execute(ptr: *anyopaque, interp: *Interpreter) !void {
        const self: *ModuleMemoBangAtWord = @ptrCast(@alignCast(ptr));
        try self.memo_word.refresh(interp);
        const cloned = try self.memo_word.value.clone(interp.allocator);
        try interp.stackPush(cloned);
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *ModuleMemoBangAtWord = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getLocation(ptr: *anyopaque) ?errors.CodeLocation {
        const self: *ModuleMemoBangAtWord = @ptrCast(@alignCast(ptr));
        return self.location;
    }

    fn setLocation(ptr: *anyopaque, loc: ?errors.CodeLocation) void {
        const self: *ModuleMemoBangAtWord = @ptrCast(@alignCast(ptr));
        self.location = loc;
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        _ = allocator;
        _ = ptr;
    }
};
