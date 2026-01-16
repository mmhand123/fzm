const std = @import("std");
const cli = @import("cli/cli.zig");
const installation = @import("commands/install/install.zig");
const list_cmd = @import("commands/list.zig");
const use_cmd = @import("commands/use.zig");
const logging = @import("logging.zig");
const env_cmd = @import("commands/env.zig");
const state = @import("state.zig");

const VERSION = "0.1.0";

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try logging.setLogLevel();

    // Load persistent state
    var app_state = try state.State.load(allocator);
    defer app_state.deinit();

    var app = cli.Cli.init(allocator, .{
        .name = "fzm",
        .description = "(Fun) Zig Version Manager",
        .version = VERSION,
    });
    defer app.deinit();

    app.setUserData(&app_state);

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

    _ = app.addCommand(.{
        .name = "env",
        .description = "Set up environment for fzm",
        .action = envAction,
    });

    _ = app.addCommand(.{
        .name = "use",
        .description = "Set the Zig version to use",
        .action = useAction,
    }).addArgument(.{
        .name = "version",
        .description = "Version to use (e.g., master, 0.13.0)",
        .required = false,
    });

    app.run() catch |err| switch (err) {
        error.UserError => std.process.exit(1),
        else => return err,
    };
}

fn installAction(ctx: cli.Context) !void {
    const version = ctx.arg("version").?;
    const app_state = ctx.getUserData(state.State).?;
    try installation.install(ctx.allocator, app_state, version);
}

fn listAction(ctx: cli.Context) !void {
    const app_state = ctx.getUserData(state.State).?;
    try list_cmd.list(ctx.allocator, app_state);
}

fn envAction(ctx: cli.Context) !void {
    const app_state = ctx.getUserData(state.State).?;
    try env_cmd.env(ctx.allocator, app_state);
}

fn useAction(ctx: cli.Context) !void {
    const version = ctx.arg("version");
    const app_state = ctx.getUserData(state.State).?;
    try use_cmd.use(ctx.allocator, app_state, version);
}

test {
    _ = @import("cli/cli.zig");
    _ = @import("dirs.zig");
    _ = @import("commands/install/install.zig");
    _ = @import("commands/list.zig");
    _ = @import("commands/use.zig");
    _ = @import("state.zig");
    _ = @import("versions.zig");
    _ = @import("zon.zig");
}
