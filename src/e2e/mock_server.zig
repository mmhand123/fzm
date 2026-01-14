//! Minimal mock HTTP server for e2e tests.
//!
//! Serves queued responses for testing CLI commands that make HTTP requests.
//! Each test can queue responses and spawn a server thread to handle requests.

const std = @import("std");

const Self = @This();

allocator: std.mem.Allocator,
server: std.net.Server,
port: u16,
responses: std.ArrayListUnmanaged(Response),

pub const Response = struct {
    status: []const u8,
    body: []const u8,
};

/// Creates and binds a mock server on an available port.
pub fn init(allocator: std.mem.Allocator) !Self {
    const address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 0);
    const server = try address.listen(.{ .reuse_address = true });

    return .{
        .allocator = allocator,
        .server = server,
        .port = server.listen_address.getPort(),
        .responses = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.server.deinit();
    self.responses.deinit(self.allocator);
}

/// Queues a response to be served for the next request.
pub fn queueResponse(self: *Self, status: []const u8, body: []const u8) !void {
    try self.responses.append(self.allocator, .{ .status = status, .body = body });
}

/// Returns the base URL for this server (e.g., "http://127.0.0.1:12345").
pub fn getBaseUrl(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{self.port});
}

/// Serves all queued responses, one per connection.
/// Call this in a separate thread before making client requests.
pub fn serveAll(self: *Self) void {
    for (self.responses.items) |response| {
        self.serveOne(response) catch |err| {
            std.log.err("mock server error: {}", .{err});
        };
    }
}

fn serveOne(self: *Self, response: Response) !void {
    const conn = try self.server.accept();
    defer conn.stream.close();

    // Read and discard request
    var buf: [4096]u8 = undefined;
    _ = conn.stream.read(&buf) catch {};

    // Write HTTP response
    var response_buf: [8192]u8 = undefined;
    const header = std.fmt.bufPrint(&response_buf, "HTTP/1.1 {s}\r\nContent-Length: {d}\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n", .{ response.status, response.body.len }) catch return;

    _ = conn.stream.write(header) catch return;
    _ = conn.stream.write(response.body) catch return;
}
