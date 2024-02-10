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

const Player = @import("Player.zig");

const gui = @import("rendering/gui.zig");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub const std_options = struct {
    pub const log_scope_levels = &[_]std.log.ScopeLevel{
        .{
            .scope = .texture_set,
            .level = .err,
        },
    };
};

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
        2,
        &rules,
    );
    defer world.deinit();

    try world.loadFromFile("maps/last_saved.map");

    // UNITS
    try world.addUnit(1200, @enumFromInt(4), 0);
    try world.addUnit(1201, @enumFromInt(2), 0);
    try world.addUnit(1203, @enumFromInt(3), 0);
    try world.addUnit(1204, @enumFromInt(7), 0);

    try world.addUnit(1206, @enumFromInt(7), 1);
    try world.addUnit(1139, @enumFromInt(3), 1);

    try world.addCity(1089, 0);
    try world.addCity(485, 1);

    var maybe_player_view: ?Player.FactionID = 0;
    maybe_player_view = 0;

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

    const EditModes = enum {
        none,
        draw,
        rivers,
        resource,
    };

    var hide_gui = false;

    const EditWindow = gui.SelectWindow(EditModes, .{
        .WIDTH = 200,
        .COLUMNS = 4,
        .ENTRY_HEIGHT = 30,
        .SPACEING = 4,
    });
    var edit_mode: EditModes = .none;

    var edit_window = EditWindow.newEmpty();
    edit_window.setName("SELECT EDIT MODE");
    edit_window.addItem(.none, "None");
    edit_window.addItem(.draw, "Draw");
    edit_window.addItem(.rivers, "River");
    edit_window.addItem(.resource, "Resource");

    const ViewWindow = gui.SelectWindow(Player.FactionID, .{
        .WIDTH = 200,
        .COLUMNS = 4,
        .ENTRY_HEIGHT = 30,
        .SPACEING = 4,
        .NULL_OPTION = true,
    });

    var view_window = ViewWindow.newEmpty();
    view_window.setName("SELECT VIEW");

    for (0..world.player_count) |i| {
        view_window.addItem(@intCast(i), "X");
    }

    view_window.bounds.x += 300;

    const PaletWindow = gui.SelectWindow(Rules.Terrain, .{
        .WIDTH = 400,
        .COLUMNS = 5,
        .NULL_OPTION = true,
        .ENTRY_HEIGHT = 50,
        .SPACEING = 2,
        .TEXTURE_ENTRY_FRACTION = 0.6,
    });

    var palet_window: PaletWindow = PaletWindow.newEmpty();
    for (0..rules.terrain_count) |ti| {
        const t = @as(Rules.Terrain, @enumFromInt(ti));
        if (t.attributes(&rules).has_freshwater or t.attributes(&rules).has_river) continue;
        const texture: ?raylib.Texture2D = texture_set.terrain_textures[ti];
        palet_window.addItemTexture(t, t.name(&rules), texture);
    }

    palet_window.setName("Edit Palet");

    var terrain_brush: ?Rules.Terrain = null;

    const ResourceWindow = gui.SelectWindow(Rules.Resource, .{
        .WIDTH = 400,
        .COLUMNS = 5,
        .NULL_OPTION = true,
        .ENTRY_HEIGHT = 50,
        .SPACEING = 2,
        .TEXTURE_ENTRY_FRACTION = 0.6,
    });

    var resource_window: ResourceWindow = ResourceWindow.newEmpty();
    for (0..rules.resource_count) |ri| {
        const r = @as(Rules.Resource, @enumFromInt(ri));

        const texture: ?raylib.Texture2D = texture_set.resource_icons[ri];
        resource_window.addItemTexture(r, r.name(&rules), texture);
    }
    resource_window.setName("Resource Palet");

    var resource_brush: ?Rules.Resource = null;

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

    const HexInfoWindow = gui.InfoWindow(.{});

    var hex_info_window: HexInfoWindow = HexInfoWindow.newEmpty();
    hex_info_window.bounds.y += 200;
    hex_info_window.setName("[HEX]");
    hex_info_window.addLine("Select a hex to view info...");

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
            if (raylib.IsKeyPressed(raylib.KEY_R)) try world.recalculateWaterAccess();
            if (raylib.IsKeyPressed(raylib.KEY_H)) hide_gui = !hide_gui;

            // GUI STUFF

            if (!hide_gui) {
                _ = edit_window.fetchSelected(&edit_mode);
                if (edit_mode != .draw) palet_window.hidden = true else palet_window.hidden = false;
                if (edit_mode != .resource) resource_window.hidden = true else resource_window.hidden = false;

                _ = promotion_window.fetchSelectedNull(&set_promotion);
                // Set unit promotions
                if (set_promotion) |promotion|
                    if (maybe_unit_reference) |unit_ref|
                        if (world.units.derefToPtr(unit_ref)) |unit|
                            unit.promotions.set(@intFromEnum(promotion));
                set_promotion = null;

                _ = palet_window.fetchSelectedNull(&terrain_brush);

                _ = city_construction_window.fetchSelectedNull(&set_production_target);
                // Set construction
                if (set_production_target) |production_target|
                    if (maybe_selected_idx) |idx| {
                        if (world.cities.getPtr(idx)) |city| {
                            _ = city.startConstruction(production_target, world.rules);
                        }
                    };
                set_production_target = null;

                // view shit

                _ = view_window.fetchSelectedNull(&maybe_player_view);

                // Set edit brush

                _ = resource_window.fetchSelectedNull(&resource_brush);

                _ = palet_window.fetchSelectedNull(&terrain_brush);

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

                // UPDATE UNIT INFO
                if (maybe_selected_idx) |idx| {
                    const terrain = world.terrain[idx];
                    const attributes = terrain.attributes(&rules);
                    hex_info_window.clear();

                    hex_info_window.addCategoryHeader("Attributes");

                    hex_info_window.addLineFormat("Freshwater: {}", .{attributes.has_freshwater}, false);
                    hex_info_window.addLineFormat("River: {}", .{attributes.has_river}, false);
                }

                // Check capture
                if (unit_info_window.checkMouseCapture()) break :control_blk;
                if (promotion_window.checkMouseCapture()) break :control_blk;
                if (palet_window.checkMouseCapture()) break :control_blk;
                if (city_construction_window.checkMouseCapture()) break :control_blk;
                if (edit_window.checkMouseCapture()) break :control_blk;
                if (resource_window.checkMouseCapture()) break :control_blk;
                if (view_window.checkMouseCapture()) break :control_blk;
            }

            // OLD SCHOOL CONTROL STUFF
            {
                // EDIT MAP STUFF
                const mouse_tile = camera.getMouseTile(world.grid, bounding_box, texture_set);
                if (raylib.IsKeyPressed(raylib.KEY_T)) {
                    const res = try world.resources.getOrPut(world.allocator, mouse_tile);
                    if (res.found_existing) res.value_ptr.amount = (res.value_ptr.amount % 12) + 1;
                }

                if (edit_mode == .draw and raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT) and terrain_brush != null) {
                    world.terrain[mouse_tile] = terrain_brush.?;
                }
                if (edit_mode == .resource and raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    if (resource_brush != null) try world.resources.put(world.allocator, mouse_tile, .{ .type = resource_brush.? }) else _ = world.resources.swapRemove(mouse_tile);
                }
                if (edit_mode == .rivers and raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    if (camera.getMouseEdge(world.grid, bounding_box, texture_set)) |e| {
                        if (world.rivers.contains(e)) {
                            _ = world.rivers.swapRemove(e);
                        } else {
                            world.rivers.put(world.allocator, e, {}) catch unreachable;
                        }
                    }
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

                        if (raylib.IsKeyDown(raylib.KEY_Q)) {} else {
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

                    if (city_key == clicked_tile) _ = city.expandBorder(&world);

                    if (city.claimed.contains(clicked_tile)) {
                        if (city.unsetWorked(clicked_tile)) break;
                        if (city.setWorkedWithAutoReassign(clicked_tile, &world)) break;
                    }
                }
            }
        }
        // SETTLE CITY
        if (raylib.IsKeyPressed(raylib.KEY_B)) {
            if (maybe_unit_reference) |unit_ref| {
                if (maybe_selected_idx) |sel_idx| {
                    if (try world.settleCity(sel_idx, unit_ref)) {
                        std.debug.print("Settled city!\n", .{});
                        //maybe_unit_reference = null;
                    } else {
                        std.debug.print("failed to settle city\n", .{});
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

        var view: ?*PlayerView = null;
        if (maybe_player_view) |player_view| view = &world.players[player_view].view;

        graphics.renderWorld(
            &world,
            bounding_box,
            view,
            camera.camera.zoom,
            maybe_unit_reference,
            texture_set,
        );
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
                .{ .tint = .{ .r = 250, .g = 100, .b = 100, .a = 150 } },
                texture_set,
            );
        }
        if (maybe_selected_idx) |selected_idx| {
            if (raylib.IsKeyDown(raylib.KEY_X)) {
                var vision_set = world.fov(3, selected_idx);
                defer vision_set.deinit();

                for (vision_set.slice()) |index| {
                    render.renderTextureHex(index, world.grid, texture_set.base_textures[6], .{ .tint = .{ .r = 250, .g = 10, .b = 10, .a = 100 } }, texture_set);
                    if (world.terrain[index].attributes(world.rules).is_obscuring)
                        render.renderTextureHex(index, world.grid, texture_set.base_textures[6], .{ .tint = .{ .r = 0, .g = 0, .b = 200, .a = 50 } }, texture_set);
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
            }
        }

        raylib.EndMode2D();

        if (!hide_gui) {
            // TODO: CAPTURE MOUSE TO DISSALLOW MULTI CLICKS

            palet_window.renderUpdate();
            promotion_window.renderUpdate();

            unit_info_window.renderUpdate();
            city_construction_window.renderUpdate();
            edit_window.renderUpdate();

            resource_window.renderUpdate();

            hex_info_window.renderUpdate();
            view_window.renderUpdate();
        }
        raylib.EndDrawing();

        _ = camera.update(16.0);
    }
}
