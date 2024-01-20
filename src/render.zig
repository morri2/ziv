const rules = @import("rules");
const Terrain = rules.Terrain;
const Grid = @import("Grid.zig");
const hex = @import("HEX.zig");
const Idx = @import("grid.zig").Idx;
const World = @import("World.zig");
const Unit = @import("Unit.zig");

const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub const TextureSet = struct {
    font: raylib.Font,
    vegetation_textures: [@typeInfo(rules.Vegetation).Enum.fields.len - 1]raylib.Texture2D,
    base_textures: [@typeInfo(rules.Base).Enum.fields.len]raylib.Texture2D,
    feature_textures: [@typeInfo(rules.Feature).Enum.fields.len - 1]raylib.Texture2D,
    unit_icons: [@typeInfo(rules.UnitType).Enum.fields.len]raylib.Texture2D,
    resource_icons: [@typeInfo(rules.Resource).Enum.fields.len]raylib.Texture2D,
    hex_radius: f32,

    pub fn init() !TextureSet {
        const font = raylib.LoadFont("textures/custom_alagard.png");
        // Load resources
        const base_textures, const texture_height = blk: {
            const enum_fields = @typeInfo(rules.Base).Enum.fields;
            var textures = [_]raylib.Texture2D{undefined} ** enum_fields.len;
            var texture_height: c_int = 0;

            inline for (enum_fields, 0..) |field, i| {
                const path = "textures/" ++ field.name ++ ".png";
                const img = if (raylib.FileExists(path)) raylib.LoadImage(path) else raylib.LoadImage("textures/placeholder.png");
                defer raylib.UnloadImage(img);

                if (i == 0) texture_height = img.height else {
                    if (img.height != texture_height) return error.InvalidResources;
                }

                textures[i] = raylib.LoadTextureFromImage(img);
            }
            break :blk .{ textures, texture_height };
        };

        const feature_textures = blk: {
            const enum_fields = @typeInfo(rules.Feature).Enum.fields;
            var textures = [_]raylib.Texture2D{undefined} ** (enum_fields.len - 1);

            inline for (enum_fields[1..], 0..) |field, i| {
                const img = raylib.LoadImage("textures/" ++ field.name ++ ".png");
                defer raylib.UnloadImage(img);

                if (img.height != texture_height) return error.InvalidResources;

                textures[i] = raylib.LoadTextureFromImage(img);
            }
            break :blk textures;
        };

        const vegetation_textures = blk: {
            const enum_fields = @typeInfo(rules.Vegetation).Enum.fields;
            var textures = [_]raylib.Texture2D{undefined} ** (enum_fields.len - 1);

            inline for (enum_fields[1..], 0..) |field, i| {
                const img = raylib.LoadImage("textures/" ++ field.name ++ ".png");
                defer raylib.UnloadImage(img);

                if (img.height != texture_height) return error.InvalidResources;

                textures[i] = raylib.LoadTextureFromImage(img);
            }
            break :blk textures;
        };

        const hex_radius = @as(f32, @floatFromInt(texture_height)) * 0.5;

        const units_icons = blk: {
            const enum_fields = @typeInfo(rules.UnitType).Enum.fields;
            var textures = [_]raylib.Texture2D{undefined} ** (enum_fields.len);
            //var buf: [255]u8 = undefined;
            inline for (enum_fields[0..], 0..) |field, i| {
                //const field_name = std.ascii.lowerString(&buf, field.name);
                const img = img: {
                    std.fs.Dir.access(std.fs.cwd(), "textures/unit_" ++ field.name ++ ".png", .{}) catch {
                        break :img raylib.LoadImage("textures/unit_placeholder.png");
                    };
                    break :img raylib.LoadImage("textures/unit_" ++ field.name ++ ".png");
                };

                defer raylib.UnloadImage(img);
                textures[i] = raylib.LoadTextureFromImage(img);
            }
            break :blk textures;
        };

        const resource_icons = blk: {
            const enum_fields = @typeInfo(rules.Resource).Enum.fields;
            var textures = [_]raylib.Texture2D{undefined} ** (enum_fields.len);
            //var buf: [255]u8 = undefined;
            inline for (enum_fields[0..], 0..) |field, i| {
                //const field_name = std.ascii.lowerString(&buf, field.name);
                const img = img: {
                    std.fs.Dir.access(std.fs.cwd(), "textures/res_" ++ field.name ++ ".png", .{}) catch {
                        break :img raylib.LoadImage("textures/res_placeholder.png");
                    };
                    break :img raylib.LoadImage("textures/res_" ++ field.name ++ ".png");
                };

                defer raylib.UnloadImage(img);
                textures[i] = raylib.LoadTextureFromImage(img);
            }
            break :blk textures;
        };

        return .{
            .resource_icons = resource_icons,
            .font = font,
            .base_textures = base_textures,
            .vegetation_textures = vegetation_textures,
            .feature_textures = feature_textures,
            .hex_radius = hex_radius,
            .unit_icons = units_icons,
        };
    }

    pub fn deinit(self: *TextureSet) void {
        for (self.vegetation_textures) |texture| raylib.UnloadTexture(texture);
        for (self.feature_textures) |texture| raylib.UnloadTexture(texture);
        for (self.base_textures) |texture| raylib.UnloadTexture(texture);
    }
};

pub fn renderUnits(world: *World, tile_idx: Idx, ts: TextureSet) void {
    var unit_container = world.topUnitContainerPtr(tile_idx);
    for (0..32) |i| {
        const unit = (unit_container orelse break).unit;
        renderUnit(unit, i, tile_idx, world.grid, ts);
        unit_container = world.nextUnitContainerPtr(unit_container.?);
    }
}

pub fn renderUnit(unit: Unit, stack_pos: usize, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    const x = grid.xFromIdx(tile_idx);
    const y = grid.yFromIdx(tile_idx);
    const real_x = hex.tilingX(x, y, ts.hex_radius);
    const real_y = hex.tilingY(y, ts.hex_radius);

    raylib.DrawTextureEx(
        ts.unit_icons[@intFromEnum(unit.type)],
        raylib.Vector2{
            .x = real_x + ts.hex_radius / 2.0 - ts.hex_radius * 0.1 * @as(f32, @floatFromInt(stack_pos)),
            .y = real_y + ts.hex_radius / 2.0 - ts.hex_radius * 0.2 * @as(f32, @floatFromInt(stack_pos)),
        },
        0.0,
        0.5,
        raylib.WHITE,
    );
    const base_x = real_x + ts.hex_radius / 2.0 + ts.hex_radius * 0.1 * @as(f32, @floatFromInt(stack_pos));
    const base_y = real_y + ts.hex_radius / 2.0 + ts.hex_radius * 0.2 * @as(f32, @floatFromInt(stack_pos));

    {
        var buf: [8:0]u8 = [_:0]u8{0} ** 8;
        const hp_str = std.fmt.bufPrint(&buf, "{} HP", .{unit.hit_points}) catch unreachable;

        raylib.DrawTextEx(ts.font, hp_str.ptr, raylib.Vector2{
            .x = base_x,
            .y = base_y,
        }, 10, 0.0, raylib.GREEN);
    }
    {
        var buf: [8:0]u8 = [_:0]u8{0} ** 8;
        const hp_str = std.fmt.bufPrint(&buf, "{d:.1}/{}", .{ unit.movement, unit.type.baseStats().moves }) catch unreachable;

        raylib.DrawTextEx(ts.font, hp_str.ptr, raylib.Vector2{
            .x = base_x,
            .y = base_y + 0.5 * ts.hex_radius,
        }, 10, 0.0, raylib.RED);
    }
}

pub fn renderTile(terrain: Terrain, tile_idx: Idx, grid: Grid, ts: TextureSet) void {
    const x = grid.xFromIdx(tile_idx);
    const y = grid.yFromIdx(tile_idx);
    const real_x = hex.tilingX(x, y, ts.hex_radius);
    const real_y = hex.tilingY(y, ts.hex_radius);

    raylib.DrawTextureEx(
        ts.base_textures[@intFromEnum(terrain.base())],
        raylib.Vector2{
            .x = real_x,
            .y = real_y,
        },
        0.0,
        1.0,
        raylib.WHITE,
    );

    if (terrain.feature() != .none) {
        raylib.DrawTextureEx(
            ts.feature_textures[@intFromEnum(terrain.feature()) - 1],
            raylib.Vector2{
                .x = real_x,
                .y = real_y,
            },
            0.0,
            1.0,
            raylib.WHITE,
        );
    }

    if (terrain.vegetation() != .none) {
        raylib.DrawTextureEx(
            ts.vegetation_textures[@intFromEnum(terrain.vegetation()) - 1],
            raylib.Vector2{
                .x = real_x,
                .y = real_y,
            },
            0.0,
            1.0,
            raylib.WHITE,
        );
    }
}

pub fn renderResource(world: *World, tile_idx: Idx, ts: TextureSet) void {
    const res_amt = world.resources.get(tile_idx) orelse return;
    const x = world.grid.xFromIdx(tile_idx);
    const y = world.grid.yFromIdx(tile_idx);
    const base_x = hex.tilingX(x, y, ts.hex_radius) + 0.2 * ts.hex_radius;
    const base_y = hex.tilingY(y, ts.hex_radius) + 0.2 * ts.hex_radius;

    raylib.DrawTextureEx(
        ts.resource_icons[@intFromEnum(res_amt.type)],
        raylib.Vector2{
            .x = base_x,
            .y = base_y,
        },
        0.0,
        0.4,
        raylib.WHITE,
    );

    if (res_amt.amount > 1) {
        var buf: [8:0]u8 = [_:0]u8{0} ** 8;
        const amt_str = std.fmt.bufPrint(&buf, "x{}", .{res_amt.amount}) catch unreachable;

        raylib.DrawTextEx(ts.font, amt_str.ptr, raylib.Vector2{
            .x = base_x + 0.3 * ts.hex_radius,
            .y = base_y + 0.3 * ts.hex_radius,
        }, 12, 0.0, raylib.WHITE);
    }
}
