const Rules = @import("../Rules.zig");
const Terrain = Rules.Terrain;
const Grid = @import("../Grid.zig");
const hex = @import("hex_util.zig");
const Idx = @import("../Grid.zig").Idx;
const World = @import("../World.zig");
const Unit = @import("../Unit.zig");
const TextureSet = @import("TextureSet.zig");
const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub const RenderTextureArgs = struct {
    scale: f32 = 1.0,
    rotation: f32 = 0.0, // unstable? might fuck up with anything other than top_left
    tint: raylib.Color = raylib.WHITE,
    anchor: Anchor = .center,
};

pub const RenderTextArgs = struct {
    font: ?raylib.Font = null, // null -> ts default font
    font_size: f32 = 10,
    spaceing: f32 = 0.0,
    rotation: f32 = 0.0, // unstable? might fuck up with anything other than left anchor
    tint: raylib.Color = raylib.WHITE,
    anchor: Anchor = .center,
};

pub const CircleBarArgs = struct {
    bar_part: f32 = 0.2,
    radius: f32 = 0.2,
    anchor: Anchor = .center,
    bar_color: raylib.Color = raylib.GREEN,
    center_color: raylib.Color = raylib.GRAY,
};

pub const Anchor = enum {
    top_left,
    top_right,
    top_center,
    right,
    left,
    center,
    bottom_left,
    bottom_right,
    bottom_center,

    pub fn getOffset(self: @This(), width: f32, height: f32) raylib.Vector2 {
        const x: f32 = switch (self) {
            .top_left, .left, .bottom_left => -width / 2,
            .top_right, .right, .bottom_right => width / 2,
            else => 0.0,
        };

        const y: f32 = switch (self) {
            .top_left, .top_center, .top_right => -height / 2,
            .bottom_left, .bottom_center, .bottom_right => height / 2,
            else => 0.0,
        };

        return .{ .x = x, .y = y };
    }

    pub fn getOffsetRelative(self: @This(), width: f32, height: f32, ref: @This()) raylib.Vector2 {
        return raylib.Vector2Subtract(
            self.getOffset(width, height),
            ref.getOffset(width, height),
        );
    }
};

pub fn renderYields(world: *World, tile_idx: Idx, ts: TextureSet) void {
    const yields = world.tileYield(tile_idx);
    renderFormatHexAuto(
        tile_idx,
        world.grid,
        "{}P  {}F  {}G",
        .{ yields.production, yields.food, yields.gold },
        0.0,
        0.5,
        .{},
        ts,
    );
}

pub fn renderCities(world: *World, ts: TextureSet) void {
    for (world.cities.keys()) |key| {
        const city = world.cities.get(key) orelse unreachable;

        for (city.claimed.slice()) |claimed| {
            renderTextureInHex(claimed, world.grid, ts.city_border_texture, 0, 0, .{
                .tint = .{ .r = 250, .g = 50, .b = 50, .a = 180 },
                .scale = 0.95,
            }, ts);

            if (city.worked.contains(claimed)) {
                renderTextureInHex(claimed, world.grid, ts.green_pop, -0.5, -0.5, .{
                    .scale = 0.15,
                }, ts);
            }
        }

        renderTextureInHex(key, world.grid, ts.city_border_texture, 0, 0, .{
            .tint = .{ .r = 250, .g = 50, .b = 50, .a = 180 },
            .scale = 0.95,
        }, ts);

        renderTextureInHex(
            key,
            world.grid,
            ts.city_texture,
            0,
            0,
            .{},
            ts,
        );
        const off = renderTextureInHexSeries(
            key,
            world.grid,
            ts.green_pop,
            city.unassignedPopulation(),
            -0.6,
            -0.5,
            0.00,
            .{ .scale = 0.15 },
            ts,
        );

        _ = renderTextureInHexSeries(
            key,
            world.grid,
            ts.red_pop,
            city.population -| city.unassignedPopulation(),
            off,
            -0.5,
            0.00,
            .{ .scale = 0.15 },
            ts,
        );

        renderFormatHexAuto(
            key,
            world.grid,
            "{s} ({})",
            .{ city.name, city.population },
            0.0,
            -0.85,
            .{ .font_size = 14 },
            ts,
        );

        renderChargeCircleInHex(key, world.grid, 0.8, 0.4, -0.6, .{}, ts);

        renderFormatHexAuto(
            key,
            world.grid,
            "{d:.0}/{d:.0}",
            .{ city.food_stockpile, city.foodTilGrowth() },
            0.9,
            -0.55,
            .{ .font_size = 8, .anchor = .right },
            ts,
        );
    }
}

pub fn renderAllUnits(world: *World, ts: TextureSet) void {
    for (world.unit_map.units.keys()) |key| {
        const unit = world.unit_map.units.get(key) orelse unreachable;
        renderUnit(unit, key.idx, world.grid, ts);
    }
}

pub fn renderUnit(unit: Unit, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    renderTextureInHex(
        tile_idx,
        grid,
        ts.unit_icons[@intFromEnum(unit.type)],
        0.0,
        0.0,
        .{ .scale = 0.4 },
        ts,
    );

    renderFormatHexAuto(
        tile_idx,
        grid,
        "{}hp",
        .{unit.hit_points},
        0.0,
        -0.3,
        .{ .tint = raylib.YELLOW },
        ts,
    );

    renderFormatHexAuto(
        tile_idx,
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

/// For rendering all the shit in the tile, split up into sub function for when rendering from player persepectives
pub fn renderTile(world: World, tile_idx: Idx, grid: Grid, ts: TextureSet, rules: *const Rules) void {
    renderTerrain(world.terrain[tile_idx], tile_idx, grid, ts, rules);
    renderTextureInHex(tile_idx, grid, ts.edge_textures[tile_idx % 3], 0, 0, .{ .tint = .{
        .a = 60,
        .r = 250,
        .g = 250,
        .b = 150,
    } }, ts);

    renderImprovement(world.improvements[tile_idx], tile_idx, grid, ts);

    const resource = world.resources.get(tile_idx);
    if (resource != null) renderResource(resource.?, tile_idx, world.grid, ts);
}

pub fn renderTerrain(terrain: Terrain, tile_idx: Idx, grid: Grid, ts: TextureSet, rules: *const Rules) void {
    const base = terrain.base(rules);
    renderTextureHex(
        tile_idx,
        grid,
        ts.base_textures[@intFromEnum(base)],
        .{},
        ts,
    );

    const feature = terrain.feature(rules);
    if (feature != .none) {
        renderTextureHex(
            tile_idx,
            grid,
            ts.feature_textures[@intFromEnum(feature)],
            .{},
            ts,
        );
    }

    const vegetation = terrain.vegetation(rules);
    if (vegetation != .none) {
        renderTextureHex(
            tile_idx,
            grid,
            ts.vegetation_textures[@intFromEnum(vegetation)],
            .{},
            ts,
        );
    }
}

pub fn renderImprovement(improvement: Rules.Improvements, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    if (improvement.building != .none) {
        renderTextureHex(
            tile_idx,
            grid,
            ts.improvement_textures[@intFromEnum(improvement.building)],
            .{},
            ts,
        );
    }

    if (improvement.transport != .none) {
        // PLACEHOLDER!
        renderTextureHex(tile_idx, grid, ts.feature_textures[3], .{}, ts);
    }
}

pub fn renderResource(res_and_amt: World.ResourceAndAmount, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    renderTextureInHex(
        tile_idx,
        grid,
        ts.resource_icons[@intFromEnum(res_and_amt.type)],
        -0.4,
        -0.4,
        .{ .scale = 0.4 },
        ts,
    );

    if (res_and_amt.amount > 1) {
        renderFormatHex(8, tile_idx, grid, "x{}", .{res_and_amt.amount}, -0.2, -0.25, .{ .font_size = 14 }, ts) catch @panic("too much of resource, cant print");
    }
}

pub fn renderChargeCircleInHex(tile_idx: Idx, grid: Grid, fill_up: f32, off_x: f32, off_y: f32, args: CircleBarArgs, ts: TextureSet) void {
    renderChargeCircle(posInHex(tile_idx, grid, off_x, off_y, ts), fill_up, args, ts);
}
pub fn renderChargeCircle(pos: raylib.Vector2, fill_up: f32, args: CircleBarArgs, ts: TextureSet) void {
    const radius = args.radius * ts.hex_radius;
    const pos_anchor = raylib.Vector2Add(pos, args.anchor.getOffsetRelative(
        radius * 2,
        radius * 2,
        .bottom_right, // .center, //.top_left,
    ));

    raylib.DrawCircleSector(pos_anchor, radius, 0, fill_up * 360, 32, args.bar_color);
    raylib.DrawCircleV(pos_anchor, radius * (1 - args.bar_part), args.center_color);
}

pub fn renderTextureInHexSeries(tile_idx: Idx, grid: Grid, texture: raylib.Texture2D, repeats: u8, off_x_start: f32, off_y: f32, spaceing: f32, args: RenderTextureArgs, ts: TextureSet) f32 {
    const step_off = (@as(f32, @floatFromInt(texture.width)) * args.scale / ts.hex_radius + spaceing);
    for (0..repeats) |i| {
        const tot_off_x = off_x_start + @as(f32, @floatFromInt(i)) * step_off;
        renderTextureInHex(tile_idx, grid, texture, tot_off_x, off_y, args, ts);
    }
    return off_x_start + @as(f32, @floatFromInt(repeats)) * step_off;
}

/// Format print can do UP TO 31 characters
pub fn renderFormatHexAuto(tile_idx: Idx, grid: Grid, comptime fmt: []const u8, fmt_args: anytype, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) void {
    const l = fmt.len;
    blk: {
        renderFormatHex(4 * l, tile_idx, grid, //
            fmt, fmt_args, off_x, off_y, args, ts) catch break :blk;
        return;
    }
    blk: {
        renderFormatHex(16 * l, tile_idx, grid, //
            fmt, fmt_args, off_x, off_y, args, ts) catch break :blk;
        return;
    }
    blk: {
        renderFormatHex(64 * l, tile_idx, grid, //
            fmt, fmt_args, off_x, off_y, args, ts) catch break :blk;
        return;
    }
    renderFormatHex(1 << 16, tile_idx, grid, //
        fmt, fmt_args, off_x, off_y, args, ts) catch
        @panic("Failed auto format.");
}

pub fn renderFormatHex(comptime buflen: comptime_int, tile_idx: Idx, grid: Grid, comptime fmt: []const u8, fmt_args: anytype, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) !void {
    var buf: [buflen]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buf, fmt, fmt_args);
    renderTextInHex(tile_idx, grid, text, off_x, off_y, args, ts);
}

/// Render text in hex. Render text with a relative position form tile center (offset messured in hex radius)
pub fn renderTextInHex(tile_idx: Idx, grid: Grid, text: []const u8, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) void {
    const pos = posInHex(tile_idx, grid, off_x, off_y, ts);
    renderText(text, args.font orelse ts.font, pos, args);
}

/// Render texture
pub fn renderTextureHex(tile_idx: Idx, grid: Grid, texture: raylib.Texture2D, args: RenderTextureArgs, ts: TextureSet) void {
    const pos = posInHex(tile_idx, grid, 0, 0, ts);
    renderTexture(texture, pos, args);
}

/// Render texture in hex . Render text with a relative position form tile center (offset messured in hex radius)
pub fn renderTextureInHex(tile_idx: Idx, grid: Grid, texture: raylib.Texture2D, off_x: f32, off_y: f32, args: RenderTextureArgs, ts: TextureSet) void {
    const pos = posInHex(tile_idx, grid, off_x, off_y, ts);
    renderTexture(texture, pos, args);
}

/// returns the point relative to the center of a point
fn posInHex(idx: Idx, grid: Grid, off_x: f32, off_y: f32, ts: TextureSet) raylib.Vector2 {
    const x = grid.xFromIdx(idx);
    const y = grid.yFromIdx(idx);
    const center_x = hex.tilingX(x, y, ts.hex_radius) + hex.widthFromRadius(ts.hex_radius) / 2.0;
    const center_y = hex.tilingY(y, ts.hex_radius) + hex.heightFromRadius(ts.hex_radius) / 2.0;

    return .{ .x = center_x + off_x * ts.hex_radius, .y = center_y + off_y * ts.hex_radius };
}

/// Render text in hex. Render text with a relative position form tile center (offset messured in hex radius)
fn renderText(text: []const u8, font: raylib.Font, pos: raylib.Vector2, args: RenderTextArgs) void {
    const text_messurements =
        raylib.MeasureTextEx(font, text.ptr, args.font_size, args.spaceing);

    const pos_anchor = raylib.Vector2Add(pos, args.anchor.getOffsetRelative(
        text_messurements.x,
        text_messurements.y,
        .bottom_right, // .center, //.top_left,
    ));

    raylib.DrawTextEx(font, text.ptr, pos_anchor, args.font_size, args.spaceing, args.tint);
}

fn renderTexture(texture: raylib.Texture2D, pos: raylib.Vector2, args: RenderTextureArgs) void {
    const pos_anchor = raylib.Vector2Add(pos, args.anchor.getOffsetRelative(
        @as(f32, @floatFromInt(texture.width)) * args.scale,
        @as(f32, @floatFromInt(texture.height)) * args.scale,
        .bottom_right, // .center, //.top_left,
    ));

    raylib.DrawTextureEx(texture, pos_anchor, args.rotation, args.scale, args.tint);
}
