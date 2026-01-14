const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mainMod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "fzm",
        .root_module = mainMod,
    });

    b.installArtifact(exe);

    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = mainMod,
    });

    const check = b.step("check", "Check if the module compiles, used in ZLS");

    check.dependOn(&exe_check.step);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    // Shared platform module for e2e tests
    const platform_mod = b.createModule(.{
        .root_source_file = b.path("src/platform.zig"),
        .target = target,
        .optimize = optimize,
    });

    // E2E tests: spawn the actual binary with custom environment
    const e2e_mod = b.createModule(.{
        .root_source_file = b.path("src/e2e/e2e.zig"),
        .target = target,
        .optimize = optimize,
    });
    e2e_mod.addImport("platform", platform_mod);

    const e2e_tests = b.addTest(.{
        .root_module = e2e_mod,
    });

    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    run_e2e_tests.step.dependOn(b.getInstallStep()); // Ensure binary is built first

    const e2e_step = b.step("e2e", "Run end-to-end tests");
    e2e_step.dependOn(&run_e2e_tests.step);
}
