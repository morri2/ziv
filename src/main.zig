const std = @import("std");
const rules = @import("rules");
const hex = @import("hex.zig");
const render = @import("render.zig");
const World = @import("World.zig");
const Unit = @import("Unit.zig");
const Grid = @import("Grid.zig");
const Idx = Grid.Idx;
const move = @import("move.zig");

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

    try world.loadFromFile("maps/last_saved.map");

    var w1 = Unit.new(.warrior);
    w1.promotions.set(@intFromEnum(rules.Promotion.Mobility));
    //world.pushUnit(1200, .{ .type = .Archer });
    world.pushUnit(1200, w1);

    var w2 = Unit.new(.archer);
    w2.promotions.set(@intFromEnum(rules.Promotion.Mobility));
    //world.pushUnit(1200, .{ .type = .Archer });
    world.pushUnit(1201, w2);

    std.debug.print("unita {} \n", .{world.topUnitContainerPtr(1200).?.unit.type});
    //std.debug.print("unitb {} \n", .{world.nextUnitContainerPtr(world.topUnitContainerPtr(1200).?).?.unit.type});

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

    var texture_set = try render.TextureSet.init();
    defer texture_set.deinit();

    // MAP DRAW MODE
    var draw_terrain: ?rules.Terrain = null;
    draw_terrain = draw_terrain; // autofix
    var edit_mode: bool = false;
    edit_mode = edit_mode;

    var selected_tile: ?Idx = null;
    selected_tile = selected_tile; // autofix

    while (!raylib.WindowShouldClose()) {
        if (raylib.IsKeyPressed(raylib.KEY_SPACE)) world.refreshUnits();
        if (raylib.IsKeyPressed(raylib.KEY_E)) edit_mode = !edit_mode;

        if (raylib.IsKeyPressed(raylib.KEY_R)) {
            const mouse_tile = getMouseTile(&camera, world.grid, texture_set);
            const res = try world.resources.getOrPut(world.allocator, mouse_tile);

            if (res.found_existing) {
                const next_enum_int: u8 = @intFromEnum(res.value_ptr.type) + 1;
                if (next_enum_int >= @typeInfo(rules.Resource).Enum.fields.len) {
                    _ = world.resources.swapRemove(mouse_tile);
                } else {
                    res.value_ptr.type = @enumFromInt(next_enum_int);
                }
            } else {
                try world.resources.put(world.allocator, mouse_tile, .{ .type = @enumFromInt(0), .amount = 1 });
            }
        }
        if (raylib.IsKeyPressed(raylib.KEY_T)) {
            const mouse_tile = getMouseTile(&camera, world.grid, texture_set);
            const res = try world.resources.getOrPut(world.allocator, mouse_tile);

            if (res.found_existing) {
                {
                    res.value_ptr.amount = res.value_ptr.amount + 1;
                    if (res.value_ptr.amount > 12) {
                        res.value_ptr.amount = 1;
                    }
                }
            }
        }
        if (raylib.IsKeyPressed(raylib.KEY_C)) {
            try world.saveToFile("maps/last_saved.map");
            std.debug.print("\nMap saved (as 'maps/last_saved.map')!\n", .{});
        }
        if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT)) {
            const clicked_tile = getMouseTile(&camera, world.grid, texture_set);
            // EDIT MAP
            if (edit_mode) {
                draw_terrain = @enumFromInt(clicked_tile % @typeInfo(rules.Terrain).Enum.fields.len);
            }
            // UNIT MOVEMENT
            if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT) and !edit_mode and (draw_terrain == null)) {
                if (draw_terrain != null) {
                    world.terrain[clicked_tile] = draw_terrain.?;
                } else {
                    if (selected_tile == null) {
                        selected_tile = clicked_tile;
                    } else {
                        _ = move.moveUnit(selected_tile.?, clicked_tile, 0, &world);
                        if (selected_tile == clicked_tile) {
                            selected_tile = null;
                        }
                        selected_tile = null;
                    }
                }
            }
        }

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

            const fwidth: f32 = @floatFromInt(world.grid.width);
            const fheight: f32 = @floatFromInt(world.grid.height);

            const min_x: usize = @intFromFloat(std.math.clamp(
                @round(top_left.x / hex.widthFromRadius(texture_set.hex_radius)) - 2.0,
                0.0,
                fwidth,
            ));
            const max_x: usize = @intFromFloat(std.math.clamp(
                @round(bottom_right.x / hex.widthFromRadius(texture_set.hex_radius)) + 2.0,
                0.0,
                fwidth,
            ));

            const min_y: usize = @intFromFloat(std.math.clamp(
                @round(top_left.y / (texture_set.hex_radius * 1.5)) - 2.0,
                0.0,
                fheight,
            ));
            const max_y: usize = @intFromFloat(std.math.clamp(
                @round(bottom_right.y / (texture_set.hex_radius * 1.5)) + 2.0,
                0.0,
                fheight,
            ));

            break :blk .{ min_x, min_y, max_x, max_y };
        };

        for (min_y..max_y) |y| {
            for (min_x..max_x) |x| {
                const index = world.grid.idxFromCoords(x, y);

                if (edit_mode) {
                    const select_terrain: rules.Terrain = @enumFromInt(index % @typeInfo(rules.Terrain).Enum.fields.len);
                    render.renderTerrain(select_terrain, index, world.grid, texture_set);
                } else {
                    // Normal mode render
                    render.renderTile(world, index, world.grid, texture_set);
                    render.renderResource(&world, index, texture_set);
                    render.renderUnits(&world, index, texture_set);

                    if (selected_tile == index)
                        render.renderYields(&world, index, texture_set);

                    // Selection menu render :)
                    if (selected_tile != null) {
                        if (selected_tile == index) {
                            const real_x = hex.tilingX(x, y, texture_set.hex_radius);
                            const real_y = hex.tilingY(y, texture_set.hex_radius);

                            raylib.DrawTextureEx(
                                texture_set.base_textures[@intFromEnum(rules.Base.snow)],
                                raylib.Vector2{
                                    .x = real_x,
                                    .y = real_y,
                                },
                                0.0,
                                1.0,
                                .{ .r = 100, .g = 100, .b = 100, .a = 100 },
                            );
                        }
                    }
                }
            }
        }

        raylib.EndMode2D();

        raylib.EndDrawing();
    }
}

/// VERY PLACEHOLDER AND SHIT
fn getMouseTile(
    camera: *raylib.Camera2D,
    grid: Grid,
    ts: render.TextureSet,
) usize {
    const click_point = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), camera.*);
    const click_x: f32 = click_point.x;
    const click_y: f32 = click_point.y;
    var click_idx: Grid.Idx = 0; // = world.tiles.coordToIdx(click_x, click_y);

    var min_dist: f32 = std.math.floatMax(f32);
    for (0..grid.width) |x| {
        for (0..grid.height) |y| {
            const real_x = hex.tilingX(x, y, ts.hex_radius) + hex.heightFromRadius(ts.hex_radius) * 0.5;
            const real_y = hex.tilingY(y, ts.hex_radius) + hex.widthFromRadius(ts.hex_radius) * 0.5;
            const dist = std.math.pow(f32, real_x - click_x, 2) + std.math.pow(f32, real_y - click_y, 2);
            if (dist < min_dist) {
                click_idx = grid.idxFromCoords(x, y);
                min_dist = dist;
            }
        }
    }
    return click_idx;
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
    if (raylib.IsKeyDown(raylib.KEY_RIGHT) or raylib.IsKeyDown(raylib.KEY_D)) camera.target.x += speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_LEFT) or raylib.IsKeyDown(raylib.KEY_A)) camera.target.x -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_UP) or raylib.IsKeyDown(raylib.KEY_W)) camera.target.y -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_DOWN) or raylib.IsKeyDown(raylib.KEY_S)) camera.target.y += speed / camera.zoom;
}
