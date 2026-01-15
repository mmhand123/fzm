//! List command for displaying installed Zig versions.

const std = @import("std");
const versions = @import("../versions.zig");

/// Soft teal color for output.
const teal = "\x1b[38;2;94;186;187m";
const reset = "\x1b[0m";

pub fn list(allocator: std.mem.Allocator) !void {
    const installed = try versions.listInstalledVersions(allocator);
    defer {
        for (installed) |v| allocator.free(v);
        allocator.free(installed);
    }

    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    defer writer.interface.flush() catch {};

    if (installed.len == 0) {
        try writer.interface.writeAll("No versions installed.\n");
        return;
    }

    // Sort versions for consistent output
    std.mem.sort([]const u8, installed, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    for (installed) |version| {
        try writer.interface.print("{s}{s}{s}\n\n", .{ teal, version, reset });
    }
}
