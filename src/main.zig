const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");
const installation = @import("./install/install.zig");
const list_cmd = @import("./list.zig");
const logging = @import("./logging.zig");

const VERSION = "0.0.1";

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    try logging.setLogLevel();

    const allocator = arena.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help      Display this help and exit.
        \\-v, --version   Print version information and exit.
        \\-i, --install <str>   Install a new Zig version. Can be a specific version or "master".
        \\-l, --list      List all installed versions.
    );

    var diag: clap.Diagnostic = .{};
    const res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return;
    };

    if (res.args.help != 0) {
        return clap.helpToFile(.stderr(), clap.Help, &params, .{});
    } else if (res.args.version != 0) {
        std.debug.print("fzm v{s}\n", .{VERSION});
    } else if (res.args.install) |version| {
        try installation.install(allocator, version);
    } else if (res.args.list != 0) {
        try list_cmd.list(allocator);
    }
}

test {
    _ = @import("install/install.zig");
    _ = @import("list.zig");
    _ = @import("versions.zig");
}
