/// A small wrapper around `std.http.Client` that allows for mocking.
const std = @import("std");
const http = std.http;
const Progress = @import("../progress.zig").Progress;

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

    /// Simple fetch without progress reporting.
    pub fn fetch(self: *@This(), url: []const u8) FetchError!FetchResult {
        return self.fetchWithProgress(url, null);
    }

    /// Fetch with optional progress callback.
    pub fn fetchWithProgress(
        self: *@This(),
        url: []const u8,
        progress: ?*Progress,
    ) FetchError!FetchResult {
        var client: http.Client = .{ .allocator = self.alloc };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return FetchError.UnexpectedFailure;

        var req = client.request(.GET, uri, .{}) catch return FetchError.UnexpectedFailure;
        defer req.deinit();

        req.sendBodiless() catch return FetchError.UnexpectedFailure;

        var head_buf: [16384]u8 = undefined;
        var response = req.receiveHead(&head_buf) catch return FetchError.UnexpectedFailure;

        if (response.head.status != .ok) {
            return .{
                .status = response.head.status,
                .body = "",
            };
        }

        const total_size = response.head.content_length;
        var downloaded: u64 = 0;

        // Read in chunks, reporting progress
        var transfer_buf: [16384]u8 = undefined;
        var reader = response.reader(&transfer_buf);

        // Stream data in chunks to report progress
        const chunk_size: usize = 16384;
        while (true) {
            const n = reader.stream(&self.response_storage.writer, std.Io.Limit.limited(chunk_size)) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return FetchError.UnexpectedFailure,
            };

            downloaded += n;
            if (progress) |p| {
                p.download(downloaded, total_size);
            }

            // If we got less than chunk_size, we might be at end
            if (n < chunk_size) {
                // Try to get more - if EndOfStream, we're done
                _ = reader.stream(&self.response_storage.writer, std.Io.Limit.limited(1)) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return FetchError.UnexpectedFailure,
                };
                downloaded += 1;
            }
        }

        return .{
            .status = response.head.status,
            .body = self.response_storage.written(),
        };
    }
};

pub const MockFetcher = struct {
    response: ?FetchResult = null,
    err: ?FetchError = null,

    pub fn fetch(self: *@This(), url: []const u8) FetchError!FetchResult {
        return self.fetchWithProgress(url, null);
    }

    pub fn fetchWithProgress(self: *@This(), _: []const u8, _: ?*Progress) FetchError!FetchResult {
        if (self.err) |e| return e;
        return self.response.?;
    }
};
