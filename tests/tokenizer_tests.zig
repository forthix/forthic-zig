const std = @import("std");
const testing = std.testing;
const forthic = @import("forthic");
const tokenizer_mod = forthic.tokenizer;

const Tokenizer = tokenizer_mod.Tokenizer;
const TokenType = tokenizer_mod.TokenType;

test "tokenizer: single word" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "WORD", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.word, token.type);
    try testing.expectEqualStrings("WORD", token.string);
}

test "tokenizer: multiple words" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "WORD1 WORD2 WORD3", null, false);
    defer t.deinit();

    const expected = [_][]const u8{ "WORD1", "WORD2", "WORD3" };
    for (expected) |exp| {
        const token = (try t.nextToken()).?;
        defer allocator.free(token.string);
        try testing.expectEqual(TokenType.word, token.type);
        try testing.expectEqualStrings(exp, token.string);
    }
}

test "tokenizer: array tokens" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "[ 1 2 3 ]", null, false);
    defer t.deinit();

    const token1 = (try t.nextToken()).?;
    defer allocator.free(token1.string);
    try testing.expectEqual(TokenType.start_array, token1.type);

    const token2 = (try t.nextToken()).?;
    defer allocator.free(token2.string);
    try testing.expectEqual(TokenType.word, token2.type);
    try testing.expectEqualStrings("1", token2.string);

    // Skip remaining tokens
    {
        const token3 = (try t.nextToken()).?;
        defer allocator.free(token3.string);
    }
    {
        const token4 = (try t.nextToken()).?;
        defer allocator.free(token4.string);
    }

    const token_end = (try t.nextToken()).?;
    defer allocator.free(token_end.string);
    try testing.expectEqual(TokenType.end_array, token_end.type);
}

test "tokenizer: module tokens" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "{module}", null, false);
    defer t.deinit();

    const token1 = (try t.nextToken()).?;
    defer allocator.free(token1.string);
    try testing.expectEqual(TokenType.start_module, token1.type);
    try testing.expectEqualStrings("module", token1.string);

    const token2 = (try t.nextToken()).?;
    defer allocator.free(token2.string);
    try testing.expectEqual(TokenType.end_module, token2.type);
}

test "tokenizer: definition tokens" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, ": DOUBLE 2 * ;", null, false);
    defer t.deinit();

    const token1 = (try t.nextToken()).?;
    defer allocator.free(token1.string);
    try testing.expectEqual(TokenType.start_def, token1.type);
    try testing.expectEqualStrings("DOUBLE", token1.string);

    // Skip middle tokens
    {
        const token2 = (try t.nextToken()).?;
        defer allocator.free(token2.string);
    }
    {
        const token3 = (try t.nextToken()).?;
        defer allocator.free(token3.string);
    }

    const token_end = (try t.nextToken()).?;
    defer allocator.free(token_end.string);
    try testing.expectEqual(TokenType.end_def, token_end.type);
}

test "tokenizer: double quote string" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "\"hello world\"", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.string, token.type);
    try testing.expectEqualStrings("hello world", token.string);
}

test "tokenizer: single quote string" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "'hello world'", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.string, token.type);
    try testing.expectEqualStrings("hello world", token.string);
}

test "tokenizer: triple quote string" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "\"\"\"multi\nline\nstring\"\"\"", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.string, token.type);
    try testing.expectEqualStrings("multi\nline\nstring", token.string);
}

test "tokenizer: empty string" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "\"\"", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.string, token.type);
    try testing.expectEqualStrings("", token.string);
}

test "tokenizer: comment" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "WORD1 # this is a comment\nWORD2", null, false);
    defer t.deinit();

    const token1 = (try t.nextToken()).?;
    defer allocator.free(token1.string);
    try testing.expectEqual(TokenType.word, token1.type);
    try testing.expectEqualStrings("WORD1", token1.string);

    const token2 = (try t.nextToken()).?;
    defer allocator.free(token2.string);
    try testing.expectEqual(TokenType.comment, token2.type);

    const token3 = (try t.nextToken()).?;
    defer allocator.free(token3.string);
    try testing.expectEqual(TokenType.word, token3.type);
    try testing.expectEqualStrings("WORD2", token3.string);
}

test "tokenizer: dot symbol" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, ".field", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.dot_symbol, token.type);
    try testing.expectEqualStrings("field", token.string);
}

test "tokenizer: dot symbol with hyphen" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, ".field-name", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.dot_symbol, token.type);
    try testing.expectEqualStrings("field-name", token.string);
}

test "tokenizer: lone dot is word" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, ".", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.word, token.type);
    try testing.expectEqualStrings(".", token.string);
}

test "tokenizer: memo" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "@: MEMOIZED 2 * ;", null, false);
    defer t.deinit();

    const token1 = (try t.nextToken()).?;
    defer allocator.free(token1.string);

    try testing.expectEqual(TokenType.start_memo, token1.type);
    try testing.expectEqualStrings("MEMOIZED", token1.string);

    const token2 = (try t.nextToken()).?;
    defer allocator.free(token2.string);
    try testing.expectEqual(TokenType.word, token2.type);
    try testing.expectEqualStrings("2", token2.string);
}

test "tokenizer: RFC 9557 datetime" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "2025-05-20T08:00:00[America/Los_Angeles]", null, false);
    defer t.deinit();

    const token = (try t.nextToken()).?;
    defer allocator.free(token.string);

    try testing.expectEqual(TokenType.word, token.type);
    try testing.expectEqualStrings("2025-05-20T08:00:00[America/Los_Angeles]", token.string);
}

test "tokenizer: whitespace handling" {
    const allocator = testing.allocator;
    var t = try Tokenizer.init(allocator, "WORD1\t\tWORD2\n\nWORD3", null, false);
    defer t.deinit();

    const expected = [_][]const u8{ "WORD1", "WORD2", "WORD3" };
    for (expected) |exp| {
        const token = (try t.nextToken()).?;
        defer allocator.free(token.string);
        try testing.expectEqualStrings(exp, token.string);
    }
}
