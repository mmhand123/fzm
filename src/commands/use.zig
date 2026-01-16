//! Sets the "in use" Zig version.
//!
//! Updates the state file and optionally updates the symlink in FZM_TMP_PATH
//! for immediate effect in the current shell session.

const std = @import("std");
const state = @import("../state.zig");
const versions = @import("../versions.zig");
const errors = @import("../errors.zig");
const linking = @import("../linking.zig");
const zon = @import("../zon.zig");

const log = std.log.scoped(.use);

pub fn use(allocator: std.mem.Allocator, app_state: *state.State, target_version: ?[]const u8) !void {
    if (target_version) |version| {
        try updateToVersion(allocator, app_state, version);
        return;
    }

    try autoswitchVersion(allocator);
}

fn updateToVersion(allocator: std.mem.Allocator, app_state: *state.State, target_version: []const u8) !void {
    const installed = versions.getInstalledVersion(allocator, target_version) catch {
        try errors.prettyError("zig version '{s}' is not installed\n", .{target_version});
        return error.UserError;
    };

    defer allocator.free(installed.?);

    try app_state.setInUse(target_version);
    try app_state.save();

    // TODO: we should not keep looking this up
    if (std.posix.getenv("FZM_TMP_PATH")) |tmp_path| {
        log.debug("updating symlink in {s}", .{tmp_path});
        try linking.updateSymlink(allocator, tmp_path, target_version);
    }

    log.debug("using zig {s} ({s})", .{ target_version, installed.? });
}

fn autoswitchVersion(allocator: std.mem.Allocator) !void {
    const build_zon = zon.readBuildZon(allocator, std.fs.cwd()) catch |err| {
        log.warn("failed to read build.zig.zon: {}", .{err});
        return;
    } orelse {
        // This should never happen, because we only setup autoswitching if we find a build.zig.zon
        // however, we can just stick with the default
        return;
    };

    const min_version = build_zon.data.minimum_zig_version orelse {
        // This is fine - we'll just use the default version and won't be able to autoswitch
        return;
    };

    const best_match = try versions.findBestMatchingVersion(allocator, min_version) orelse {
        return;
    };

    log.debug("minimum_zig_version: {s}, best match: {s}", .{ min_version, best_match });

    // TODO: we should not keep looking this up
    if (std.posix.getenv("FZM_TMP_PATH")) |tmp_path| {
        log.debug("updating symlink in {s}", .{tmp_path});
        try linking.updateSymlink(allocator, tmp_path, best_match);
    }
}
