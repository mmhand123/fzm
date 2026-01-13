//! Main CLI struct and entry point.
//!
//! The Cli struct is the top-level builder for command-line applications.
//! It manages commands, handles parsing, and dispatches to actions.
//!
//! ## Example
//! ```zig
//! var app = Cli.init(allocator, .{
//!     .name = "myapp",
//!     .description = "My application",
//!     .version = "1.0.0",
//! });
//! defer app.deinit();
//!
//! _ = app.addCommand(.{
//!     .name = "install",
//!     .description = "Install a package",
//!     .action = installAction,
//! }).addArgument(.{
//!     .name = "package",
//!     .description = "Package to install",
//! });
//!
//! app.run() catch |err| switch (err) {
//!     error.UserError => std.process.exit(1),
//!     else => return err,
//! };
//! ```

const std = @import("std");
const builtin = @import("builtin");

pub const command = @import("command.zig");
pub const flag = @import("flag.zig");
pub const parser = @import("parser.zig");
pub const help = @import("help.zig");

const Command = command.Command;
const CommandOptions = command.CommandOptions;
const Parser = parser.Parser;
const ParseError = parser.ParseError;

/// Parsed context passed to command action handlers.
pub const Context = command.Context;

/// Error returned when the user provides invalid input.
/// The error message has already been printed.
pub const UserError = error.UserError;

/// Options for initializing a Cli.
pub const CliOptions = struct {
    /// Name of the application (used in help text)
    name: []const u8,
    /// Description of the application
    description: []const u8 = "",
    /// Version string (enables -v/--version and `version` command)
    version: ?[]const u8 = null,
};

/// Main CLI application builder.
pub const Cli = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    version: ?[]const u8,

    /// Root command containing all subcommands
    root: Command,

    /// Create a new CLI application.
    pub fn init(allocator: std.mem.Allocator, opts: CliOptions) Cli {
        return .{
            .allocator = allocator,
            .name = opts.name,
            .description = opts.description,
            .version = opts.version,
            .root = Command.init(allocator, .{
                .name = opts.name,
                .description = opts.description,
            }),
        };
    }

    /// Free allocated memory.
    pub fn deinit(self: *Cli) void {
        self.root.deinit();
    }

    /// Add a command to the CLI. Returns the command for further configuration.
    pub fn addCommand(self: *Cli, opts: CommandOptions) *Command {
        return self.root.addSubcommand(opts);
    }

    /// Parse arguments and run the appropriate command.
    /// Call with `std.process.argsAlloc` result, skipping argv[0].
    pub fn run(self: *Cli) anyerror!void {
        const args = try std.process.argsAlloc(self.allocator);
        // Skip argv[0] (program name)
        const cmd_args = if (args.len > 1) args[1..] else args[0..0];
        return self.runWithArgs(cmd_args);
    }

    /// Parse and run with explicit arguments (useful for testing).
    pub fn runWithArgs(self: *Cli, args: []const []const u8) anyerror!void {
        // Handle empty args - show help
        if (args.len == 0) {
            try self.printRootHelp();
            return;
        }

        // Check for version flag/command at root level
        if (self.version) |ver| {
            const first = args[0];
            if (std.mem.eql(u8, first, "-v") or
                std.mem.eql(u8, first, "--version") or
                std.mem.eql(u8, first, "version"))
            {
                std.debug.print("{s} v{s}\n", .{ self.name, ver });
                return;
            }
        }

        // Check for help flag/command at root level (before parsing)
        const first = args[0];
        if (std.mem.eql(u8, first, "-h") or
            std.mem.eql(u8, first, "--help") or
            std.mem.eql(u8, first, "help"))
        {
            // Check if help is for a specific command: `help install` or `fzm help install`
            if (args.len > 1 and std.mem.eql(u8, first, "help")) {
                if (self.root.findSubcommand(args[1])) |subcmd| {
                    try self.printCommandHelp(subcmd);
                    return;
                }
            }
            try self.printRootHelp();
            return;
        }

        // Check if first arg is a known command
        if (self.root.findSubcommand(first)) |_| {
            // Parse starting from root, parser will find the subcommand
            var p = Parser.init(self.allocator, args);
            defer p.deinit();

            const result = p.parse(&self.root) catch {
                return error.UserError;
            };

            // Handle help request for the matched command
            if (result.help_requested) {
                const is_root = (result.command == &self.root);
                try self.printCommandHelpWithRoot(result.command, is_root);
                return;
            }

            // Execute the command action
            if (result.command.action) |action| {
                try action(result.context);
            } else {
                // No action defined - show help for this command
                try self.printCommandHelp(result.command);
            }
        } else {
            // Unknown command
            if (!builtin.is_test) {
                std.debug.print("\x1b[1;31merror:\x1b[0m unknown command: {s}\n\n", .{first});
                try self.printRootHelp();
            }
            return error.UserError;
        }
    }

    /// Print help for the root application.
    fn printRootHelp(self: *Cli) !void {
        var buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);

        try help.printHelp(stream.writer(), &self.root, .{
            .app_name = self.name,
            .description = self.description,
            .version = self.version,
        }, true);

        std.debug.print("{s}", .{stream.getWritten()});
    }

    /// Print help for a specific command.
    fn printCommandHelp(self: *Cli, cmd: *const Command) !void {
        try self.printCommandHelpWithRoot(cmd, false);
    }

    /// Print help for a command, specifying whether it's root level.
    fn printCommandHelpWithRoot(self: *Cli, cmd: *const Command, is_root: bool) !void {
        var buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);

        try help.printHelp(stream.writer(), cmd, .{
            .app_name = self.name,
            .description = self.description,
            .version = self.version,
        }, is_root);

        std.debug.print("{s}", .{stream.getWritten()});
    }
};

// Re-export commonly used types for convenience
pub const ActionFn = command.ActionFn;

test "Cli basic setup" {
    var app = Cli.init(std.testing.allocator, .{
        .name = "testapp",
        .description = "A test application",
        .version = "1.0.0",
    });
    defer app.deinit();

    _ = app.addCommand(.{
        .name = "install",
        .description = "Install something",
    }).addArgument(.{
        .name = "package",
        .required = true,
    });

    _ = app.addCommand(.{
        .name = "list",
        .aliases = &.{"ls"},
        .description = "List items",
    });

    // Verify structure
    try std.testing.expectEqual(2, app.root.subcommands.items.len);
    try std.testing.expectEqualStrings("install", app.root.subcommands.items[0].name);
    try std.testing.expectEqualStrings("list", app.root.subcommands.items[1].name);
}

test {
    _ = @import("flag.zig");
    _ = @import("command.zig");
    _ = @import("parser.zig");
    _ = @import("help.zig");
    _ = @import("tests.zig");
}
