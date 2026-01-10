const std = @import("std");
const installErrors = @import("install_errors.zig");

const http = std.http;
const VERSION_INDEX_URL = "https://ziglang.org/download/index.json";

/// Download artifact info (tarball URL, checksum, size).
pub const Artifact = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: []const u8,
};

/// Version metadata from the Zig CDN index.
pub const VersionInfo = struct {
    /// Full version string (e.g., "0.16.0-dev.2135+7c0b42ba0" for master)
    version: ?[]const u8 = null,
    /// Release date (e.g., "2026-01-09")
    date: ?[]const u8 = null,
    /// Documentation URL
    docs: ?[]const u8 = null,
    /// Standard library documentation URL
    stdDocs: ?[]const u8 = null,
    /// Release notes URL (only present for some versions)
    notes: ?[]const u8 = null,
    /// Source tarball
    src: ?Artifact = null,
    /// Bootstrap tarball
    bootstrap: ?Artifact = null,

    // Platform-specific artifacts
    @"x86_64-linux": ?Artifact = null,
    @"aarch64-linux": ?Artifact = null,
    @"arm-linux": ?Artifact = null,
    @"riscv64-linux": ?Artifact = null,
    @"powerpc64le-linux": ?Artifact = null,
    @"x86-linux": ?Artifact = null,
    @"loongarch64-linux": ?Artifact = null,
    @"s390x-linux": ?Artifact = null,
    @"x86_64-macos": ?Artifact = null,
    @"aarch64-macos": ?Artifact = null,
    @"x86_64-windows": ?Artifact = null,
    @"aarch64-windows": ?Artifact = null,
    @"x86-windows": ?Artifact = null,
    @"x86_64-freebsd": ?Artifact = null,
    @"aarch64-freebsd": ?Artifact = null,
    @"arm-freebsd": ?Artifact = null,
    @"powerpc64-freebsd": ?Artifact = null,
    @"powerpc64le-freebsd": ?Artifact = null,
    @"riscv64-freebsd": ?Artifact = null,
    @"aarch64-netbsd": ?Artifact = null,
    @"arm-netbsd": ?Artifact = null,
    @"x86-netbsd": ?Artifact = null,
    @"x86_64-netbsd": ?Artifact = null,
};

/// Validates that a version string is either "master" or valid semver (x.x.x).
///
/// Semver must be exactly three numeric components separated by dots.
/// Examples: "0.15.2", "1.0.0", "master"
pub fn validateVersion(version: []const u8) installErrors.InstallError!void {
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

/// Fetches the Zig CDN index and returns the version info for the specified version.
pub fn fetchVersionInfo(allocator: std.mem.Allocator, version: []const u8) installErrors.InstallError!std.json.Parsed(VersionInfo) {
    var client: http.Client = .{ .allocator = allocator };

    var response_body = std.io.Writer.Allocating.init(allocator);
    const result = client.fetch(.{
        .location = .{ .url = VERSION_INDEX_URL },
        .response_writer = &response_body.writer,
    }) catch return error.HttpRequestFailed;

    if (result.status != .ok) return error.HttpRequestFailed;

    // Parse as generic JSON to extract the version-specific object
    const index = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        response_body.written(),
        .{},
    ) catch return error.JsonParseFailed;
    defer index.deinit();

    const root = index.value;
    if (root != .object) return error.JsonParseFailed;

    const version_value = root.object.get(version) orelse return error.VersionNotFound;

    // Parse the version-specific Value into our typed struct
    return std.json.parseFromValue(VersionInfo, allocator, version_value, .{
        .ignore_unknown_fields = true,
    }) catch return error.JsonParseFailed;
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
    try expectError(error.HttpRequestFailed, validateVersion("0.15.2.1"));

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
