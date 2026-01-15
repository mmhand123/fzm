//! E2E test runner utilities.
//!
//! Provides helpers for spawning the fzm binary with custom environment
//! variables and capturing output.

const std = @import("std");

/// Path to the built binary (relative to project root).
const FZM_BINARY = "zig-out/bin/fzm";

pub const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    pub fn deinit(self: *RunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// Runs the fzm binary with the given arguments and environment.
pub fn run(allocator: std.mem.Allocator, args: []const []const u8, env: *const std.process.EnvMap) !RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, FZM_BINARY);
    try argv.appendSlice(allocator, args);

    var child = std.process.Child.init(argv.items, allocator);
    child.env_map = env;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read stdout and stderr
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;

    var stdout_reader = child.stdout.?.reader(&stdout_buf);
    const stdout = try stdout_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(64 * 1024));
    errdefer allocator.free(stdout);

    var stderr_reader = child.stderr.?.reader(&stderr_buf);
    const stderr = try stderr_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(64 * 1024));
    errdefer allocator.free(stderr);

    const term = try child.wait();

    return .{ .stdout = stdout, .stderr = stderr, .term = term };
}
