const std = @import("std");
const testing = std.testing;
const runner = @import("runner.zig");

test "e2e: uninstall happy path" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const data_dir = try std.fs.path.join(allocator, &.{ tmp_path, "data" });
    defer allocator.free(data_dir);

    try tmp_dir.dir.makePath("data/versions/0.13.0");
    try tmp_dir.dir.writeFile(.{
        .sub_path = "data/versions/0.13.0/.fzm-version",
        .data = "0.13.0",
    });

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", data_dir);

    var result = try runner.run(allocator, &.{ "uninstall", "0.13.0" }, &env);
    defer result.deinit(allocator);

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);

    const version_dir_path = try std.fs.path.join(allocator, &.{
        data_dir, "versions", "0.13.0",
    });
    defer allocator.free(version_dir_path);

    const dir_exists = blk: {
        std.fs.accessAbsolute(version_dir_path, .{}) catch break :blk false;
        break :blk true;
    };
    try testing.expect(!dir_exists);
}

test "e2e: uninstall non-existent version shows error" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const data_dir = try std.fs.path.join(allocator, &.{ tmp_path, "data" });
    defer allocator.free(data_dir);

    try std.fs.makeDirAbsolute(data_dir);

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", data_dir);

    var result = try runner.run(allocator, &.{ "uninstall", "0.13.0" }, &env);
    defer result.deinit(allocator);

    try testing.expect(std.mem.indexOf(u8, result.stderr, "is not installed") != null);
}

test "e2e: uninstall in-use version clears state" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const data_dir = try std.fs.path.join(allocator, &.{ tmp_path, "data" });
    defer allocator.free(data_dir);

    try tmp_dir.dir.makePath("data/versions/0.13.0");
    try tmp_dir.dir.writeFile(.{
        .sub_path = "data/versions/0.13.0/.fzm-version",
        .data = "0.13.0",
    });

    try tmp_dir.dir.writeFile(.{
        .sub_path = "data/state.json",
        .data = "{\"in_use\":\"0.13.0\"}",
    });

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", data_dir);

    var result = try runner.run(allocator, &.{ "uninstall", "0.13.0" }, &env);
    defer result.deinit(allocator);

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);

    const version_dir_path = try std.fs.path.join(allocator, &.{
        data_dir, "versions", "0.13.0",
    });
    defer allocator.free(version_dir_path);

    const dir_exists = blk: {
        std.fs.accessAbsolute(version_dir_path, .{}) catch break :blk false;
        break :blk true;
    };
    try testing.expect(!dir_exists);

    const state_path = try std.fs.path.join(allocator, &.{ data_dir, "state.json" });
    defer allocator.free(state_path);

    const state_content = try std.fs.cwd().readFileAlloc(allocator, state_path, 4096);
    defer allocator.free(state_content);

    try testing.expect(std.mem.indexOf(u8, state_content, "\"in_use\":\"0.13.0\"") == null);
}
