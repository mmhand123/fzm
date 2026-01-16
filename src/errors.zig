const std = @import("std");

/// Prints a pretty error message to stderr with bold red "error:" prefix.
pub fn prettyError(comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    const file = std.fs.File.stderr();
    var stderr = file.writer(&buf);
    defer stderr.interface.flush() catch {};
    const tty = std.io.tty.detectConfig(file);

    try tty.setColor(&stderr.interface, .bold);
    try tty.setColor(&stderr.interface, .red);
    try stderr.interface.writeAll("error:");
    try tty.setColor(&stderr.interface, .reset);

    try stderr.interface.print(" " ++ fmt ++ "\n", args);

    try stderr.interface.flush();
    std.process.exit(1);
}

/// Prints a pretty warning message to stderr with bold yellow "warning:" prefix.
pub fn prettyWarning(comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    const file = std.fs.File.stderr();
    var stderr = file.writer(&buf);
    defer stderr.interface.flush() catch {};
    const tty = std.io.tty.detectConfig(file);

    try tty.setColor(&stderr.interface, .bold);
    try tty.setColor(&stderr.interface, .yellow);
    try stderr.interface.writeAll("warning:");
    try tty.setColor(&stderr.interface, .reset);

    try stderr.interface.print(" " ++ fmt ++ "\n", args);
    try stderr.interface.flush();
}
