const std = @import("std");
const dirs = @import("dirs.zig");

pub fn install(allocator: std.mem.Allocator, version: []const u8) !void {
    const data_dir = try dirs.getDataDir(allocator);

    std.debug.print("installing {s}\n", .{version});
    std.debug.print("exe_dir: {s}\n", .{data_dir});
}
