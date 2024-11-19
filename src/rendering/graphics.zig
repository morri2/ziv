const std = @import("std");

const Rules = @import("../Rules.zig");
const Terrain = Rules.Terrain;
const Yield = Rules.Yield;

const Grid = @import("../Grid.zig");
const Idx = Grid.Idx;

const World = @import("../World.zig");
const Unit = @import("../Unit.zig");
const Units = @import("../Units.zig");
const View = @import("../View.zig");

const TextureSet = @import("TextureSet.zig");

const render = @import("render_util.zig");

const Camera = @import("Camera.zig");
const BoundingBox = Camera.BoundingBox;

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub fn renderWorld(
    world: *const World,
    bbox: BoundingBox,
    maybe_view: ?*const View,
    zoom: f32,
    maybe_unit_reference: ?Units.Reference,
    ts: TextureSet,
    rules: *const Rules,
) void {
    renderTerrainLayer(world, bbox, maybe_view, ts, rules);
    renderTerraIncognita(world.grid, bbox, maybe_view, ts);

    renderCities(world, bbox, maybe_view, ts);
    renderUnits(world, bbox, maybe_view, maybe_unit_reference, zoom, ts);
    renderYields(world, bbox, maybe_view, ts, rules);

    renderResources(world, bbox, maybe_view, ts);
}

pub fn renderTerraIncognita(grid: Grid, bbox: BoundingBox, maybe_view: ?*const View, ts: TextureSet) void {
    const view = maybe_view orelse return;

    const fow_color = .{ .a = 90, .r = 150, .g = 150, .b = 150 };
    for (bbox.x_min..bbox.x_max) |x| {
        for (bbox.y_min..bbox.y_max) |y| {
            const idx = grid.idxFromCoords(@intCast(x), @intCast(y));
            switch (view.visibility(idx)) {
                .fov => render.renderTextureHex(idx, grid, ts.fog, .{ .tint = fow_color }, ts),
                .hidden => render.renderTextureHex(idx, grid, ts.fog, .{}, ts),
                else => {},
            }
        }
    }
}

/// For rendering all the shit in the tile, split up into sub function for when rendering from player persepectives
pub fn renderTerrainLayer(world: *const World, bbox: BoundingBox, maybe_view: ?*const View, ts: TextureSet, rules: *const Rules) void {
    const outline_color = .{ .tint = .{ .a = 60, .r = 250, .g = 250, .b = 150 } };
    for (bbox.y_min..bbox.y_max) |y| {
        for (bbox.x_min..bbox.x_max) |x| {
            const idx = world.grid.idxFromCoords(@intCast(x), @intCast(y));

            var terrain = world.terrain[idx];
            var improvement = world.improvements[idx];

            if (maybe_view) |view| {
                if (!view.explored.contains(idx)) continue;

                terrain = view.viewTerrain(idx, world) orelse unreachable;
                improvement = view.viewImprovements(idx, world) orelse unreachable;
            }

            renderTerrain(terrain, idx, world.grid, ts, rules);

            if (improvement.transport != .none) {
                var flag = false;
                for (world.grid.neighbours(idx), 0..) |maybe_n_idx, i| if (maybe_n_idx) |n_idx| {
                    if (world.improvements[n_idx].transport != .none or world.cities.contains(n_idx)) {
                        render.renderTextureInHex(idx, world.grid, ts.road_textures[i], 0, 0, .{}, ts);
                        flag = true;
                    }
                };
                if (!flag) {
                    render.renderTextureInHex(idx, world.grid, ts.road_textures[6], 0, 0, .{}, ts);
                }
            }

            renderImprovements(improvement, idx, world.grid, ts);

            render.renderTextureInHex(
                idx,
                world.grid,
                ts.edge,
                0,
                0,
                outline_color,
                ts,
            );

            if (world.work_in_progress.get(idx)) |wip| {
                const progress: f32 = @as(f32, @floatFromInt(wip.progress)) / 3.0;
                render.renderChargeCircleInHex(idx, world.grid, progress, 0.0, 0.6, .{ .bar_color = raylib.BLUE, .radius = 0.1 }, ts);
            }
        }
    }
    for (world.rivers.keys()) |edge| {
        const edge_dir = world.grid.edgeDirection(edge) orelse continue;
        const texture = ts.river_textures[@intFromEnum(edge_dir)];
        render.renderTextureInHex(edge.low, world.grid, texture, 0, 0, .{}, ts);
    }
}

pub fn renderCities(world: *const World, bbox: BoundingBox, maybe_view: ?*const View, ts: TextureSet) void {
    for (world.cities.keys(), world.cities.values()) |idx, city| {
        const x = world.grid.xFromIdx(idx);
        const y = world.grid.yFromIdx(idx);
        if (!bbox.contains(x, y)) continue;

        for (city.claimed.indices()) |claimed| {
            if (maybe_view) |view| if (!view.in_view.contains(claimed)) continue;
            render.renderTextureInHex(claimed, world.grid, ts.city_border, 0, 0, .{
                .tint = ts.player_primary_color[@intFromEnum(city.faction_id)],
                .scale = 0.95,
            }, ts);

            if (city.worked.contains(claimed)) {
                render.renderTextureInHex(claimed, world.grid, ts.green_pop, -0.5, -0.5, .{
                    .scale = 0.15,
                }, ts);
            }
        }

        if (maybe_view) |view| if (!view.in_view.contains(idx)) return;

        render.renderTextureInHex(idx, world.grid, ts.city_border, 0, 0, .{
            .tint = ts.player_primary_color[@intFromEnum(city.faction_id)],
            .scale = 0.95,
        }, ts);

        const city_texture = ts.city_textures[@min(ts.city_textures.len - 1, city.population / 2)];

        render.renderTextureInHex(idx, world.grid, city_texture, 0, 0, .{}, ts);
        const off = render.renderTextureInHexSeries(
            idx,
            world.grid,
            ts.green_pop,
            city.unassignedPopulation(),
            -0.6,
            -0.5,
            0.00,
            .{ .scale = 0.15 },
            ts,
        );

        _ = render.renderTextureInHexSeries(
            idx,
            world.grid,
            ts.red_pop,
            city.population -| city.unassignedPopulation(),
            off,
            -0.5,
            0.00,
            .{ .scale = 0.15 },
            ts,
        );

        render.renderFormatHexAuto(
            idx,
            world.grid,
            "{s} ({})",
            .{ city.name, city.population },
            0.0,
            -0.85,
            .{ .font_size = 14 },
            ts,
        );

        render.renderChargeCircleInHex(
            idx,
            world.grid,
            city.food_stockpile / city.foodTilGrowth(),
            0.0,
            0.6,
            .{ .radius = 0.1 },
            ts,
        );

        render.renderFormatHexAuto(
            idx,
            world.grid,
            "{d:.0}/{d:.0}",
            .{ city.food_stockpile, city.foodTilGrowth() },
            0.9,
            -0.55,
            .{ .font_size = 8, .anchor = .right },
            ts,
        );

        if (city.current_production_project) |project| {
            const production_percentage = project.progress / project.production_needed;

            //TODO fix Perpetual icons and Building
            const icon = switch (project.project) {
                .unit => |unit_type| ts.unit_symbols[@intFromEnum(unit_type)],
                .building => unreachable,
                .perpetual_money => unreachable,
                .perpetual_research => unreachable,
            };

            render.renderChargeCircleInHex(
                idx,
                world.grid,
                production_percentage,
                0.5,
                -0.6,
                .{ .radius = 0.15 },
                ts,
            );

            render.renderTextureInHex(
                idx,
                world.grid,
                icon,
                0.5,
                -0.6,
                .{ .scale = 0.05 },
                ts,
            );
        }
    }
}

pub fn renderYields(world: *const World, bbox: BoundingBox, maybe_view: ?*const View, ts: TextureSet, rules: *const Rules) void {
    for (bbox.x_min..bbox.x_max) |x| {
        for (bbox.y_min..bbox.y_max) |y| {
            const idx = world.grid.idxFromCoords(@intCast(x), @intCast(y));

            var yield = world.tileYield(idx, rules);
            if (maybe_view) |view| {
                switch (view.visibility(idx)) {
                    .fov => yield = view.last_seen_yields[idx],
                    .hidden => continue,
                    else => {},
                }
            }

            var yield_textures: [8]raylib.Texture2D = undefined;

            var yield_type_count: u8 = 0;

            if (yield.food > 0) {
                yield_textures[yield_type_count] = ts.food_yield_icons[yield.food];
                yield_type_count += 1;
            }
            if (yield.production > 0) {
                yield_textures[yield_type_count] = ts.production_yield_icons[yield.production];
                yield_type_count += 1;
            }
            if (yield.gold > 0) {
                yield_textures[yield_type_count] = ts.gold_yield_icons[yield.gold];
                yield_type_count += 1;
            }

            // if (yield.culture> 0) {
            //     yield_textures[yield_type_count] = ts.culture_yield_icons[yield.culture];
            //     yield_type_count += 1;
            // }

            const x_step: f32 = 0.35;
            const x_start: f32 = -(x_step * (@as(f32, @floatFromInt(yield_type_count)) - 1.0) / 2.0);

            for (0..yield_type_count) |i| {
                render.renderTextureInHex(idx, world.grid, yield_textures[i], x_start + x_step * @as(f32, @floatFromInt(i)), 0.5, .{ .scale = 0.075 }, ts);
            }
        }
    }
}

pub fn renderUnits(
    world: *const World,
    bbox: BoundingBox,
    view: ?*const View,
    maybe_unit_reference: ?Units.Reference,
    zoom: f32,
    ts: TextureSet,
) void {
    var iter = world.units.iterator();
    while (iter.next()) |entry| {
        const in_view = if (view) |v| v.in_view.contains(entry.idx) else true;
        if (!in_view) continue;
        if (!bbox.containsIdx(entry.idx, world.grid)) continue;

        const is_selected = if (maybe_unit_reference) |reference|
            reference.idx == entry.idx and
                reference.slot == entry.slot and
                reference.stacked == entry.stacked
        else
            false;

        renderUnit(entry.idx, world.grid, entry.unit, .{
            .slot = entry.slot,
            .faction_id = entry.unit.faction_id,
            .stack = entry.depth,
            .zoom = zoom,
            .glow = is_selected,
        }, ts);
    }
}

pub const RenderUnitContext = struct {
    slot: Units.Slot,
    faction_id: World.FactionID,
    stack: u8 = 0,
    glow: bool = false,
    exausted: bool = false,
    zoom: f32 = 1.0,
};

const ZOOM_MAX_SCALE = 0.2;
const ZOOM_MIN_SCALE = 0.1;
const ZOOM_FACTOR = 0.2;
pub fn renderUnit(idx: Idx, grid: Grid, unit: Unit, context: RenderUnitContext, ts: TextureSet) void {
    const back_texture = ts.unit_slot_frame_back[@intFromEnum(context.slot)];
    const line_texture = ts.unit_slot_frame_line[@intFromEnum(context.slot)];
    const glow_texture = ts.unit_slot_frame_glow[@intFromEnum(context.slot)];
    const unit_symbol = ts.unit_symbols[@intFromEnum(unit.type)];

    var off_y: f32 = -0.1 * @as(f32, @floatFromInt(context.stack));
    const off_x: f32 = 0.1 * @as(f32, @floatFromInt(context.stack));

    switch (context.slot) {
        .civilian_land, .civilian_sea => off_y -= 0.7,
        .military_land, .military_sea => off_y -= 0.3,
        .embarked => off_y -= 0.5,
        .trade => off_y -= 1.0,
    }

    const bg_color: raylib.Color = ts.player_primary_color[@intFromEnum(context.faction_id)];
    const fg_color: raylib.Color = ts.player_secondary_color[@intFromEnum(context.faction_id)];
    const glow_color = raylib.YELLOW;
    const scale: f32 = @max(ZOOM_MIN_SCALE, @min(ZOOM_MAX_SCALE, ZOOM_FACTOR * 1 / context.zoom));
    if (context.glow) render.renderTextureInHex(idx, grid, glow_texture, off_x, off_y, .{ .tint = glow_color, .scale = scale }, ts);
    render.renderTextureInHex(idx, grid, back_texture, off_x, off_y, .{ .tint = bg_color, .scale = scale }, ts);
    render.renderTextureInHex(idx, grid, line_texture, off_x, off_y, .{ .tint = fg_color, .scale = scale }, ts);
    render.renderTextureInHex(idx, grid, unit_symbol, off_x, off_y, .{ .tint = fg_color, .scale = scale * 0.5 }, ts);

    render.renderFormatHexAuto(idx, grid, "{d:.0}", .{
        unit.hit_points,
    }, off_x + 0.2, off_y - 0.1, .{ .tint = raylib.WHITE, .font_size = 8 }, ts);

    render.renderFormatHexAuto(idx, grid, "{d:.0}", .{
        unit.movement,
    }, off_x + 0.2, off_y + 0.1, .{ .tint = raylib.WHITE, .font_size = 8 }, ts);
}

pub fn renderResources(world: *const World, bbox: BoundingBox, maybe_view: ?*const View, ts: TextureSet) void {
    for (world.resources.keys(), world.resources.values()) |idx, res| {
        const x = world.grid.xFromIdx(idx);
        const y = world.grid.yFromIdx(idx);
        if (!bbox.contains(x, y)) continue;

        if (maybe_view) |view| {
            if (view.visibility(idx) == .hidden) continue;
        }

        const icon = ts.resource_icons[@intFromEnum(res.type)];
        render.renderTextureInHex(idx, world.grid, icon, 0.5, -0.4, .{ .scale = 0.6 }, ts);

        if (res.amount > 1) render.renderFormatHexAuto(
            idx,
            world.grid,
            "x{}",
            .{res.amount},
            0.2,
            -0.25,
            .{ .font_size = 10 },
            ts,
        );
    }
}

pub fn renderTerrain(terrain: Terrain, idx: Idx, grid: Grid, ts: TextureSet, rules: *const Rules) void {
    _ = rules;
    const terrain_texture = ts.terrain_textures[@intFromEnum(terrain)];
    render.renderTextureHex(idx, grid, terrain_texture, .{}, ts);

    // OLD LAYER RENDERING
    //const base = terrain.base(rules);

    // const base_texture = ts.base_textures[@intFromEnum(base)];
    // render.renderTextureHex(idx, grid, base_texture, .{}, ts);

    // const feature = terrain.feature(rules);
    // if (feature != .none) {
    //     const feature_texture = ts.feature_textures[@intFromEnum(feature)];
    //     render.renderTextureHex(idx, grid, feature_texture, .{}, ts);
    // }

    // const vegetation = terrain.vegetation(rules);
    // if (vegetation != .none) {
    //     const vegetation_texture = ts.vegetation_textures[@intFromEnum(vegetation)];
    //     render.renderTextureHex(idx, grid, vegetation_texture, .{}, ts);
    // }
}

pub fn renderImprovements(improvement: Rules.Improvements, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    if (improvement.building != .none) {
        const improvement_texture = ts.improvement_textures[@intFromEnum(improvement.building)];
        render.renderTextureHex(tile_idx, grid, improvement_texture, .{}, ts);
    }
}
