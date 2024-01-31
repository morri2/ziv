const Rules = @import("../Rules.zig");
const Terrain = Rules.Terrain;
const Grid = @import("../Grid.zig");
const hex = @import("hex_util.zig");
const Idx = @import("../Grid.zig").Idx;
const World = @import("../World.zig");
const Unit = @import("../Unit.zig");
const TextureSet = @import("TextureSet.zig");
const std = @import("std");
const render = @import("render.zig");
const control = @import("control.zig");
const PlayerView = @import("../PlayerView.zig");
const Yield = @import("../yield.zig").Yield;
const BoundBox = @import("control.zig").BoundBox;
const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub fn renderWorld(world: *const World, cbb: *BoundBox, view: ?*const PlayerView, ts: TextureSet) void {
    renderTerrainLayer(world, cbb, view, ts);

    renderCities(world, cbb, ts);
    renderAllUnits(world, cbb, ts);
    renderAllYields(world, cbb, view, ts);

    renderAllResources(world, cbb, view, ts);
    renderTerraIncognita(world.grid, cbb, view, ts);
}

pub fn renderTerraIncognita(grid: Grid, cbb: *BoundBox, view: ?*const PlayerView, ts: TextureSet) void {
    if (view == null) return;
    cbb.restart();

    const FOV_COLOR = .{ .a = 90, .r = 150, .g = 150, .b = 150 };
    while (cbb.iterNext()) |idx| {
        switch (view.?.visability(idx)) {
            .fov => render.renderTextureHex(idx, grid, ts.smoke_texture, .{ .tint = FOV_COLOR }, ts),
            .hidden => render.renderTextureHex(idx, grid, ts.smoke_texture, .{}, ts),
            else => {},
        }
    }
}

const OUTLINE_COLOR = .{ .tint = .{ .a = 60, .r = 250, .g = 250, .b = 150 } };
/// For rendering all the shit in the tile, split up into sub function for when rendering from player persepectives
pub fn renderTerrainLayer(world: *const World, cbb: *BoundBox, view: ?*const PlayerView, ts: TextureSet) void {
    cbb.restart();
    while (cbb.iterNext()) |idx| {
        var terrain = world.terrain[idx];
        var improvement = world.improvements[idx];

        if (!(view == null)) {
            if (!(view.?.explored.contains(idx))) {
                // RENDER DENSE FOG
                continue;
            }
            if (view.?.in_view.contains(idx)) {
                terrain = view.?.last_seen_terrain[idx];
                improvement = view.?.last_seen_improvements[idx];
            }
        }

        renderTerrain(terrain, idx, world.grid, ts, world.rules);
        renderImprovements(improvement, idx, world.grid, ts);

        render.renderTextureInHex(
            idx,
            world.grid,
            ts.edge_textures[idx % 3],
            0,
            0,
            OUTLINE_COLOR,
            ts,
        );
    }
}

pub fn renderCities(world: *const World, cbb: *BoundBox, ts: TextureSet) void {
    for (world.cities.keys()) |idx| {
        if (!(cbb.contains(idx))) continue;

        const city = world.cities.get(idx) orelse unreachable;

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

        render.renderTextureInHex(
            idx,
            world.grid,
            ts.city_texture,
            0,
            0,
            .{},
            ts,
        );
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

pub fn renderAllYields(world: *const World, cbb: *BoundBox, view: ?*const PlayerView, ts: TextureSet) void {
    cbb.restart();
    while (cbb.iterNext()) |idx| {
        var yield = world.tileYield(idx);
        if (view != null) {
            switch (view.?.visability(idx)) {
                .fov => yield = view.?.last_seen_yields[idx],
                .hidden => continue,
                else => {},
            }
        }
        renderYield(yield, world.grid, idx, ts);
    }
}

pub fn renderYield(yield: Yield, grid: Grid, idx: Idx, ts: TextureSet) void {
    const fmt_args = .{ yield.production, yield.food, yield.gold };
    render.renderFormatHexAuto(idx, grid, "{}P  {}F  {}G", fmt_args, 0.0, 0.5, .{ .font_size = 6 }, ts);
}

pub fn renderAllUnits(world: *const World, cbb: *BoundBox, ts: TextureSet) void {
    var iter = world.units.iterator();
    while (iter.next()) |unit| {
        if (!cbb.contains(unit.idx)) continue;
        renderUnit(unit.unit, unit.idx, world.grid, ts);
    }
}

pub fn renderUnit(unit: Unit, idx: Idx, grid: Grid, ts: TextureSet) void {
    const icon = ts.unit_icons[@intFromEnum(unit.type)];
    render.renderTextureInHex(
        idx,
        grid,
        icon,
        0.0,
        0.0,
        .{ .scale = 0.4 },
        ts,
    );

    render.renderFormatHexAuto(
        idx,
        grid,
        "{}hp",
        .{unit.hit_points},
        0.0,
        -0.3,
        .{ .tint = raylib.YELLOW },
        ts,
    );

    render.renderFormatHexAuto(
        idx,
        grid,
        "{d:.0}",
        .{unit.movement},
        // TODO: FIX
        // .{ unit.movement, unit.maxMovement() },
        -0.2,
        0.2,
        .{ .tint = raylib.YELLOW, .font_size = 12 },
        ts,
    );
}

pub fn renderAllResources(world: *const World, cbb: *BoundBox, view: ?*const PlayerView, ts: TextureSet) void {
    for (world.resources.keys(), world.resources.values()) |idx, res| {
        if (!(cbb.contains(idx))) continue;
        if (view == null or view.?.visability(idx) == .hidden) continue;
        renderResource(res, idx, world.grid, ts);
    }
}

pub fn renderResource(res_and_amt: World.ResourceAndAmount, idx: Idx, grid: Grid, ts: TextureSet) void {
    const icon = ts.resource_icons[@intFromEnum(res_and_amt.type)];
    render.renderTextureInHex(idx, grid, icon, -0.4, -0.4, .{ .scale = 0.4 }, ts);

    if (res_and_amt.amount > 1) {
        render.renderFormatHexAuto(idx, grid, "x{}", .{res_and_amt.amount}, -0.2, -0.25, .{ .font_size = 14 }, ts);
    }
}

pub fn renderTerrain(terrain: Terrain, idx: Idx, grid: Grid, ts: TextureSet, rules: *const Rules) void {
    const base = terrain.base(rules);

    const base_texture = ts.base_textures[@intFromEnum(base)];
    render.renderTextureHex(idx, grid, base_texture, .{}, ts);

    const feature = terrain.feature(rules);
    if (feature != .none) {
        const feature_texture = ts.feature_textures[@intFromEnum(feature)];
        render.renderTextureHex(idx, grid, feature_texture, .{}, ts);
    }

    const vegetation = terrain.vegetation(rules);
    if (vegetation != .none) {
        const vegetation_texture = ts.vegetation_textures[@intFromEnum(vegetation)];
        render.renderTextureHex(idx, grid, vegetation_texture, .{}, ts);
    }
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
