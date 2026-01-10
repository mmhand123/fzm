//! Zig version installation and management.
//!
//! Handles downloading and installing Zig versions from the official CDN.
//! Supports both release versions (semver format) and master builds.

const std = @import("std");
const dirs = @import("../dirs.zig");
const errors = @import("../errors.zig");
const version = @import("version.zig");
const installErrors = @import("install_errors.zig");
const http = std.http;
const Uri = std.Uri;

const log = std.log.scoped(.install);

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

pub fn install(allocator: std.mem.Allocator, target_version: []const u8) void {
    version.validateVersion(target_version) catch |err| {
        return installErrors.printInstallError(err, target_version);
    };

    const version_info = version.fetchVersionInfo(allocator, target_version) catch |err| {
        return installErrors.printInstallError(err, target_version);
    };
    defer version_info.deinit();

    const data_dir = dirs.getDataDir(allocator) catch {
        return errors.prettyError("error: failed to get data directory\n", .{}) catch {};
    };

    log.debug("version_info: {f}", .{std.json.fmt(version_info.value, .{ .whitespace = .indent_2 })});

    log.debug("installing {s}", .{target_version});
    log.debug("exe_dir: {s}", .{data_dir});
    if (version_info.value.version) |v| {
        log.debug("full version: {s}", .{v});
    }
}
