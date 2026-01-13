//! End-to-end tests for the list command.

const std = @import("std");
const testing = std.testing;
const runner = @import("runner.zig");

test "e2e: list with no versions installed shows message" {
    const allocator = testing.allocator;

    // Create empty temp directory
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Build env with FZM_DATA_DIR override
    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", tmp_path);
    try env.put("HOME", std.posix.getenv("HOME") orelse "/tmp");

    // Run: fzm list
    var result = try runner.run(allocator, &.{"list"}, &env);
    defer result.deinit(allocator);

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqualStrings("No versions installed.\n", result.stdout);
}

test "e2e: list with versions installed shows them sorted" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create fake version directories
    try tmp_dir.dir.makePath("versions/0.14.0");
    try tmp_dir.dir.makePath("versions/0.13.0");
    try tmp_dir.dir.makePath("versions/master");

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", tmp_path);
    try env.put("HOME", std.posix.getenv("HOME") orelse "/tmp");

    var result = try runner.run(allocator, &.{"list"}, &env);
    defer result.deinit(allocator);

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);

    // Verify sorted output (0.13.0 < 0.14.0 < master)
    // Output includes ANSI colors, so check for version substrings
    try testing.expect(std.mem.indexOf(u8, result.stdout, "0.13.0") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "0.14.0") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "master") != null);

    // Verify order: 0.13.0 appears before 0.14.0, which appears before master
    const pos_013 = std.mem.indexOf(u8, result.stdout, "0.13.0").?;
    const pos_014 = std.mem.indexOf(u8, result.stdout, "0.14.0").?;
    const pos_master = std.mem.indexOf(u8, result.stdout, "master").?;

    try testing.expect(pos_013 < pos_014);
    try testing.expect(pos_014 < pos_master);
}

test "e2e: list alias 'ls' works" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", tmp_path);
    try env.put("HOME", std.posix.getenv("HOME") orelse "/tmp");

    // Run: fzm ls (alias)
    var result = try runner.run(allocator, &.{"ls"}, &env);
    defer result.deinit(allocator);

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqualStrings("No versions installed.\n", result.stdout);
}
