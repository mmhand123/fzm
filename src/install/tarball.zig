const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const installErrors = @import("install_errors.zig");
const InstallError = installErrors.InstallError;
const log = std.log.scoped(.install);
const version = @import("version.zig");
const dirs = @import("../dirs.zig");

pub const FetchResult = struct {
    status: http.Status,
    body: []const u8,
};

pub const FetchError = error{
    ConnectionRefused,
    ConnectionTimedOut,
    UnexpectedFailure,
};

pub fn downloadTarball(allocator: std.mem.Allocator, version_info: version.VersionInfo) !void {
    const cache_dir_path = try dirs.getCacheDir(allocator);
    const target = builtin.target;
    const arch_name = @tagName(target.cpu.arch);
    const os_name = @tagName(target.os.tag);
    const download_name = arch_name ++ "-" ++ os_name;
    const maybe_artifact: ?version.Artifact = @field(version_info, download_name);
    const artifact = maybe_artifact orelse {
        log.err("artifact not found for {s}", .{download_name});
        return error.ArtifactNotFound;
    };

    log.debug("artifact: {f}", .{std.json.fmt(artifact, .{ .whitespace = .indent_2 })});

    std.fs.makeDirAbsolute(cache_dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var cache_dir = try std.fs.openDirAbsolute(cache_dir_path, .{});
    defer cache_dir.close();

    const Fetcher = struct {
        alloc: std.mem.Allocator,
        response_storage: std.io.Writer.Allocating,

        fn fetch(self: *@This(), url: []const u8) FetchError!FetchResult {
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

    var fetcher: Fetcher = .{
        .alloc = allocator,
        .response_storage = std.io.Writer.Allocating.init(allocator),
    };
    defer fetcher.response_storage.deinit();

    return downloadTarballWithFetch(artifact, cache_dir, &fetcher);
}

fn downloadTarballWithFetch(
    artifact: version.Artifact,
    cache_dir: std.fs.Dir,
    fetcher: anytype,
) InstallError!void {
    const result = fetcher.fetch(artifact.tarball) catch return InstallError.HttpRequestFailed;
    if (result.status != .ok) return InstallError.ArtifactDownloadFailed;

    const filename = std.fs.path.basename(artifact.tarball);
    cache_dir.writeFile(.{
        .sub_path = filename,
        .data = result.body,
        .flags = .{},
    }) catch return InstallError.TarballWriteFailed;
}

const testing = std.testing;

const MockFetcher = struct {
    response: ?FetchResult = null,
    err: ?FetchError = null,

    fn fetch(self: *@This(), _: []const u8) FetchError!FetchResult {
        if (self.err) |e| return e;
        return self.response.?;
    }
};

fn testArtifact(tarball_url: []const u8) version.Artifact {
    return .{
        .tarball = tarball_url,
        .shasum = "abc123",
        .size = "1024",
    };
}

test "downloadTarballWithFetch returns HttpRequestFailed on fetch error" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var fetcher: MockFetcher = .{ .err = FetchError.ConnectionRefused };
    const result = downloadTarballWithFetch(
        testArtifact("https://example.com/zig-0.13.0.tar.xz"),
        tmp.dir,
        &fetcher,
    );

    try testing.expectError(InstallError.HttpRequestFailed, result);
}

test "downloadTarballWithFetch returns ArtifactDownloadFailed on non-200" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var fetcher: MockFetcher = .{ .response = .{ .status = .not_found, .body = "" } };
    const result = downloadTarballWithFetch(
        testArtifact("https://example.com/zig-0.13.0.tar.xz"),
        tmp.dir,
        &fetcher,
    );

    try testing.expectError(InstallError.ArtifactDownloadFailed, result);
}

test "downloadTarballWithFetch writes file with correct name and content" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const body = "fake tarball content";
    var fetcher: MockFetcher = .{ .response = .{ .status = .ok, .body = body } };

    try downloadTarballWithFetch(
        testArtifact("https://example.com/zig-0.13.0.tar.xz"),
        tmp.dir,
        &fetcher,
    );

    const written = try tmp.dir.readFileAlloc(testing.allocator, "zig-0.13.0.tar.xz", 1024);
    defer testing.allocator.free(written);

    try testing.expectEqualStrings(body, written);
}
