const std = @import("std");
const rules = @import("rules");
const hex = @import("hex.zig");

const World = @import("World.zig");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const WIDTH = 56;
    const HEIGHT = 36;
    var world = try World.init(
        gpa.allocator(),
        WIDTH,
        HEIGHT,
        false,
    );
    defer world.deinit();

    const screen_width = 1920;
    const screen_height = 1080;

    raylib.SetTraceLogLevel(raylib.LOG_WARNING);

    raylib.InitWindow(screen_width, screen_height, "ziv");
    defer raylib.CloseWindow();

    raylib.SetTargetFPS(60);

    var camera = raylib.Camera2D{
        .target = raylib.Vector2{ .x = 0.0, .y = 0.0 },
        .offset = raylib.Vector2{
            .x = @floatFromInt(screen_width / 2),
            .y = @floatFromInt(screen_height / 2),
        },
        .zoom = 0.5,
    };

    // Load resources
    const base_textures, const texture_height = blk: {
        const enum_fields = @typeInfo(rules.Base).Enum.fields;
        var textures = [_]raylib.Texture2D{undefined} ** enum_fields.len;
        var texture_height: c_int = 0;

        inline for (enum_fields, 0..) |field, i| {
            const path = "textures/" ++ field.name ++ ".png";
            const img = if (raylib.FileExists(path)) raylib.LoadImage(path) else raylib.LoadImage("textures/placeholder.png");
            defer raylib.UnloadImage(img);

            if (i == 0) texture_height = img.height else {
                if (img.height != texture_height) return error.InvalidResources;
            }

            textures[i] = raylib.LoadTextureFromImage(img);
        }
        break :blk .{ textures, texture_height };
    };
    defer {
        for (base_textures) |texture| {
            raylib.UnloadTexture(texture);
        }
    }

    const feature_textures = blk: {
        const enum_fields = @typeInfo(rules.Feature).Enum.fields;
        var textures = [_]raylib.Texture2D{undefined} ** (enum_fields.len - 1);

        inline for (enum_fields[1..], 0..) |field, i| {
            const img = raylib.LoadImage("textures/" ++ field.name ++ ".png");
            defer raylib.UnloadImage(img);

            if (img.height != texture_height) return error.InvalidResources;

            textures[i] = raylib.LoadTextureFromImage(img);
        }
        break :blk textures;
    };
    defer {
        for (feature_textures) |texture| {
            raylib.UnloadTexture(texture);
        }
    }

    const vegetation_textures = blk: {
        const enum_fields = @typeInfo(rules.Vegetation).Enum.fields;
        var textures = [_]raylib.Texture2D{undefined} ** (enum_fields.len - 1);

        inline for (enum_fields[1..], 0..) |field, i| {
            const img = raylib.LoadImage("textures/" ++ field.name ++ ".png");
            defer raylib.UnloadImage(img);

            if (img.height != texture_height) return error.InvalidResources;

            textures[i] = raylib.LoadTextureFromImage(img);
        }
        break :blk textures;
    };
    defer {
        for (vegetation_textures) |texture| {
            raylib.UnloadTexture(texture);
        }
    }

    const hex_radius = @as(f32, @floatFromInt(texture_height)) * 0.5;

    while (!raylib.WindowShouldClose()) {
        updateCamera(&camera, 16.0);
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        raylib.BeginMode2D(camera);
        const min_x, const min_y, const max_x, const max_y = blk: {
            const top_left = raylib.GetScreenToWorld2D(raylib.Vector2{}, camera);
            const bottom_right = raylib.GetScreenToWorld2D(raylib.Vector2{
                .x = @floatFromInt(screen_width),
                .y = @as(f32, @floatFromInt(screen_height)),
            }, camera);

            const fwidth: f32 = @floatFromInt(world.width);
            const fheight: f32 = @floatFromInt(world.height);

            const min_x: usize = @intFromFloat(std.math.clamp(
                @round(top_left.x / hex.hexWidth(hex_radius)) - 2.0,
                0.0,
                fwidth,
            ));
            const max_x: usize = @intFromFloat(std.math.clamp(
                @round(bottom_right.x / hex.hexWidth(hex_radius)) + 2.0,
                0.0,
                fwidth,
            ));

            const min_y: usize = @intFromFloat(std.math.clamp(
                @round(top_left.y / (hex_radius * 1.5)) - 2.0,
                0.0,
                fheight,
            ));
            const max_y: usize = @intFromFloat(std.math.clamp(
                @round(bottom_right.y / (hex_radius * 1.5)) + 2.0,
                0.0,
                fheight,
            ));

            break :blk .{ min_x, min_y, max_x, max_y };
        };

        for (min_y..max_y) |y| {
            const real_y = hex.tilingPosY(y, hex_radius);

            for (min_x..max_x) |x| {
                const index = world.tiles.coordToIdx(x, y);
                const real_x = hex.tilingPosX(x, y, hex_radius);

                const tile = world.tiles.get(index);
                const terrain = tile.terrain;

                raylib.DrawTextureEx(
                    base_textures[@intFromEnum(terrain.base())],
                    raylib.Vector2{
                        .x = real_x,
                        .y = real_y,
                    },
                    0.0,
                    1.0,
                    raylib.WHITE,
                );

                if (terrain.feature() != .none) {
                    raylib.DrawTextureEx(
                        feature_textures[@intFromEnum(terrain.feature()) - 1],
                        raylib.Vector2{
                            .x = real_x,
                            .y = real_y,
                        },
                        0.0,
                        1.0,
                        raylib.WHITE,
                    );
                }

                if (terrain.vegetation() != .none) {
                    raylib.DrawTextureEx(
                        vegetation_textures[@intFromEnum(terrain.vegetation()) - 1],
                        raylib.Vector2{
                            .x = real_x,
                            .y = real_y,
                        },
                        0.0,
                        1.0,
                        raylib.WHITE,
                    );
                }
            }
        }
        raylib.EndMode2D();

        raylib.EndDrawing();
    }
}

fn updateCamera(camera: *raylib.Camera2D, speed: f32) void {

    // Drag controls
    if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_MIDDLE)) {
        const delta = raylib.Vector2Scale(raylib.GetMouseDelta(), -1.0 / camera.zoom);

        camera.target = raylib.Vector2Add(camera.target, delta);
    }

    // Zoom controls
    const wheel = raylib.GetMouseWheelMove();
    if (wheel != 0.0) {
        const world_pos = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), camera.*);

        camera.offset = raylib.GetMousePosition();
        camera.target = world_pos;

        const zoom_inc = 0.3;
        camera.zoom += (wheel * zoom_inc);
        camera.zoom = std.math.clamp(camera.zoom, 0.3, 2.0);
    }

    // Arrow key controls
    if (raylib.IsKeyDown(raylib.KEY_RIGHT)) camera.target.x += speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_LEFT)) camera.target.x -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_UP)) camera.target.y -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_DOWN)) camera.target.y += speed / camera.zoom;
}
