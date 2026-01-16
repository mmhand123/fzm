//! Sets up things related to the environment needed to run fzm.
//! Primarily this involves setting up a shell hook for the given shell to
//! automatically load the correct version of Zig when changing directories.

const std = @import("std");
const errors = @import("../errors.zig");
const tmp = @import("../tmp.zig");
const log = std.log.scoped(.env);

const Shell = enum {
    bash,
    zsh,
};

const EnvError = error{
    UnsupportedShell,
};

pub fn env(allocator: std.mem.Allocator) !void {
    // Note: avoid log.debug here since output is meant to be eval'd by the shell
    const shell_env = std.process.getEnvVarOwned(allocator, "SHELL") catch {
        try errors.prettyError("SHELL environment variable not set\n", .{});
        return;
    };
    const last_slash_idx = std.mem.lastIndexOf(u8, shell_env, "/").?;
    const shell_str = shell_env[last_slash_idx + 1 ..];
    const shell = std.meta.stringToEnum(Shell, shell_str) orelse {
        try errors.prettyError("unsupported shell: {s}\n", .{shell_str});
        return EnvError.UnsupportedShell;
    };

    const tmp_dir = try tmp.makeTempDir(allocator);
    // TODO: symlink to the correct version of zig
    const path_update = std.fmt.allocPrint(allocator, "EXPORT PATH={s}:$PATH\n", .{tmp_dir});

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(path_update);

    switch (shell) {
        .bash => try autoloadBash(allocator, stdout),
        .zsh => try autoloadZsh(allocator, stdout),
    }

    try stdout.flush();
}

fn autoloadBash(_: std.mem.Allocator, _: *std.io.Writer) !void {
    // TODO
}

fn autoloadZsh(_: std.mem.Allocator, writer: *std.io.Writer) !void {
    const script =
        \\fzm_autoload() {
        \\    if [[ -f build.zig.zon ]]; then
        \\        fzm use
        \\    fi
        \\}
        \\
        \\autoload -U add-zsh-hook
        \\add-zsh-hook chpwd fzm_autoload
        \\
        \\fzm_autoload
    ;

    try writer.writeAll(script);
    try writer.writeAll("\n");
}
