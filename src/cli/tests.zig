//! Comprehensive test suite for the CLI module.
//!
//! These tests cover integration scenarios and edge cases
//! beyond the unit tests in individual modules.

const std = @import("std");
const cli = @import("cli.zig");
const command_mod = @import("command.zig");
const parser_mod = @import("parser.zig");
const help_mod = @import("help.zig");

const Command = command_mod.Command;
const Context = command_mod.Context;
const Parser = parser_mod.Parser;

// ============================================================================
// Integration Tests
// ============================================================================

test "full CLI flow with action" {
    const allocator = std.testing.allocator;

    var action_called = false;
    var captured_version: ?[]const u8 = null;

    const TestAction = struct {
        var called: *bool = undefined;
        var version: *?[]const u8 = undefined;

        fn action(ctx: Context) !void {
            called.* = true;
            version.* = ctx.positional("version");
        }
    };
    TestAction.called = &action_called;
    TestAction.version = &captured_version;

    var app = cli.Cli.init(allocator, .{
        .name = "testapp",
        .description = "Test application",
        .version = "1.0.0",
    });
    defer app.deinit();

    _ = app.addCommand(.{
        .name = "install",
        .description = "Install a version",
        .action = TestAction.action,
    }).addArgument(.{
        .name = "version",
        .description = "Version to install",
        .required = true,
    });

    const args = [_][]const u8{ "install", "0.13.0" };
    try app.runWithArgs(&args);

    try std.testing.expect(action_called);
    try std.testing.expectEqualStrings("0.13.0", captured_version.?);
}

test "CLI with flags" {
    const allocator = std.testing.allocator;

    var force_flag = false;
    var output_value: ?[]const u8 = null;

    const TestAction = struct {
        var force: *bool = undefined;
        var output: *?[]const u8 = undefined;

        fn action(ctx: Context) !void {
            force.* = ctx.flag("force");
            output.* = ctx.flagValue("output");
        }
    };
    TestAction.force = &force_flag;
    TestAction.output = &output_value;

    var app = cli.Cli.init(allocator, .{
        .name = "testapp",
        .description = "Test",
        .version = null,
    });
    defer app.deinit();

    _ = app.addCommand(.{
        .name = "build",
        .action = TestAction.action,
    }).addFlag(.{
        .long = "force",
        .short = 'f',
        .description = "Force rebuild",
    }).addFlag(.{
        .long = "output",
        .short = 'o',
        .takes_value = true,
        .description = "Output path",
    });

    const args = [_][]const u8{ "build", "--force", "-o", "dist/" };
    try app.runWithArgs(&args);

    try std.testing.expect(force_flag);
    try std.testing.expectEqualStrings("dist/", output_value.?);
}

test "CLI alias resolution" {
    const allocator = std.testing.allocator;

    var action_called = false;

    const TestAction = struct {
        var called: *bool = undefined;

        fn action(_: Context) !void {
            called.* = true;
        }
    };
    TestAction.called = &action_called;

    var app = cli.Cli.init(allocator, .{
        .name = "testapp",
        .description = "Test",
        .version = null,
    });
    defer app.deinit();

    _ = app.addCommand(.{
        .name = "list",
        .aliases = &.{ "ls", "show" },
        .action = TestAction.action,
    });

    // Test with alias
    const args = [_][]const u8{"ls"};
    try app.runWithArgs(&args);

    try std.testing.expect(action_called);
}

test "CLI subcommand parsing" {
    const allocator = std.testing.allocator;

    var clean_called = false;

    const TestAction = struct {
        var called: *bool = undefined;

        fn action(_: Context) !void {
            called.* = true;
        }
    };
    TestAction.called = &clean_called;

    var app = cli.Cli.init(allocator, .{
        .name = "testapp",
        .description = "Test",
        .version = null,
    });
    defer app.deinit();

    const cache = app.addCommand(.{
        .name = "cache",
        .description = "Manage cache",
    });

    _ = cache.addSubcommand(.{
        .name = "clean",
        .description = "Clean the cache",
        .action = TestAction.action,
    });

    const args = [_][]const u8{ "cache", "clean" };
    try app.runWithArgs(&args);

    try std.testing.expect(clean_called);
}

test "CLI unknown command returns error" {
    const allocator = std.testing.allocator;

    var app = cli.Cli.init(allocator, .{
        .name = "testapp",
        .description = "Test",
        .version = null,
    });
    defer app.deinit();

    _ = app.addCommand(.{
        .name = "install",
    });

    const args = [_][]const u8{"nonexistent"};
    const result = app.runWithArgs(&args);
    try std.testing.expectError(error.UserError, result);
}

// ============================================================================
// Parser Edge Cases
// ============================================================================

test "parser: flags after positional" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addArgument(.{ .name = "file", .required = true });
    _ = cmd.addFlag(.{ .long = "verbose", .short = 'v' });

    // Flag after positional should still work
    const args = [_][]const u8{ "myfile.txt", "--verbose" };
    var p = Parser.init(std.testing.allocator, &args);
    defer p.deinit();

    const result = try p.parse(&cmd);
    try std.testing.expectEqualStrings("myfile.txt", result.context.positional("file").?);
    try std.testing.expect(result.context.flag("verbose"));
}

test "parser: mixed short and long flags" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{ .long = "all", .short = 'a' });
    _ = cmd.addFlag(.{ .long = "verbose", .short = 'v' });
    _ = cmd.addFlag(.{ .long = "quiet" }); // no short form

    const args = [_][]const u8{ "-a", "--verbose", "--quiet" };
    var p = Parser.init(std.testing.allocator, &args);
    defer p.deinit();

    const result = try p.parse(&cmd);
    try std.testing.expect(result.context.flag("all"));
    try std.testing.expect(result.context.flag("verbose"));
    try std.testing.expect(result.context.flag("quiet"));
}

test "parser: value flag with equals in value" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{ .long = "config", .takes_value = true });

    // Value contains = sign
    const args = [_][]const u8{"--config=key=value"};
    var p = Parser.init(std.testing.allocator, &args);
    defer p.deinit();

    const result = try p.parse(&cmd);
    try std.testing.expectEqualStrings("key=value", result.context.flagValue("config").?);
}

test "parser: multiple positionals" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "copy" });
    defer cmd.deinit();
    _ = cmd.addArgument(.{ .name = "source", .required = true });
    _ = cmd.addArgument(.{ .name = "dest", .required = true });
    _ = cmd.addArgument(.{ .name = "extra", .required = false });

    const args = [_][]const u8{ "src.txt", "dst.txt" };
    var p = Parser.init(std.testing.allocator, &args);
    defer p.deinit();

    const result = try p.parse(&cmd);
    try std.testing.expectEqualStrings("src.txt", result.context.positional("source").?);
    try std.testing.expectEqualStrings("dst.txt", result.context.positional("dest").?);
    try std.testing.expect(result.context.positional("extra") == null);
}

test "parser: default flag value" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{
        .long = "format",
        .takes_value = true,
        .default = "json",
    });

    const args = [_][]const u8{};
    var p = Parser.init(std.testing.allocator, &args);
    defer p.deinit();

    const result = try p.parse(&cmd);
    try std.testing.expectEqualStrings("json", result.context.flagValue("format").?);
}

test "parser: default value overridden" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{
        .long = "format",
        .takes_value = true,
        .default = "json",
    });

    const args = [_][]const u8{ "--format", "yaml" };
    var p = Parser.init(std.testing.allocator, &args);
    defer p.deinit();

    const result = try p.parse(&cmd);
    try std.testing.expectEqualStrings("yaml", result.context.flagValue("format").?);
}

// ============================================================================
// Help Generation Tests
// ============================================================================

test "help: shows aliases" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "root",
    });
    defer cmd.deinit();

    _ = cmd.addSubcommand(.{
        .name = "list",
        .aliases = &.{ "ls", "l" },
        .description = "List items",
    });

    var output: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try help_mod.printHelp(stream.writer(), &cmd, .{
        .app_name = "myapp",
        .description = "Test app",
        .version = null,
    }, true);

    const result = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "list, ls, l") != null);
}

test "help: shows positional arguments" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "install",
        .description = "Install a package",
    });
    defer cmd.deinit();

    _ = cmd.addArgument(.{
        .name = "package",
        .description = "Package to install",
        .required = true,
    });
    _ = cmd.addArgument(.{
        .name = "version",
        .description = "Specific version",
        .required = false,
    });

    var output: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try help_mod.printHelp(stream.writer(), &cmd, .{
        .app_name = "myapp",
        .description = "",
        .version = null,
    }, false);

    const result = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "Arguments:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "package") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "version") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "(optional)") != null);
}

test "help: usage line with positionals" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "install",
    });
    defer cmd.deinit();

    _ = cmd.addArgument(.{ .name = "package", .required = true });
    _ = cmd.addArgument(.{ .name = "version", .required = false });

    var output: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try help_mod.printHelp(stream.writer(), &cmd, .{
        .app_name = "myapp",
        .description = "",
        .version = null,
    }, false);

    const result = stream.getWritten();
    // Usage should show <package> [version]
    try std.testing.expect(std.mem.indexOf(u8, result, "<package>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[version]") != null);
}
