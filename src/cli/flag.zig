//! Flag and argument definitions for the CLI.
//!
//! Flags are optional parameters like `--verbose` or `-f`.
//! Arguments are unnamed parameters identified by position.

const std = @import("std");

/// A command-line flag (optional named argument).
///
/// Flags can be boolean (presence = true) or take a value.
/// Examples: `--verbose`, `-v`, `--output file.txt`, `--config=path`
pub const Flag = struct {
    /// Long name without dashes (e.g., "verbose" for --verbose)
    long: []const u8,

    /// Optional single-character short form (e.g., 'v' for -v)
    short: ?u8 = null,

    /// Human-readable description for help text
    description: []const u8 = "",

    /// Whether this flag expects a value (--flag value vs --flag)
    takes_value: bool = false,

    /// Default value if flag takes a value and isn't provided
    default: ?[]const u8 = null,

    /// Format the flag for display in help text (e.g., "-v, --verbose")
    pub fn formatNames(self: Flag, buf: []u8) []const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        if (self.short) |s| {
            writer.print("-{c}, --{s}", .{ s, self.long }) catch return "";
        } else {
            writer.print("    --{s}", .{self.long}) catch return "";
        }

        if (self.takes_value) {
            writer.print(" <value>", .{}) catch return "";
        }

        return stream.getWritten();
    }
};

/// A positional argument (unnamed, identified by position).
///
/// Arguments are the non-flag parameters in order.
/// Example: in `fzm install 0.13.0`, "0.13.0" is an argument.
pub const Argument = struct {
    /// Name for documentation and lookup (e.g., "version")
    name: []const u8,

    /// Human-readable description for help text
    description: []const u8 = "",

    /// Whether this argument must be provided
    required: bool = true,

    /// Format for display in usage line (e.g., "<version>" or "[version]")
    pub fn formatUsage(self: Argument, buf: []u8) []const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        if (self.required) {
            writer.print("<{s}>", .{self.name}) catch return "";
        } else {
            writer.print("[{s}]", .{self.name}) catch return "";
        }

        return stream.getWritten();
    }
};

/// Options for creating a Flag via the fluent API.
pub const FlagOptions = struct {
    long: []const u8,
    short: ?u8 = null,
    description: []const u8 = "",
    takes_value: bool = false,
    default: ?[]const u8 = null,
};

/// Options for creating an Argument via the fluent API.
pub const ArgumentOptions = struct {
    name: []const u8,
    description: []const u8 = "",
    required: bool = true,
};

test "Flag.formatNames with short and long" {
    const flag: Flag = .{
        .long = "verbose",
        .short = 'v',
        .description = "Enable verbose output",
    };

    var buf: [64]u8 = undefined;
    const result = flag.formatNames(&buf);
    try std.testing.expectEqualStrings("-v, --verbose", result);
}

test "Flag.formatNames long only" {
    const flag: Flag = .{
        .long = "force",
        .description = "Force operation",
    };

    var buf: [64]u8 = undefined;
    const result = flag.formatNames(&buf);
    try std.testing.expectEqualStrings("    --force", result);
}

test "Flag.formatNames with value" {
    const flag: Flag = .{
        .long = "output",
        .short = 'o',
        .takes_value = true,
    };

    var buf: [64]u8 = undefined;
    const result = flag.formatNames(&buf);
    try std.testing.expectEqualStrings("-o, --output <value>", result);
}

test "Argument.formatUsage required" {
    const pos: Argument = .{
        .name = "version",
        .required = true,
    };

    var buf: [32]u8 = undefined;
    const result = pos.formatUsage(&buf);
    try std.testing.expectEqualStrings("<version>", result);
}

test "Argument.formatUsage optional" {
    const pos: Argument = .{
        .name = "target",
        .required = false,
    };

    var buf: [32]u8 = undefined;
    const result = pos.formatUsage(&buf);
    try std.testing.expectEqualStrings("[target]", result);
}
