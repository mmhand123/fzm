//! ZON parsing utilities for build.zig.zon files.
//!
//! Provides functionality to parse build.zig.zon and extract version requirements.

const std = @import("std");

const log = std.log.scoped(.zon);

/// Represents the fields we care about from build.zig.zon.
/// Other fields are ignored via parse options.
pub const BuildZon = struct {
    minimum_zig_version: ?[]const u8 = null,
};

/// Result of parsing build.zig.zon, owns its memory.
pub const ParseResult = struct {
    data: BuildZon,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        std.zon.parse.free(self.allocator, self.data);
    }
};

pub const ParseError = error{
    ParseZon,
    OutOfMemory,
};

/// Parses a build.zig.zon source string and extracts relevant fields.
/// The source must be zero-terminated.
/// Caller must call deinit() on the returned ParseResult.
pub fn parseBuildZon(allocator: std.mem.Allocator, source: [:0]const u8) ParseError!ParseResult {
    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(allocator);

    const data = std.zon.parse.fromSlice(BuildZon, allocator, source, &diag, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        log.err("failed to parse build.zig.zon: {any}", .{diag});
        return err;
    };

    return .{
        .data = data,
        .allocator = allocator,
    };
}

/// Reads and parses build.zig.zon from the given directory.
/// Returns null if no build.zig.zon exists.
pub fn readBuildZon(allocator: std.mem.Allocator, dir: std.fs.Dir) !?ParseResult {
    const file = dir.openFile("build.zig.zon", .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    // Read with sentinel for ZON parser
    const source = try file.readToEndAllocOptions(allocator, 1024 * 1024, null, .@"1", 0);
    defer allocator.free(source);

    return try parseBuildZon(allocator, source);
}

// Tests

const testing = std.testing;

test "parseBuildZon extracts minimum_zig_version" {
    const source =
        \\.{
        \\    .name = .test_project,
        \\    .version = "1.0.0",
        \\    .minimum_zig_version = "0.15.2",
        \\    .dependencies = .{},
        \\    .paths = .{},
        \\}
    ;
    // Add null terminator
    const terminated = source ++ [_]u8{0};
    const slice: [:0]const u8 = terminated[0 .. terminated.len - 1 :0];

    var result = try parseBuildZon(testing.allocator, slice);
    defer result.deinit();

    try testing.expect(result.data.minimum_zig_version != null);
    try testing.expectEqualStrings("0.15.2", result.data.minimum_zig_version.?);
}

test "parseBuildZon handles missing minimum_zig_version" {
    const source =
        \\.{
        \\    .name = .test_project,
        \\    .version = "1.0.0",
        \\    .dependencies = .{},
        \\    .paths = .{},
        \\}
    ;
    const terminated = source ++ [_]u8{0};
    const slice: [:0]const u8 = terminated[0 .. terminated.len - 1 :0];

    var result = try parseBuildZon(testing.allocator, slice);
    defer result.deinit();

    try testing.expect(result.data.minimum_zig_version == null);
}

test "readBuildZon returns null for missing file" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const result = try readBuildZon(testing.allocator, tmp_dir.dir);
    try testing.expect(result == null);
}

test "readBuildZon parses existing file" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const content =
        \\.{
        \\    .name = .test_project,
        \\    .version = "1.0.0",
        \\    .minimum_zig_version = "0.14.0",
        \\    .dependencies = .{},
        \\    .paths = .{},
        \\}
    ;
    const file = try tmp_dir.dir.createFile("build.zig.zon", .{});
    try file.writeAll(content);
    file.close();

    var result = (try readBuildZon(testing.allocator, tmp_dir.dir)).?;
    defer result.deinit();

    try testing.expect(result.data.minimum_zig_version != null);
    try testing.expectEqualStrings("0.14.0", result.data.minimum_zig_version.?);
}
