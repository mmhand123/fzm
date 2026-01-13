//! Help text generation for the CLI.
//!
//! Generates formatted help output for commands at any level,
//! including usage lines, command lists, flag descriptions, and arguments.

const std = @import("std");
const command_mod = @import("command.zig");
const flag_mod = @import("flag.zig");

const Command = command_mod.Command;
const Flag = flag_mod.Flag;
const Argument = flag_mod.Argument;

/// Configuration for help generation.
pub const HelpConfig = struct {
    /// Name of the CLI application
    app_name: []const u8,
    /// Application description
    description: []const u8,
    /// Application version (null = no version)
    version: ?[]const u8,
};

/// Generate and print help for a command.
pub fn printHelp(
    writer: anytype,
    cmd: *const Command,
    config: HelpConfig,
    is_root: bool,
) !void {
    // Header: app name + version + description (for root) or command description
    if (is_root) {
        if (config.version) |ver| {
            try writer.print("{s} v{s}", .{ config.app_name, ver });
        } else {
            try writer.print("{s}", .{config.app_name});
        }
        if (config.description.len > 0) {
            try writer.print(" - {s}", .{config.description});
        }
        try writer.print("\n\n", .{});
    } else {
        // Subcommand help
        if (cmd.description.len > 0) {
            try writer.print("{s}\n\n", .{cmd.description});
        }
    }

    // Usage line
    try printUsage(writer, cmd, config.app_name, is_root);

    // Arguments section
    if (cmd.args.items.len > 0) {
        try writer.print("\nArguments:\n", .{});
        try printArguments(writer, cmd);
    }

    // Commands section (subcommands)
    if (cmd.subcommands.items.len > 0) {
        try writer.print("\nCommands:\n", .{});
        try printCommands(writer, cmd);
    }

    // Flags section
    try writer.print("\nOptions:\n", .{});
    try printFlags(writer, cmd, is_root, config.version != null);
}

/// Print the usage line.
fn printUsage(
    writer: anytype,
    cmd: *const Command,
    app_name: []const u8,
    is_root: bool,
) !void {
    try writer.print("Usage: ", .{});

    if (is_root) {
        try writer.print("{s}", .{app_name});
    } else {
        // Build full command path
        var path_buf: [256]u8 = undefined;
        const path = cmd.getFullPath(app_name, &path_buf);
        try writer.print("{s}", .{path});
    }

    // Add subcommand placeholder if has subcommands
    if (cmd.subcommands.items.len > 0) {
        try writer.print(" <command>", .{});
    }

    // Add arguments
    for (cmd.args.items) |pos| {
        var buf: [64]u8 = undefined;
        const formatted = pos.formatUsage(&buf);
        try writer.print(" {s}", .{formatted});
    }

    // Add options placeholder if has flags
    if (cmd.flags.items.len > 0) {
        try writer.print(" [options]", .{});
    } else {
        // Always show [options] for built-in -h
        try writer.print(" [options]", .{});
    }

    try writer.print("\n", .{});
}

/// Print the list of subcommands.
fn printCommands(writer: anytype, cmd: *const Command) !void {
    // Find max command name length for alignment
    var max_len: usize = 0;
    for (cmd.subcommands.items) |subcmd| {
        var len = subcmd.name.len;
        // Add alias lengths
        if (subcmd.aliases.len > 0) {
            for (subcmd.aliases) |alias| {
                len += 2 + alias.len; // ", " + alias
            }
        }
        if (len > max_len) max_len = len;
    }

    // Ensure minimum width
    if (max_len < 12) max_len = 12;

    for (cmd.subcommands.items) |subcmd| {
        // Build name with aliases
        var name_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&name_buf);
        const name_writer = stream.writer();

        name_writer.print("{s}", .{subcmd.name}) catch continue;
        for (subcmd.aliases) |alias| {
            name_writer.print(", {s}", .{alias}) catch continue;
        }
        const name_str = stream.getWritten();

        // Print with padding
        try writer.print("  {s}", .{name_str});
        const padding = max_len - name_str.len + 2;
        try writer.writeByteNTimes(' ', padding);
        try writer.print("{s}\n", .{subcmd.description});
    }
}

/// Print the list of flags.
fn printFlags(
    writer: anytype,
    cmd: *const Command,
    is_root: bool,
    has_version: bool,
) !void {
    // Collect all flags to print (command flags + built-ins)
    var all_flags: [32]Flag = undefined;
    var flag_count: usize = 0;

    // Add command-specific flags
    for (cmd.flags.items) |f| {
        if (flag_count < all_flags.len) {
            all_flags[flag_count] = f;
            flag_count += 1;
        }
    }

    // Add built-in help flag
    if (flag_count < all_flags.len) {
        all_flags[flag_count] = .{
            .long = "help",
            .short = 'h',
            .description = "Show this help",
        };
        flag_count += 1;
    }

    // Add version flag (only at root level if version is set)
    if (is_root and has_version and flag_count < all_flags.len) {
        all_flags[flag_count] = .{
            .long = "version",
            .short = 'v',
            .description = "Print version",
        };
        flag_count += 1;
    }

    // Find max flag name length for alignment
    var max_len: usize = 0;
    for (all_flags[0..flag_count]) |f| {
        var buf: [64]u8 = undefined;
        const formatted = f.formatNames(&buf);
        if (formatted.len > max_len) max_len = formatted.len;
    }

    // Ensure minimum width
    if (max_len < 16) max_len = 16;

    // Print each flag
    for (all_flags[0..flag_count]) |f| {
        var buf: [64]u8 = undefined;
        const formatted = f.formatNames(&buf);

        try writer.print("  {s}", .{formatted});
        const padding = max_len - formatted.len + 2;
        try writer.writeByteNTimes(' ', padding);
        try writer.print("{s}\n", .{f.description});
    }
}

/// Print the list of arguments.
fn printArguments(writer: anytype, cmd: *const Command) !void {
    // Find max name length for alignment
    var max_len: usize = 0;
    for (cmd.args.items) |arg| {
        if (arg.name.len > max_len) max_len = arg.name.len;
    }

    // Ensure minimum width
    if (max_len < 12) max_len = 12;

    for (cmd.args.items) |pos| {
        try writer.print("  {s}", .{pos.name});
        const padding = max_len - pos.name.len + 2;
        try writer.writeByteNTimes(' ', padding);
        try writer.print("{s}", .{pos.description});
        if (!pos.required) {
            try writer.print(" (optional)", .{});
        }
        try writer.print("\n", .{});
    }
}

test "printHelp root command" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "root",
        .description = "Root command",
    });
    defer cmd.deinit();

    _ = cmd.addSubcommand(.{ .name = "install", .description = "Install something" });
    _ = cmd.addSubcommand(.{ .name = "list", .aliases = &.{"ls"}, .description = "List items" });

    var output: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try printHelp(stream.writer(), &cmd, .{
        .app_name = "myapp",
        .description = "A test application",
        .version = "1.0.0",
    }, true);

    const result = stream.getWritten();

    // Check header
    try std.testing.expect(std.mem.indexOf(u8, result, "myapp v1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "A test application") != null);

    // Check commands section
    try std.testing.expect(std.mem.indexOf(u8, result, "Commands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "install") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "list, ls") != null);

    // Check built-in flags
    try std.testing.expect(std.mem.indexOf(u8, result, "-h, --help") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "-v, --version") != null);
}

test "printHelp subcommand" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "install",
        .description = "Install a package",
    });
    defer cmd.deinit();

    _ = cmd.addArgument(.{ .name = "package", .description = "Package name", .required = true });
    _ = cmd.addFlag(.{ .long = "force", .short = 'f', .description = "Force installation" });

    var output: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try printHelp(stream.writer(), &cmd, .{
        .app_name = "myapp",
        .description = "",
        .version = null,
    }, false);

    const result = stream.getWritten();

    // Check description
    try std.testing.expect(std.mem.indexOf(u8, result, "Install a package") != null);

    // Check arguments section
    try std.testing.expect(std.mem.indexOf(u8, result, "Arguments:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "package") != null);

    // Check flags section
    try std.testing.expect(std.mem.indexOf(u8, result, "-f, --force") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "-h, --help") != null);

    // Version should NOT appear (not root)
    try std.testing.expect(std.mem.indexOf(u8, result, "--version") == null);
}
