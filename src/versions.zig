//! Version directory management utilities.
//!
//! Provides functions to query and manage installed Zig versions.
//! Used by the install command and will be used by future commands like `list`.

const std = @import("std");
const dirs = @import("dirs.zig");

/// Name of the file that stores the full version string in each version directory.
pub const VERSION_FILE_NAME = ".fzm-version";

pub fn getVersionsDir(allocator: std.mem.Allocator) ![]const u8 {
    const data_dir = try dirs.getDataDir(allocator);
    defer allocator.free(data_dir);
    return std.fs.path.join(allocator, &.{ data_dir, "versions" });
}

pub fn getInstalledVersion(allocator: std.mem.Allocator, version: []const u8) !?[]const u8 {
    const versions_dir = try getVersionsDir(allocator);
    defer allocator.free(versions_dir);
    return getInstalledVersionFromDir(allocator, versions_dir, version);
}

fn getInstalledVersionFromDir(allocator: std.mem.Allocator, versions_dir: []const u8, version: []const u8) !?[]const u8 {
    const version_path = try std.fs.path.join(allocator, &.{ versions_dir, version });
    defer allocator.free(version_path);
    const version_file_path = try std.fs.path.join(allocator, &.{ version_path, VERSION_FILE_NAME });
    defer allocator.free(version_file_path);

    const file = std.fs.openFileAbsolute(version_file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);

    return std.mem.trim(u8, content, &std.ascii.whitespace);
}

pub fn listInstalledVersions(allocator: std.mem.Allocator) ![][]const u8 {
    const versions_dir = try getVersionsDir(allocator);
    defer allocator.free(versions_dir);
    return listInstalledVersionsFromDir(allocator, versions_dir);
}

fn listInstalledVersionsFromDir(allocator: std.mem.Allocator, versions_dir: []const u8) ![][]const u8 {
    var dir = std.fs.openDirAbsolute(versions_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer dir.close();

    var list: std.ArrayListUnmanaged([]const u8) = .empty;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            try list.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    return try list.toOwnedSlice(allocator);
}

// Tests

const testing = std.testing;

test "getInstalledVersionFromDir returns null when no file" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("0.13.0");

    const allocator = testing.allocator;
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const result = try getInstalledVersionFromDir(allocator, tmp_path, "0.13.0");
    try testing.expect(result == null);
}

test "getInstalledVersionFromDir returns content" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("master");

    const version_content = "0.16.0-dev.2135+7c0b42ba0";
    const file = try tmp_dir.dir.createFile("master/" ++ VERSION_FILE_NAME, .{});
    try file.writeAll(version_content);
    file.close();

    const allocator = testing.allocator;
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const result = try getInstalledVersionFromDir(allocator, tmp_path, "master");
    defer if (result) |r| allocator.free(r);

    try testing.expect(result != null);
    try testing.expectEqualStrings(version_content, result.?);
}

test "listInstalledVersionsFromDir returns empty slice for non-existent directory" {
    const allocator = testing.allocator;
    const result = try listInstalledVersionsFromDir(allocator, "/non/existent/path");
    try testing.expectEqual(0, result.len);
}

test "listInstalledVersionsFromDir returns empty slice for empty directory" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const allocator = testing.allocator;
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const result = try listInstalledVersionsFromDir(allocator, tmp_path);
    defer allocator.free(result);

    try testing.expectEqual(0, result.len);
}

test "listInstalledVersionsFromDir returns version directories" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("0.13.0");
    try tmp_dir.dir.makeDir("0.14.0");
    try tmp_dir.dir.makeDir("master");

    const allocator = testing.allocator;
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const result = try listInstalledVersionsFromDir(allocator, tmp_path);
    defer {
        for (result) |v| allocator.free(v);
        allocator.free(result);
    }

    try testing.expectEqual(3, result.len);

    // Sort for deterministic comparison (directory iteration order is not guaranteed)
    std.mem.sort([]const u8, result, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    try testing.expectEqualStrings("0.13.0", result[0]);
    try testing.expectEqualStrings("0.14.0", result[1]);
    try testing.expectEqualStrings("master", result[2]);
}

test "listInstalledVersionsFromDir ignores files" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("0.13.0");
    const file = try tmp_dir.dir.createFile("not-a-version.txt", .{});
    file.close();

    const allocator = testing.allocator;
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const result = try listInstalledVersionsFromDir(allocator, tmp_path);
    defer {
        for (result) |v| allocator.free(v);
        allocator.free(result);
    }

    try testing.expectEqual(1, result.len);
    try testing.expectEqualStrings("0.13.0", result[0]);
}
