const std = @import("std");
const builtin = @import("builtin");
const installation = @import("./install/install.zig");
const list_cmd = @import("./list.zig");
const logging = @import("./logging.zig");

const VERSION = "0.0.1";

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
};

const Command = enum {
    help,
    version,
    list,
    install,
};

fn parseCommand(arg: []const u8) ?Command {
    const commands = .{
        .{ "help", .help },
        .{ "-h", .help },
        .{ "--help", .help },
        .{ "version", .version },
        .{ "-v", .version },
        .{ "--version", .version },
        .{ "ls", .list },
        .{ "list", .list },
        .{ "--list", .list },
        .{ "install", .install },
        .{ "-i", .install },
        .{ "--install", .install },
    };
    inline for (commands) |entry| {
        if (std.mem.eql(u8, arg, entry[0])) return entry[1];
    }
    return null;
}

fn printHelp() void {
    const help_text =
        \\fzm v{s} - Zig version manager
        \\
        \\Usage: fzm <command> [arguments]
        \\
        \\Commands:
        \\  help, -h, --help           Display this help and exit
        \\  version, -v, --version     Print version information and exit
        \\  ls, list, --list           List all installed versions
        \\  install, -i, --install     Install a Zig version (e.g., "master" or "0.13.0")
        \\
    ;
    std.debug.print(help_text, .{VERSION});
}

fn printError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("error: " ++ fmt ++ "\n\n", args);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    try logging.setLogLevel();

    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);

    // No arguments provided - show help
    if (args.len < 2) {
        printHelp();
        return;
    }

    const command = parseCommand(args[1]) orelse {
        printError("unknown command: {s}", .{args[1]});
        printHelp();
        std.process.exit(1);
    };

    switch (command) {
        .help => printHelp(),
        .version => std.debug.print("fzm v{s}\n", .{VERSION}),
        .list => try list_cmd.list(allocator),
        .install => {
            if (args.len < 3) {
                printError("install requires a version argument", .{});
                printHelp();
                std.process.exit(1);
            }
            try installation.install(allocator, args[2]);
        },
    }
}

test {
    _ = @import("install/install.zig");
    _ = @import("list.zig");
    _ = @import("versions.zig");
}
