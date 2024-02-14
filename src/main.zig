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

const hex_set = @import("hex_set.zig");

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

    var game = if (clap_res.args.client != 0) blk: {
        const socket = try Socket.connect(try std.net.Ip4Address.parse("127.0.0.1", 2000));
        errdefer socket.close();
        break :blk try Game.connect(
            socket,
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

        const map_path = "maps/last_saved.map";
        var maybe_map_file: ?std.fs.File = map_blk: {
            break :map_blk std.fs.cwd().openFile(map_path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.print("Could not find map at: {s}\n", .{map_path});
                    break :map_blk null;
                },
                else => return err,
            };
        };
        defer if (maybe_map_file) |*map_file| map_file.close();

        var rules_dir = try std.fs.cwd().openDir(clap_res.args.rules orelse "base_rules", .{});
        defer rules_dir.close();

        break :blk try Game.host(
            if (maybe_map_file) |map_file| .{
                .new_load_terrain = map_file,
            } else .{
                .new = .{
                    .width = 56,
                    .height = 36,
                    .wrap_around = true,
                },
            },
            @enumFromInt(0),
            2,
            players,
            rules_dir,
            gpa.allocator(),
        );
    };
    defer game.deinit();

    if (game.is_host) {
        _ = try game.addUnit(1200, @enumFromInt(4), @enumFromInt(0));
        _ = try game.addUnit(1202, @enumFromInt(2), @enumFromInt(0));
        _ = try game.addUnit(1089, @enumFromInt(0), @enumFromInt(0));
        _ = try game.addUnit(1205, @enumFromInt(3), @enumFromInt(0));
        _ = try game.addUnit(1203, @enumFromInt(7), @enumFromInt(0));

        _ = try game.addUnit(1150, @enumFromInt(7), @enumFromInt(1));
        _ = try game.addUnit(1139, @enumFromInt(3), @enumFromInt(1));

        _ = try game.addCity(1089, @enumFromInt(0));
        _ = try game.addCity(485, @enumFromInt(1));
    }

    const screen_width = 1920;
    const screen_height = 1080;

    raylib.SetTraceLogLevel(raylib.LOG_WARNING);

    raylib.InitWindow(screen_width, screen_height, "ziv");
    defer raylib.CloseWindow();

    raylib.SetTargetFPS(60);

    var camera = Camera.init(screen_width, screen_height);

    var texture_set = try TextureSet.init(&game.rules, gpa.allocator());
    defer texture_set.deinit();

    var maybe_selected_idx: ?Idx = null;
    var maybe_unit_reference: ?Units.Reference = null;

    // MAP EDIT MODE

    const EditMode = enum {
        none,
        draw,
        river,
        resource,
    };

    var hide_gui = false;

    const EditWindow = gui.SelectWindow("Select edit mode", EditMode, .{
        .width = 200,
        .columns = 4,
        .entry_height = 30,
        .spacing = 4,
        .nullable = .not_nullable,
    });

    var edit_window = EditWindow.newEmpty(true, .none);
    inline for (@typeInfo(EditMode).Enum.fields) |field| {
        edit_window.addItem(@enumFromInt(field.value), field.name);
    }

    const ImprovementWindow = gui.SelectWindow("Build improvement", World.TileWork, .{
        .width = 600,
        .columns = 4,
        .entry_height = 50,
        .spacing = 2,
        .texture_entry_fraction = 0.0,
        .keep_highlight = false,
        .nullable = .null_option,
    });

    var improvement_window = ImprovementWindow.newEmpty(true, null);
    improvement_window.bounds.y += 800;

    const TerrainWindow = gui.SelectWindow("Pick terrain", Rules.Terrain, .{
        .width = 400,
        .columns = 5,
        .entry_height = 50,
        .spacing = 2,
        .texture_entry_fraction = 0.6,
        .nullable = .null_option,
    });

    var terrain_window = TerrainWindow.newEmpty(true, null);
    for (0..game.rules.terrain_count) |ti| {
        const t: Rules.Terrain = @enumFromInt(ti);
        if (t.attributes(&game.rules).has_freshwater or t.attributes(&game.rules).has_river) continue;
        terrain_window.addItemTexture(
            t,
            t.name(&game.rules),
            texture_set.terrain_textures[ti],
        );
    }

    const ResourceWindow = gui.SelectWindow("Select resource", Rules.Resource, .{
        .width = 400,
        .columns = 5,
        .entry_height = 50,
        .spacing = 2,
        .texture_entry_fraction = 0.6,
        .nullable = .null_option,
    });

    var resource_window = ResourceWindow.newEmpty(true, null);
    for (0..game.rules.resource_count) |ri| {
        const r: Rules.Resource = @enumFromInt(ri);

        resource_window.addItemTexture(
            r,
            r.name(&game.rules),
            texture_set.resource_icons[ri],
        );
    }

    const PromotionWindow = gui.SelectWindow("Add promotion", Rules.Promotion, .{
        .width = 150,
        .columns = 1,
        .entry_height = 25,
        .keep_highlight = false,
        .spacing = 2,
    });

    var promotion_window = PromotionWindow.newEmpty(true, null);
    for (0..game.rules.promotion_count) |pi| {
        const p = @as(Rules.Promotion, @enumFromInt(pi));

        promotion_window.addItem(p, p.name(&game.rules));
    }
    promotion_window.bounds.y += 50;

    const CityConstructionWindow = gui.SelectWindow("Select unit to build in city", City.ProductionTarget, .{
        .width = 150,
        .columns = 1,
        .entry_height = 25,
        .keep_highlight = false,
        .spacing = 2,
    });

    var city_construction_window = CityConstructionWindow.newEmpty(true, null);
    city_construction_window.bounds.y += 150;

    for (0..game.rules.unit_type_count) |uti| {
        const ut: Rules.UnitType = @enumFromInt(uti);
        const pt = City.ProductionTarget{ .unit = ut };
        var buf: [255]u8 = undefined;
        const label = try std.fmt.bufPrint(&buf, "Build unit: {s}", .{ut.name(&game.rules)});
        city_construction_window.addItem(pt, label);
    }

    const UnitInfoWindow = gui.InfoWindow("Unit info", .{});

    var unit_info_window = UnitInfoWindow.newEmpty(true);
    unit_info_window.bounds.y += 100;
    unit_info_window.addLine("Select a unit to view info...");

    const TerrainInfoWindow = gui.InfoWindow("Terrain info", .{});

    var terrain_info_window = TerrainInfoWindow.newEmpty(true);
    terrain_info_window.bounds.y += 200;
    terrain_info_window.addLine("Select a hex to view info...");

    // MAIN GAME LOOP
    while (!raylib.WindowShouldClose()) {
        const bounding_box = camera.boundingBox(
            game.world.grid.width,
            game.world.grid.height,
            screen_width,
            screen_height,
            texture_set,
        );

        control_blk: {
            if (raylib.IsKeyPressed(raylib.KEY_C)) {
                var file = try std.fs.cwd().createFile("maps/last_saved.map", .{});
                defer file.close();
                try game.world.serializeTerrain(file.writer());
                std.debug.print("Map saved at 'maps/last_saved.map'\n", .{});
            }

            if (raylib.IsKeyPressed(raylib.KEY_SPACE)) _ = try game.nextTurn();

            if (raylib.IsKeyPressed(raylib.KEY_R)) try game.world.recalculateWaterAccess(&game.rules);
            if (raylib.IsKeyPressed(raylib.KEY_H)) hide_gui = !hide_gui;

            if (raylib.IsKeyPressed(raylib.KEY_P)) game.nextPlayer();

            if (!hide_gui) {
                // Set unit promotions
                if (promotion_window.getSelected()) |promotion| {
                    if (maybe_unit_reference) |unit_ref| {
                        _ = try game.promoteUnit(unit_ref, promotion);
                    }
                }

                // Set construction
                if (city_construction_window.getSelected()) |production_target| {
                    if (maybe_selected_idx) |idx| {
                        if (game.world.cities.get(idx)) |city| {
                            if (city.faction_id == game.civ_id.toFactionID()) {
                                _ = try game.setCityProduction(idx, production_target);
                            }
                        }
                    }
                }

                // UPDATE UNIT INFO
                if (maybe_unit_reference) |ref| {
                    if (game.world.units.derefToPtr(ref)) |unit| {
                        unit_info_window.clear();

                        unit_info_window.addCategoryHeader("General");
                        unit_info_window.addLineFormat("Type: {s}", .{unit.type.name(&game.rules)}, false);
                        unit_info_window.addLineFormat("HP: {}", .{unit.hit_points}, false);
                        unit_info_window.addLineFormat("Move: {d:.1}/{d:.1}", .{ unit.movement, unit.maxMovement(&game.rules) }, false);
                        unit_info_window.addLineFormat("Faction id: {}", .{unit.faction_id}, false);
                        unit_info_window.addLineFormat("Fortified: {}", .{unit.fortified}, false);
                        unit_info_window.addLineFormat("Prepared: {}", .{unit.prepared}, false);

                        unit_info_window.addCategoryHeader("Promotions");
                        for (0..game.rules.promotion_count) |pi| {
                            const p: Rules.Promotion = @enumFromInt(pi);

                            if (unit.promotions.isSet(pi)) {
                                unit_info_window.addLineFormat("{s}", .{p.name(&game.rules)}, false);
                            }
                        }
                    }

                    if (improvement_window.getSelected()) |work| _ = try game.tileWork(ref, work);
                }

                // UPDATE UNIT INFO
                if (maybe_selected_idx) |idx| {
                    const terrain = game.world.terrain[idx];
                    const attributes = terrain.attributes(&game.rules);
                    terrain_info_window.clear();

                    terrain_info_window.addCategoryHeader("Attributes");

                    terrain_info_window.addLineFormat("Freshwater: {}", .{attributes.has_freshwater}, false);
                    terrain_info_window.addLineFormat("River: {}", .{attributes.has_river}, false);
                }
            }

            // SETTLE CITY
            if (raylib.IsKeyPressed(raylib.KEY_B)) {
                if (maybe_unit_reference) |unit_ref| {
                    _ = try game.settleCity(unit_ref);
                }
            }

            const mouse_idx = camera.getMouseTile(
                game.world.grid,
                bounding_box,
                texture_set,
            );

            // Check capture
            if (unit_info_window.checkMouseCapture()) break :control_blk;
            if (terrain_info_window.checkMouseCapture()) break :control_blk;
            if (promotion_window.checkMouseCapture()) break :control_blk;
            if (city_construction_window.checkMouseCapture()) break :control_blk;
            if (edit_window.checkMouseCapture()) break :control_blk;
            if (improvement_window.checkMouseCapture()) break :control_blk;

            switch (edit_window.getSelected()) {
                .draw => if (terrain_window.checkMouseCapture()) break :control_blk,
                .resource => if (resource_window.checkMouseCapture()) break :control_blk,
                .none, .river => {},
            }

            if (raylib.IsKeyPressed(raylib.KEY_T)) {
                const res = try game.world.resources.getOrPut(game.world.allocator, mouse_idx);
                if (res.found_existing) res.value_ptr.amount = (res.value_ptr.amount % 12) + 1;
            }

            switch (edit_window.getSelected()) {
                .draw => if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT)) {
                    if (terrain_window.getSelected()) |terrain| game.world.terrain[mouse_idx] = terrain;
                },
                .resource => if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    if (resource_window.getSelected()) |resource|
                        try game.world.resources.put(game.world.allocator, mouse_idx, .{
                            .type = resource,
                        })
                    else
                        _ = game.world.resources.swapRemove(mouse_idx);
                },
                .river => if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                    if (camera.getMouseEdge(game.world.grid, bounding_box, texture_set)) |e| {
                        if (game.world.rivers.contains(e)) {
                            _ = game.world.rivers.swapRemove(e);
                        } else {
                            game.world.rivers.put(game.world.allocator, e, {}) catch unreachable;
                        }
                    }
                },
                .none => {},
            }
            if (edit_window.getSelected() != .none) break :control_blk;

            if (raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
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
                    if (game.world.canDoImprovementWork(ref, .remove_vegetation, &game.rules)) {
                        improvement_window.addItem(.remove_vegetation, "Clear Vegetation");
                    }
                    for (0..game.rules.building_count) |bi| {
                        const b: Rules.Building = @enumFromInt(bi);

                        if (game.world.canDoImprovementWork(ref, .{ .building = b }, &game.rules)) {
                            var buf: [255]u8 = undefined;
                            const label = try std.fmt.bufPrint(&buf, "Build: \n {s}", .{b.name(&game.rules)});
                            improvement_window.addItem(.{ .building = b }, label);
                        } else if (game.world.canDoImprovementWork(ref, .{ .remove_vegetation_building = b }, &game.rules)) {
                            var buf: [255]u8 = undefined;
                            const label = try std.fmt.bufPrint(&buf, "Clear & Build: \n {s}", .{b.name(&game.rules)});
                            improvement_window.addItem(.{ .remove_vegetation_building = b }, label);
                        }
                    }
                    if (game.world.canDoImprovementWork(ref, .{ .transport = .road }, &game.rules))
                        improvement_window.addItem(.{ .transport = .road }, "Transport: \n Road");
                    if (game.world.canDoImprovementWork(ref, .{ .transport = .rail }, &game.rules))
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
                    if (city_idx == clicked_tile) _ = try city.expandBorder(&game.world, &game.rules);

                    if (try game.unsetWorked(city_idx, clicked_tile)) |_| break;
                    if (try game.setWorked(city_idx, clicked_tile)) |_| break;
                }
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
            &game.rules,
        );

        if (maybe_selected_idx) |selected_idx| {
            render.renderTextureHex(
                selected_idx,
                game.world.grid,
                texture_set.edge_textures[0],
                .{ .tint = .{ .r = 250, .g = 100, .b = 100, .a = 150 } },
                texture_set,
            );

            if (raylib.IsKeyDown(raylib.KEY_M)) {
                for (bounding_box.x_min..bounding_box.x_max) |x| {
                    for (bounding_box.y_min..bounding_box.y_max) |y| {
                        const idx = game.world.grid.idxFromCoords(@intCast(x), @intCast(y));
                        render.renderFormatHexAuto(idx, game.world.grid, "{}", .{game.world.grid.distance(selected_idx, idx)}, 0.0, 0.0, .{ .font_size = 25 }, texture_set);
                    }
                }
            }

            if (raylib.IsKeyDown(raylib.KEY_X)) {
                var vision_set = hex_set.HexSet(0).init(gpa.allocator());
                defer vision_set.deinit();
                try game.world.fov(3, selected_idx, &vision_set, &game.rules);

                for (vision_set.indices()) |index| {
                    render.renderTextureHex(index, game.world.grid, texture_set.base_textures[6], .{ .tint = .{ .r = 250, .g = 10, .b = 10, .a = 100 } }, texture_set);
                    if (game.world.terrain[index].attributes(&game.rules).is_obscuring)
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
                        render.renderFormatHexAuto(index, game.world.grid, "D:{}", .{game.world.grid.distance(index, selected_idx)}, 0, -0.5, .{}, texture_set);

                        const view = game.getView();

                        render.renderFormatHexAuto(index, game.world.grid, "view: {}", .{
                            if (view.in_view.hexes.get(index)) |c| c + 1 else 0,
                        }, 0, 0.8, .{}, texture_set);
                    }
                }
            }
        }

        raylib.EndMode2D();

        if (!hide_gui) {
            var accept_input = true;

            edit_window.renderUpdate(accept_input);
            if (edit_window.checkMouseCapture()) accept_input = false;

            unit_info_window.renderUpdate(accept_input);
            if (unit_info_window.checkMouseCapture()) accept_input = false;

            terrain_info_window.renderUpdate(accept_input);
            if (terrain_info_window.checkMouseCapture()) accept_input = false;

            if (maybe_selected_idx) |selected_index| {
                if (game.world.cities.get(selected_index)) |city| if (city.faction_id == game.civ_id.toFactionID()) {
                    city_construction_window.renderUpdate(accept_input);
                    if (city_construction_window.checkMouseCapture()) accept_input = false;
                };
            }

            if (maybe_unit_reference) |ref| if (game.world.units.deref(ref)) |unit| {
                if (unit.faction_id == game.civ_id.toFactionID()) {
                    promotion_window.renderUpdate(accept_input);
                    if (promotion_window.checkMouseCapture()) accept_input = false;

                    improvement_window.renderUpdate(accept_input);
                    if (improvement_window.checkMouseCapture()) accept_input = false;
                }
            };

            switch (edit_window.getSelected()) {
                .none, .river => {},
                .draw => terrain_window.renderUpdate(accept_input),
                .resource => resource_window.renderUpdate(accept_input),
            }
        }
        raylib.EndDrawing();

        _ = try game.update();

        _ = camera.update(16.0);
    }
}
