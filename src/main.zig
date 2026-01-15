const std = @import("std");
const cli = @import("cli/cli.zig");
const installation = @import("commands/install/install.zig");
const list_cmd = @import("commands/list.zig");
const logging = @import("logging.zig");

const VERSION = "0.0.1";

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try logging.setLogLevel();

    var app = cli.Cli.init(allocator, .{
        .name = "fzm",
        .description = "(Fun) Zig Version Manager",
        .version = VERSION,
    });
    defer app.deinit();

    _ = app.addCommand(.{
        .name = "install",
        .aliases = &.{"i"},
        .description = "Install a Zig version (e.g., master, 0.15.2)",
        .action = installAction,
    }).addArgument(.{
        .name = "version",
        .description = "Version to install",
        .required = true,
    });

    _ = app.addCommand(.{
        .name = "list",
        .aliases = &.{"ls"},
        .description = "List installed Zig versions",
        .action = listAction,
    });

    app.run() catch |err| switch (err) {
        error.UserError => std.process.exit(1),
        else => return err,
    };
}

fn installAction(ctx: cli.Context) !void {
    const version = ctx.arg("version").?;
    try installation.install(ctx.allocator, version);
}

fn listAction(ctx: cli.Context) !void {
    try list_cmd.list(ctx.allocator);
}

test {
    _ = @import("cli/cli.zig");
    _ = @import("dirs.zig");
    _ = @import("commands/install/install.zig");
    _ = @import("commands/list.zig");
    _ = @import("versions.zig");
}
