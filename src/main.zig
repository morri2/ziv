const std = @import("std");
const Rules = @import("Rules.zig");

const TextureSet = @import("gui/TextureSet.zig");
const World = @import("World.zig");
const Unit = @import("Unit.zig");
const Grid = @import("Grid.zig");
const Idx = Grid.Idx;
const Units = @import("Units.zig");
const City = @import("City.zig");
const PlayerView = @import("PlayerView.zig");

const control = @import("gui/control.zig");
const render = @import("gui/render.zig");
const graphics = @import("gui/graphics.zig");

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
        true,
        1,
        &rules,
    );
    defer world.deinit();

    try world.loadFromFile("maps/last_saved.map");

    var w1 = Unit.new(@enumFromInt(3), 0, &rules); // Warrior
    w1.promotions.set(11); // Mobility

    var a1 = Unit.new(@enumFromInt(4), 0, &rules);
    a1.promotions.set(11); // Mobility
    a1.promotions.set(5); // Shock I
    a1.promotions.set(6); // Shock II
    a1.promotions.set(7); // Shock III
    a1.promotions.set(13); // CanEmbark

    const b1 = Unit.new(@enumFromInt(7), 0, &rules); // Trireme

    var s1 = Unit.new(@enumFromInt(5), 0, &rules);
    s1.promotions.set(8); // Drill I
    s1.promotions.set(9); // Drill II
    s1.promotions.set(10); // Drill III
    s1.promotions.set(13); // CanEmbark
    s1.promotions.set(14); // Can cross ocean

    try world.units.putNoStackAutoSlot(1200, w1);
    try world.units.putNoStackAutoSlot(1201, a1);
    try world.units.putNoStackAutoSlot(1203, b1);
    try world.units.putNoStackAutoSlot(1198, s1);

    try world.addCity(1089);

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

    var texture_set = try TextureSet.init(&rules, gpa.allocator());
    defer texture_set.deinit();

    var maybe_selected_idx: ?Idx = null;
    var maybe_unit_reference: ?Units.Reference = null;

    var camera_bound_box = control.cameraRenderBoundBox(camera, &world.grid, screen_width, screen_height, texture_set);

    // MAP EDIT MODE
    var in_edit_mode = false;
    var in_pallet = false;
    var terrain_brush: ?Rules.Terrain = null;

    while (!raylib.WindowShouldClose()) {
        world.fullUpdateViews();
        {
            if (raylib.IsKeyPressed(raylib.KEY_Y)) in_edit_mode = !in_edit_mode;

            // EDIT MODE CONTROLLS
            if (in_edit_mode) {
                if (raylib.IsKeyPressed(raylib.KEY_E)) in_pallet = !in_pallet;
                const mouse_tile = control.getMouseTile(&camera, world.grid, texture_set);
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
                if (raylib.IsKeyPressed(raylib.KEY_B)) {}

                if (raylib.IsKeyPressed(raylib.KEY_SPACE)) {
                    for (world.cities.keys()) |city_key| {
                        var city = world.cities.getPtr(city_key) orelse continue;
                        const ya = city.getWorkedTileYields(&world);

                        _ = city.processYields(&ya);
                        const growth_res = city.checkGrowth(&world);
                        _ = city.checkExpansion();
                        _ = try city.checkProduction(&world);

                        switch (growth_res) {
                            .growth => std.debug.print("TOWN HAS GROWN! \n", .{}),
                            else => {},
                        }
                    }

                    world.units.refresh();
                }

                // SELECTION
                if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    const mouse_idx = control.getMouseTile(&camera, world.grid, texture_set);

                    if (maybe_selected_idx) |selected_idx| {
                        if (selected_idx != mouse_idx) blk: {
                            if (maybe_unit_reference == null) {
                                maybe_unit_reference = world.units.firstReference(selected_idx);
                                if (maybe_unit_reference == null) {
                                    maybe_selected_idx = mouse_idx;
                                    maybe_unit_reference = world.units.firstReference(mouse_idx);
                                    break :blk;
                                }
                            }

                            if (raylib.IsKeyDown(raylib.KEY_Q)) {
                                // Unit.tryBattle(selected_idx.?, clicked_idx, &world);
                            } else {
                                _ = try world.move(maybe_unit_reference.?, mouse_idx);
                            }
                            maybe_selected_idx = null;
                        } else if (maybe_unit_reference) |ref| {
                            maybe_unit_reference = world.units.nextReference(ref);
                        } else {
                            maybe_unit_reference = world.units.firstReference(selected_idx);
                        }
                    } else {
                        maybe_selected_idx = mouse_idx;
                        maybe_unit_reference = world.units.firstReference(mouse_idx);
                    }
                }

                if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_RIGHT)) {
                    const clicked_tile = control.getMouseTile(&camera, world.grid, texture_set);

                    for (world.cities.keys()) |city_key| {
                        var city = world.cities.getPtr(city_key) orelse continue;

                        if (city_key == clicked_tile) {
                            if (raylib.IsKeyDown(raylib.KEY_Y)) {
                                // Warrior
                                _ = city.startConstruction(City.ProductionTarget{ .UnitType = @enumFromInt(3) }, &rules);
                            } else if (raylib.IsKeyDown(raylib.KEY_U)) {
                                // Settler
                                _ = city.startConstruction(City.ProductionTarget{ .UnitType = @enumFromInt(1) }, &rules);
                            } else if (raylib.IsKeyDown(raylib.KEY_I)) {
                                // Archer
                                _ = city.startConstruction(City.ProductionTarget{ .UnitType = @enumFromInt(4) }, &rules);
                            } else if (raylib.IsKeyDown(raylib.KEY_O)) {
                                // Work Boat
                                _ = city.startConstruction(City.ProductionTarget{ .UnitType = @enumFromInt(2) }, &rules);
                            } else if (raylib.IsKeyDown(raylib.KEY_P)) {
                                // Chariot Archer
                                _ = city.startConstruction(City.ProductionTarget{ .UnitType = @enumFromInt(6) }, &rules);
                            }

                            std.debug.print("EXPANDING CITY!\n", .{});
                            _ = city.expandBorder(&world);
                        }
                        if (city.claimed.contains(clicked_tile)) {
                            if (city.unsetWorked(clicked_tile)) break;
                            if (city.setWorkedWithAutoReassign(clicked_tile, &world)) break;
                        }
                    }
                }
            }
        }

        _ = control.updateCamera(&camera, 16.0);

        camera_bound_box = control.cameraRenderBoundBox(
            camera,
            &world.grid,
            screen_width,
            screen_height,
            texture_set,
        );

        camera_bound_box.ymax = @min(camera_bound_box.ymax, world.grid.height);
        camera_bound_box.xmax = @min(camera_bound_box.xmax, world.grid.width - 1);

        // ///////// //
        // RENDERING //
        // ///////// //
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        raylib.BeginMode2D(camera);
        if (in_pallet) {
            camera_bound_box.restart();
            while (camera_bound_box.iterNext()) |index|
                graphics.renderTerrain(
                    @enumFromInt(index % rules.terrain_count),
                    index,
                    world.grid,
                    texture_set,
                    &rules,
                );
        } else {
            graphics.renderWorld(&world, &camera_bound_box, &world.players[0].view, texture_set);
            if (maybe_selected_idx) |selected_idx| {
                if (raylib.IsKeyDown(raylib.KEY_M)) {
                    while (camera_bound_box.iterNext()) |i| {
                        render.renderFormatHexAuto(i, world.grid, "{}", .{world.grid.distance(selected_idx, i)}, 0.0, 0.0, .{ .font_size = 25 }, texture_set);
                    }
                }

                render.renderTextureHex(
                    selected_idx,
                    world.grid,
                    texture_set.base_textures[6],
                    .{ .tint = .{ .r = 200, .g = 200, .b = 100, .a = 100 } },
                    texture_set,
                );
                camera_bound_box.restart();
            }

            //const GridNEW = @import("GridNEW.zig");

            camera_bound_box.restart();
            if (raylib.IsKeyDown(raylib.KEY_Z)) {
                while (camera_bound_box.iterNext()) |index| {
                    const xy = Grid.CoordXY.fromIdx(index, world.grid);
                    const qrs = Grid.CoordQRS.fromIdx(index, world.grid);

                    render.renderFormatHexAuto(index, world.grid, "idx: {}", .{index}, 0, -0.3, .{}, texture_set);
                    render.renderFormatHexAuto(index, world.grid, "(x{}, y{}) = {?}", .{ xy.x, xy.y, xy.toIdx(world.grid) }, 0, 0, .{ .font_size = 8 }, texture_set);
                    render.renderFormatHexAuto(index, world.grid, "(q{}, r{}) = {?}", .{ qrs.q, qrs.r, qrs.toIdx(world.grid) }, 0, 0.3, .{ .font_size = 8 }, texture_set);
                    if (maybe_selected_idx != null) render.renderFormatHexAuto(index, world.grid, "D:{}", .{world.grid.distance(index, maybe_selected_idx.?)}, 0, -0.5, .{}, texture_set);
                }
                if (maybe_selected_idx != null) {
                    const ns = world.grid.neighbours(maybe_selected_idx.?);

                    var xxx: f32 = 0.1;
                    for (ns) |n| {
                        xxx += 0.1;
                        if (n == null) continue;
                        render.renderTextInHex(n.?, world.grid, "N", 0, 0.7, .{}, texture_set);
                        render.renderFormatHexAuto(maybe_selected_idx.?, world.grid, "{}", .{n.?}, 0.7, -0.4 + xxx, .{ .font_size = 6 }, texture_set);
                    }
                }
            }

            // blk: {
            //     const idx1 = maybe_selected_idx orelse break :blk;
            //     const idx2 = 12;

            //     const dist = world.grid.distance(idx1, idx2);

            //     for (0..(dist + 1)) |n| {
            //         const fxy = world.grid.nthLerp(dist, @intCast(n), idx1, idx2);
            //         raylib.DrawCircleV(
            //             fxy.raylibVector2(texture_set.hex_radius),
            //             10,
            //             raylib.RED,
            //         );
            //         const theidx = fxy.roundToIdx(world.grid) orelse continue;
            //         render.renderTextureInHex(
            //             theidx,
            //             world.grid,
            //             texture_set.red_pop,
            //             0,
            //             0,
            //             .{ .scale = 0.1 },
            //             texture_set,
            //         );
            //     }
            //     render.renderTextureInHex(
            //         idx1,
            //         world.grid,
            //         texture_set.green_pop,
            //         0,
            //         0,
            //         .{ .scale = 0.1 },
            //         texture_set,
            //     );
            //     render.renderTextureInHex(
            //         idx2,
            //         world.grid,
            //         texture_set.green_pop,
            //         0,
            //         0,
            //         .{ .scale = 0.1 },
            //         texture_set,
            //     );

            //     raylib.DrawLineEx(
            //         render.posInHex(idx1, world.grid, 0, 0, texture_set),
            //         render.posInHex(idx2, world.grid, 0, 0, texture_set),
            //         2,
            //         raylib.WHITE,
            //     );
            // }
        }

        raylib.EndMode2D();
        raylib.EndDrawing();
    }
}
