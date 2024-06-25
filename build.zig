const std = @import("std");
const raylib_dep = @import("raylib");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_lib = try raylib_dep.addRaylib(
        b,
        target,
        optimize,
        .{
            .raygui = true,
        },
    );

    const zig_clap_dep = b.dependency("zig-clap", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "ziv",
        .root_source_file = .{
            .src_path = .{
                .owner = b,
                .sub_path = "src/main.zig",
            },
        },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("clap", zig_clap_dep.module("clap"));
    b.installArtifact(exe);
    exe.linkLibrary(raylib_lib);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{
            .src_path = .{
                .owner = b,
                .sub_path = "src/main.zig",
            },
        },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
