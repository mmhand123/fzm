const std = @import("std");
const state = @import("state.zig");
const versions = @import("versions.zig");
const log = std.log.scoped(.linking);

pub fn createZigSymlink(allocator: std.mem.Allocator, app_state: *const state.State, tmp_dir: []const u8) !void {
    const in_use = app_state.in_use orelse {
        return; // No version set yet
    };

    const versions_dir = try versions.getVersionsDir(allocator);
    defer allocator.free(versions_dir);

    const zig_path = try std.fs.path.join(allocator, &.{ versions_dir, in_use, "zig" });
    defer allocator.free(zig_path);

    const symlink_path = try std.fs.path.join(allocator, &.{ tmp_dir, "zig" });
    defer allocator.free(symlink_path);

    std.fs.symLinkAbsolute(zig_path, symlink_path, .{}) catch |err| {
        log.warn("failed to create zig symlink: {}", .{err});
    };
}

pub fn updateSymlink(allocator: std.mem.Allocator, tmp_path: []const u8, target_version: []const u8) !void {
    const versions_dir = try versions.getVersionsDir(allocator);
    defer allocator.free(versions_dir);

    const zig_path = try std.fs.path.join(allocator, &.{ versions_dir, target_version, "zig" });
    defer allocator.free(zig_path);

    const symlink_path = try std.fs.path.join(allocator, &.{ tmp_path, "zig" });
    defer allocator.free(symlink_path);

    std.fs.deleteFileAbsolute(symlink_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    std.fs.symLinkAbsolute(zig_path, symlink_path, .{}) catch |err| {
        log.warn("failed to update symlink: {}", .{err});
    };
}
