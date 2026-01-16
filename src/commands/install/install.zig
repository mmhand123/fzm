//! Zig version installation and management.
//!
//! Handles downloading and installing Zig versions from the official CDN.
//! Supports both release versions (semver format) and master builds.

const std = @import("std");
const builtin = @import("builtin");
const dirs = @import("../../dirs.zig");
const errors = @import("../../errors.zig");
const state = @import("../../state.zig");
const versions = @import("../../versions.zig");
const version = @import("version.zig");
const installErrors = @import("install_errors.zig");
const tarball = @import("tarball.zig");
const http = std.http;
const Uri = std.Uri;

const log = std.log.scoped(.install);

pub fn install(allocator: std.mem.Allocator, app_state: *state.State, target_version: []const u8) !void {
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

    const tarball_path = tarball.downloadTarball(allocator, version_info.value) catch |err| {
        log.err("failed to download tarball: {}", .{err});
        return errors.prettyError("failed to download tarball\n", .{}) catch {};
    };

    log.debug("downloaded tarball to {s}", .{tarball_path});

    const version_dir_path = versions.getVersionsDir(allocator) catch {
        return errors.prettyError("failed to get versions directory\n", .{}) catch {};
    };

    const dest_path = std.fs.path.join(allocator, &.{ version_dir_path, target_version }) catch {
        return errors.prettyError("failed to create version path\n", .{}) catch {};
    };

    log.debug("installing to {s}", .{dest_path});

    // Create version directory (and parent directories if needed)
    std.fs.cwd().makePath(dest_path) catch |err| {
        log.err("failed to create version directory: {}", .{err});
        return errors.prettyError("failed to create version directory\n", .{}) catch {};
    };

    var dest_dir = std.fs.openDirAbsolute(dest_path, .{}) catch {
        return errors.prettyError("failed to open version directory\n", .{}) catch {};
    };

    log.debug("extracting to {s}", .{dest_path});

    tarball.extractTarball(allocator, tarball_path, dest_dir) catch |err| {
        log.err("failed to extract tarball: {}", .{err});
        return errors.prettyError("failed to extract tarball\n", .{}) catch {};
    };

    const version_file = dest_dir.createFile(versions.VERSION_FILE_NAME, .{}) catch {
        return errors.prettyError("failed to create version file\n", .{}) catch {};
    };

    log.debug("writing version file", .{});
    version_file.writeAll(full_version) catch {
        return errors.prettyError("failed to write version file\n", .{}) catch {};
    };

    log.info("installed zig {s}", .{full_version});

    if (app_state.in_use == null) {
        app_state.setInUse(target_version) catch {
            log.err("failed to set default version", .{});
            return;
        };
        app_state.save() catch {
            log.err("failed to save state", .{});
            return;
        };
        log.debug("set {s} as the in-use version", .{target_version});
    }
}

test {
    _ = @import("tarball.zig");
    _ = @import("version.zig");
}
