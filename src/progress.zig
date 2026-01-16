//! Terminal progress indicators with graceful TTY fallback.
//!
//! Provides phase-based status messages and download progress bars.
//! Automatically degrades to simple line output in non-TTY environments.

const std = @import("std");

/// Minimum bytes between progress updates in non-TTY mode.
const non_tty_update_threshold: u64 = 5 * 1024 * 1024; // 5 MB

/// Progress indicator with TTY-aware output.
pub const Progress = struct {
    is_tty: bool,
    tty_config: std.io.tty.Config,
    file: std.fs.File,
    buf: [4096]u8,
    /// Tracks bytes reported at last non-TTY update (for throttling).
    last_reported: u64,

    pub fn init(file: std.fs.File) Progress {
        const tty_config = std.io.tty.Config.detect(file);
        return .{
            .is_tty = tty_config != .no_color,
            .tty_config = tty_config,
            .file = file,
            .buf = undefined,
            .last_reported = 0,
        };
    }

    /// Print a phase status message (e.g., "Fetching version info...").
    pub fn status(self: *Progress, comptime fmt: []const u8, args: anytype) void {
        var writer = self.file.writer(&self.buf);
        defer writer.interface.flush() catch {};

        writer.interface.print(fmt ++ "\n", args) catch return;
    }

    /// Update download progress (in-place on TTY, throttled lines on non-TTY).
    pub fn download(self: *Progress, downloaded: u64, total: ?u64) void {
        if (self.is_tty) {
            self.renderProgressTty(downloaded, total);
        } else {
            // Throttle updates for non-TTY to avoid log spam
            if (downloaded - self.last_reported >= non_tty_update_threshold or
                (total != null and downloaded >= total.?))
            {
                self.renderProgressNonTty(downloaded, total);
                self.last_reported = downloaded;
            }
        }
    }

    /// Signal download complete (clear progress line on TTY).
    pub fn downloadComplete(self: *Progress) void {
        if (self.is_tty) {
            var writer = self.file.writer(&self.buf);
            defer writer.interface.flush() catch {};
            // Clear line
            writer.interface.writeAll("\r\x1b[K") catch return;
        }
    }

    fn renderProgressTty(self: *Progress, downloaded: u64, total: ?u64) void {
        var writer = self.file.writer(&self.buf);
        defer writer.interface.flush() catch {};

        // Move to start of line and clear
        writer.interface.writeAll("\r\x1b[K") catch return;

        if (total) |t| {
            if (t > 0) {
                const percent: u64 = @min((downloaded * 100) / t, 100);
                var bar: [20]u8 = undefined;
                const filled: usize = @intCast((percent * 20) / 100);
                @memset(bar[0..filled], '#');
                @memset(bar[filled..], '.');

                writer.interface.print("  [{s}] {d}%  {s}/{s}", .{
                    &bar,
                    percent,
                    formatBytes(downloaded),
                    formatBytes(t),
                }) catch return;
            }
        } else {
            // Unknown total size (chunked encoding)
            writer.interface.print("  {s} downloaded", .{formatBytes(downloaded)}) catch return;
        }
    }

    fn renderProgressNonTty(self: *Progress, downloaded: u64, total: ?u64) void {
        var writer = self.file.writer(&self.buf);
        defer writer.interface.flush() catch {};

        if (total) |t| {
            writer.interface.print("  {s}/{s}\n", .{
                formatBytes(downloaded),
                formatBytes(t),
            }) catch return;
        } else {
            writer.interface.print("  {s} downloaded\n", .{formatBytes(downloaded)}) catch return;
        }
    }
};

fn formatBytes(bytes: u64) []const u8 {
    const Static = struct {
        threadlocal var buf: [32]u8 = undefined;
    };

    if (bytes >= 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
        return std.fmt.bufPrint(&Static.buf, "{d:.1} MB", .{mb}) catch "? MB";
    } else if (bytes >= 1024) {
        const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
        return std.fmt.bufPrint(&Static.buf, "{d:.1} KB", .{kb}) catch "? KB";
    } else {
        return std.fmt.bufPrint(&Static.buf, "{d} B", .{bytes}) catch "? B";
    }
}

test "formatBytes formats megabytes" {
    const result = formatBytes(47_500_000);
    try std.testing.expectEqualStrings("45.3 MB", result);
}

test "formatBytes formats kilobytes" {
    const result = formatBytes(512 * 1024);
    try std.testing.expectEqualStrings("512.0 KB", result);
}

test "formatBytes formats bytes" {
    const result = formatBytes(100);
    try std.testing.expectEqualStrings("100 B", result);
}
