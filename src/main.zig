const std = @import("std");
const Rules = @import("Rules.zig");

const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

const Game = @import("Game.zig");
const World = @import("World.zig");
const Unit = @import("Unit.zig");
const Units = @import("Units.zig");
const City = @import("City.zig");

const Camera = @import("rendering/Camera.zig");
const TextureSet = @import("rendering/TextureSet.zig");
const render = @import("rendering/render_util.zig");
const graphics = @import("rendering/graphics.zig");

const gui = @import("rendering/gui.zig");

const Socket = @import("Socket.zig");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

const clap = @import("clap");

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

    const clap_params = comptime clap.parseParamsComptime(
        \\-h, --help          Display this help and exit.
        \\-r, --rules <str>   Path to rules directory.
        \\-c, --client        Start as client.
        \\-h, --host <u8>  Start as host with x number of slots.
        \\
    );

    var clap_res = try clap.parse(clap.Help, &clap_params, clap.parsers.default, .{
        .allocator = gpa.allocator(),
    });
    defer clap_res.deinit();

    if (clap_res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &clap_params, .{});
    }

    var rules = blk: {
        var rules_dir = try std.fs.cwd().openDir(clap_res.args.rules orelse "base_rules", .{});
        defer rules_dir.close();
        break :blk try Rules.parse(rules_dir, gpa.allocator());
    };
    defer rules.deinit();

    var game = if (clap_res.args.client != 0) blk: {
        const socket = try Socket.connect(try std.net.Ip4Address.parse("127.0.0.1", 2000));
        errdefer socket.close();
        break :blk try Game.connect(
            socket,
            &rules,
            gpa.allocator(),
        );
    } else blk: {
        const connections = clap_res.args.host orelse 0;
        const socket = try Socket.create(2000);
        defer socket.close();
        const players = try gpa.allocator().alloc(Game.Player, connections);
        errdefer gpa.allocator().free(players);
        for (players, 1..) |*player, i| {
            player.socket = try socket.listenForConnection();
            player.civ_id = @enumFromInt(i);
        }
        break :blk try Game.host(
            56,
            36,
            true,
            @enumFromInt(0),
            2,
            players,
            &rules,
            gpa.allocator(),
        );
    };
    defer game.deinit();

    try game.world.loadFromFile("maps/last_saved.map");

    // UNITS
    try game.world.addUnit(1200, @enumFromInt(4), @enumFromInt(0));
    try game.world.addUnit(1202, @enumFromInt(2), @enumFromInt(0));
    try game.world.addUnit(1089, @enumFromInt(0), @enumFromInt(0));
    try game.world.addUnit(1205, @enumFromInt(3), @enumFromInt(0));
    try game.world.addUnit(1203, @enumFromInt(7), @enumFromInt(0));

    try game.world.addUnit(1150, @enumFromInt(7), @enumFromInt(1));
    try game.world.addUnit(1139, @enumFromInt(3), @enumFromInt(1));

    try game.world.addCity(1089, @enumFromInt(0));
    try game.world.addCity(485, @enumFromInt(1));

    game.world.fullUpdateViews();

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

    const ImprovementWindow = gui.SelectWindow(World.TileWork, .{
        .WIDTH = 600,
        .COLUMNS = 4,
        .ENTRY_HEIGHT = 50,
        .SPACEING = 2,
        .TEXTURE_ENTRY_FRACTION = 0.0,
    });

    var improvement_window: ImprovementWindow = ImprovementWindow.newEmpty();
    improvement_window.setName("Build improvement");

    improvement_window.bounds.y += 800;

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
        const pt = City.ProductionTarget{ .unit = ut };
        var buf: [255]u8 = undefined;
        const label = try std.fmt.bufPrint(&buf, "Build unit: {s}", .{ut.name(game.world.rules)});
        city_construction_window.addItem(pt, label);
    }

    var set_production_target: ?City.ProductionTarget = null;

    // MAIN GAME LOOP
    while (!raylib.WindowShouldClose()) {
        const bounding_box = camera.boundingBox(
            game.world.grid.width,
            game.world.grid.height,
            screen_width,
            screen_height,
            texture_set,
        );

        // ////////////// //
        // CONTROLL STUFF //
        // ////////////// //
        control_blk: {
            // SAVE MAP
            if (raylib.IsKeyPressed(raylib.KEY_C)) {
                try game.world.saveToFile("maps/last_saved.map");
                std.debug.print("\nMap saved (as 'maps/last_saved.map')!\n", .{});
            }

            if (raylib.IsKeyPressed(raylib.KEY_SPACE)) _ = try game.nextTurn();

            if (raylib.IsKeyPressed(raylib.KEY_R)) try game.world.recalculateWaterAccess();
            if (raylib.IsKeyPressed(raylib.KEY_H)) hide_gui = !hide_gui;

            if (raylib.IsKeyPressed(raylib.KEY_P)) game.nextPlayer();

            // GUI STUFF

            if (!hide_gui) {
                _ = edit_window.fetchSelected(&edit_mode);
                if (edit_mode != .draw) palet_window.hidden = true else palet_window.hidden = false;
                if (edit_mode != .resource) resource_window.hidden = true else resource_window.hidden = false;

                // Set unit promotions
                if (promotion_window.fetchSelectedNull(&set_promotion)) {
                    if (set_promotion) |promotion| if (maybe_unit_reference) |unit_ref| {
                        _ = try game.promoteUnit(unit_ref, promotion);
                    };
                }
                _ = palet_window.fetchSelectedNull(&terrain_brush);

                _ = city_construction_window.fetchSelectedNull(&set_production_target);
                // Set construction
                if (set_production_target) |production_target| {
                    if (maybe_selected_idx) |idx| {
                        if (game.world.cities.get(idx)) |city| {
                            if (city.faction_id == game.civ_id.toFactionID()) {
                                _ = try game.setCityProduction(idx, production_target);
                            }
                        }
                    }
                }
                set_production_target = null;

                // Set edit brush

                _ = resource_window.fetchSelectedNull(&resource_brush);

                _ = palet_window.fetchSelectedNull(&terrain_brush);

                // UPDATE UNIT INFO
                if (maybe_unit_reference) |ref| {
                    if (game.world.units.derefToPtr(ref)) |unit| {
                        unit_info_window.clear();

                        unit_info_window.addCategoryHeader("General");

                        unit_info_window.addLineFormat("HP: {}", .{unit.hit_points}, false);
                        unit_info_window.addLineFormat("Move: {d:.1}/{d:.1}", .{ unit.movement, unit.maxMovement(game.world.rules) }, false);
                        unit_info_window.addLineFormat("Faction id: {}", .{unit.faction_id}, false);
                        unit_info_window.addLineFormat("Fortified: {}", .{unit.fortified}, false);
                        unit_info_window.addLineFormat("Prepared: {}", .{unit.prepared}, false);

                        unit_info_window.addCategoryHeader("Promotions");
                        for (0..rules.promotion_count) |pi| {
                            unit_info_window.setName(unit.type.name(game.world.rules));
                            const p: Rules.Promotion = @enumFromInt(pi);

                            if (unit.promotions.isSet(pi)) {
                                unit_info_window.addLineFormat("{s}", .{p.name(game.world.rules)}, false);
                            }
                        }
                    }

                    // TODO when new selection

                    var maybe_work: ?World.TileWork = null;
                    if (improvement_window.fetchSelectedNull(&maybe_work)) {
                        if (maybe_work) |work| {
                            _ = try game.performAction(.{ .tile_work = .{ .unit = ref, .work = work } });
                        }
                    }
                }

                // UPDATE UNIT INFO
                if (maybe_selected_idx) |idx| {
                    const terrain = game.world.terrain[idx];
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
                if (improvement_window.checkMouseCapture()) break :control_blk;
            }

            // OLD SCHOOL CONTROL STUFF
            {
                // EDIT MAP STUFF
                const mouse_tile = camera.getMouseTile(game.world.grid, bounding_box, texture_set);
                if (raylib.IsKeyPressed(raylib.KEY_T)) {
                    const res = try game.world.resources.getOrPut(game.world.allocator, mouse_tile);
                    if (res.found_existing) res.value_ptr.amount = (res.value_ptr.amount % 12) + 1;
                }

                if (edit_mode == .draw and raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT) and terrain_brush != null) {
                    game.world.terrain[mouse_tile] = terrain_brush.?;
                }
                if (edit_mode == .resource and raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    if (resource_brush != null) try game.world.resources.put(game.world.allocator, mouse_tile, .{ .type = resource_brush.? }) else _ = game.world.resources.swapRemove(mouse_tile);
                }
                if (edit_mode == .rivers and raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    if (camera.getMouseEdge(game.world.grid, bounding_box, texture_set)) |e| {
                        if (game.world.rivers.contains(e)) {
                            _ = game.world.rivers.swapRemove(e);
                        } else {
                            game.world.rivers.put(game.world.allocator, e, {}) catch unreachable;
                        }
                    }
                }
            }

            // SELECTION
            if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                const mouse_idx = camera.getMouseTile(
                    game.world.grid,
                    bounding_box,
                    texture_set,
                );

                if (maybe_selected_idx) |selected_idx| {
                    if (selected_idx != mouse_idx) blk: {
                        if (maybe_unit_reference == null) {
                            maybe_unit_reference = game.world.units.firstReference(selected_idx);
                            if (maybe_unit_reference == null) {
                                maybe_selected_idx = mouse_idx;
                                maybe_unit_reference = game.world.units.firstReference(mouse_idx);
                                break :blk;
                            }
                        }

                        var attacked: bool = false;
                        if (game.world.units.firstReference(mouse_idx)) |ref| {
                            const unit = game.world.units.deref(ref) orelse unreachable;
                            if (unit.faction_id != game.civ_id.toFactionID()) {
                                _ = try game.attack(maybe_unit_reference.?, mouse_idx);
                                attacked = true;
                            }
                        }

                        if (!attacked) _ = try game.move(maybe_unit_reference.?, mouse_idx);

                        maybe_selected_idx = null;
                    } else if (maybe_unit_reference) |ref| {
                        maybe_unit_reference = game.world.units.nextReference(ref);
                    } else {
                        maybe_unit_reference = game.world.units.firstReference(selected_idx);
                    }
                } else {
                    maybe_selected_idx = mouse_idx;
                    maybe_unit_reference = game.world.units.firstReference(mouse_idx);
                }

                // BUILD IMPROVEMENTS MENU!
                if (maybe_unit_reference) |ref| {
                    improvement_window.clearItems();
                    if (game.world.canDoImprovementWork(ref, .remove_vegetation)) {
                        improvement_window.addItem(.remove_vegetation, "Clear Vegetation");
                    }
                    for (0..rules.building_count) |bi| {
                        const b: Rules.Building = @enumFromInt(bi);

                        if (game.world.canDoImprovementWork(ref, .{ .building = b })) {
                            var buf: [255]u8 = undefined;
                            const label = try std.fmt.bufPrint(&buf, "Build: \n {s}", .{b.name(&rules)});
                            improvement_window.addItem(.{ .building = b }, label);
                        } else if (game.world.canDoImprovementWork(ref, .{ .remove_vegetation_building = b })) {
                            var buf: [255]u8 = undefined;
                            const label = try std.fmt.bufPrint(&buf, "Clear & Build: \n {s}", .{b.name(&rules)});
                            improvement_window.addItem(.{ .remove_vegetation_building = b }, label);
                        }
                    }
                    if (game.world.canDoImprovementWork(ref, .{ .transport = .road }))
                        improvement_window.addItem(.{ .transport = .road }, "Transport: \n Road");
                    if (game.world.canDoImprovementWork(ref, .{ .transport = .rail }))
                        improvement_window.addItem(.{ .transport = .rail }, "Transport: \n Rail");
                }
            }

            if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_RIGHT)) {
                const clicked_tile = camera.getMouseTile(
                    game.world.grid,
                    bounding_box,
                    texture_set,
                );

                for (game.world.cities.keys(), game.world.cities.values()) |city_idx, *city| {
                    if (city_idx == clicked_tile) _ = city.expandBorder(&game.world);

                    if (try game.unsetWorked(city_idx, clicked_tile)) break;
                    if (try game.setWorked(city_idx, clicked_tile)) break;
                }
            }
        }
        // SETTLE CITY
        if (raylib.IsKeyPressed(raylib.KEY_B)) {
            if (maybe_unit_reference) |unit_ref| {
                _ = try game.settleCity(unit_ref);
            }
        }

        // ///////// //
        // RENDERING //
        // ///////// //
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        raylib.BeginMode2D(camera.camera);

        graphics.renderWorld(
            &game.world,
            bounding_box,
            game.getView(),
            camera.camera.zoom,
            maybe_unit_reference,
            texture_set,
        );
        if (maybe_selected_idx) |selected_idx| {
            if (raylib.IsKeyDown(raylib.KEY_M)) {
                for (bounding_box.x_min..bounding_box.x_max) |x| {
                    for (bounding_box.y_min..bounding_box.y_max) |y| {
                        const idx = game.world.grid.idxFromCoords(@intCast(x), @intCast(y));
                        render.renderFormatHexAuto(idx, game.world.grid, "{}", .{game.world.grid.distance(selected_idx, idx)}, 0.0, 0.0, .{ .font_size = 25 }, texture_set);
                    }
                }
            }

            render.renderTextureHex(
                selected_idx,
                game.world.grid,
                texture_set.edge_textures[0],
                .{ .tint = .{ .r = 250, .g = 100, .b = 100, .a = 150 } },
                texture_set,
            );
        }
        if (maybe_selected_idx) |selected_idx| {
            if (raylib.IsKeyDown(raylib.KEY_X)) {
                var vision_set = game.world.fov(3, selected_idx);
                defer vision_set.deinit();

                for (vision_set.slice()) |index| {
                    render.renderTextureHex(index, game.world.grid, texture_set.base_textures[6], .{ .tint = .{ .r = 250, .g = 10, .b = 10, .a = 100 } }, texture_set);
                    if (game.world.terrain[index].attributes(game.world.rules).is_obscuring)
                        render.renderTextureHex(index, game.world.grid, texture_set.base_textures[6], .{ .tint = .{ .r = 0, .g = 0, .b = 200, .a = 50 } }, texture_set);
                }
            }
            if (raylib.IsKeyDown(raylib.KEY_Z)) {
                for (bounding_box.x_min..bounding_box.x_max) |x| {
                    for (bounding_box.y_min..bounding_box.y_max) |y| {
                        const index = game.world.grid.idxFromCoords(@intCast(x), @intCast(y));
                        const xy = Grid.CoordXY.fromIdx(index, game.world.grid);
                        const qrs = Grid.CoordQRS.fromIdx(index, game.world.grid);

                        render.renderFormatHexAuto(index, game.world.grid, "idx: {}", .{index}, 0, -0.3, .{}, texture_set);
                        render.renderFormatHexAuto(index, game.world.grid, "(x{}, y{}) = {?}", .{ xy.x, xy.y, xy.toIdx(game.world.grid) }, 0, 0, .{ .font_size = 8 }, texture_set);
                        render.renderFormatHexAuto(index, game.world.grid, "(q{}, r{}) = {?}", .{ qrs.q, qrs.r, qrs.toIdx(game.world.grid) }, 0, 0.3, .{ .font_size = 8 }, texture_set);
                        if (maybe_selected_idx != null) render.renderFormatHexAuto(index, game.world.grid, "D:{}", .{game.world.grid.distance(index, maybe_selected_idx.?)}, 0, -0.5, .{}, texture_set);

                        const view = game.getView();

                        render.renderFormatHexAuto(index, game.world.grid, "view: {}", .{
                            view.in_view.hexes.get(index) orelse 0,
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

            improvement_window.renderUpdate();
        }
        raylib.EndDrawing();

        try game.update();

        _ = camera.update(16.0);
    }
}
