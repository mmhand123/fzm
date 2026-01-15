//! Argument parsing logic for the CLI.
//!
//! Handles parsing of command-line arguments including:
//! - Long flags: --verbose, --output=value, --output value
//! - Short flags: -v, -o value, -o=value
//! - Combined short flags: -abc (expands to -a -b -c)
//! - Arguments (non-flag parameters)
//! - The -- separator to stop flag parsing

const std = @import("std");
const command_mod = @import("command.zig");
const flag_mod = @import("flag.zig");

const Command = command_mod.Command;
const Context = command_mod.Context;
const Flag = flag_mod.Flag;

pub const ParseError = error{
    UnknownFlag,
    MissingFlagValue,
    MissingRequiredArg,
    UnknownCommand,
    OutOfMemory,
};

pub const ParseResult = struct {
    /// The command that was matched (could be subcommand)
    command: *Command,
    /// Parsed context to pass to action
    context: Context,
    /// Whether help was requested
    help_requested: bool,
};

/// Parser state machine for processing arguments.
pub const Parser = struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
    index: usize,
    stop_parsing_flags: bool,

    // Accumulated results
    flag_values: std.StringHashMapUnmanaged([]const u8),
    flag_present: std.StringHashMapUnmanaged(void),
    arg_values: std.ArrayList([]const u8),
    arg_map: std.StringHashMapUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator, args: []const []const u8) Parser {
        return .{
            .allocator = allocator,
            .args = args,
            .index = 0,
            .stop_parsing_flags = false,
            .flag_values = .empty,
            .flag_present = .empty,
            .arg_values = .empty,
            .arg_map = .empty,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.flag_values.deinit(self.allocator);
        self.flag_present.deinit(self.allocator);
        self.arg_values.deinit(self.allocator);
        self.arg_map.deinit(self.allocator);
    }

    /// Parse arguments for a specific command.
    /// Returns error and prints message on failure.
    pub fn parse(self: *Parser, cmd: *Command) ParseError!ParseResult {
        var current_cmd = cmd;
        var help_requested = false;

        while (self.index < self.args.len) {
            const arg = self.args[self.index];

            // Check for -- separator
            if (!self.stop_parsing_flags and std.mem.eql(u8, arg, "--")) {
                self.stop_parsing_flags = true;
                self.index += 1;
                continue;
            }

            // Check for flags (only if we haven't hit --)
            if (!self.stop_parsing_flags and arg.len > 0 and arg[0] == '-') {
                // Check for help flags first (built-in)
                if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                    help_requested = true;
                    self.index += 1;
                    continue;
                }

                if (arg.len > 1 and arg[1] == '-') {
                    // Long flag: --flag or --flag=value
                    try self.parseLongFlag(arg[2..], current_cmd);
                } else {
                    // Short flag(s): -v or -abc
                    try self.parseShortFlags(arg[1..], current_cmd);
                }
                self.index += 1;
                continue;
            }

            // Not a flag - could be a subcommand or argument
            // Check for subcommand first (only if no arguments collected yet)
            if (self.arg_values.items.len == 0) {
                if (current_cmd.findSubcommand(arg)) |subcmd| {
                    current_cmd = subcmd;
                    self.index += 1;
                    continue;
                }
            }

            // It's an argument
            self.arg_values.append(self.allocator, arg) catch return error.OutOfMemory;
            self.index += 1;
        }

        // Map arguments to their defined names
        for (current_cmd.args.items, 0..) |arg_def, i| {
            if (i < self.arg_values.items.len) {
                self.arg_map.put(self.allocator, arg_def.name, self.arg_values.items[i]) catch return error.OutOfMemory;
            } else if (arg_def.required and !help_requested) {
                printError("missing required argument: <{s}>", .{arg_def.name});
                return error.MissingRequiredArg;
            }
        }

        // Apply default values for flags
        for (current_cmd.flags.items) |f| {
            if (f.takes_value and f.default != null) {
                if (!self.flag_values.contains(f.long)) {
                    self.flag_values.put(self.allocator, f.long, f.default.?) catch return error.OutOfMemory;
                }
            }
        }

        return .{
            .command = current_cmd,
            .context = .{
                .allocator = self.allocator,
                .flag_values = self.flag_values,
                .flag_present = self.flag_present,
                .arg_values = self.arg_map,
                .raw_args = self.arg_values.items,
            },
            .help_requested = help_requested,
        };
    }

    /// Parse a long flag (everything after --)
    fn parseLongFlag(self: *Parser, flag_str: []const u8, cmd: *const Command) ParseError!void {
        // Check for = in flag
        var name: []const u8 = undefined;
        var value: ?[]const u8 = null;

        if (std.mem.indexOfScalar(u8, flag_str, '=')) |eq_pos| {
            name = flag_str[0..eq_pos];
            value = flag_str[eq_pos + 1 ..];
        } else {
            name = flag_str;
        }

        // Look up the flag definition
        const flag_def = cmd.findFlag(name) orelse {
            printError("unknown flag: --{s}", .{name});
            return error.UnknownFlag;
        };

        if (flag_def.takes_value) {
            if (value == null) {
                // Value should be next argument
                if (self.index + 1 < self.args.len) {
                    self.index += 1;
                    value = self.args[self.index];
                } else {
                    printError("flag --{s} requires a value", .{name});
                    return error.MissingFlagValue;
                }
            }
            self.flag_values.put(self.allocator, flag_def.long, value.?) catch return error.OutOfMemory;
        } else {
            if (value != null) {
                // Boolean flag shouldn't have = value
                printError("flag --{s} does not take a value", .{name});
                return error.UnknownFlag;
            }
            self.flag_present.put(self.allocator, flag_def.long, {}) catch return error.OutOfMemory;
        }
    }

    /// Parse short flag(s) (everything after single -)
    fn parseShortFlags(self: *Parser, flag_str: []const u8, cmd: *const Command) ParseError!void {
        // Check for = in flag string (e.g., -o=value)
        if (std.mem.indexOfScalar(u8, flag_str, '=')) |eq_pos| {
            if (eq_pos != 1) {
                // Only single char before = is valid
                printError("invalid flag format: -{s}", .{flag_str});
                return error.UnknownFlag;
            }
            const short = flag_str[0];
            const value = flag_str[eq_pos + 1 ..];

            const flag_def = cmd.findFlagByShort(short) orelse {
                printError("unknown flag: -{c}", .{short});
                return error.UnknownFlag;
            };

            if (!flag_def.takes_value) {
                printError("flag -{c} does not take a value", .{short});
                return error.UnknownFlag;
            }

            self.flag_values.put(self.allocator, flag_def.long, value) catch return error.OutOfMemory;
            return;
        }

        // Process each character as a separate flag
        for (flag_str, 0..) |short, i| {
            const flag_def = cmd.findFlagByShort(short) orelse {
                printError("unknown flag: -{c}", .{short});
                return error.UnknownFlag;
            };

            if (flag_def.takes_value) {
                // If this is the last char, value is next arg
                // Otherwise, rest of string is the value
                if (i + 1 < flag_str.len) {
                    // Rest of string is value
                    self.flag_values.put(self.allocator, flag_def.long, flag_str[i + 1 ..]) catch return error.OutOfMemory;
                    return;
                } else {
                    // Value is next argument
                    if (self.index + 1 < self.args.len) {
                        self.index += 1;
                        self.flag_values.put(self.allocator, flag_def.long, self.args[self.index]) catch return error.OutOfMemory;
                    } else {
                        printError("flag -{c} requires a value", .{short});
                        return error.MissingFlagValue;
                    }
                }
            } else {
                self.flag_present.put(self.allocator, flag_def.long, {}) catch return error.OutOfMemory;
            }
        }
    }
};

const builtin = @import("builtin");

fn printError(comptime fmt: []const u8, args: anytype) void {
    // Suppress error output during tests to avoid polluting test output
    if (builtin.is_test) return;
    // Bold red "error:" prefix, then reset formatting for the message
    std.debug.print("\x1b[1;31merror:\x1b[0m " ++ fmt ++ "\n", args);
}

test "Parser long flag" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{ .long = "verbose", .short = 'v' });

    const args = [_][]const u8{"--verbose"};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expect(result.context.flag("verbose"));
}

test "Parser long flag with equals value" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{ .long = "output", .short = 'o', .takes_value = true });

    const args = [_][]const u8{"--output=foo.txt"};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expectEqualStrings("foo.txt", result.context.flagValue("output").?);
}

test "Parser long flag with space value" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{ .long = "output", .takes_value = true });

    const args = [_][]const u8{ "--output", "bar.txt" };
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expectEqualStrings("bar.txt", result.context.flagValue("output").?);
}

test "Parser combined short flags" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{ .long = "all", .short = 'a' });
    _ = cmd.addFlag(.{ .long = "verbose", .short = 'v' });
    _ = cmd.addFlag(.{ .long = "force", .short = 'f' });

    const args = [_][]const u8{"-avf"};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expect(result.context.flag("all"));
    try std.testing.expect(result.context.flag("verbose"));
    try std.testing.expect(result.context.flag("force"));
}

test "Parser short flag with equals value" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addFlag(.{ .long = "output", .short = 'o', .takes_value = true });

    const args = [_][]const u8{"-o=file.txt"};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expectEqualStrings("file.txt", result.context.flagValue("output").?);
}

test "Parser arguments" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "install" });
    defer cmd.deinit();
    _ = cmd.addArgument(.{ .name = "version", .required = true });

    const args = [_][]const u8{"0.13.0"};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expectEqualStrings("0.13.0", result.context.arg("version").?);
}

test "Parser double dash stops flag parsing" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();
    _ = cmd.addArgument(.{ .name = "arg", .required = true });

    // After --, "--foo" should be treated as an argument
    const args = [_][]const u8{ "--", "--foo" };
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expectEqualStrings("--foo", result.context.arg("arg").?);
}

test "Parser help flag" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();

    const args = [_][]const u8{"--help"};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expect(result.help_requested);
}

test "Parser subcommand" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "app" });
    defer cmd.deinit();
    const subcmd = cmd.addSubcommand(.{ .name = "install" });
    _ = subcmd.addArgument(.{ .name = "version", .required = true });

    const args = [_][]const u8{ "install", "0.13.0" };
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = try parser.parse(&cmd);
    try std.testing.expectEqualStrings("install", result.command.name);
    try std.testing.expectEqualStrings("0.13.0", result.context.arg("version").?);
}

test "Parser missing required arg" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "install" });
    defer cmd.deinit();
    _ = cmd.addArgument(.{ .name = "version", .required = true });

    const args = [_][]const u8{};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = parser.parse(&cmd);
    try std.testing.expectError(error.MissingRequiredArg, result);
}

test "Parser unknown flag" {
    var cmd = Command.init(std.testing.allocator, .{ .name = "test" });
    defer cmd.deinit();

    const args = [_][]const u8{"--unknown"};
    var parser = Parser.init(std.testing.allocator, &args);
    defer parser.deinit();

    const result = parser.parse(&cmd);
    try std.testing.expectError(error.UnknownFlag, result);
}
