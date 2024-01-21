const rules = @import("rules");
const Terrain = rules.Terrain;
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
    font: raylib.Font,
    vegetation_textures: [@typeInfo(rules.Vegetation).Enum.fields.len]raylib.Texture2D,
    base_textures: [@typeInfo(rules.Base).Enum.fields.len]raylib.Texture2D,
    feature_textures: [@typeInfo(rules.Feature).Enum.fields.len]raylib.Texture2D,
    unit_icons: [@typeInfo(rules.UnitType).Enum.fields.len]raylib.Texture2D,
    resource_icons: [@typeInfo(rules.Resource).Enum.fields.len]raylib.Texture2D,
    transport_textures: [@typeInfo(rules.Improvements.Transport).Enum.fields.len]raylib.Texture2D,
    improvement_textures: [@typeInfo(rules.Improvements.Building).Enum.fields.len]raylib.Texture2D,
    edge_textures: [3]raylib.Texture2D,
    hex_radius: f32,

    pub fn init() !TextureSet {
        const font = raylib.LoadFont("textures/custom_alagard.png");
        const universal_fallback = loadTexture("textures/placeholder.png", null);

        const hex_radius = @as(f32, @floatFromInt(universal_fallback.height)) * 0.5;
        return .{
            .font = font,
            .hex_radius = hex_radius,
            .edge_textures = loadTexturesList(
                &[_][]const u8{
                    "textures/edge1.png",
                    "textures/edge2.png",
                    "textures/edge3.png",
                },
                universal_fallback,
            ),
            .base_textures = loadEnumTextures(
                "textures/{s}.png",
                universal_fallback,
                rules.Base,
            ),
            .vegetation_textures = loadEnumTextures(
                "textures/{s}.png",
                universal_fallback,
                rules.Vegetation,
            ),
            .feature_textures = loadEnumTextures(
                "textures/{s}.png",
                universal_fallback,
                rules.Feature,
            ),
            .improvement_textures = loadEnumTextures(
                "textures/impr_{s}.png",
                universal_fallback,
                rules.Improvements.Building,
            ),
            .transport_textures = loadEnumTextures(
                "textures/transp_{s}.png",
                universal_fallback,
                rules.Improvements.Transport,
            ),
            .resource_icons = loadEnumTextures(
                "textures/res_{s}.png",
                universal_fallback,
                rules.Resource,
            ),
            .unit_icons = loadEnumTextures(
                "textures/unit_{s}.png",
                universal_fallback,
                rules.UnitType,
            ),
        };
    }

    pub fn deinit(self: *TextureSet) void {
        for (self.vegetation_textures) |texture| raylib.UnloadTexture(texture);
        for (self.feature_textures) |texture| raylib.UnloadTexture(texture);
        for (self.base_textures) |texture| raylib.UnloadTexture(texture);
    }
};

pub fn loadTexturesList(
    comptime paths: []const []const u8,
    fallback: ?raylib.Texture2D,
) [paths.len]raylib.Texture2D {
    var textures = [_]raylib.Texture2D{undefined} ** (paths.len);
    for (paths, 0..) |path, i| {
        var path_buf: [256]u8 = undefined;
        const path_0 = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch unreachable;
        textures[i] = loadTexture(path_0, fallback);
    }

    return textures;
}

pub fn loadEnumTextures(
    comptime path_fmt: []const u8,
    universal_fallback: ?raylib.Texture2D,
    comptime E: type,
) [@typeInfo(E).Enum.fields.len]raylib.Texture2D {
    const enum_fields = @typeInfo(E).Enum.fields;
    var textures = [_]raylib.Texture2D{undefined} ** (enum_fields.len);

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
pub fn renderTile(world: World, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    renderTerrain(world.terrain[tile_idx], tile_idx, grid, ts);
    renderHexTextureArgs(tile_idx, grid, ts.edge_textures[tile_idx % 3], .{ .tint = .{
        .a = 60,
        .r = 250,
        .g = 250,
        .b = 150,
    } }, ts);
    renderImprovement(world.improvements[tile_idx], tile_idx, grid, ts);

    const resource = world.resources.get(tile_idx);
    if (resource != null) renderResource(resource.?, tile_idx, world.grid, ts);
}

pub fn renderTerrain(terrain: Terrain, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    renderHexTexture(
        tile_idx,
        grid,
        ts.base_textures[@intFromEnum(terrain.base())],
        ts,
    );

    if (terrain.feature() != .none) {
        renderHexTexture(
            tile_idx,
            grid,
            ts.feature_textures[@intFromEnum(terrain.feature())],
            ts,
        );
    }

    if (terrain.vegetation() != .none) {
        renderHexTexture(
            tile_idx,
            grid,
            ts.vegetation_textures[@intFromEnum(terrain.vegetation())],
            ts,
        );
    }
}

pub fn renderImprovement(improvement: rules.Improvements, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
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

pub fn renderResource(resource_and_amt: World.ResourceAndAmount, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    renderInHexTexture(
        tile_idx,
        grid,
        ts.resource_icons[@intFromEnum(resource_and_amt.type)],
        -0.4,
        -0.4,
        .{ .scale = 0.4 },
        ts,
    );

    if (resource_and_amt.amount > 1) {
        var buf: [8]u8 = [_]u8{0} ** 8;
        const amt_str = std.fmt.bufPrintZ(&buf, "x{}", .{resource_and_amt.amount}) catch unreachable;

        renderInHexText(tile_idx, grid, amt_str, -0.2, -0.25, .{ .font_size = 14 }, ts);
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

/// Render hex texture but with args! NOTE THAT NOT ALL ARGS WILL HAVE THE INTENDED/ANY EFFECT
pub fn renderHexTextureArgs(tile_idx: Idx, grid: Grid, texture: raylib.Texture2D, args: RenderTextureArgs, ts: TextureSet) void {
    const x = grid.xFromIdx(tile_idx);
    const y = grid.yFromIdx(tile_idx);
    const hex_x = hex.tilingX(x, y, ts.hex_radius);
    const hex_y = hex.tilingY(y, ts.hex_radius);

    raylib.DrawTextureEx(texture, raylib.Vector2{
        .x = hex_x,
        .y = hex_y,
    }, args.rotation, args.scale, args.tint);
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

pub fn cameraRenderBoundBox(camera: raylib.Camera2D, grid: *Grid, screen_width: usize, screen_height: usize, ts: TextureSet) Grid.BoundBox {
    const min_x, const min_y, const max_x, const max_y = blk: {
        const top_left = raylib.GetScreenToWorld2D(raylib.Vector2{}, camera);
        const bottom_right = raylib.GetScreenToWorld2D(raylib.Vector2{
            .x = @floatFromInt(screen_width),
            .y = @as(f32, @floatFromInt(screen_height)),
        }, camera);

        const fwidth: f32 = @floatFromInt(grid.width);
        const fheight: f32 = @floatFromInt(grid.height);

        const min_x: usize = @intFromFloat(std.math.clamp(
            @round(top_left.x / hex.widthFromRadius(ts.hex_radius)) - 2.0,
            0.0,
            fwidth,
        ));
        const max_x: usize = @intFromFloat(std.math.clamp(
            @round(bottom_right.x / hex.widthFromRadius(ts.hex_radius)) + 2.0,
            0.0,
            fwidth,
        ));

        const min_y: usize = @intFromFloat(std.math.clamp(
            @round(top_left.y / (ts.hex_radius * 1.5)) - 2.0,
            0.0,
            fheight,
        ));
        const max_y: usize = @intFromFloat(std.math.clamp(
            @round(bottom_right.y / (ts.hex_radius * 1.5)) + 2.0,
            0.0,
            fheight,
        ));

        break :blk .{ min_x, min_y, max_x, max_y };
    };
    return Grid.BoundBox{
        .xmax = max_x,
        .xmin = min_x,
        .ymax = max_y,
        .ymin = min_y,
        .grid = grid,
    };
}

/// VERY PLACEHOLDER AND SHIT
pub fn getMouseTile(
    camera: *raylib.Camera2D,
    grid: Grid,
    ts: TextureSet,
) usize {
    const click_point = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), camera.*);
    const click_x: f32 = click_point.x;
    const click_y: f32 = click_point.y;
    var click_idx: Grid.Idx = 0; // = world.tiles.coordToIdx(click_x, click_y);

    var min_dist: f32 = std.math.floatMax(f32);
    for (0..grid.width) |x| {
        for (0..grid.height) |y| {
            const real_x = hex.tilingX(x, y, ts.hex_radius) + hex.heightFromRadius(ts.hex_radius) * 0.5;
            const real_y = hex.tilingY(y, ts.hex_radius) + hex.widthFromRadius(ts.hex_radius) * 0.5;
            const dist = std.math.pow(f32, real_x - click_x, 2) + std.math.pow(f32, real_y - click_y, 2);
            if (dist < min_dist) {
                click_idx = grid.idxFromCoords(x, y);
                min_dist = dist;
            }
        }
    }
    return click_idx;
}

pub fn updateCamera(camera: *raylib.Camera2D, speed: f32) bool {
    const last_zoom = camera.zoom;
    const last_target = camera.target;

    // Drag controls
    if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_MIDDLE)) {
        const delta = raylib.Vector2Scale(raylib.GetMouseDelta(), -1.0 / camera.zoom);

        camera.target = raylib.Vector2Add(camera.target, delta);
    }

    // Zoom controls
    const wheel = raylib.GetMouseWheelMove();
    if (wheel != 0.0) {
        const world_pos = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), camera.*);

        camera.offset = raylib.GetMousePosition();
        camera.target = world_pos;

        const zoom_inc = 0.3;
        camera.zoom += (wheel * zoom_inc);
        camera.zoom = std.math.clamp(camera.zoom, 0.3, 2.0);
    }

    // Arrow key controls
    if (raylib.IsKeyDown(raylib.KEY_RIGHT) or raylib.IsKeyDown(raylib.KEY_D)) camera.target.x += speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_LEFT) or raylib.IsKeyDown(raylib.KEY_A)) camera.target.x -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_UP) or raylib.IsKeyDown(raylib.KEY_W)) camera.target.y -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_DOWN) or raylib.IsKeyDown(raylib.KEY_S)) camera.target.y += speed / camera.zoom;

    return camera.zoom != last_zoom or raylib.Vector2Equals(camera.target, last_target) != 0;
}
