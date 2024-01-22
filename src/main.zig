const std = @import("std");
const Rules = @import("Rules.zig");
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

    var rules = blk: {
        var rules_dir = try std.fs.cwd().openDir("base_rules", .{});
        defer rules_dir.close();
        break :blk try Rules.parse(rules_dir, gpa.allocator());
    };
    defer rules.deinit();

    const WIDTH = 56;
    const HEIGHT = 36;
    var world = try World.init(
        gpa.allocator(),
        WIDTH,
        HEIGHT,
        false,
        &rules,
    );
    defer world.deinit();

    try world.loadFromFile("maps/last_saved.map");

    var w1 = Unit.new(.warrior);
    w1.promotions.set(@intFromEnum(Rules.Promotion.Mobility));
    //world.pushUnit(1200, .{ .type = .Archer });
    world.pushUnit(1200, w1);

    var w2 = Unit.new(.archer);
    w2.promotions.set(@intFromEnum(Rules.Promotion.Mobility));
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

    var texture_set = try render.TextureSet.init(&rules, gpa.allocator());
    defer texture_set.deinit();

    var selected_tile: ?Idx = null;
    selected_tile = selected_tile; // autofix

    var camera_bound_box = render.cameraRenderBoundBox(camera, &world.grid, screen_width, screen_height, texture_set);

    // MAP EDIT MODE
    var in_edit_mode = false;
    var in_pallet = false;
    var terrain_brush: ?Rules.Terrain = null;
    terrain_brush = terrain_brush; // autofix

    while (!raylib.WindowShouldClose()) {
        {
            if (raylib.IsKeyPressed(raylib.KEY_Y)) in_edit_mode = !in_edit_mode;

            // EDIT MODE CONTROLLS
            if (in_edit_mode) {
                if (raylib.IsKeyPressed(raylib.KEY_E)) in_pallet = !in_pallet;
                const mouse_tile = render.getMouseTile(&camera, world.grid, texture_set);
                if (raylib.IsKeyPressed(raylib.KEY_R)) {
                    const res = world.resources.getPtr(mouse_tile);

                    if (res != null) {
                        res.?.type = @enumFromInt((@intFromEnum(res.?.type) + 1) % rules.resource_count);
                    } else {
                        try world.resources.put(world.allocator, mouse_tile, .{ .type = @enumFromInt(0), .amount = 1 });
                    }
                }
                if (raylib.IsKeyPressed(raylib.KEY_F)) {
                    const res = world.resources.getPtr(mouse_tile);
                    if (res != null) {
                        if (@intFromEnum(res.?.type) == 0) {
                            _ = world.resources.swapRemove(mouse_tile);
                        } else {
                            res.?.type = @enumFromInt(@as(u8, (@intFromEnum(res.?.type)) -| 1));
                        }
                    }
                }
                if (raylib.IsKeyPressed(raylib.KEY_T)) {
                    const res = try world.resources.getOrPut(world.allocator, mouse_tile);
                    if (res.found_existing) res.value_ptr.amount = (res.value_ptr.amount % 12) + 1;
                }

                if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT) and in_edit_mode) { // DRAW / Pallet
                    if (!in_pallet and terrain_brush != null) world.terrain[mouse_tile] = terrain_brush.?;
                    if (in_pallet) terrain_brush = @enumFromInt(mouse_tile % rules.terrain_count);
                }
            }

            // SAVE MAP
            if (raylib.IsKeyPressed(raylib.KEY_C)) {
                try world.saveToFile("maps/last_saved.map");
                std.debug.print("\nMap saved (as 'maps/last_saved.map')!\n", .{});
            }

            if (!in_edit_mode) {
                if (raylib.IsKeyPressed(raylib.KEY_SPACE)) world.refreshUnits();
                // SELECTION
                if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    const clicked_tile = render.getMouseTile(&camera, world.grid, texture_set);
                    if (selected_tile == clicked_tile) {
                        selected_tile = null;
                    } else if (selected_tile == null) {
                        selected_tile = clicked_tile;
                    } else {
                        // UNIT MOVEMENT
                        if (raylib.IsKeyDown(raylib.KEY_Q)) {
                            Unit.tryBattle(selected_tile.?, clicked_tile, &world);
                        } else {
                            _ = move.moveUnit(selected_tile.?, clicked_tile, 0, &world);
                        }

                        selected_tile = null;
                    }
                }
            }
        }

        _ = render.updateCamera(&camera, 16.0);

        camera_bound_box = render.cameraRenderBoundBox(
            camera,
            &world.grid,
            screen_width,
            screen_height,
            texture_set,
        );

        camera_bound_box.ymax = @min(camera_bound_box.ymax, world.grid.height);
        camera_bound_box.xmax = @min(camera_bound_box.xmax, world.grid.width - 1);

        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        raylib.BeginMode2D(camera);

        while (camera_bound_box.iterNext()) |index| {
            if (in_pallet) {
                render.renderTerrain(
                    @enumFromInt(index % rules.terrain_count),
                    index,
                    world.grid,
                    texture_set,
                    &rules,
                );
            } else {
                // Normal mode render
                render.renderTile(world, index, world.grid, texture_set, &rules);

                render.renderUnits(&world, index, texture_set);

                if (selected_tile == index)
                    render.renderYields(&world, index, texture_set);

                if (selected_tile == index) {
                    render.renderHexTextureArgs(
                        index,
                        world.grid,
                        texture_set.base_textures[1],
                        .{ .tint = .{ .r = 100, .g = 100, .b = 100, .a = 100 } },
                        texture_set,
                    );
                }
            }
        }

        raylib.EndMode2D();

        raylib.EndDrawing();
    }
}
