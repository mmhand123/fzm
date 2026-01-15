const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const installErrors = @import("install_errors.zig");
const InstallError = installErrors.InstallError;
const log = std.log.scoped(.install);
const version = @import("version.zig");
const dirs = @import("../../dirs.zig");
const fetching = @import("../../http/fetching.zig");
const platform = @import("../../platform.zig");
const Fetcher = fetching.Fetcher;
const FetchResult = fetching.FetchResult;
const FetchError = fetching.FetchError;

/// Downloads the tarball for the current platform and returns the path to the cached file.
pub fn downloadTarball(allocator: std.mem.Allocator, version_info: version.VersionInfo) ![]const u8 {
    const cache_dir_path = try dirs.getCacheDir(allocator);
    defer allocator.free(cache_dir_path);

    const maybe_artifact: ?version.Artifact = @field(version_info, platform.platform_key);
    const artifact = maybe_artifact orelse {
        log.err("artifact not found for {s}", .{platform.platform_key});
        return error.ArtifactNotFound;
    };

    std.fs.makeDirAbsolute(cache_dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var cache_dir = try std.fs.openDirAbsolute(cache_dir_path, .{});
    defer cache_dir.close();

    var fetcher: Fetcher = .{
        .alloc = allocator,
        .response_storage = std.io.Writer.Allocating.init(allocator),
    };

    try downloadTarballWithFetch(artifact, cache_dir, &fetcher);

    const filename = std.fs.path.basename(artifact.tarball);
    return std.fs.path.join(allocator, &.{ cache_dir_path, filename });
}

/// Extracts a .tar.xz tarball to the destination directory.
/// Strips the root component (e.g., "zig-linux-x86_64-0.13.0/") so files
/// are extracted directly into dest_dir.
pub fn extractTarball(allocator: std.mem.Allocator, tarball_path: []const u8, dest_dir: std.fs.Dir) !void {
    const file = try std.fs.openFileAbsolute(tarball_path, .{});
    defer file.close();

    var file_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&file_buf);
    const old_reader = file_reader.interface.adaptToOldInterface();

    var xz_stream = try std.compress.xz.decompress(allocator, old_reader);
    defer xz_stream.deinit();

    // Bridge xz GenericReader output back to new std.Io.Reader for tar
    var adapter_buf: [4096]u8 = undefined;
    var tar_adapter = xz_stream.reader().adaptToNewApi(&adapter_buf);

    try std.tar.pipeToFileSystem(dest_dir, &tar_adapter.new_interface, .{
        .strip_components = 1,
    });
}

fn downloadTarballWithFetch(
    artifact: version.Artifact,
    cache_dir: std.fs.Dir,
    fetcher: anytype,
) InstallError!void {
    log.debug("downloading artifact: {f}", .{std.json.fmt(artifact, .{ .whitespace = .indent_2 })});
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
const MockFetcher = fetching.MockFetcher;

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

test "extractTarball extracts files with root component stripped" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const tarball_bytes = @embedFile("../../e2e/fixtures/test.tar.xz");
    try tmp.dir.writeFile(.{ .sub_path = "test.tar.xz", .data = tarball_bytes });

    const tarball_path = try tmp.dir.realpathAlloc(testing.allocator, "test.tar.xz");
    defer testing.allocator.free(tarball_path);

    try tmp.dir.makeDir("extracted");
    var dest_dir = try tmp.dir.openDir("extracted", .{});
    defer dest_dir.close();

    try extractTarball(testing.allocator, tarball_path, dest_dir);

    const content = try dest_dir.readFileAlloc(testing.allocator, "zig", 1024);
    defer testing.allocator.free(content);

    try testing.expectEqualStrings("test-zig-binary\n", content);
}

test "extractTarball returns error for corrupted tarball" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "bad.tar.xz", .data = "not a valid tarball" });

    const tarball_path = try tmp.dir.realpathAlloc(testing.allocator, "bad.tar.xz");
    defer testing.allocator.free(tarball_path);

    try tmp.dir.makeDir("extracted");
    var dest_dir = try tmp.dir.openDir("extracted", .{});
    defer dest_dir.close();

    const result = extractTarball(testing.allocator, tarball_path, dest_dir);
    try testing.expectError(error.BadHeader, result);
}
