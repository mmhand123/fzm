const std = @import("std");
const clap = @import("clap");

const VERSION = "0.0.1";

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help      Display this help and exit.
        \\-v, --version   Print version information and exit.
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
    }
}
