const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

/// ============================================================================
/// WordOptions - Container for word optional parameters
/// ============================================================================

/// WordOptions stores key-value pairs for word options
/// Created from flat array: [key1, val1, key2, val2, ...]
pub const WordOptions = struct {
    options: StringHashMap(?*anyopaque),
    allocator: Allocator,

    /// Create WordOptions from flat array of alternating keys and values
    pub fn fromArray(allocator: Allocator, flatArray: anytype) !WordOptions {
        const TypeInfo = @typeInfo(@TypeOf(flatArray));
        const slice = switch (TypeInfo) {
            .pointer => |ptr| switch (ptr.size) {
                .slice => flatArray,
                .one => switch (@typeInfo(ptr.child)) {
                    .array => flatArray[0..],
                    else => return error.InvalidFormat,
                },
                else => return error.InvalidFormat,
            },
            else => return error.InvalidFormat,
        };

        if (slice.len % 2 != 0) {
            return error.InvalidFormat;
        }

        var options = StringHashMap(?*anyopaque).init(allocator);
        errdefer options.deinit();

        var i: usize = 0;
        while (i < slice.len) : (i += 2) {
            const key_ptr = slice[i] orelse return error.InvalidFormat;
            const key = @as(*const []const u8, @ptrCast(@alignCast(key_ptr))).*;
            const value = slice[i + 1];

            try options.put(key, value);
        }

        return WordOptions{
            .options = options,
            .allocator = allocator,
        };
    }

    pub fn init(allocator: Allocator) WordOptions {
        return WordOptions{
            .options = StringHashMap(?*anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WordOptions) void {
        self.options.deinit();
    }

    /// Get option value, returns null if not found
    pub fn get(self: *const WordOptions, key: []const u8) ?*anyopaque {
        return self.options.get(key) orelse null;
    }

    /// Get option value with default
    pub fn getWithDefault(self: *const WordOptions, key: []const u8, default: ?*anyopaque) ?*anyopaque {
        return self.options.get(key) orelse default;
    }

    /// Check if key exists
    pub fn has(self: *const WordOptions, key: []const u8) bool {
        return self.options.contains(key);
    }

    /// Get all keys
    pub fn keys(self: *const WordOptions, allocator: Allocator) ![][]const u8 {
        var result = ArrayList([]const u8){};
        errdefer result.deinit(allocator);

        var it = self.options.keyIterator();
        while (it.next()) |key| {
            try result.append(allocator, key.*);
        }

        return result.toOwnedSlice(allocator);
    }

    /// Convert to hashmap
    pub fn toRecord(self: *const WordOptions, allocator: Allocator) !StringHashMap(?*anyopaque) {
        var result = StringHashMap(?*anyopaque).init(allocator);
        errdefer result.deinit();

        var it = self.options.iterator();
        while (it.next()) |entry| {
            try result.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        return result;
    }

    /// Get number of options
    pub fn count(self: *const WordOptions) usize {
        return self.options.count();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "WordOptions: create from flat array" {
    const allocator = std.testing.allocator;

    const key1 = "depth";
    const key2 = "with_key";
    const val1: i32 = 2;
    const val2: bool = true;

    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    const val2_ptr = try allocator.create(bool);
    defer allocator.destroy(val2_ptr);
    val2_ptr.* = val2;

    const key1_ptr = try allocator.create([]const u8);
    defer allocator.destroy(key1_ptr);
    key1_ptr.* = key1;

    const key2_ptr = try allocator.create([]const u8);
    defer allocator.destroy(key2_ptr);
    key2_ptr.* = key2;

    const flatArray = [_]?*anyopaque{
        @ptrCast(key1_ptr),
        @ptrCast(val1_ptr),
        @ptrCast(key2_ptr),
        @ptrCast(val2_ptr),
    };

    var opts = try WordOptions.fromArray(allocator, &flatArray);
    defer opts.deinit();

    try std.testing.expect(opts.has("depth"));
    try std.testing.expect(opts.has("with_key"));
}

test "WordOptions: requires even length" {
    const allocator = std.testing.allocator;

    const key1 = "depth";
    const val1: i32 = 2;

    const val1_ptr = try allocator.create(i32);
    defer allocator.destroy(val1_ptr);
    val1_ptr.* = val1;

    const key1_ptr = try allocator.create([]const u8);
    defer allocator.destroy(key1_ptr);
    key1_ptr.* = key1;

    const flatArray = [_]?*anyopaque{
        @ptrCast(key1_ptr),
        @ptrCast(val1_ptr),
        @ptrCast(key1_ptr), // Odd length
    };

    const result = WordOptions.fromArray(allocator, &flatArray);
    try std.testing.expectError(error.InvalidFormat, result);
}

test "WordOptions: has method" {
    const allocator = std.testing.allocator;
    var opts = WordOptions.init(allocator);
    defer opts.deinit();

    const key = "depth";
    const val: i32 = 2;

    const val_ptr = try allocator.create(i32);
    defer allocator.destroy(val_ptr);
    val_ptr.* = val;

    try opts.options.put(key, val_ptr);

    try std.testing.expect(opts.has("depth"));
    try std.testing.expect(!opts.has("missing"));
}

test "WordOptions: empty options" {
    const allocator = std.testing.allocator;
    var opts = WordOptions.init(allocator);
    defer opts.deinit();

    try std.testing.expect(!opts.has("anything"));
    try std.testing.expectEqual(@as(usize, 0), opts.count());
}
