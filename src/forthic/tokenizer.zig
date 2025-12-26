const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// ============================================================================
/// Token Types
/// ============================================================================

pub const TokenType = enum {
    string,
    comment,
    start_array,
    end_array,
    start_module,
    end_module,
    start_def,
    end_def,
    start_memo,
    word,
    dot_symbol,
    eos,
};

/// ============================================================================
/// Code Location
/// ============================================================================

pub const CodeLocation = struct {
    source: ?[]const u8,
    line: usize,
    column: usize,
    start_pos: usize,
    end_pos: usize,

    pub fn init(source: ?[]const u8, line: usize, column: usize, start_pos: usize, end_pos: usize) CodeLocation {
        return .{
            .source = source,
            .line = line,
            .column = column,
            .start_pos = start_pos,
            .end_pos = end_pos,
        };
    }
};

/// ============================================================================
/// Token
/// ============================================================================

pub const Token = struct {
    type: TokenType,
    string: []const u8,
    location: CodeLocation,

    pub fn deinit(self: *Token, allocator: Allocator) void {
        allocator.free(self.string);
    }
};

/// ============================================================================
/// Tokenizer
/// ============================================================================

pub const Tokenizer = struct {
    allocator: Allocator,
    reference_location: CodeLocation,
    line: usize,
    column: usize,
    input_string: []const u8,
    input_pos: usize,
    whitespace: []const u8,
    quote_chars: []const u8,
    token_start_pos: usize,
    token_line: usize,
    token_column: usize,
    token_string: ArrayList(u8),
    streaming: bool,

    pub fn init(allocator: Allocator, input_string: []const u8, reference_location: ?CodeLocation, streaming: bool) !Tokenizer {
        const ref_loc = reference_location orelse CodeLocation.init(null, 1, 1, 0, 0);
        const unescaped = try unescapeString(allocator, input_string);

        return Tokenizer{
            .allocator = allocator,
            .reference_location = ref_loc,
            .line = ref_loc.line,
            .column = ref_loc.column,
            .input_string = unescaped,
            .input_pos = 0,
            .whitespace = &[_]u8{ ' ', '\t', '\n', '\r', '(', ')', ',' },
            .quote_chars = &[_]u8{ '"', '\'', '^' },
            .token_start_pos = 0,
            .token_line = 0,
            .token_column = 0,
            .token_string = std.ArrayList(u8){},
            .streaming = streaming,
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.allocator.free(self.input_string);
        self.token_string.deinit(self.allocator);
    }

    /// Get next token from input
    pub fn nextToken(self: *Tokenizer) !?Token {
        self.clearTokenString();
        return try self.transitionFromSTART();
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

    fn clearTokenString(self: *Tokenizer) void {
        self.token_string.clearRetainingCapacity();
    }

    fn noteStartToken(self: *Tokenizer) void {
        self.token_start_pos = self.input_pos + self.reference_location.start_pos;
        self.token_line = self.line;
        self.token_column = self.column;
    }

    fn isWhitespace(self: *Tokenizer, ch: u8) bool {
        return std.mem.indexOfScalar(u8, self.whitespace, ch) != null;
    }

    fn isQuote(self: *Tokenizer, ch: u8) bool {
        return std.mem.indexOfScalar(u8, self.quote_chars, ch) != null;
    }

    fn isTripleQuote(self: *Tokenizer, index: usize, ch: u8) bool {
        if (!self.isQuote(ch)) return false;
        if (index + 2 >= self.input_string.len) return false;
        return self.input_string[index + 1] == ch and self.input_string[index + 2] == ch;
    }

    fn isStartMemo(self: *Tokenizer, index: usize) bool {
        if (index + 1 >= self.input_string.len) return false;
        return self.input_string[index] == '@' and self.input_string[index + 1] == ':';
    }

    fn advancePosition(self: *Tokenizer, num_chars: isize) void {
        if (num_chars >= 0) {
            var i: usize = 0;
            while (i < num_chars) : (i += 1) {
                if (self.input_pos < self.input_string.len and self.input_string[self.input_pos] == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
                self.input_pos += 1;
            }
        } else {
            var i: usize = 0;
            const abs_chars = @as(usize, @intCast(-num_chars));
            while (i < abs_chars) : (i += 1) {
                self.input_pos -= 1;
                if (self.input_string[self.input_pos] == '\n') {
                    self.line -= 1;
                    self.column = 1;
                } else {
                    self.column -= 1;
                }
            }
        }
    }

    fn getTokenLocation(self: *Tokenizer) CodeLocation {
        return CodeLocation.init(
            self.reference_location.source,
            self.token_line,
            self.token_column,
            self.token_start_pos,
            self.token_start_pos + self.token_string.items.len,
        );
    }

    // ========================================================================
    // State Transitions
    // ========================================================================

    fn transitionFromSTART(self: *Tokenizer) !?Token {
        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.noteStartToken();
            self.advancePosition(1);

            if (self.isWhitespace(ch)) {
                continue;
            } else if (ch == '#') {
                return try self.transitionFromCOMMENT();
            } else if (ch == ':') {
                return try self.transitionFromSTART_DEFINITION();
            } else if (self.isStartMemo(self.input_pos - 1)) {
                self.advancePosition(1); // Skip over ":" in "@:"
                return try self.transitionFromSTART_MEMO();
            } else if (ch == ';') {
                try self.token_string.append(self.allocator,ch);
                const str_copy = try self.allocator.dupe(u8, self.token_string.items);
                return Token{ .type = .end_def, .string = str_copy, .location = self.getTokenLocation() };
            } else if (ch == '[') {
                try self.token_string.append(self.allocator,ch);
                const str_copy = try self.allocator.dupe(u8, self.token_string.items);
                return Token{ .type = .start_array, .string = str_copy, .location = self.getTokenLocation() };
            } else if (ch == ']') {
                try self.token_string.append(self.allocator,ch);
                const str_copy = try self.allocator.dupe(u8, self.token_string.items);
                return Token{ .type = .end_array, .string = str_copy, .location = self.getTokenLocation() };
            } else if (ch == '{') {
                return try self.transitionFromGATHER_MODULE();
            } else if (ch == '}') {
                try self.token_string.append(self.allocator,ch);
                const str_copy = try self.allocator.dupe(u8, self.token_string.items);
                return Token{ .type = .end_module, .string = str_copy, .location = self.getTokenLocation() };
            } else if (self.isTripleQuote(self.input_pos - 1, ch)) {
                self.advancePosition(2); // Skip over 2nd and 3rd quote chars
                return try self.transitionFromGATHER_TRIPLE_QUOTE_STRING(ch);
            } else if (self.isQuote(ch)) {
                return try self.transitionFromGATHER_STRING(ch);
            } else if (ch == '.') {
                self.advancePosition(-1); // Back up to beginning of dot symbol
                return try self.transitionFromGATHER_DOT_SYMBOL();
            } else {
                self.advancePosition(-1); // Back up to beginning of word
                return try self.transitionFromGATHER_WORD();
            }
        }

        const str_copy = try self.allocator.dupe(u8, "");
        return Token{ .type = .eos, .string = str_copy, .location = self.getTokenLocation() };
    }

    fn transitionFromCOMMENT(self: *Tokenizer) !?Token {
        self.noteStartToken();
        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            try self.token_string.append(self.allocator,ch);
            self.advancePosition(1);
            if (ch == '\n') {
                self.advancePosition(-1);
                break;
            }
        }
        const str_copy = try self.allocator.dupe(u8, self.token_string.items);
        return Token{ .type = .comment, .string = str_copy, .location = self.getTokenLocation() };
    }

    fn transitionFromSTART_DEFINITION(self: *Tokenizer) !?Token {
        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.advancePosition(1);

            if (self.isWhitespace(ch)) {
                continue;
            } else if (self.isQuote(ch)) {
                return error.InvalidWordName;
            } else {
                self.advancePosition(-1);
                return try self.transitionFromGATHER_DEFINITION_NAME();
            }
        }
        return error.InvalidWordName;
    }

    fn transitionFromSTART_MEMO(self: *Tokenizer) !?Token {
        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.advancePosition(1);

            if (self.isWhitespace(ch)) {
                continue;
            } else if (self.isQuote(ch)) {
                return error.InvalidWordName;
            } else {
                self.advancePosition(-1);
                return try self.transitionFromGATHER_MEMO_NAME();
            }
        }
        return error.InvalidWordName;
    }

    fn gatherDefinitionName(self: *Tokenizer) !void {
        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.advancePosition(1);

            if (self.isWhitespace(ch)) {
                break;
            }
            if (self.isQuote(ch)) {
                return error.InvalidWordName;
            }
            if (ch == '[' or ch == ']' or ch == '{' or ch == '}') {
                return error.InvalidWordName;
            }
            try self.token_string.append(self.allocator,ch);
        }
    }

    fn transitionFromGATHER_DEFINITION_NAME(self: *Tokenizer) !?Token {
        self.noteStartToken();
        try self.gatherDefinitionName();
        const str_copy = try self.allocator.dupe(u8, self.token_string.items);
        return Token{ .type = .start_def, .string = str_copy, .location = self.getTokenLocation() };
    }

    fn transitionFromGATHER_MEMO_NAME(self: *Tokenizer) !?Token {
        self.noteStartToken();
        try self.gatherDefinitionName();
        const str_copy = try self.allocator.dupe(u8, self.token_string.items);
        return Token{ .type = .start_memo, .string = str_copy, .location = self.getTokenLocation() };
    }

    fn transitionFromGATHER_MODULE(self: *Tokenizer) !?Token {
        self.noteStartToken();
        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.advancePosition(1);

            if (self.isWhitespace(ch)) {
                break;
            } else if (ch == '}') {
                self.advancePosition(-1);
                break;
            } else {
                try self.token_string.append(self.allocator,ch);
            }
        }
        const str_copy = try self.allocator.dupe(u8, self.token_string.items);
        return Token{ .type = .start_module, .string = str_copy, .location = self.getTokenLocation() };
    }

    fn transitionFromGATHER_TRIPLE_QUOTE_STRING(self: *Tokenizer, delim: u8) !?Token {
        self.noteStartToken();

        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];

            if (ch == delim and self.isTripleQuote(self.input_pos, ch)) {
                // Check if this triple quote is followed by at least one more quote (greedy mode)
                if (self.input_pos + 3 < self.input_string.len and self.input_string[self.input_pos + 3] == delim) {
                    self.advancePosition(1);
                    try self.token_string.append(self.allocator,delim);
                    continue;
                }

                // Normal behavior: close at first triple quote
                self.advancePosition(3);
                const str_copy = try self.allocator.dupe(u8, self.token_string.items);
                return Token{ .type = .string, .string = str_copy, .location = self.getTokenLocation() };
            } else {
                self.advancePosition(1);
                try self.token_string.append(self.allocator,ch);
            }
        }

        if (self.streaming) {
            return null;
        }
        return error.UnterminatedString;
    }

    fn transitionFromGATHER_STRING(self: *Tokenizer, delim: u8) !?Token {
        self.noteStartToken();

        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.advancePosition(1);

            if (ch == delim) {
                const str_copy = try self.allocator.dupe(u8, self.token_string.items);
                return Token{ .type = .string, .string = str_copy, .location = self.getTokenLocation() };
            } else {
                try self.token_string.append(self.allocator,ch);
            }
        }

        if (self.streaming) {
            return null;
        }
        return error.UnterminatedString;
    }

    fn transitionFromGATHER_WORD(self: *Tokenizer) !?Token {
        self.noteStartToken();
        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.advancePosition(1);

            if (self.isWhitespace(ch)) {
                break;
            }
            if (ch == ';' or ch == '{' or ch == '}' or ch == '#') {
                self.advancePosition(-1);
                break;
            }

            // Handle RFC 9557 datetime with IANA timezone
            if (ch == '[') {
                if (std.mem.indexOf(u8, self.token_string.items, "T") != null) {
                    // This looks like a datetime, gather until ']'
                    try self.token_string.append(self.allocator,ch);
                    while (self.input_pos < self.input_string.len) {
                        const tz_char = self.input_string[self.input_pos];
                        self.advancePosition(1);
                        try self.token_string.append(self.allocator,tz_char);
                        if (tz_char == ']') break;
                    }
                    break;
                } else {
                    // Not a datetime, treat '[' as delimiter
                    self.advancePosition(-1);
                    break;
                }
            }
            if (ch == ']') {
                self.advancePosition(-1);
                break;
            }
            try self.token_string.append(self.allocator,ch);
        }
        const str_copy = try self.allocator.dupe(u8, self.token_string.items);
        return Token{ .type = .word, .string = str_copy, .location = self.getTokenLocation() };
    }

    fn transitionFromGATHER_DOT_SYMBOL(self: *Tokenizer) !?Token {
        self.noteStartToken();
        var full_token = ArrayList(u8){};
        defer full_token.deinit(self.allocator);

        while (self.input_pos < self.input_string.len) {
            const ch = self.input_string[self.input_pos];
            self.advancePosition(1);

            if (self.isWhitespace(ch)) {
                break;
            }
            if (ch == ';' or ch == '[' or ch == ']' or ch == '{' or ch == '}' or ch == '#') {
                self.advancePosition(-1);
                break;
            } else {
                try full_token.append(self.allocator, ch);
                try self.token_string.append(self.allocator,ch);
            }
        }

        // If dot symbol has no characters after the dot, treat it as a word
        if (full_token.items.len < 2) {
            const str_copy = try self.allocator.dupe(u8, full_token.items);
            return Token{ .type = .word, .string = str_copy, .location = self.getTokenLocation() };
        }

        // For DOT_SYMBOL, return the string without the dot prefix
        const symbol_without_dot = try self.allocator.dupe(u8, full_token.items[1..]);
        return Token{ .type = .dot_symbol, .string = symbol_without_dot, .location = self.getTokenLocation() };
    }
};

/// ============================================================================
/// Helper Functions
/// ============================================================================

fn unescapeString(allocator: Allocator, s: []const u8) ![]const u8 {
    const result = try allocator.dupe(u8, s);
    // Simple replacements for &lt; and &gt;
    // In a real implementation, you'd want a more robust string replacement
    return result;
}
