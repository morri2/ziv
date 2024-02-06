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

const gui = @import("rendering/gui.zig");

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

    // UNITS
    const w1 = Unit.new(@enumFromInt(3), 0, &rules); // Warrior
    const a1 = Unit.new(@enumFromInt(4), 0, &rules); // Archer
    const b1 = Unit.new(@enumFromInt(7), 0, &rules); // Trireme
    const s1 = Unit.new(@enumFromInt(5), 0, &rules); // Scout

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

    var hide_gui = false;

    const PaletWindow = gui.SelectWindow(Rules.Terrain, .{
        .WIDTH = 400,
        .COLUMNS = 5,
        .NULL_OPTION = true,
        .ENTRY_HEIGHT = 50,
        .SPACEING = 2,
        .TEXTURE_ENTRY_FRACTION = 0.6,
    });

    var edit_window: PaletWindow = PaletWindow.newEmpty();
    for (0..rules.terrain_count) |ti| {
        const t = @as(Rules.Terrain, @enumFromInt(ti));
        if (t.attributes(&rules).has_freshwater or t.attributes(&rules).has_river) continue;
        const texture: ?raylib.Texture2D = texture_set.terrain_textures[ti];
        edit_window.addItemTexture(t, t.name(&rules), texture);
    }
    edit_window.setName("Edit Palet");

    var terrain_brush: ?Rules.Terrain = null;

    const PromotionWindow = gui.SelectWindow(Rules.Promotion, .{
        .WIDTH = 150,
        .COLUMNS = 1,
        .ENTRY_HEIGHT = 25,
        .KEEP_HIGHLIGHT = false,
        .SPACEING = 2,
    });

    var promotion_window: PromotionWindow = PromotionWindow.newEmpty();
    for (0..rules.promotion_count) |pi| {
        const p = @as(Rules.Promotion, @enumFromInt(pi));

        promotion_window.addItem(p, p.name(&rules));
    }
    promotion_window.setName("Add Promotion");
    promotion_window.bounds.y += 50;
    var set_promotion: ?Rules.Promotion = null;

    const UnitInfoWindow = gui.InfoWindow(.{});

    var unit_info_window: UnitInfoWindow = UnitInfoWindow.newEmpty();
    unit_info_window.bounds.y += 100;
    unit_info_window.setName("[UNIT]");
    unit_info_window.addLine("Select a unit to view info...");

    const CityConstructionWindow = gui.SelectWindow(City.ProductionTarget, .{
        .WIDTH = 150,
        .COLUMNS = 1,
        .ENTRY_HEIGHT = 25,
        .KEEP_HIGHLIGHT = false,
        .SPACEING = 2,
    });

    var city_construction_window: CityConstructionWindow = CityConstructionWindow.newEmpty();
    city_construction_window.bounds.y += 150;
    city_construction_window.setName("Build in city.");

    for (0..rules.unit_type_count) |uti| {
        const ut: Rules.UnitType = @enumFromInt(uti);
        const pt = City.ProductionTarget{ .UnitType = ut };
        var buf: [255]u8 = undefined;
        const label = try std.fmt.bufPrint(&buf, "Build unit: {s}", .{ut.name(world.rules)});
        city_construction_window.addItem(pt, label);
    }

    var set_production_target: ?City.ProductionTarget = null;

    // MAIN GAME LOOP
    while (!raylib.WindowShouldClose()) {
        world.fullUpdateViews();

        const bounding_box = camera.boundingBox(
            world.grid.width,
            world.grid.height,
            screen_width,
            screen_height,
            texture_set,
        );

        // ////////////// //
        // CONTROLL STUFF //
        // ////////////// //
        control_blk: {
            if (raylib.IsKeyPressed(raylib.KEY_H)) hide_gui = !hide_gui;

            // GUI STUFF

            if (!hide_gui) {
                _ = promotion_window.fetchSelectedNull(&set_promotion);
                // Set unit promotions
                if (set_promotion) |promotion|
                    if (maybe_unit_reference) |unit_ref|
                        if (world.units.derefToPtr(unit_ref)) |unit|
                            unit.promotions.set(@intFromEnum(promotion));
                set_promotion = null;

                _ = edit_window.fetchSelectedNull(&terrain_brush);

                _ = city_construction_window.fetchSelectedNull(&set_production_target);
                // Set construction
                if (set_production_target) |production_target|
                    if (maybe_selected_idx) |idx| {
                        if (world.cities.getPtr(idx)) |city| {
                            _ = city.startConstruction(production_target, world.rules);
                        }
                    };
                set_production_target = null;

                // Set edit brush

                _ = edit_window.fetchSelectedNull(&terrain_brush);

                // UPDATE UNIT INFO
                if (maybe_unit_reference) |ref| {
                    if (world.units.derefToPtr(ref)) |unit| {
                        unit_info_window.clear();

                        unit_info_window.addCategoryHeader("General");

                        unit_info_window.addLineFormat("HP: {}", .{unit.hit_points}, false);
                        unit_info_window.addLineFormat("Move: {d:.1}/{d:.1}", .{ unit.movement, unit.maxMovement(world.rules) }, false);
                        unit_info_window.addLineFormat("Faction id: {}", .{unit.faction_id}, false);
                        unit_info_window.addLineFormat("Fortified: {}", .{unit.fortified}, false);
                        unit_info_window.addLineFormat("Prepared: {}", .{unit.prepared}, false);

                        unit_info_window.addCategoryHeader("Promotions");
                        for (0..rules.promotion_count) |pi| {
                            unit_info_window.setName(unit.type.name(world.rules));
                            const p: Rules.Promotion = @enumFromInt(pi);

                            if (unit.promotions.isSet(pi)) {
                                unit_info_window.addLineFormat("{s}", .{p.name(world.rules)}, false);
                            }
                        }
                    }
                }

                // Check capture
                if (unit_info_window.checkMouseCapture()) break :control_blk;
                if (promotion_window.checkMouseCapture()) break :control_blk;
                if (edit_window.checkMouseCapture()) break :control_blk;
                if (city_construction_window.checkMouseCapture()) break :control_blk;
            }

            // OLD SCHOOL CONTROL STUFF
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
                        const idx = world.grid.idxFromCoords(@intCast(x), @intCast(y));
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
                        const index = world.grid.idxFromCoords(@intCast(x), @intCast(y));
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

        if (!hide_gui) {
            // TODO: CAPTURE MOUSE TO DISSALLOW MULTI CLICKS

            edit_window.renderUpdate();
            promotion_window.renderUpdate();

            unit_info_window.renderUpdate();
            city_construction_window.renderUpdate();
        }
        raylib.EndDrawing();

        _ = camera.update(16.0);
    }
}
