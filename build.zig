const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib", .{});
    const raylib_lib = raylib_dep.artifact("raylib");

    const raygui_dep = b.dependency("raygui", .{});
    const raygui_lib = b.addStaticLibrary(.{
        .name = "raygui",
        .optimize = optimize,
        .target = target,
    });
    const wf = b.addWriteFiles();
    const raygui_c = wf.addCopyFile(raygui_dep.path("src/raygui.h"), "raygui.c");
    raygui_lib.addCSourceFile(.{
        .file = raygui_c,
        .flags = &.{
            "-std=gnu99",
            "-D_GNU_SOURCE",
            "-DRAYGUI_IMPLEMENTATION",
        },
    });
    raygui_lib.linkLibrary(raylib_lib);
    raygui_lib.addIncludePath(raylib_dep.path("src"));
    raygui_lib.addIncludePath(raygui_dep.path("src"));
    raygui_lib.linkLibC();

    const zig_clap_dep = b.dependency("zig-clap", .{});

    const exe = b.addExecutable(.{
        .name = "ziv",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.linkLibrary(raylib_lib);
    exe.linkLibrary(raygui_lib);
    exe.addIncludePath(raylib_dep.path("src"));
    exe.addIncludePath(raygui_dep.path("src"));
    exe.root_module.addImport("clap", zig_clap_dep.module("clap"));

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

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
