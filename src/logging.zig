const std = @import("std");

var log_level: std.log.Level = std.log.default_level;

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(log_level)) {
        std.log.defaultLog(message_level, scope, format, args);
    }
}

/// Sets the log level from the FZM_LOG_LEVEL environment variable.
/// Defaults to `std.log.default_level`, which is `.info` in prod builds and `.debug` in debug builds.
pub fn setLogLevel() !void {
    if (std.posix.getenv("FZM_LOG_LEVEL")) |env| {
        log_level = std.meta.stringToEnum(std.log.Level, env) orelse return error.InvalidLogLevel;
    }
}
