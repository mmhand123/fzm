//! Cross-platform directory resolution following XDG Base Directory spec on Linux
//! and standard conventions on macOS.

const std = @import("std");
const builtin = @import("builtin");

const Env = struct {
    fzm_dir: ?[]const u8,
    xdg_dir: ?[]const u8,
    home: ?[]const u8,
};

/// Returns the base data directory for fzm (where Zig versions are installed).
/// - Override: `$FZM_DATA_DIR` (useful for testing)
/// - Linux: `$XDG_DATA_HOME/fzm` or `~/.local/share/fzm`
/// - macOS: `$XDG_DATA_HOME/fzm` or `~/Library/Application Support/fzm`
pub fn getDataDir(allocator: std.mem.Allocator) error{ NoHomeDirectory, OutOfMemory }![]const u8 {
    return getDataDirInner(allocator, .{
        .fzm_dir = std.posix.getenv("FZM_DATA_DIR"),
        .xdg_dir = std.posix.getenv("XDG_DATA_HOME"),
        .home = std.posix.getenv("HOME"),
    });
}

fn getDataDirInner(allocator: std.mem.Allocator, env: Env) error{ NoHomeDirectory, OutOfMemory }![]const u8 {
    // FZM_DATA_DIR takes precedence for testing/custom configurations
    if (env.fzm_dir) |dir| {
        return allocator.dupe(u8, dir);
    }

    if (env.xdg_dir) |xdg| {
        return std.fs.path.join(allocator, &.{ xdg, "fzm" });
    }

    const home = env.home orelse return error.NoHomeDirectory;

    return switch (builtin.os.tag) {
        .macos => std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "fzm" }),
        else => std.fs.path.join(allocator, &.{ home, ".local", "share", "fzm" }),
    };
}

/// Returns the cache directory for fzm (for downloaded tarballs, etc.).
/// - Override: `$FZM_CACHE_DIR` (useful for testing)
/// - Linux: `$XDG_CACHE_HOME/fzm` or `~/.cache/fzm`
/// - macOS: `$XDG_CACHE_HOME/fzm` or `~/Library/Caches/fzm`
pub fn getCacheDir(allocator: std.mem.Allocator) error{ NoHomeDirectory, OutOfMemory }![]const u8 {
    return getCacheDirInner(allocator, .{
        .fzm_dir = std.posix.getenv("FZM_CACHE_DIR"),
        .xdg_dir = std.posix.getenv("XDG_CACHE_HOME"),
        .home = std.posix.getenv("HOME"),
    });
}

fn getCacheDirInner(allocator: std.mem.Allocator, env: Env) error{ NoHomeDirectory, OutOfMemory }![]const u8 {
    // FZM_CACHE_DIR takes precedence for testing/custom configurations
    if (env.fzm_dir) |dir| {
        return allocator.dupe(u8, dir);
    }

    if (env.xdg_dir) |xdg| {
        return std.fs.path.join(allocator, &.{ xdg, "fzm" });
    }

    const home = env.home orelse return error.NoHomeDirectory;

    return switch (builtin.os.tag) {
        .macos => std.fs.path.join(allocator, &.{ home, "Library", "Caches", "fzm" }),
        else => std.fs.path.join(allocator, &.{ home, ".cache", "fzm" }),
    };
}

/// Returns the config directory for fzm.
/// - Linux: `$XDG_CONFIG_HOME/fzm` or `~/.config/fzm`
/// - macOS: `$XDG_CONFIG_HOME/fzm` or `~/Library/Preferences/fzm`
pub fn getConfigDir(allocator: std.mem.Allocator) error{ NoHomeDirectory, OutOfMemory }![]const u8 {
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fs.path.join(allocator, &.{ xdg, "fzm" });
    }

    const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

    return switch (builtin.os.tag) {
        .macos => std.fs.path.join(allocator, &.{ home, "Library", "Preferences", "fzm" }),
        else => std.fs.path.join(allocator, &.{ home, ".config", "fzm" }),
    };
}

test "FZM_DATA_DIR overrides default data directory" {
    const allocator = std.testing.allocator;

    const result = try getDataDirInner(allocator, .{
        .fzm_dir = "/custom/data/path",
        .xdg_dir = "/xdg/data",
        .home = "/home/user",
    });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/custom/data/path", result);
}

test "FZM_CACHE_DIR overrides default cache directory" {
    const allocator = std.testing.allocator;

    const result = try getCacheDirInner(allocator, .{
        .fzm_dir = "/custom/cache/path",
        .xdg_dir = "/xdg/cache",
        .home = "/home/user",
    });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/custom/cache/path", result);
}

test "XDG_DATA_HOME used when FZM_DATA_DIR not set" {
    const allocator = std.testing.allocator;

    const result = try getDataDirInner(allocator, .{
        .fzm_dir = null,
        .xdg_dir = "/xdg/data",
        .home = "/home/user",
    });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/xdg/data/fzm", result);
}

test "XDG_CACHE_HOME used when FZM_CACHE_DIR not set" {
    const allocator = std.testing.allocator;

    const result = try getCacheDirInner(allocator, .{
        .fzm_dir = null,
        .xdg_dir = "/xdg/cache",
        .home = "/home/user",
    });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/xdg/cache/fzm", result);
}

test "data dir falls back to home directory" {
    const allocator = std.testing.allocator;

    const result = try getDataDirInner(allocator, .{
        .fzm_dir = null,
        .xdg_dir = null,
        .home = "/home/user",
    });
    defer allocator.free(result);

    // Platform-dependent fallback
    const expected = switch (builtin.os.tag) {
        .macos => "/home/user/Library/Application Support/fzm",
        else => "/home/user/.local/share/fzm",
    };
    try std.testing.expectEqualStrings(expected, result);
}

test "cache dir falls back to home directory" {
    const allocator = std.testing.allocator;

    const result = try getCacheDirInner(allocator, .{
        .fzm_dir = null,
        .xdg_dir = null,
        .home = "/home/user",
    });
    defer allocator.free(result);

    // Platform-dependent fallback
    const expected = switch (builtin.os.tag) {
        .macos => "/home/user/Library/Caches/fzm",
        else => "/home/user/.cache/fzm",
    };
    try std.testing.expectEqualStrings(expected, result);
}

test "returns error when no home directory" {
    const allocator = std.testing.allocator;

    const data_result = getDataDirInner(allocator, .{
        .fzm_dir = null,
        .xdg_dir = null,
        .home = null,
    });
    try std.testing.expectError(error.NoHomeDirectory, data_result);

    const cache_result = getCacheDirInner(allocator, .{
        .fzm_dir = null,
        .xdg_dir = null,
        .home = null,
    });
    try std.testing.expectError(error.NoHomeDirectory, cache_result);
}
