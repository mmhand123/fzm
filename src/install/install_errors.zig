const std = @import("std");
const errors = @import("../errors.zig");

pub const InstallError = error{
    /// Version string is not "master" or valid semver (x.x.x)
    InvalidVersion,
    /// Version does not exist on the Zig CDN
    VersionNotFound,
    /// HTTP request failed or returned non-success status
    HttpRequestFailed,
    /// Failed to parse CDN response as JSON
    JsonParseFailed,
};

pub fn printInstallError(err: InstallError, version: []const u8) void {
    var buf: [4096]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&buf);
    defer stderr.interface.flush() catch {};

    switch (err) {
        error.InvalidVersion => errors.prettyError(
            "error: invalid version \"{s}\" - must be \"master\" or semver (e.g., 0.15.2)\n",
            .{version},
        ) catch {},
        error.VersionNotFound => errors.prettyError(
            "error: version \"{s}\" not found on Zig download server\n",
            .{version},
        ) catch {},
        error.HttpRequestFailed => errors.prettyError(
            "error: failed to connect to Zig download server\n",
            .{},
        ) catch {},
        error.JsonParseFailed => errors.prettyError(
            "error: failed to parse response from Zig download server\n",
            .{},
        ) catch {},
    }
}
