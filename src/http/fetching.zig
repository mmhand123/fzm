/// A small wrapper around `std.http.Client` that allows for mocking.
const std = @import("std");
const http = std.http;

pub const FetchResult = struct {
    status: http.Status,
    body: []const u8,
};

pub const FetchError = error{
    ConnectionRefused,
    ConnectionTimedOut,
    UnexpectedFailure,
};

pub const Fetcher = struct {
    alloc: std.mem.Allocator,
    response_storage: std.io.Writer.Allocating,

    pub fn fetch(self: *@This(), url: []const u8) FetchError!FetchResult {
        var client: http.Client = .{ .allocator = self.alloc };
        const result = client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &self.response_storage.writer,
        }) catch return FetchError.UnexpectedFailure;

        return .{
            .status = result.status,
            .body = self.response_storage.written(),
        };
    }
};

pub const MockFetcher = struct {
    response: ?FetchResult = null,
    err: ?FetchError = null,

    pub fn fetch(self: *@This(), _: []const u8) FetchError!FetchResult {
        if (self.err) |e| return e;
        return self.response.?;
    }
};
