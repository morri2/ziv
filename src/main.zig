const std = @import("std");
const Rules = @import("Rules.zig");

const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

const World = @import("World.zig");
const Unit = @import("Unit.zig");
const Units = @import("Units.zig");
const City = @import("City.zig");
const PlayerView = @import("PlayerView.zig");

const Camera = @import("rendering/Camera.zig");
const TextureSet = @import("rendering/TextureSet.zig");
const render = @import("rendering/render_util.zig");
const graphics = @import("rendering/graphics.zig");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
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

    var camera = Camera.init(screen_width, screen_height);

    var texture_set = try TextureSet.init(&rules, gpa.allocator());
    defer texture_set.deinit();

    var maybe_selected_idx: ?Idx = null;
    var maybe_unit_reference: ?Units.Reference = null;

    // MAP EDIT MODE
    var in_edit_mode = false;
    var in_pallet = false;
    var terrain_brush: ?Rules.Terrain = null;

    const gui = @import("rendering/gui.zig");

    const EditWindow = gui.SelectWindow(Rules.Terrain, .{
        .WIDTH = 400,
        .COLUMNS = 5,
        .NULL_OPTION = true,
        .ENTRY_HEIGHT = 75,
        .TEXTURE_ENTRY_FRACTION = 0.6,
    });

    var edit_window: EditWindow = EditWindow.newEmpty();
    for (0..rules.terrain_count) |ti| {
        const t = @as(Rules.Terrain, @enumFromInt(ti));
        if (t.attributes(&rules).has_freshwater or t.attributes(&rules).has_river or t.attributes(&rules).is_wonder) continue;
        const texture: ?raylib.Texture2D = texture_set.terrain_textures[ti];
        edit_window.addItemTexture(t, t.name(&rules), texture);
    }
    for (0..rules.terrain_count) |ti| {
        const t = @as(Rules.Terrain, @enumFromInt(ti));
        if (t.attributes(&rules).has_freshwater or t.attributes(&rules).has_river or !t.attributes(&rules).is_wonder) continue;
        edit_window.addItem(t, t.name(&rules));
    }

    while (!raylib.WindowShouldClose()) {
        world.fullUpdateViews();

        const bounding_box = camera.boundingBox(
            world.grid.width,
            world.grid.height,
            screen_width,
            screen_height,
            texture_set,
        );
        {
            {
                // EDIT MAP STUFF
                const mouse_tile = camera.getMouseTile(world.grid, bounding_box, texture_set);
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

                if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT) and terrain_brush != null) {
                    if (terrain_brush != null) world.terrain[mouse_tile] = terrain_brush.?;
                }
            }

            // SAVE MAP
            if (raylib.IsKeyPressed(raylib.KEY_C)) {
                try world.saveToFile("maps/last_saved.map");
                std.debug.print("\nMap saved (as 'maps/last_saved.map')!\n", .{});
            }

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
                    const mouse_idx = camera.getMouseTile(
                        world.grid,
                        bounding_box,
                        texture_set,
                    );

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
                    const clicked_tile = camera.getMouseTile(
                        world.grid,
                        bounding_box,
                        texture_set,
                    );

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

        _ = edit_window.fetchSelectedNull(&terrain_brush);

        if (maybe_selected_idx) |selected_idx| {
            if (raylib.IsKeyPressed(raylib.KEY_B)) {
                const b = world.canBuildImprovement(selected_idx, @as(Rules.Building, @enumFromInt(building)));
                std.debug.print("\nCAN BUILD: {s} ", .{@tagName(b)});
                if (b == .allowed) {
                    _ = world.progressTileWork(
                        selected_idx,
                        .{ .building = @as(Rules.Building, @enumFromInt(building)) },
                    );
                }
            }
        } else {
            if (raylib.IsKeyPressed(raylib.KEY_B)) {
                building += 1;
                building = building % @as(u8, @intCast(world.rules.building_count));
                const name = @as(Rules.Building, @enumFromInt(building)).name(world.rules);
                std.debug.print("\n BUILDING: {s} \n", .{name});
            }
        }

        // ///////// //
        // RENDERING //
        // ///////// //
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        raylib.BeginMode2D(camera.camera);

            graphics.renderWorld(&world, bounding_box, &world.players[0].view, texture_set);
            if (maybe_selected_idx) |selected_idx| {
                if (raylib.IsKeyDown(raylib.KEY_M)) {
                    for (bounding_box.x_min..bounding_box.x_max) |x| {
                        for (bounding_box.y_min..bounding_box.y_max) |y| {
                            const idx = world.grid.idxFromCoords(x, y);
                            render.renderFormatHexAuto(idx, world.grid, "{}", .{world.grid.distance(selected_idx, idx)}, 0.0, 0.0, .{ .font_size = 25 }, texture_set);
                        }
                    }
                }

                render.renderTextureHex(
                    selected_idx,
                    world.grid,
                    texture_set.edge_textures[0],
                    .{ .tint = .{ .r = 0, .g = 250, .b = 150, .a = 100 } },
                    texture_set,
                );
            }
            if (maybe_selected_idx) |selected_idx| {
                if (raylib.IsKeyDown(raylib.KEY_X)) {
                    var vision_set = world.fov(3, selected_idx);
                    defer vision_set.deinit();

                    for (vision_set.slice()) |index| {
                        render.renderTextureHex(
                            index,
                            world.grid,
                            texture_set.base_textures[6],
                            .{ .tint = .{ .r = 250, .g = 10, .b = 10, .a = 100 } },
                            texture_set,
                        );

                        if (world.terrain[index].attributes(world.rules).is_obscuring) {
                            render.renderTextureHex(
                                index,
                                world.grid,
                                texture_set.base_textures[6],
                                .{ .tint = .{ .r = 0, .g = 0, .b = 200, .a = 50 } },
                                texture_set,
                            );
                        }
                    }
                }
                if (raylib.IsKeyDown(raylib.KEY_Z)) {
                    for (bounding_box.x_min..bounding_box.x_max) |x| {
                        for (bounding_box.y_min..bounding_box.y_max) |y| {
                            const index = world.grid.idxFromCoords(x, y);
                            const xy = Grid.CoordXY.fromIdx(index, world.grid);
                            const qrs = Grid.CoordQRS.fromIdx(index, world.grid);

                            render.renderFormatHexAuto(index, world.grid, "idx: {}", .{index}, 0, -0.3, .{}, texture_set);
                            render.renderFormatHexAuto(index, world.grid, "(x{}, y{}) = {?}", .{ xy.x, xy.y, xy.toIdx(world.grid) }, 0, 0, .{ .font_size = 8 }, texture_set);
                            render.renderFormatHexAuto(index, world.grid, "(q{}, r{}) = {?}", .{ qrs.q, qrs.r, qrs.toIdx(world.grid) }, 0, 0.3, .{ .font_size = 8 }, texture_set);
                            if (maybe_selected_idx != null) render.renderFormatHexAuto(index, world.grid, "D:{}", .{world.grid.distance(index, maybe_selected_idx.?)}, 0, -0.5, .{}, texture_set);

                            render.renderFormatHexAuto(index, world.grid, "view: {}", .{
                                world.players[0].view.in_view.hexes.get(index) orelse 0,
                            }, 0, 0.8, .{}, texture_set);
                        }
                    }

                    var spiral_iter = Grid.SpiralIterator.new(selected_idx, 12, world.grid);
                    //var ring_iter = Grid.RingIterator.new(maybe_selected_idx.?, 2, world.grid);
                    var j: u32 = 0;
                    while (spiral_iter.next(world.grid)) |idx| {
                        render.renderFormatHexAuto(
                            idx,
                            world.grid,
                            "spiral={}",
                            .{j},
                            -0.4,
                            -0.6,
                            .{ .font_size = 6 },
                            texture_set,
                        );
                        j += 1;
                }
            }
        }

        raylib.EndMode2D();

        edit_window.renderUpdate();

        raylib.EndDrawing();

        _ = camera.update(16.0);
    }
}
