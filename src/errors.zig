const std = @import("std");

pub fn prettyError(comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    const file = std.fs.File.stderr();
    var stderr = file.writer(&buf);
    defer stderr.interface.flush() catch {};
    const tty = std.io.tty.detectConfig(file);

    try tty.setColor(&stderr.interface, .bold);
    try tty.setColor(&stderr.interface, .red);

    try stderr.interface.print(fmt, args);
    try stderr.interface.writeByte('\n');

    try tty.setColor(&stderr.interface, .reset);
}
