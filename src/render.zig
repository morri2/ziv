const Rules = @import("Rules.zig");
const Terrain = Rules.Terrain;
const Grid = @import("Grid.zig");
const hex = @import("hex.zig");
const Idx = @import("Grid.zig").Idx;
const World = @import("World.zig");
const Unit = @import("Unit.zig");

const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub const TextureSet = struct {
    allocator: std.mem.Allocator,
    font: raylib.Font,
    vegetation_textures: []const raylib.Texture2D,
    base_textures: []const raylib.Texture2D,
    feature_textures: []const raylib.Texture2D,
    unit_icons: []const raylib.Texture2D,
    resource_icons: []const raylib.Texture2D,
    transport_textures: []const raylib.Texture2D,
    improvement_textures: []const raylib.Texture2D,
    hex_radius: f32,

    pub fn init(rules: *const Rules, allocator: std.mem.Allocator) !TextureSet {
        const font = raylib.LoadFont("textures/custom_alagard.png");
        const universal_fallback = loadTexture("textures/placeholder.png", null);

        const hex_radius = @as(f32, @floatFromInt(universal_fallback.height)) * 0.5;
        return .{
            .allocator = allocator,
            .font = font,
            .hex_radius = hex_radius,

            .base_textures = try loadTextures(
                "textures/{s}.png",
                universal_fallback,
                Rules.Terrain.Base,
                rules,
                rules.base_count,
                allocator,
            ),
            .feature_textures = try loadTextures(
                "textures/{s}.png",
                universal_fallback,
                Rules.Terrain.Feature,
                rules,
                rules.feature_count,
                allocator,
            ),
            .vegetation_textures = try loadTextures(
                "textures/{s}.png",
                universal_fallback,
                Rules.Terrain.Vegetation,
                rules,
                rules.vegetation_count,
                allocator,
            ),
            .resource_icons = try loadTextures(
                "textures/res_{s}.png",
                universal_fallback,
                Rules.Resource,
                rules,
                rules.resource_count,
                allocator,
            ),
            .improvement_textures = try loadTextures(
                "textures/impr_{s}.png",
                universal_fallback,
                Rules.Building,
                rules,
                rules.building_count,
                allocator,
            ),
            .transport_textures = try loadEnumTextures(
                "textures/transp_{s}.png",
                universal_fallback,
                Rules.Transport,
                allocator,
            ),
            .unit_icons = try loadEnumTextures(
                "textures/unit_{s}.png",
                universal_fallback,
                Rules.UnitType,
                allocator,
            ),
        };
    }

    pub fn deinit(self: *TextureSet) void {
        for (self.vegetation_textures) |texture| raylib.UnloadTexture(texture);
        for (self.feature_textures) |texture| raylib.UnloadTexture(texture);
        for (self.base_textures) |texture| raylib.UnloadTexture(texture);

        self.allocator.free(self.unit_icons);
        self.allocator.free(self.transport_textures);
        self.allocator.free(self.improvement_textures);
        self.allocator.free(self.resource_icons);
        self.allocator.free(self.vegetation_textures);
        self.allocator.free(self.feature_textures);
        self.allocator.free(self.base_textures);
    }
};

pub fn loadTextures(
    comptime path_fmt: []const u8,
    universal_fallback: ?raylib.Texture2D,
    comptime Enum: type,
    rules: *const Rules,
    len: usize,
    allocator: std.mem.Allocator,
) ![]const raylib.Texture2D {
    const textures = try allocator.alloc(raylib.Texture2D, len);
    errdefer allocator.free(textures);

    var fallback_path_buf: [256]u8 = undefined;
    const fallback_path = std.fmt.bufPrintZ(&fallback_path_buf, path_fmt, .{"placeholder"}) catch unreachable;

    const fallback_texture = loadTexture(fallback_path, universal_fallback);

    for (0..len) |i| {
        const e: Enum = @enumFromInt(i);
        const name = e.name(rules);
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, path_fmt, .{name}) catch unreachable;
        textures[i] = loadTexture(path, fallback_texture);
    }
    return textures;
}

pub fn loadEnumTextures(
    comptime path_fmt: []const u8,
    universal_fallback: ?raylib.Texture2D,
    comptime E: type,
    allocator: std.mem.Allocator,
) ![]const raylib.Texture2D {
    const enum_fields = @typeInfo(E).Enum.fields;
    const textures = try allocator.alloc(raylib.Texture2D, enum_fields.len);
    errdefer allocator.free(textures);

    var fallback_path_buf: [256]u8 = undefined;
    const fallback_path = std.fmt.bufPrintZ(&fallback_path_buf, path_fmt, .{"placeholder"}) catch unreachable;

    const fallback_texture = loadTexture(fallback_path, universal_fallback);

    inline for (@typeInfo(E).Enum.fields, 0..) |field, i| {
        var enum_name_buf: [256]u8 = undefined;
        const enum_name = std.ascii.lowerString(&enum_name_buf, field.name);

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, path_fmt, .{enum_name}) catch unreachable;
        textures[i] = loadTexture(path, fallback_texture);
    }
    return textures;
}

pub fn loadTexture(path: []const u8, fallback: ?raylib.Texture2D) raylib.Texture2D {
    std.fs.Dir.access(std.fs.cwd(), path, .{}) catch {
        if (!std.mem.containsAtLeast(u8, path, 1, "none")) {
            std.debug.print("No texture '{s}', resorting to placeholder.\n", .{path});
        }
        return fallback orelse unreachable;
    };
    const img = raylib.LoadImage(path.ptr);
    defer raylib.UnloadImage(img);
    return raylib.LoadTextureFromImage(img);
}

pub fn renderYields(world: *World, tile_idx: Idx, ts: TextureSet) void {
    const yields = world.tileYield(tile_idx);
    renderInHexTextFormat(
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

pub fn renderUnits(world: *World, tile_idx: Idx, ts: TextureSet) void {
    var unit_container = world.topUnitContainerPtr(tile_idx);
    for (0..32) |i| {
        _ = i; // autofix

        const unit = (unit_container orelse break).unit;
        renderUnit(unit, tile_idx, world.grid, ts);
        unit_container = world.nextUnitContainerPtr(unit_container.?);
    }
}

pub fn renderUnit(unit: Unit, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    renderInHexTexture(
        tile_idx,
        grid,
        ts.unit_icons[@intFromEnum(unit.type)],
        0.0,
        0.0,
        .{ .scale = 0.4 },
        ts,
    );

    renderInHexTextFormat(
        tile_idx,
        grid,
        "{}hp",
        .{unit.hit_points},
        0.0,
        -0.3,
        .{},
        ts,
    );

    renderInHexTextFormat(
        tile_idx,
        grid,
        "{d:.0}/{d:.0}",
        .{ unit.movement, unit.maxMovement() },
        0.0,
        0.3,
        .{},
        ts,
    );
}

/// For rendering all the shit in the tile, split up into sub function for when rendering from player persepectives
pub fn renderTile(world: World, tile_idx: Idx, grid: Grid, ts: TextureSet, rules: *const Rules) void {
    renderTerrain(world.terrain[tile_idx], tile_idx, grid, ts, rules);
    renderImprovement(world.improvements[tile_idx], tile_idx, grid, ts);
}

pub fn renderTerrain(terrain: Terrain, tile_idx: Idx, grid: Grid, ts: TextureSet, rules: *const Rules) void {
    const base = terrain.base(rules);
    renderHexTexture(
        tile_idx,
        grid,
        ts.base_textures[@intFromEnum(base)],
        ts,
    );

    const feature = terrain.feature(rules);
    if (feature != .none) {
        renderHexTexture(
            tile_idx,
            grid,
            ts.feature_textures[@intFromEnum(feature)],
            ts,
        );
    }

    const vegetation = terrain.vegetation(rules);
    if (vegetation != .none) {
        renderHexTexture(
            tile_idx,
            grid,
            ts.vegetation_textures[@intFromEnum(vegetation)],
            ts,
        );
    }
}

pub fn renderImprovement(improvement: Rules.Improvements, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    if (improvement.building != .none) {
        renderHexTexture(
            tile_idx,
            grid,
            ts.improvement_textures[@intFromEnum(improvement.building)],
            ts,
        );
    }

    if (improvement.transport != .none) {
        // PLACEHOLDER!
        renderHexTexture(
            tile_idx,
            grid,
            ts.feature_textures[3],
            ts,
        );
    }
}

pub fn renderResource(world: *World, tile_idx: Idx, ts: TextureSet) void {
    const res_amt = world.resources.get(tile_idx) orelse return;

    renderInHexTexture(
        tile_idx,
        world.grid,
        ts.resource_icons[@intFromEnum(res_amt.type)],
        -0.4,
        -0.4,
        .{ .scale = 0.4 },
        ts,
    );

    if (res_amt.amount > 1) {
        var buf: [8]u8 = [_]u8{0} ** 8;
        const amt_str = std.fmt.bufPrintZ(&buf, "x{}", .{res_amt.amount}) catch unreachable;

        renderInHexText(tile_idx, world.grid, amt_str, -0.2, -0.25, .{ .font_size = 14 }, ts);
    }
}

/// For rendering a texture with the dimensions of a Hex tile covering a full hex tile
pub fn renderHexTexture(tile_idx: Idx, grid: Grid, texture: raylib.Texture2D, ts: TextureSet) void {
    const x = grid.xFromIdx(tile_idx);
    const y = grid.yFromIdx(tile_idx);
    const hex_x = hex.tilingX(x, y, ts.hex_radius);
    const hex_y = hex.tilingY(y, ts.hex_radius);

    raylib.DrawTextureEx(texture, raylib.Vector2{
        .x = hex_x,
        .y = hex_y,
    }, 0.0, 1.0, raylib.WHITE);
}

pub const RenderTextArgs = struct {
    font: ?raylib.Font = null, // null -> ts default font
    font_size: f32 = 10,
    spaceing: f32 = 0.0,
    rotation: f32 = 0.0, // unstable? might fuck up with anything other than left anchor
    tint: raylib.Color = raylib.WHITE,
    anchor: enum { center, right, left } = .center,
};

/// Format print can do UP TO 31 characters
pub fn renderInHexTextFormat(tile_idx: Idx, grid: Grid, comptime fmt: []const u8, fmt_args: anytype, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) void {
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, fmt, fmt_args) catch unreachable;
    renderInHexText(tile_idx, grid, text, off_x, off_y, args, ts);
}

/// Format print can do UP TO 255 characters
pub fn renderInHexTextFormatLong(tile_idx: Idx, grid: Grid, comptime fmt: []const u8, fmt_args: anytype, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) void {
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, fmt, fmt_args) catch unreachable;
    renderInHexText(tile_idx, grid, text, off_x, off_y, args, ts);
}

/// Render text in hex. Render text with a relative position form tile center (offset messured in hex radius)
pub fn renderInHexText(tile_idx: Idx, grid: Grid, text: []const u8, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) void {
    const x = grid.xFromIdx(tile_idx);
    const y = grid.yFromIdx(tile_idx);
    const center_x = hex.tilingX(x, y, ts.hex_radius) + hex.widthFromRadius(ts.hex_radius) / 2.0;
    const center_y = hex.tilingY(y, ts.hex_radius) + hex.heightFromRadius(ts.hex_radius) / 2.0;

    const text_messurements = raylib.MeasureTextEx(ts.font, text.ptr, args.font_size, args.spaceing);

    const pos = switch (args.anchor) {
        .center => raylib.Vector2{
            .x = center_x + off_x * ts.hex_radius - text_messurements.x / 2,
            .y = center_y + off_y * ts.hex_radius - text_messurements.y / 2,
        },
        .left => raylib.Vector2{ .x = center_x + off_x * ts.hex_radius, .y = center_y + off_y * ts.hex_radius },
        .right => raylib.Vector2{
            .x = center_x + off_x * ts.hex_radius - text_messurements.x,
            .y = center_y + off_y * ts.hex_radius - text_messurements.y,
        },
    };

    raylib.DrawTextEx(args.font orelse ts.font, text.ptr, pos, args.font_size, args.spaceing, args.tint);
}

pub const RenderTextureArgs = struct {
    scale: f32 = 1.0,
    rotation: f32 = 0.0, // unstable? might fuck up with anything other than top_left
    tint: raylib.Color = raylib.WHITE,
    anchor: enum { center, bot_right, top_left } = .center,
};

/// Render texture in hex . Render text with a relative position form tile center (offset messured in hex radius)
pub fn renderInHexTexture(tile_idx: Idx, grid: Grid, texture: raylib.Texture2D, off_x: f32, off_y: f32, args: RenderTextureArgs, ts: TextureSet) void {
    const x = grid.xFromIdx(tile_idx);
    const y = grid.yFromIdx(tile_idx);
    const center_x = hex.tilingX(x, y, ts.hex_radius) + hex.widthFromRadius(ts.hex_radius) / 2.0;
    const center_y = hex.tilingY(y, ts.hex_radius) + hex.heightFromRadius(ts.hex_radius) / 2.0;

    const pos = switch (args.anchor) {
        .center => raylib.Vector2{
            .x = center_x + off_x * ts.hex_radius - args.scale * @as(f32, @floatFromInt(texture.width)) / 2,
            .y = center_y + off_y * ts.hex_radius - args.scale * @as(f32, @floatFromInt(texture.height)) / 2,
        },
        .top_left => raylib.Vector2{ .x = center_x + off_x * ts.hex_radius, .y = center_y + off_y * ts.hex_radius },
        .bot_right => raylib.Vector2{
            .x = center_x + off_x * ts.hex_radius - args.scale * @as(f32, @floatFromInt(texture.width)),
            .y = center_y + off_y * ts.hex_radius - args.scale * @as(f32, @floatFromInt(texture.height)),
        },
    };

    raylib.DrawTextureEx(texture, pos, args.rotation, args.scale, raylib.WHITE);
}
