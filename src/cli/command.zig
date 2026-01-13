//! Command definition and builder for the CLI.
//!
//! Commands represent actions the user can invoke (e.g., `install`, `list`).
//! Each command can have flags, positional arguments, and subcommands.

const std = @import("std");
const flag_mod = @import("flag.zig");

const Flag = flag_mod.Flag;
const FlagOptions = flag_mod.FlagOptions;
const Positional = flag_mod.Positional;
const PositionalOptions = flag_mod.PositionalOptions;

/// Parsed result passed to command actions.
pub const Context = struct {
    allocator: std.mem.Allocator,
    flag_values: std.StringHashMapUnmanaged([]const u8),
    flag_present: std.StringHashMapUnmanaged(void),
    positional_values: std.StringHashMapUnmanaged([]const u8),
    raw_positionals: []const []const u8,

    /// Check if a boolean flag is present.
    pub fn flag(self: Context, name: []const u8) bool {
        return self.flag_present.contains(name);
    }

    /// Get the value of a flag that takes a value.
    pub fn flagValue(self: Context, name: []const u8) ?[]const u8 {
        return self.flag_values.get(name);
    }

    /// Get a positional argument by name.
    pub fn positional(self: Context, name: []const u8) ?[]const u8 {
        return self.positional_values.get(name);
    }

    /// Get all positional arguments in order.
    pub fn positionals(self: Context) []const []const u8 {
        return self.raw_positionals;
    }
};

/// Function signature for command actions.
pub const ActionFn = *const fn (Context) anyerror!void;

/// A CLI command with optional flags, positionals, and subcommands.
pub const Command = struct {
    allocator: std.mem.Allocator,

    /// Primary name of the command (e.g., "install")
    name: []const u8,

    /// Alternative names (e.g., ["ls"] for "list")
    aliases: []const []const u8 = &.{},

    /// Human-readable description for help text
    description: []const u8 = "",

    /// Function to execute when this command is invoked
    action: ?ActionFn = null,

    /// Flags specific to this command
    flags: std.ArrayListUnmanaged(Flag) = .empty,

    /// Positional arguments for this command
    positional_args: std.ArrayListUnmanaged(Positional) = .empty,

    /// Subcommands nested under this command
    subcommands: std.ArrayListUnmanaged(*Command) = .empty,

    /// Parent command (null for top-level commands)
    parent: ?*Command = null,

    /// Create a new command with the given options.
    pub fn init(allocator: std.mem.Allocator, opts: CommandOptions) Command {
        return .{
            .allocator = allocator,
            .name = opts.name,
            .aliases = opts.aliases,
            .description = opts.description,
            .action = opts.action,
        };
    }

    /// Free allocated memory.
    pub fn deinit(self: *Command) void {
        // Recursively deinit subcommands
        for (self.subcommands.items) |subcmd| {
            subcmd.deinit();
            self.allocator.destroy(subcmd);
        }
        self.subcommands.deinit(self.allocator);
        self.flags.deinit(self.allocator);
        self.positional_args.deinit(self.allocator);
    }

    /// Add a flag to this command. Returns self for chaining.
    pub fn addFlag(self: *Command, opts: FlagOptions) *Command {
        self.flags.append(self.allocator, .{
            .long = opts.long,
            .short = opts.short,
            .description = opts.description,
            .takes_value = opts.takes_value,
            .default = opts.default,
        }) catch @panic("failed to add flag");
        return self;
    }

    /// Add a positional argument. Returns self for chaining.
    pub fn addPositional(self: *Command, opts: PositionalOptions) *Command {
        self.positional_args.append(self.allocator, .{
            .name = opts.name,
            .description = opts.description,
            .required = opts.required,
        }) catch @panic("failed to add positional");
        return self;
    }

    /// Add a subcommand. Returns the new subcommand for further configuration.
    pub fn addSubcommand(self: *Command, opts: CommandOptions) *Command {
        const subcmd = self.allocator.create(Command) catch @panic("failed to create subcommand");
        subcmd.* = Command.init(self.allocator, opts);
        subcmd.parent = self;
        self.subcommands.append(self.allocator, subcmd) catch @panic("failed to add subcommand");
        return subcmd;
    }

    /// Find a subcommand by name or alias.
    pub fn findSubcommand(self: *const Command, name: []const u8) ?*Command {
        for (self.subcommands.items) |subcmd| {
            if (std.mem.eql(u8, subcmd.name, name)) {
                return subcmd;
            }
            for (subcmd.aliases) |alias| {
                if (std.mem.eql(u8, alias, name)) {
                    return subcmd;
                }
            }
        }
        return null;
    }

    /// Find a flag by long name or short character.
    pub fn findFlag(self: *const Command, name: []const u8) ?Flag {
        // Check if it's a short flag (single character)
        if (name.len == 1) {
            for (self.flags.items) |f| {
                if (f.short) |short| {
                    if (short == name[0]) {
                        return f;
                    }
                }
            }
        }

        // Check long names
        for (self.flags.items) |f| {
            if (std.mem.eql(u8, f.long, name)) {
                return f;
            }
        }

        return null;
    }

    /// Find a flag by short character only.
    pub fn findFlagByShort(self: *const Command, short: u8) ?Flag {
        for (self.flags.items) |f| {
            if (f.short) |s| {
                if (s == short) {
                    return f;
                }
            }
        }
        return null;
    }

    /// Get the full command path (e.g., "fzm cache clean")
    pub fn getFullPath(self: *const Command, root_name: []const u8, buf: []u8) []const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        // Build path by walking up parent chain (stop before root, which has no parent)
        var path_parts: [16][]const u8 = undefined;
        var depth: usize = 0;

        var current: ?*const Command = self;
        while (current) |cmd| : (current = cmd.parent) {
            // Stop before the root command (root has no parent)
            if (cmd.parent == null) break;
            if (depth < path_parts.len) {
                path_parts[depth] = cmd.name;
                depth += 1;
            }
        }

        // Write root name first
        writer.print("{s}", .{root_name}) catch return "";

        // Write path parts in reverse (root to leaf)
        var i: usize = depth;
        while (i > 0) {
            i -= 1;
            writer.print(" {s}", .{path_parts[i]}) catch return "";
        }

        return stream.getWritten();
    }

    /// Check if this command matches the given name or any alias.
    pub fn matches(self: *const Command, name: []const u8) bool {
        if (std.mem.eql(u8, self.name, name)) {
            return true;
        }
        for (self.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) {
                return true;
            }
        }
        return false;
    }
};

/// Options for creating a Command.
pub const CommandOptions = struct {
    name: []const u8,
    aliases: []const []const u8 = &.{},
    description: []const u8 = "",
    action: ?ActionFn = null,
};

test "Command.addFlag chaining" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "test",
    });
    defer cmd.deinit();

    _ = cmd
        .addFlag(.{ .long = "verbose", .short = 'v' })
        .addFlag(.{ .long = "force", .short = 'f' });

    try std.testing.expectEqual(2, cmd.flags.items.len);
    try std.testing.expectEqualStrings("verbose", cmd.flags.items[0].long);
    try std.testing.expectEqualStrings("force", cmd.flags.items[1].long);
}

test "Command.addPositional chaining" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "install",
    });
    defer cmd.deinit();

    _ = cmd
        .addPositional(.{ .name = "version", .required = true })
        .addPositional(.{ .name = "target", .required = false });

    try std.testing.expectEqual(2, cmd.positional_args.items.len);
    try std.testing.expectEqualStrings("version", cmd.positional_args.items[0].name);
    try std.testing.expect(cmd.positional_args.items[0].required);
    try std.testing.expect(!cmd.positional_args.items[1].required);
}

test "Command.findSubcommand" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "cache",
    });
    defer cmd.deinit();

    _ = cmd.addSubcommand(.{ .name = "clean" });
    _ = cmd.addSubcommand(.{ .name = "show", .aliases = &.{"info"} });

    try std.testing.expect(cmd.findSubcommand("clean") != null);
    try std.testing.expect(cmd.findSubcommand("show") != null);
    try std.testing.expect(cmd.findSubcommand("info") != null); // alias
    try std.testing.expect(cmd.findSubcommand("nonexistent") == null);
}

test "Command.findFlag" {
    var cmd = Command.init(std.testing.allocator, .{
        .name = "test",
    });
    defer cmd.deinit();

    _ = cmd.addFlag(.{ .long = "verbose", .short = 'v' });
    _ = cmd.addFlag(.{ .long = "force" }); // no short form

    // Find by long name
    const verbose = cmd.findFlag("verbose");
    try std.testing.expect(verbose != null);
    try std.testing.expectEqual('v', verbose.?.short.?);

    // Find by short name
    const v = cmd.findFlag("v");
    try std.testing.expect(v != null);
    try std.testing.expectEqualStrings("verbose", v.?.long);

    // Find flag without short form
    const force = cmd.findFlag("force");
    try std.testing.expect(force != null);
    try std.testing.expect(force.?.short == null);

    // Non-existent
    try std.testing.expect(cmd.findFlag("nonexistent") == null);
}

test "Command.matches" {
    const cmd = Command.init(std.testing.allocator, .{
        .name = "list",
        .aliases = &.{ "ls", "show" },
    });

    try std.testing.expect(cmd.matches("list"));
    try std.testing.expect(cmd.matches("ls"));
    try std.testing.expect(cmd.matches("show"));
    try std.testing.expect(!cmd.matches("install"));
}
