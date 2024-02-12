const Rules = @import("../Rules.zig");
const Self = @This();
const Terrain = Rules.Terrain;

const Idx = @import("../Grid.zig").Idx;

const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub const log = std.log.scoped(.texture_set);

allocator: std.mem.Allocator,
font: raylib.Font,
vegetation_textures: []const raylib.Texture2D,
base_textures: []const raylib.Texture2D,
feature_textures: []const raylib.Texture2D,
unit_icons: []const raylib.Texture2D,
resource_icons: []const raylib.Texture2D,
improvement_textures: []const raylib.Texture2D,
edge_textures: []const raylib.Texture2D,
red_pop: raylib.Texture2D,
green_pop: raylib.Texture2D,
city_textures: []const raylib.Texture2D,
city_border_texture: raylib.Texture2D,
smoke_texture: raylib.Texture2D,
river_textures: []const raylib.Texture2D,
road_textures: []const raylib.Texture2D,
rail_textures: []const raylib.Texture2D,

unit_slot_frame_back: []const raylib.Texture2D,
unit_slot_frame_line: []const raylib.Texture2D,
unit_slot_frame_glow: []const raylib.Texture2D,
unit_symbols: []const raylib.Texture2D,
//hex_radius: f32,

player_primary_color: []const raylib.Color,
player_secoundary_color: []const raylib.Color,

unit: f32, // the unit for rendering non hex elements, should be set as a function of hex size

// width and height (allows for asymetric hexes :))))
hex_width: f32,
hex_height: f32,

terrain_textures: []const raylib.Texture2D,

pub fn init(rules: *const Rules, allocator: std.mem.Allocator) !Self {
    const font = raylib.LoadFont("textures/custom_alagard.png");
    //const universal_fallback = loadTexture("textures/placeholder.png", null);
    const universal_fallback = loadTexture("textures/rastor/h_blank.png", null);

    //const hex_radius = @as(f32, @floatFromInt(universal_fallback.height)) * 0.5;

    // const hex_width = std.math.sqrt(3) * hex_radius * 2; //@as(f32, @floatFromInt(universal_fallback.height));
    // const hex_height = 2 * hex_radius;

    const hex_width = @as(f32, @floatFromInt(universal_fallback.width)) - 0.02;
    const hex_height = @as(f32, @floatFromInt(universal_fallback.height));
    const unit = hex_height / 2;

    const frame_shapes = &[_][]const u8{
        "circle", "circle", "pin", "pin", "boxpin", "trade",
    };

    return .{
        .allocator = allocator,
        .font = font,
        //.hex_radius = hex_radius,
        .edge_textures = try loadTexturesList(&[_][]const u8{
            "textures/rastor/edge.png",
            "textures/rastor/edge.png",
            "textures/rastor/edge.png",
        }, universal_fallback, 3, allocator),

        .unit_slot_frame_back = try loadTexturesTextList(
            "textures/frames/{s}_inner.png",
            universal_fallback,
            frame_shapes,
            6,
            allocator,
        ),

        .unit_slot_frame_line = try loadTexturesTextList(
            "textures/frames/{s}_line.png",
            universal_fallback,
            frame_shapes,
            6,
            allocator,
        ),

        .unit_slot_frame_glow = try loadTexturesTextList(
            "textures/frames/{s}_blur.png",
            universal_fallback,
            frame_shapes,
            6,
            allocator,
        ),

        .unit_symbols = try loadTexturesEnum(
            "textures/units/unit_{s}.png",
            null,
            Rules.UnitType,
            rules,
            rules.unit_type_count,
            allocator,
        ),

        .player_primary_color = &[_]raylib.Color{
            raylib.DARKPURPLE,
            raylib.DARKBLUE,
            raylib.ORANGE,
            raylib.DARKGREEN,
            raylib.DARKBROWN,
            raylib.DARKGREEN,

            raylib.DARKGRAY,
        },
        .player_secoundary_color = &[_]raylib.Color{
            raylib.BEIGE,
            raylib.BEIGE,
            raylib.BEIGE,
            raylib.BEIGE,
            raylib.BEIGE,
            raylib.BEIGE,
        },

        .road_textures = try loadNumberedTextures("textures/rastor/road_{}.png", universal_fallback, 7, allocator),

        .rail_textures = try loadNumberedTextures("textures/rastor/road_{}.png", universal_fallback, 7, allocator),

        .river_textures = try loadNumberedTextures("textures/rastor/river_{}.png", universal_fallback, 6, allocator),

        .city_textures = try loadNumberedTextures("textures/rastor/city_{}.png", universal_fallback, 6, allocator),

        .base_textures = try loadTexturesEnum(
            "textures/{s}.png",
            universal_fallback,
            Rules.Terrain.Base,
            rules,
            rules.base_count,
            allocator,
        ),
        .feature_textures = try loadTexturesEnum(
            "textures/{s}.png",
            universal_fallback,
            Rules.Terrain.Feature,
            rules,
            rules.feature_count,
            allocator,
        ),
        .vegetation_textures = try loadTexturesEnum(
            "textures/{s}.png",
            universal_fallback,
            Rules.Terrain.Vegetation,
            rules,
            rules.vegetation_count,
            allocator,
        ),
        .resource_icons = try loadTexturesEnum(
            "textures/res_{s}.png",
            universal_fallback,
            Rules.Resource,
            rules,
            rules.resource_count,
            allocator,
        ),
        .improvement_textures = try loadTexturesEnum(
            "textures/impr_{s}.png",
            universal_fallback,
            Rules.Building,
            rules,
            rules.building_count,
            allocator,
        ),

        .unit_icons = try loadTexturesEnum(
            "textures/unit_{s}.png",
            universal_fallback,
            Rules.UnitType,
            rules,
            rules.unit_type_count,
            allocator,
        ),
        .smoke_texture = loadTexture("textures/rastor/h_fog.png", null),
        .red_pop = loadTexture("textures/redpop.png", null),
        .green_pop = loadTexture("textures/pop.png", null),
        .city_border_texture = loadTexture("textures/rastor/h_outline_dashed.png", null),

        //.hex_radius = hex_radius,
        .unit = unit,
        .hex_height = hex_height,
        .hex_width = hex_width,
        .terrain_textures = try loadTerrainTextures("textures/rastor/t_{s}.png", universal_fallback, rules, allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.unit_icons) |texture| raylib.UnloadTexture(texture);
    for (self.improvement_textures) |texture| raylib.UnloadTexture(texture);
    for (self.resource_icons) |texture| raylib.UnloadTexture(texture);
    for (self.vegetation_textures) |texture| raylib.UnloadTexture(texture);
    for (self.feature_textures) |texture| raylib.UnloadTexture(texture);
    for (self.base_textures) |texture| raylib.UnloadTexture(texture);
    for (self.edge_textures) |texture| raylib.UnloadTexture(texture);
    for (self.terrain_textures) |texture| raylib.UnloadTexture(texture);
    for (self.city_textures) |texture| raylib.UnloadTexture(texture);
    for (self.river_textures) |texture| raylib.UnloadTexture(texture);
    for (self.unit_slot_frame_back) |texture| raylib.UnloadTexture(texture);
    for (self.unit_slot_frame_line) |texture| raylib.UnloadTexture(texture);
    for (self.unit_slot_frame_glow) |texture| raylib.UnloadTexture(texture);
    for (self.unit_symbols) |texture| raylib.UnloadTexture(texture);
    for (self.road_textures) |texture| raylib.UnloadTexture(texture);
    for (self.rail_textures) |texture| raylib.UnloadTexture(texture);

    self.allocator.free(self.unit_icons);
    self.allocator.free(self.improvement_textures);
    self.allocator.free(self.resource_icons);
    self.allocator.free(self.vegetation_textures);
    self.allocator.free(self.feature_textures);
    self.allocator.free(self.base_textures);
    self.allocator.free(self.edge_textures);
    self.allocator.free(self.city_textures);
    self.allocator.free(self.terrain_textures);
    self.allocator.free(self.river_textures);
    self.allocator.free(self.unit_slot_frame_back);
    self.allocator.free(self.unit_slot_frame_line);
    self.allocator.free(self.unit_slot_frame_glow);
    self.allocator.free(self.unit_symbols);
    self.allocator.free(self.road_textures);
    self.allocator.free(self.rail_textures);
}

/// For loading textures for full terrain, eg not components
pub fn loadTerrainTextures(
    comptime path_fmt: []const u8,
    universal_fallback: ?raylib.Texture2D,
    rules: *const Rules,
    allocator: std.mem.Allocator,
) ![]const raylib.Texture2D {
    const len = rules.terrain_count;
    const textures = try allocator.alloc(raylib.Texture2D, len);
    errdefer allocator.free(textures);

    var fallback_path_buf: [256]u8 = undefined;
    const fallback_path = std.fmt.bufPrintZ(&fallback_path_buf, path_fmt, .{"placeholder"}) catch unreachable;

    const fallback_texture = loadTexture(fallback_path, universal_fallback);

    for (0..len) |i| {
        const e: Rules.Terrain = @enumFromInt(i);
        var name_buf: [256]u8 = undefined;
        var j: usize = 0;
        var name: []u8 = &name_buf;
        if (!e.attributes(rules).is_wonder) {
            name = std.fmt.bufPrintZ(name_buf[j..], "{s}", .{e.base(rules).name(rules)}) catch unreachable;
            j += name.len;

            if (e.feature(rules) != .none) {
                name = std.fmt.bufPrintZ(name_buf[j..], "_{s}", .{e.feature(rules).name(rules)}) catch unreachable;
                j += name.len;
            }

            if (e.vegetation(rules) != .none) {
                name = std.fmt.bufPrintZ(name_buf[j..], "_{s}", .{e.vegetation(rules).name(rules)}) catch unreachable;
                j += name.len;
            }
        } else {
            name = std.fmt.bufPrintZ(name_buf[0..], "nw_mountain", .{}) catch unreachable;

            if (e.attributes(rules).is_water) // WTF IS WATER MAKES SHIT CRASH....
                name = std.fmt.bufPrintZ(name_buf[0..], "nw_lake", .{}) catch unreachable;
            j = name.len;
        }

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, path_fmt, .{name_buf[0..j]}) catch unreachable;
        textures[i] = loadTexture(path, fallback_texture);
    }
    return textures;
}

pub fn loadTexturesList(
    comptime paths: []const []const u8,
    fallback: ?raylib.Texture2D,
    len: usize,
    allocator: std.mem.Allocator,
) ![]raylib.Texture2D {
    const textures = try allocator.alloc(raylib.Texture2D, len);
    errdefer allocator.free(textures);

    for (paths, 0..) |path, i| {
        var path_buf: [256]u8 = undefined;
        const path_0 = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch unreachable;
        textures[i] = loadTexture(path_0, fallback);
    }
    return textures;
}

pub fn loadTexturesTextList(
    comptime path_fmt: []const u8,
    universal_fallback: ?raylib.Texture2D,
    comptime text_strings: []const []const u8,
    len: usize,
    allocator: std.mem.Allocator,
) ![]const raylib.Texture2D {
    const textures = try allocator.alloc(raylib.Texture2D, len);
    errdefer allocator.free(textures);

    var fallback_path_buf: [256]u8 = undefined;
    const fallback_path = std.fmt.bufPrintZ(&fallback_path_buf, path_fmt, .{"placeholder"}) catch unreachable;

    const fallback_texture = loadTexture(fallback_path, universal_fallback);

    for (0..len) |i| {
        const name = text_strings[i];
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, path_fmt, .{name}) catch unreachable;
        textures[i] = loadTexture(path, fallback_texture);
    }
    return textures;
}

pub fn loadTexturesEnum(
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

/// loads textures differentiated by a number eg "city0" "city1" "city2" and so on
pub fn loadNumberedTextures(
    comptime path_fmt: []const u8,
    universal_fallback: ?raylib.Texture2D,
    n: usize,
    allocator: std.mem.Allocator,
) ![]const raylib.Texture2D {
    const textures = try allocator.alloc(raylib.Texture2D, n);
    errdefer allocator.free(textures);

    var fallback_path_buf: [256]u8 = undefined;
    // 4711 is official placeholder for numerated types
    const fallback_path = std.fmt.bufPrintZ(&fallback_path_buf, path_fmt, .{4711}) catch unreachable;

    const fallback_texture = loadTexture(fallback_path, universal_fallback);

    for (0..n) |i| {
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, path_fmt, .{i}) catch unreachable;
        textures[i] = loadTexture(path, fallback_texture);
    }
    return textures;
}

/// probably outdated
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
            log.warn("No texture '{s}'.", .{path});
        }
        return fallback orelse @panic("loadTexture failed (No placeholder set)\n");
    };
    const img = raylib.LoadImage(path.ptr);
    defer raylib.UnloadImage(img);
    return raylib.LoadTextureFromImage(img);
}

/// functions from hex util
pub fn tilingX(self: *const Self, x: u32, y: u32) f32 {
    const fx: f32 = @floatFromInt(x);
    const y_odd: f32 = @floatFromInt(y & 1);

    return self.hex_width * fx + self.hex_width * 0.5 * y_odd;
}

pub fn tilingY(self: *const Self, y: u32) f32 {
    const fy: f32 = @floatFromInt(y);
    return fy * (self.hex_height / 2) * 1.5;
}

pub fn tilingWidth(self: *const Self, map_width: u32) f32 {
    const fwidth: f32 = @floatFromInt(map_width);
    return self.hex_width * (fwidth + 0.5); // TODO is this why one column is not renderd?
}

pub fn tilingHeight(self: *const Self, map_height: u32) f32 {
    const fheight: f32 = @floatFromInt(map_height);
    return 0.5 * (self.hex_height / 1.5) * (fheight - 1.0) + self.hex_height; // messy :)
}
