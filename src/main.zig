const std = @import("std");
const World = @import("World.zig");

const raylib = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var world = try World.init(
        gpa.allocator(),
        128,
        80,
        false,
    );
    defer world.deinit();

    const screen_width = 1920;
    const screen_height = 1080;

    raylib.InitWindow(screen_width, screen_height, "ziv");
    defer raylib.CloseWindow();

    raylib.SetTargetFPS(60);

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);
        raylib.EndDrawing();
    }
}
