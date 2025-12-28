const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const Module = @import("../forthic/module.zig").Module;
const Word = @import("../forthic/word.zig").Word;
const GrpcClient = @import("client.zig").GrpcClient;
const RemoteWord = @import("remote_word.zig").RemoteWord;

/// Module that wraps a remote Forthic module via gRPC
pub const RemoteModule = struct {
    allocator: Allocator,
    name: []const u8,
    description: []const u8,
    client: *GrpcClient,
    runtime_name: []const u8,
    words: ArrayList(*RemoteWord),
    initialized: bool,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        name: []const u8,
        client: *GrpcClient,
        runtime_name: []const u8,
    ) !Self {
        return Self{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .description = try allocator.dupe(u8, ""),
            .client = client,
            .runtime_name = try allocator.dupe(u8, runtime_name),
            .words = ArrayList(*RemoteWord).init(allocator),
            .initialized = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.words.items) |word| {
            word.deinit();
            self.allocator.destroy(word);
        }
        self.words.deinit();
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        self.allocator.free(self.runtime_name);
    }

    /// Initialize by fetching module info from remote runtime
    pub fn initialize(self: *Self) !void {
        if (self.initialized) return;

        // TODO: Call client.getModuleInfo() when implemented
        // For now, mark as initialized without remote words
        self.initialized = true;
    }

    pub fn addRemoteWord(
        self: *Self,
        name: []const u8,
        stack_effect: []const u8,
        description: []const u8,
    ) !void {
        const word = try self.allocator.create(RemoteWord);
        word.* = try RemoteWord.init(
            self.allocator,
            name,
            self.client,
            self.runtime_name,
            self.name,
            stack_effect,
            description,
        );
        try self.words.append(word);
    }

    pub fn getName(self: *const Self) []const u8 {
        return self.name;
    }

    pub fn getDescription(self: *const Self) []const u8 {
        return self.description;
    }

    pub fn findWord(self: *Self, name: []const u8) ?*RemoteWord {
        for (self.words.items) |word| {
            if (std.mem.eql(u8, word.name, name)) {
                return word;
            }
        }
        return null;
    }
};
