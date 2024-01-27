const Rules = @import("../Rules.zig");
const Self = @This();
const Terrain = Rules.Terrain;

const hex = @import("hex_util.zig");
const Idx = @import("../Grid.zig").Idx;

const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

allocator: std.mem.Allocator,
font: raylib.Font,
vegetation_textures: []const raylib.Texture2D,
base_textures: []const raylib.Texture2D,
feature_textures: []const raylib.Texture2D,
unit_icons: []const raylib.Texture2D,
resource_icons: []const raylib.Texture2D,
transport_textures: []const raylib.Texture2D,
improvement_textures: []const raylib.Texture2D,
edge_textures: []const raylib.Texture2D,
red_pop: raylib.Texture2D,
green_pop: raylib.Texture2D,
city_texture: raylib.Texture2D,
city_border_texture: raylib.Texture2D,
hex_radius: f32,

pub fn init(rules: *const Rules, allocator: std.mem.Allocator) !Self {
    const font = raylib.LoadFont("textures/custom_alagard.png");
    const universal_fallback = loadTexture("textures/placeholder.png", null);

    const hex_radius = @as(f32, @floatFromInt(universal_fallback.height)) * 0.5;
    return .{
        .allocator = allocator,
        .font = font,
        .hex_radius = hex_radius,
        .edge_textures = try loadTexturesList(&[_][]const u8{
            "textures/edge1.png",
            "textures/edge2.png",
            "textures/edge3.png",
        }, universal_fallback, 3, allocator),

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
        .unit_icons = try loadTextures(
            "textures/unit_{s}.png",
            universal_fallback,
            Rules.UnitType,
            rules,
            rules.unit_type_count,
            allocator,
        ),
        .city_texture = loadTexture("textures/city.png", null),
        .red_pop = loadTexture("textures/redpop.png", null),
        .green_pop = loadTexture("textures/pop.png", null),
        .city_border_texture = loadTexture("textures/city_border.png", null),
    };
}

pub fn deinit(self: *Self) void {
    for (self.unit_icons) |texture| raylib.UnloadTexture(texture);
    for (self.transport_textures) |texture| raylib.UnloadTexture(texture);
    for (self.improvement_textures) |texture| raylib.UnloadTexture(texture);
    for (self.resource_icons) |texture| raylib.UnloadTexture(texture);
    for (self.vegetation_textures) |texture| raylib.UnloadTexture(texture);
    for (self.feature_textures) |texture| raylib.UnloadTexture(texture);
    for (self.base_textures) |texture| raylib.UnloadTexture(texture);
    for (self.edge_textures) |texture| raylib.UnloadTexture(texture);

    self.allocator.free(self.unit_icons);
    self.allocator.free(self.transport_textures);
    self.allocator.free(self.improvement_textures);
    self.allocator.free(self.resource_icons);
    self.allocator.free(self.vegetation_textures);
    self.allocator.free(self.feature_textures);
    self.allocator.free(self.base_textures);
    self.allocator.free(self.edge_textures);
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
            std.debug.print("No texture '{s}'.\n", .{path});
        }
        return fallback orelse @panic("loadTexture failed (No placeholder set)\n");
    };
    const img = raylib.LoadImage(path.ptr);
    defer raylib.UnloadImage(img);
    return raylib.LoadTextureFromImage(img);
}
