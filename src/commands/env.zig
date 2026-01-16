//! Sets up things related to the environment needed to run fzm.
//! Primarily this involves setting up a shell hook for the given shell to
//! automatically load the correct version of Zig when changing directories.

const std = @import("std");
const errors = @import("../errors.zig");
const state = @import("../state.zig");
const tmp = @import("../tmp.zig");
const versions = @import("../versions.zig");
const linking = @import("../linking.zig");
const log = std.log.scoped(.env);

const Shell = enum {
    bash,
    zsh,
};

const EnvError = error{
    UnsupportedShell,
};

pub fn env(allocator: std.mem.Allocator, app_state: *const state.State) !void {
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

    const tmp_result = try tmp.makeTempDir(allocator);
    const tmp_dir = tmp_result.path;

    try linking.createZigSymlink(allocator, app_state, tmp_dir);

    const path_update = try std.fmt.allocPrint(allocator, "export PATH={s}:$PATH\n", .{tmp_dir});
    const path_env = try std.fmt.allocPrint(allocator, "export FZM_TMP_PATH={s}\n", .{tmp_dir});

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(path_update);
    try stdout.writeAll(path_env);

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
