const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const GrpcClient = @import("client.zig").GrpcClient;
const RemoteModule = @import("remote_module.zig").RemoteModule;

/// Singleton manager for gRPC runtime connections
pub const RuntimeManager = struct {
    allocator: Allocator,
    clients: StringHashMap(*GrpcClient),
    modules: StringHashMap(*RemoteModule),

    const Self = @This();

    var instance: ?*Self = null;

    pub fn getInstance(allocator: Allocator) !*Self {
        if (instance) |inst| {
            return inst;
        }

        const mgr = try allocator.create(Self);
        mgr.* = Self{
            .allocator = allocator,
            .clients = StringHashMap(*GrpcClient).init(allocator),
            .modules = StringHashMap(*RemoteModule).init(allocator),
        };
        instance = mgr;
        return mgr;
    }

    pub fn deinit(self: *Self) void {
        // Clean up clients
        var client_iter = self.clients.iterator();
        while (client_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.clients.deinit();

        // Clean up modules
        var module_iter = self.modules.iterator();
        while (module_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.modules.deinit();

        instance = null;
        self.allocator.destroy(self);
    }

    pub fn connectRuntime(self: *Self, runtime_name: []const u8, address: []const u8) !*GrpcClient {
        // Check if already connected
        if (self.clients.get(runtime_name)) |client| {
            return client;
        }

        // Create new client
        const client = try self.allocator.create(GrpcClient);
        client.* = try GrpcClient.init(self.allocator, address);

        const key = try self.allocator.dupe(u8, runtime_name);
        try self.clients.put(key, client);

        return client;
    }

    pub fn getClient(self: *Self, runtime_name: []const u8) ?*GrpcClient {
        return self.clients.get(runtime_name);
    }

    pub fn registerModule(
        self: *Self,
        runtime_name: []const u8,
        module_name: []const u8,
    ) !*RemoteModule {
        const client = self.clients.get(runtime_name) orelse return error.RuntimeNotConnected;

        const module = try self.allocator.create(RemoteModule);
        module.* = try RemoteModule.init(self.allocator, module_name, client, runtime_name);

        const key = try self.allocator.dupe(u8, module_name);
        try self.modules.put(key, module);

        return module;
    }

    pub fn getModule(self: *Self, module_name: []const u8) ?*RemoteModule {
        return self.modules.get(module_name);
    }
};
