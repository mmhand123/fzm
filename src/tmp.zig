const std = @import("std");

pub fn makeTempDir(allocator: std.mem.Allocator) !struct { dir: std.fs.Dir, path: []const u8 } {
    const tmp_dir_path = std.posix.getenv("TMPDIR") orelse
        std.posix.getenv("TMP") orelse
        std.posix.getenv("TEMP") orelse
        "/tmp";

    const timestamp: u64 = @intCast(std.time.timestamp());
    const pid = std.c.getpid();
    var buf: [64]u8 = undefined;
    const sub_path = std.fmt.bufPrint(&buf, "myapp-{d}-{d}", .{ timestamp, pid }) catch unreachable;

    var tmp_dir = try std.fs.openDirAbsolute(tmp_dir_path, .{});
    defer tmp_dir.close();

    try tmp_dir.makeDir(&sub_path);
    const dir = try tmp_dir.openDir(&sub_path, .{});

    const full_path = try std.fs.path.join(allocator, &.{ tmp_dir_path, &sub_path });

    return .{ .dir = dir, .path = full_path };
}
