const std = @import("std");
const util = @import("util.zig");

const Yields = util.Yields;

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

const Base = struct {
    name: []const u8,
    yields: Yields = .{},
    is_water: bool = false,
    is_rough: bool = false,
    is_impassable: bool = false,
};

const Feature = struct {
    name: []const u8,
    yields: Yields = .{},
    bases: []const []const u8,
    features: []const []const u8 = &.{},
    is_rough: bool = false,
    is_impassable: bool = false,
};

pub const Terrain = struct {
    name: []const u8,
    yields: Yields,
    flags: Flags,
    has_feature: bool = false,
    has_vegetation: bool = false,
    is_water: bool,
    is_rough: bool,
    is_impassable: bool,
};

pub fn parseAndOutput(
    text: []const u8,
    flag_index_map: *FlagIndexMap,
    writer: anytype,
    allocator: std.mem.Allocator,
) ![]const Terrain {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const parsed = try std.json.parseFromSlice(struct {
        bases: []const Base,
        features: []const Feature,
        vegetation: []const Feature,
    }, allocator, text, .{});
    defer parsed.deinit();

    const terrain = parsed.value;

    try util.startEnum("Base", terrain.bases.len, writer);
    for (terrain.bases, 0..) |base, i| {
        try writer.print("{s} = {},", .{ base.name, i });
    }
    try util.endStructEnumUnion(writer);

    try util.startEnum("Feature", terrain.features.len, writer);
    try writer.print("none = 0,", .{});
    for (terrain.features, 1..) |feature, i| {
        try writer.print("{s} = {},", .{ feature.name, i });
    }
    try util.endStructEnumUnion(writer);

    try util.startEnum("Vegetation", terrain.vegetation.len, writer);
    try writer.print("none = 0,", .{});
    for (terrain.vegetation, 1..) |vegetation, i| {
        try writer.print("{s} = {},", .{ vegetation.name, i });
    }
    try util.endStructEnumUnion(writer);

    var terrain_tiles = std.ArrayList(Terrain).init(allocator);
    defer terrain_tiles.deinit();

    // Add all base tiles to terrain combinations
    for (terrain.bases) |base| {
        const base_index = try flag_index_map.add(base.name);

        var flags = Flags.initEmpty();
        flags.set(base_index);

        try terrain_tiles.append(.{
            .name = base.name,
            .yields = base.yields,
            .flags = flags,
            .is_water = base.is_water,
            .is_rough = base.is_rough,
            .is_impassable = base.is_impassable,
        });
    }

    inline for ([_][]const u8{ "features", "vegetation" }, 0..) |field_name, i| {
        for (@field(terrain, field_name)) |feature| {
            const feature_index = try flag_index_map.add(feature.name);

            const allowed_flags = flag_index_map.flagsFromKeys(feature.bases).unionWith(
                flag_index_map.flagsFromKeys(feature.features),
            );

            for (0..terrain_tiles.items.len) |tile_index| {
                const tile = terrain_tiles.items[tile_index];
                if (!tile.flags.intersectWith(allowed_flags).eql(tile.flags)) continue;

                var new_flags = tile.flags;
                new_flags.set(feature_index);

                try terrain_tiles.append(.{
                    .name = try std.mem.concat(arena.allocator(), u8, &.{
                        tile.name,
                        "_",
                        feature.name,
                    }),
                    .yields = feature.yields,
                    .flags = new_flags,
                    .has_feature = if (i == 0) true else tile.has_feature,
                    .has_vegetation = if (i == 1) true else tile.has_vegetation,
                    .is_water = tile.is_water,
                    .is_rough = tile.is_rough or feature.is_rough,
                    .is_impassable = tile.is_impassable or feature.is_impassable,
                });
            }
        }
    }

    try util.startEnum("Terrain", terrain_tiles.items.len, writer);
    for (terrain_tiles.items, 0..) |tile, i| {
        try writer.print("{s} = {},", .{ tile.name, i });
    }

    try writer.print("\n\n", .{});
    try util.emitYieldsFunc(Terrain, terrain_tiles.items, writer);

    // Emit base()
    {
        try writer.print(
            \\pub fn base(self: @This()) Base {{
            \\return switch(self) {{
        , .{});
        for (terrain.bases) |base| {
            for (terrain_tiles.items) |tile| {
                if (tile.flags.isSet(flag_index_map.get(base.name).?)) {
                    try writer.print(
                        \\.{s},
                    , .{tile.name});
                }
            }
            try writer.print(
                \\=> .{s},
            , .{base.name});
        }
        try writer.print(
            \\}};
            \\}}
        , .{});
    }

    // Emit feature(), vegetation()
    inline for (
        [_][]const u8{ "features", "vegetation" },
        [_][]const u8{ "feature", "vegetation" },
        [_][]const u8{ "Feature", "Vegetation" },
    ) |field_name, func_name, enum_name| {
        try writer.print(
            \\pub fn {s}(self: @This()) {s} {{
            \\return switch(self) {{
        , .{ func_name, enum_name });
        for (@field(terrain, field_name)) |feature| {
            for (terrain_tiles.items) |tile| {
                if (tile.flags.isSet(flag_index_map.get(feature.name).?)) {
                    try writer.print(
                        \\.{s},
                    , .{tile.name});
                }
            }
            try writer.print(
                \\=> .{s},
            , .{feature.name});
        }
        try writer.print(
            \\else => .none,
            \\}};
            \\}}
        , .{});
    }

    // Emit isSomething functions
    inline for (
        [_][]const u8{ "is_water", "is_impassable", "is_rough" },
        [_][]const u8{ "isWater", "isImpassable", "isRough" },
    ) |field_name, func_name| {
        try writer.print(
            \\pub fn {s}(self: @This()) bool {{
            \\return switch(self) {{
        , .{func_name});

        var count: usize = 0;
        for (terrain_tiles.items) |tile| {
            if (@field(tile, field_name)) {
                try writer.print(".{s},", .{tile.name});
                count += 1;
            }
        }
        if (count != 0) {
            try writer.print("=> true,", .{});
        }
        if (count != terrain_tiles.items.len) {
            try writer.print("else => false,", .{});
        }
        try writer.print(
            \\}};
            \\}}
        , .{});
    }

    try util.endStructEnumUnion(writer);

    return try terrain_tiles.toOwnedSlice();
}
