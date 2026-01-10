//! Cross-platform directory resolution following XDG Base Directory spec on Linux
//! and standard conventions on macOS.

const std = @import("std");
const builtin = @import("builtin");

/// Returns the base data directory for fzm (where Zig versions are installed).
/// - Linux: `$XDG_DATA_HOME/fzm` or `~/.local/share/fzm`
/// - macOS: `$XDG_DATA_HOME/fzm` or `~/Library/Application Support/fzm`
pub fn getDataDir(allocator: std.mem.Allocator) error{ NoHomeDirectory, OutOfMemory }![]const u8 {
    if (std.posix.getenv("XDG_DATA_HOME")) |xdg| {
        return std.fs.path.join(allocator, &.{ xdg, "fzm" });
    }

    const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

    return switch (builtin.os.tag) {
        .macos => std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "fzm" }),
        else => std.fs.path.join(allocator, &.{ home, ".local", "share", "fzm" }),
    };
}

/// Returns the cache directory for fzm (for downloaded tarballs, etc.).
/// - Linux: `$XDG_CACHE_HOME/fzm` or `~/.cache/fzm`
/// - macOS: `$XDG_CACHE_HOME/fzm` or `~/Library/Caches/fzm`
pub fn getCacheDir(allocator: std.mem.Allocator) error{ NoHomeDirectory, OutOfMemory }![]const u8 {
    if (std.posix.getenv("XDG_CACHE_HOME")) |xdg| {
        return std.fs.path.join(allocator, &.{ xdg, "fzm" });
    }

    const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

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
