//! Zig version installation and management.
//!
//! Handles downloading and installing Zig versions from the official CDN.
//! Supports both release versions (semver format) and master builds.

const std = @import("std");
const builtin = @import("builtin");
const dirs = @import("../dirs.zig");
const errors = @import("../errors.zig");
const versions = @import("../versions.zig");
const version = @import("version.zig");
const installErrors = @import("install_errors.zig");
const tarball = @import("tarball.zig");
const http = std.http;
const Uri = std.Uri;

const log = std.log.scoped(.install);

pub fn install(allocator: std.mem.Allocator, target_version: []const u8) !void {
    version.validateVersion(target_version) catch |err| {
        return installErrors.printInstallError(err, target_version);
    };

    const version_info = version.fetchVersionInfo(allocator, target_version) catch |err| {
        return installErrors.printInstallError(err, target_version);
    };

    const full_version = version_info.value.version orelse target_version;
    const installed = versions.getInstalledVersion(allocator, target_version) catch null;

    if (installed) |installed_version| {
        if (std.mem.eql(u8, installed_version, full_version)) {
            errors.prettyWarning("zig {s} is already installed, skipping", .{installed_version}) catch {};
            return;
        }

        if (std.mem.eql(u8, target_version, "master")) {
            log.info("updating master from {s} to {s}", .{ installed_version, full_version });
        }
    }

    const data_dir = dirs.getDataDir(allocator) catch {
        return errors.prettyError("error: failed to get data directory\n", .{}) catch {};
    };

    try tarball.downloadTarball(allocator, version_info.value);

    log.debug("version_info: {f}", .{std.json.fmt(version_info.value, .{ .whitespace = .indent_2 })});

    log.debug("installing {s}", .{target_version});
    log.debug("exe_dir: {s}", .{data_dir});
    if (version_info.value.version) |v| {
        log.debug("full version: {s}", .{v});
    }
}

test {
    _ = @import("tarball.zig");
    _ = @import("version.zig");
}
