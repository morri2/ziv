const std = @import("std");
const RuleGenStep = @import("build/RuleGenStep.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const foundation = b.addModule("foundation", .{
        .source_file = .{ .path = "foundation/lib.zig" },
    });

    const rule_gen_step = RuleGenStep.create(
        b,
        .{ .cwd_relative = "base_rules" },
        b.option(
            bool,
            "print_rules_zig",
            "Print generated rules.zig",
        ) orelse false,
        foundation,
    );

    const raylib_dep = b.dependency("raylib", .{});
    const raylib_lib = raylib_dep.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "ziv",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.addModule("rules", rule_gen_step.getModule());
    exe.addModule("foundation", foundation);
    exe.linkLibrary(raylib_lib);
    exe.addIncludePath(raylib_dep.path("src"));
    exe.step.dependOn(&rule_gen_step.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("foundation", foundation);
    exe_unit_tests.addModule("rules", rule_gen_step.getModule());
    exe_unit_tests.step.dependOn(&rule_gen_step.step);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
