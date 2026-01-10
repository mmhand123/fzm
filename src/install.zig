//! Zig version installation and management.
//!
//! Handles downloading and installing Zig versions from the official CDN.
//! Supports both release versions (semver format) and master builds.

const std = @import("std");
const dirs = @import("dirs.zig");
const errors = @import("errors.zig");
const http = std.http;
const Uri = std.Uri;

const CDN_INDEX_URL = "https://ziglang.org/download/index.json";

const InstallError = error{
    /// Version string is not "master" or valid semver (x.x.x)
    InvalidVersion,
    /// Version does not exist on the Zig CDN
    VersionNotFound,
    /// HTTP request failed or returned non-success status
    HttpRequestFailed,
    /// Failed to parse CDN response as JSON
    JsonParseFailed,
};

/// Validates that a version string is either "master" or valid semver (x.x.x).
///
/// Semver must be exactly three numeric components separated by dots.
/// Examples: "0.15.2", "1.0.0", "master"
fn validateVersion(version: []const u8) InstallError!void {
    if (std.mem.eql(u8, version, "master")) return;

    var dot_count: usize = 0;
    var last_was_dot = true; // Start true to catch leading dot

    for (version) |c| {
        if (c == '.') {
            if (last_was_dot) return error.InvalidVersion; // Consecutive or leading dot
            dot_count += 1;
            last_was_dot = true;
        } else if (std.ascii.isDigit(c)) {
            last_was_dot = false;
        } else {
            return error.InvalidVersion;
        }
    }

    // Must have exactly 2 dots and not end with a dot
    if (dot_count != 2 or last_was_dot) return error.InvalidVersion;
}

/// Checks that a version exists on the Zig CDN by fetching the index.json
/// and verifying the version key is present.
fn checkVersionExists(allocator: std.mem.Allocator, version: []const u8) InstallError!void {
    var client: http.Client = .{ .allocator = allocator };

    var response_body = std.io.Writer.Allocating.init(allocator);
    const result = client.fetch(.{
        .location = .{ .url = CDN_INDEX_URL },
        .response_writer = &response_body.writer,
    }) catch return error.HttpRequestFailed;

    if (result.status != .ok) return error.HttpRequestFailed;

    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        response_body.written(),
        .{},
    ) catch return error.JsonParseFailed;

    // Check if version key exists in the top-level object
    const root = parsed.value;
    if (root != .object) return error.JsonParseFailed;

    if (!root.object.contains(version)) {
        return error.VersionNotFound;
    }
}

pub fn install(allocator: std.mem.Allocator, version: []const u8) void {
    validateVersion(version) catch |err| {
        return printInstallError(err, version);
    };

    checkVersionExists(allocator, version) catch |err| {
        return printInstallError(err, version);
    };

    const data_dir = dirs.getDataDir(allocator) catch {
        return errors.prettyError("error: failed to get data directory\n", .{}) catch {};
    };

    std.debug.print("installing {s}\n", .{version});
    std.debug.print("exe_dir: {s}\n", .{data_dir});
}

fn printInstallError(err: InstallError, version: []const u8) void {
    var buf: [4096]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&buf);
    defer stderr.interface.flush() catch {};

    switch (err) {
        error.InvalidVersion => errors.prettyError(
            "error: invalid version \"{s}\" - must be \"master\" or semver (e.g., 0.15.2)\n",
            .{version},
        ) catch {},
        error.VersionNotFound => errors.prettyError(
            "error: version \"{s}\" not found on Zig download server\n",
            .{version},
        ) catch {},
        error.HttpRequestFailed => errors.prettyError(
            "error: failed to connect to Zig download server\n",
            .{},
        ) catch {},
        error.JsonParseFailed => errors.prettyError(
            "error: failed to parse response from Zig download server\n",
            .{},
        ) catch {},
    }
}

test "validateVersion accepts master" {
    try validateVersion("master");
}

test "validateVersion accepts valid semver" {
    try validateVersion("0.15.2");
    try validateVersion("0.9.1");
    try validateVersion("1.0.0");
    try validateVersion("12.34.56");
}

test "validateVersion rejects invalid input" {
    const expectError = std.testing.expectError;

    // Wrong keywords
    try expectError(error.InvalidVersion, validateVersion("latest"));
    try expectError(error.InvalidVersion, validateVersion("stable"));

    // Missing components
    try expectError(error.InvalidVersion, validateVersion("0.15"));
    try expectError(error.InvalidVersion, validateVersion("0"));
    try expectError(error.InvalidVersion, validateVersion(""));

    // Extra components
    try expectError(error.InvalidVersion, validateVersion("0.15.2.1"));

    // Prefix/suffix
    try expectError(error.InvalidVersion, validateVersion("v0.15.2"));
    try expectError(error.InvalidVersion, validateVersion("0.15.2-dev"));
    try expectError(error.InvalidVersion, validateVersion("0.15.2+abc"));

    // Invalid characters
    try expectError(error.InvalidVersion, validateVersion("0.15.x"));
    try expectError(error.InvalidVersion, validateVersion("a.b.c"));

    // Malformed dots
    try expectError(error.InvalidVersion, validateVersion(".0.15.2"));
    try expectError(error.InvalidVersion, validateVersion("0.15.2."));
    try expectError(error.InvalidVersion, validateVersion("0..15.2"));
}
