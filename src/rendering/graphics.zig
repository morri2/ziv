const std = @import("std");

const Rules = @import("../Rules.zig");
const Terrain = Rules.Terrain;
const Yield = Rules.Yield;

const Grid = @import("../Grid.zig");
const Idx = Grid.Idx;

const World = @import("../World.zig");
const Unit = @import("../Unit.zig");
const PlayerView = @import("../PlayerView.zig");

const TextureSet = @import("TextureSet.zig");

const render = @import("render_util.zig");

const Camera = @import("Camera.zig");
const BoundingBox = Camera.BoundingBox;

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub fn renderWorld(world: *const World, bbox: BoundingBox, maybe_view: ?*const PlayerView, ts: TextureSet) void {
    renderTerrainLayer(world, bbox, maybe_view, ts);

    renderCities(world, bbox, ts);
    renderUnits(world, bbox, ts);
    renderYields(world, bbox, maybe_view, ts);

    renderResources(world, bbox, maybe_view, ts);
    renderTerraIncognita(world.grid, bbox, maybe_view, ts);
}

pub fn renderTerraIncognita(grid: Grid, bbox: BoundingBox, maybe_view: ?*const PlayerView, ts: TextureSet) void {
    if (maybe_view == null) return;

    const fow_color = .{ .a = 90, .r = 150, .g = 150, .b = 150 };
    for (bbox.x_min..bbox.x_max) |x| {
        for (bbox.y_min..bbox.y_max) |y| {
            const idx = grid.idxFromCoords(@intCast(x), @intCast(y));
            switch (maybe_view.?.visability(idx)) {
                .fov => render.renderTextureHex(idx, grid, ts.smoke_texture, .{ .tint = fow_color }, ts),
                .hidden => render.renderTextureHex(idx, grid, ts.smoke_texture, .{}, ts),
                else => {},
            }
        }
    }
}

/// For rendering all the shit in the tile, split up into sub function for when rendering from player persepectives
pub fn renderTerrainLayer(world: *const World, bbox: BoundingBox, maybe_view: ?*const PlayerView, ts: TextureSet) void {
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

            renderTerrain(terrain, idx, world.grid, ts, world.rules);
            renderImprovements(improvement, idx, world.grid, ts);

            render.renderTextureInHex(
                idx,
                world.grid,
                ts.edge_textures[idx % 3],
                0,
                0,
                outline_color,
                ts,
            );
        }
    }
    for (world.rivers.keys()) |edge| {
        const edge_dir = world.grid.edgeDirection(edge) orelse continue;
        const texture = ts.river_textures[@intFromEnum(edge_dir)];
        render.renderTextureInHex(edge.low, world.grid, texture, 0, 0, .{}, ts);
    }
}

pub fn renderCities(world: *const World, bbox: BoundingBox, ts: TextureSet) void {
    for (world.cities.keys(), world.cities.values()) |idx, city| {
        const x = world.grid.xFromIdx(idx);
        const y = world.grid.yFromIdx(idx);
        if (!bbox.contains(x, y)) continue;

        for (city.claimed.slice()) |claimed| {
            render.renderTextureInHex(claimed, world.grid, ts.city_border_texture, 0, 0, .{
                .tint = .{ .r = 250, .g = 50, .b = 50, .a = 180 },
                .scale = 0.95,
            }, ts);

            if (city.worked.contains(claimed)) {
                render.renderTextureInHex(claimed, world.grid, ts.green_pop, -0.5, -0.5, .{
                    .scale = 0.15,
                }, ts);
            }
        }

        render.renderTextureInHex(idx, world.grid, ts.city_border_texture, 0, 0, .{
            .tint = .{ .r = 250, .g = 50, .b = 50, .a = 180 },
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
                .UnitType => ts.unit_icons[@intFromEnum(project.project.UnitType)],
                .Perpetual => unreachable,
                .Building => unreachable,
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
                .{ .scale = 0.15 },
                ts,
            );
        }
    }
}

pub fn renderYields(world: *const World, bbox: BoundingBox, maybe_view: ?*const PlayerView, ts: TextureSet) void {
    for (bbox.x_min..bbox.x_max) |x| {
        for (bbox.y_min..bbox.y_max) |y| {
            const idx = world.grid.idxFromCoords(@intCast(x), @intCast(y));

            var yield = world.tileYield(idx);
            if (maybe_view) |view| {
                switch (view.visability(idx)) {
                    .fov => yield = view.last_seen_yields[idx],
                    .hidden => continue,
                    else => {},
                }
            }
            const fmt_args = .{ yield.production, yield.food, yield.gold };
            render.renderFormatHexAuto(idx, world.grid, "{}P  {}F  {}G", fmt_args, 0.0, 0.5, .{ .font_size = 6 }, ts);
        }
    }
}

pub fn renderUnits(world: *const World, bbox: BoundingBox, ts: TextureSet) void {
    var iter = world.units.iterator();
    while (iter.next()) |unit| {
        const x = world.grid.xFromIdx(unit.idx);
        const y = world.grid.yFromIdx(unit.idx);
        if (!bbox.contains(x, y)) continue;
        const icon = ts.unit_icons[@intFromEnum(unit.unit.type)];
        render.renderTextureInHex(
            unit.idx,
            world.grid,
            icon,
            0.0,
            0.0,
            .{ .scale = 0.4 },
            ts,
        );

        render.renderFormatHexAuto(
            unit.idx,
            world.grid,
            "{}hp",
            .{unit.unit.hit_points},
            0.0,
            -0.3,
            .{ .tint = raylib.YELLOW },
            ts,
        );

        render.renderFormatHexAuto(
            unit.idx,
            world.grid,
            "{d:.0}",
            .{unit.unit.movement},
            // TODO: FIX
            // .{ unit.movement, unit.maxMovement() },
            -0.2,
            0.2,
            .{ .tint = raylib.YELLOW, .font_size = 12 },
            ts,
        );
    }
}

pub fn renderResources(world: *const World, bbox: BoundingBox, maybe_view: ?*const PlayerView, ts: TextureSet) void {
    for (world.resources.keys(), world.resources.values()) |idx, res| {
        const x = world.grid.xFromIdx(idx);
        const y = world.grid.yFromIdx(idx);
        if (!bbox.contains(x, y)) continue;

        if (maybe_view) |view| {
            if (view.visability(idx) == .hidden) continue;
        } else continue;

        const icon = ts.resource_icons[@intFromEnum(res.type)];
        render.renderTextureInHex(idx, world.grid, icon, -0.5, -0.4, .{ .scale = 0.6 }, ts);

        if (res.amount > 1) render.renderFormatHexAuto(
            idx,
            world.grid,
            "x{}",
            .{res.amount},
            -0.2,
            -0.25,
            .{ .font_size = 14 },
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

    if (improvement.transport != .none) {
        // PLACEHOLDER!
        render.renderTextureHex(tile_idx, grid, ts.transport_textures[0], .{ .scale = 0.1 }, ts);
    }
}
