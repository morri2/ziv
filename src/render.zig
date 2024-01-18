const rules = @import("rules");
const Terrain = rules.Terrain;
const Grid = @import("Grid.zig");
const hex = @import("HEX.zig");
const Idx = @import("grid.zig").Idx;
const tr = @import("grid.zig").Idx;

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub const TextureSet = struct {
    vegetation_textures: [@typeInfo(rules.Vegetation).Enum.fields.len - 1]raylib.Texture2D,
    base_textures: [@typeInfo(rules.Base).Enum.fields.len]raylib.Texture2D,
    feature_textures: [@typeInfo(rules.Feature).Enum.fields.len - 1]raylib.Texture2D,
    hex_radius: f32,

    pub fn init() !TextureSet {

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

        return .{
            .base_textures = base_textures,
            .vegetation_textures = vegetation_textures,
            .feature_textures = feature_textures,
            .hex_radius = hex_radius,
        };
    }

    pub fn deinit(self: *TextureSet) void {
        for (self.vegetation_textures) |texture| raylib.UnloadTexture(texture);
        for (self.feature_textures) |texture| raylib.UnloadTexture(texture);
        for (self.base_textures) |texture| raylib.UnloadTexture(texture);
    }
};

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
