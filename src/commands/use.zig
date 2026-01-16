//! Sets the "in use" Zig version.
//!
//! Updates the state file and optionally updates the symlink in FZM_TMP_PATH
//! for immediate effect in the current shell session.

const std = @import("std");
const state = @import("../state.zig");
const versions = @import("../versions.zig");
const errors = @import("../errors.zig");
const linking = @import("../linking.zig");

const log = std.log.scoped(.use);

pub fn use(allocator: std.mem.Allocator, app_state: *state.State, target_version: []const u8) !void {
    const installed = versions.getInstalledVersion(allocator, target_version) catch {
        try errors.prettyError("zig version '{s}' is not installed\n", .{target_version});
        return error.UserError;
    };

    defer allocator.free(installed.?);

    try app_state.setInUse(target_version);
    try app_state.save();

    if (std.posix.getenv("FZM_TMP_PATH")) |tmp_path| {
        log.debug("updating symlink in {s}", .{tmp_path});
        try linking.updateSymlink(allocator, tmp_path, target_version);
    }

    log.debug("using zig {s} ({s})", .{ target_version, installed.? });
}
