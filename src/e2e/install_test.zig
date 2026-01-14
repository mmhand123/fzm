const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const runner = @import("runner.zig");
const MockServer = @import("mock_server.zig");
const platform = @import("platform");

test "e2e: install happy path" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const data_dir = try std.fs.path.join(allocator, &.{ tmp_path, "data" });
    defer allocator.free(data_dir);
    const cache_dir = try std.fs.path.join(allocator, &.{ tmp_path, "cache" });
    defer allocator.free(cache_dir);

    var server = try MockServer.init(allocator);
    defer server.deinit();

    const base_url = try server.getBaseUrl(allocator);
    defer allocator.free(base_url);

    const tarball_url = try std.fmt.allocPrint(allocator, "{s}/zig-test.tar.xz", .{base_url});
    defer allocator.free(tarball_url);

    var index_buf: [2048]u8 = undefined;
    const version_index = try std.fmt.bufPrint(&index_buf,
        \\{{"0.13.0":{{"version":"0.13.0","{s}":{{"tarball":"{s}","shasum":"abc","size":"228"}}}}}}
    , .{ platform.platform_key, tarball_url });

    const tarball_bytes = @embedFile("fixtures/test.tar.xz");
    try server.queueResponse("200 OK", version_index);
    try server.queueResponse("200 OK", tarball_bytes);

    const server_thread = try std.Thread.spawn(.{}, MockServer.serveAll, .{&server});

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", data_dir);
    try env.put("FZM_CACHE_DIR", cache_dir);
    try env.put("FZM_CDN_URL", base_url);

    var result = try runner.run(allocator, &.{ "install", "0.13.0" }, &env);
    defer result.deinit(allocator);

    server_thread.join();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);

    const version_file_path = try std.fs.path.join(allocator, &.{
        data_dir, "versions", "0.13.0", ".fzm-version",
    });
    defer allocator.free(version_file_path);

    const version_content = try std.fs.cwd().readFileAlloc(allocator, version_file_path, 1024);
    defer allocator.free(version_content);

    try testing.expectEqualStrings("0.13.0", version_content);

    const zig_path = try std.fs.path.join(allocator, &.{
        data_dir, "versions", "0.13.0", "zig",
    });
    defer allocator.free(zig_path);

    const zig_content = try std.fs.cwd().readFileAlloc(allocator, zig_path, 1024);
    defer allocator.free(zig_content);

    try testing.expectEqualStrings("test-zig-binary\n", zig_content);
}

test "e2e: install invalid version format shows error" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", tmp_path);
    try env.put("FZM_CACHE_DIR", tmp_path);

    var result = try runner.run(allocator, &.{ "install", "bad-version" }, &env);
    defer result.deinit(allocator);

    try testing.expect(std.mem.indexOf(u8, result.stderr, "invalid version") != null);
}

test "e2e: install already installed shows warning" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const data_dir = try std.fs.path.join(allocator, &.{ tmp_path, "data" });
    defer allocator.free(data_dir);
    const cache_dir = try std.fs.path.join(allocator, &.{ tmp_path, "cache" });
    defer allocator.free(cache_dir);

    try std.fs.makeDirAbsolute(data_dir);
    try std.fs.makeDirAbsolute(cache_dir);

    try tmp_dir.dir.makePath("data/versions/0.13.0");
    try tmp_dir.dir.writeFile(.{
        .sub_path = "data/versions/0.13.0/.fzm-version",
        .data = "0.13.0",
    });

    var server = try MockServer.init(allocator);
    defer server.deinit();

    const base_url = try server.getBaseUrl(allocator);
    defer allocator.free(base_url);

    const tarball_url = try std.fmt.allocPrint(allocator, "{s}/zig-test.tar.xz", .{base_url});
    defer allocator.free(tarball_url);

    var index_buf: [2048]u8 = undefined;
    const version_index = try std.fmt.bufPrint(&index_buf,
        \\{{"0.13.0":{{"version":"0.13.0","{s}":{{"tarball":"{s}","shasum":"abc","size":"228"}}}}}}
    , .{ platform.platform_key, tarball_url });

    try server.queueResponse("200 OK", version_index);

    const server_thread = try std.Thread.spawn(.{}, MockServer.serveAll, .{&server});

    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("FZM_DATA_DIR", data_dir);
    try env.put("FZM_CACHE_DIR", cache_dir);
    try env.put("FZM_CDN_URL", base_url);

    var result = try runner.run(allocator, &.{ "install", "0.13.0" }, &env);
    defer result.deinit(allocator);

    server_thread.join();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);

    try testing.expect(std.mem.indexOf(u8, result.stderr, "already installed") != null);
}
