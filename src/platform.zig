const builtin = @import("builtin");

/// Platform key for the current build target (e.g., "x86_64-linux").
/// Comptime-known to allow use with @field() for struct field access.
pub const platform_key = @tagName(builtin.target.cpu.arch) ++ "-" ++ @tagName(builtin.target.os.tag);
