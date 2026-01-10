const std = @import("std");
const clap = @import("clap");
const installation = @import("install.zig");

const VERSION = "0.0.1";

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help      Display this help and exit.
        \\-v, --version   Print version information and exit.
        \\-i, --install <str>   Install a new Zig version. Can be a specific version or "master".
    );

    var diag: clap.Diagnostic = .{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return;
    };

    defer res.deinit();

    if (res.args.help != 0) {
        return clap.helpToFile(.stderr(), clap.Help, &params, .{});
    } else if (res.args.version != 0) {
        std.debug.print("fzm v{s}\n", .{VERSION});
    } else if (res.args.install) |version| {
        try installation.install(gpa.allocator(), version);
    }
}
