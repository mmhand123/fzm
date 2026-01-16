//! End-to-end test module.
//!
//! These tests spawn the actual fzm binary with custom environment
//! variables to verify CLI behavior in isolation.
//!
//! Run with: zig build e2e

test {
    _ = @import("list_test.zig");
    _ = @import("install_test.zig");
    _ = @import("uninstall_test.zig");
}
