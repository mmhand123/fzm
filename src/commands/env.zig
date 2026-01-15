//! Sets up things related to the environment needed to run fzm.
//! Primarily this involves setting up a shell hook for the given shell to
//! automatically load the correct version of Zig when changing directories.

const std = @import("std");
const errors = @import("../errors.zig");
const log = std.log.scoped(.env);

const Shell = enum {
    bash,
    zsh,
};

const EnvError = error{
    UnsupportedShell,
};

pub fn env(allocator: std.mem.Allocator) !void {
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

    // Note: avoid log.debug here since output is meant to be eval'd by the shell

    switch (shell) {
        .bash => try setupBash(allocator),
        .zsh => try setupZsh(allocator),
    }
}

fn setupBash(_: std.mem.Allocator) !void {
    // TODO
}

fn setupZsh(_: std.mem.Allocator) !void {
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
    const stdout_file = std.fs.File.stdout();
    try stdout_file.writeAll(script);
    try stdout_file.writeAll("\n");
}
