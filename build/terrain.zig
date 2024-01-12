const std = @import("std");
const util = @import("util.zig");

const Yields = util.Yields;

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

const Base = struct {
    name: []const u8,
    yields: Yields = .{},
    happiness: u8 = 0,

    attributes: []const []const u8 = &.{},
    combat_bonus: i8 = 0,
};

const Feature = struct {
    name: []const u8,
    yields: Yields = .{},

    bases: []const []const u8,

    attributes: []const []const u8 = &.{},
    combat_bonus: i8 = 0,
};

const Vegetation = struct {
    name: []const u8,
    yields: Yields = .{},

    bases: []const []const u8,
    features: []const []const u8 = &.{},

    attributes: []const []const u8 = &.{},
    combat_bonus: i8 = 0,
};

const Override = struct {
    name: ?[]const u8 = null,
    yields: ?Yields = null,
    happiness: u8 = 0,

    base: []const u8,
    feature: ?[]const u8 = null,
    vegetation: ?[]const u8 = null,

    attributes: []const []const u8 = &.{},
    combat_bonus: ?i8 = null,
};

pub const Tile = struct {
    name: []const u8,
    yields: Yields,
    happiness: u8,
    combat_bonus: i8,

    base: usize,
    feature: ?usize = null,
    vegetation: ?usize = null,
    attributes: Flags = Flags.initEmpty(),
};

pub const Terrain = struct {
    tiles: []const Tile,
    maps: struct {
        bases: FlagIndexMap,
        features: FlagIndexMap,
        vegetation: FlagIndexMap,
        attributes: FlagIndexMap,
    },
    arena: std.heap.ArenaAllocator,
};

pub fn parseAndOutput(
    text: []const u8,
    writer: anytype,
    allocator: std.mem.Allocator,
) !Terrain {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var maps = .{
        .bases = try FlagIndexMap.init(allocator),
        .features = try FlagIndexMap.init(allocator),
        .vegetation = try FlagIndexMap.init(allocator),
        .attributes = try FlagIndexMap.init(allocator),
    };

    const parsed = try std.json.parseFromSlice(struct {
        bases: []const Base,
        features: []const Feature,
        vegetation: []const Vegetation,
        overrides: []const Override,
    }, allocator, text, .{});
    defer parsed.deinit();

    const terrain = parsed.value;

    try util.startEnum("Base", terrain.bases.len, writer);
    for (terrain.bases, 0..) |base, i| {
        try writer.print("{s} = {},", .{ base.name, i });
    }
    try util.endStructEnumUnion(writer);

    try util.startEnum("Feature", terrain.features.len + 1, writer);
    try writer.print("none = 0,", .{});
    for (terrain.features, 1..) |feature, i| {
        try writer.print("{s} = {},", .{ feature.name, i });
    }
    try util.endStructEnumUnion(writer);

    try util.startEnum("Vegetation", terrain.vegetation.len + 1, writer);
    try writer.print("none = 0,", .{});
    for (terrain.vegetation, 1..) |vegetation, i| {
        try writer.print("{s} = {},", .{ vegetation.name, i });
    }
    try util.endStructEnumUnion(writer);

    var tiles = std.ArrayList(Tile).init(allocator);
    defer tiles.deinit();

    // Add all base tiles to terrain combinations
    for (terrain.bases) |base| {
        const base_index = try maps.bases.add(base.name);

        try tiles.append(.{
            .name = try arena.allocator().dupe(u8, base.name),
            .yields = base.yields,
            .happiness = base.happiness,
            .base = base_index,
            .attributes = try maps.attributes.addAndGetFlagsFromKeys(base.attributes),
            .combat_bonus = base.combat_bonus,
        });
    }

    {
        const tiles_len = tiles.items.len;
        for (terrain.features) |feature| {
            const feature_index = try maps.features.add(feature.name);

            const allowed_bases = maps.bases.flagsFromKeys(feature.bases);
            for (0..tiles_len) |tile_index| {
                const tile = tiles.items[tile_index];
                if (!allowed_bases.isSet(tile.base)) continue;

                var new_tile = tile;
                new_tile.name = try std.mem.concat(
                    arena.allocator(),
                    u8,
                    &.{ tile.name, "_", feature.name },
                );
                new_tile.yields = feature.yields;
                new_tile.feature = feature_index;
                new_tile.attributes = new_tile.attributes.unionWith(
                    try maps.attributes.addAndGetFlagsFromKeys(feature.attributes),
                );
                new_tile.combat_bonus = feature.combat_bonus;
                try tiles.append(new_tile);
            }
        }
    }

    {
        const tiles_len = tiles.items.len;
        for (terrain.vegetation) |vegetation| {
            const vegetation_index = try maps.vegetation.add(vegetation.name);

            const allowed_bases = maps.bases.flagsFromKeys(vegetation.bases);
            const allowed_features = maps.features.flagsFromKeys(vegetation.features);

            for (0..tiles_len) |tile_index| {
                const tile = tiles.items[tile_index];
                if (!allowed_bases.isSet(tile.base)) continue;
                if (tile.feature != null and !allowed_features.isSet(tile.feature.?)) continue;

                var new_tile = tile;
                new_tile.name = try std.mem.concat(
                    arena.allocator(),
                    u8,
                    &.{ tile.name, "_", vegetation.name },
                );
                new_tile.yields = vegetation.yields;
                new_tile.vegetation = vegetation_index;
                new_tile.attributes = new_tile.attributes.unionWith(
                    try maps.attributes.addAndGetFlagsFromKeys(vegetation.attributes),
                );
                new_tile.combat_bonus = vegetation.combat_bonus;
                try tiles.append(new_tile);
            }
        }
    }

    // Add river and freshwater attribute tiles
    {
        const river_index = try maps.attributes.add("river");
        const freshwater_index = try maps.attributes.add("freshwater");

        const water_index = try maps.attributes.addOrGet("water");
        for (0..tiles.items.len) |tile_index| {
            const tile = tiles.items[tile_index];
            if (tile.attributes.isSet(water_index)) continue;

            var new_attributes = tile.attributes;
            new_attributes.set(river_index);
            new_attributes.set(freshwater_index);

            var new_tile = tile;
            new_tile.name = try std.mem.concat(
                arena.allocator(),
                u8,
                &.{ tile.name, "_river" },
            );
            new_tile.attributes = new_attributes;
            try tiles.append(new_tile);
        }

        for (0..tiles.items.len) |tile_index| {
            const tile = tiles.items[tile_index];
            if (tile.attributes.isSet(water_index)) continue;

            if (tile.attributes.isSet(freshwater_index)) continue;

            var new_attributes = tile.attributes;
            new_attributes.set(freshwater_index);

            var new_tile = tile;
            new_tile.name = try std.mem.concat(
                arena.allocator(),
                u8,
                &.{ tile.name, "_freshwater" },
            );
            new_tile.attributes = new_attributes;
            try tiles.append(new_tile);
        }
    }

    // Add overrides
    {
        for (terrain.overrides) |override| {
            const base_index = maps.bases.get(override.base) orelse return error.UnknownBase;
            const feature_index = if (override.feature) |feature| maps.features.get(feature) orelse return error.UnknownFeature else null;
            const vegetation_index = if (override.vegetation) |vegetation| maps.vegetation.get(vegetation) orelse return error.UnknownVegetation else null;
            const attributes = blk: {
                var attributes = maps.attributes.flagsFromKeys(override.attributes);
                const river_index = maps.attributes.get("river").?;
                const freshwater_index = maps.attributes.get("freshwater").?;
                if (attributes.isSet(river_index)) attributes.set(freshwater_index);

                break :blk attributes;
            };
            for (tiles.items) |*tile| {
                if (tile.base != base_index) continue;
                if (tile.feature != feature_index) continue;
                if (tile.vegetation != vegetation_index) continue;

                if (!attributes.intersectWith(tile.attributes).eql(attributes)) continue;

                if (override.name) |name| tile.name = try arena.allocator().dupe(u8, name);

                if (override.yields) |yields| tile.yields = yields;
                if (override.combat_bonus) |combat_bonus| tile.combat_bonus = combat_bonus;
            }
        }
    }

    try writer.print("pub const Attributes = packed struct {{", .{});
    for (maps.attributes.indices.keys()) |name| {
        try writer.print("{s}: bool = false,", .{name});
    }
    try writer.print("}};", .{});

    try util.startEnum("Terrain", tiles.items.len, writer);
    for (tiles.items, 0..) |tile, i| {
        try writer.print("{s} = {},", .{ tile.name, i });
    }

    try writer.print("\n\n", .{});

    // yield()
    try util.emitYieldTable(Tile, tiles.items, writer);

    // base(), feature(), vegetation()
    {
        const base_names = maps.bases.indices.keys();
        try writer.print("pub const base_table = [_]Base{{", .{});
        for (tiles.items) |tile| {
            try writer.print(".{s},", .{base_names[tile.base]});
        }
        try writer.print("}};", .{});

        const feature_names = maps.features.indices.keys();
        try writer.print("pub const feature_table = [_]Feature{{", .{});
        for (tiles.items) |tile| {
            if (tile.feature) |feature| {
                try writer.print(".{s},", .{feature_names[feature]});
            } else {
                try writer.print(".none,", .{});
            }
        }
        try writer.print("}};", .{});

        const vegetation_names = maps.vegetation.indices.keys();
        try writer.print("pub const vegetation_table = [_]Vegetation{{", .{});
        for (tiles.items) |tile| {
            if (tile.vegetation) |vegetation| {
                try writer.print(".{s},", .{vegetation_names[vegetation]});
            } else {
                try writer.print(".none,", .{});
            }
        }
        try writer.print("}};", .{});

        try writer.print(
            \\pub inline fn base(self: @This()) Base {{
            \\return base_table[@intFromEnum(self)];
            \\}}
            \\pub inline fn feature(self: @This()) Feature {{
            \\return feature_table[@intFromEnum(self)];
            \\}}
            \\pub inline fn vegetation(self: @This()) Vegetation {{
            \\return vegetation_table[@intFromEnum(self)];
            \\}}
        , .{});
    }

    // attributes()
    {
        const attribute_names = maps.attributes.indices.keys();
        try writer.print("pub const attribute_table = [_]Attributes {{", .{});
        for (tiles.items) |tile| {
            var flags = tile.attributes;
            try writer.print(".{{", .{});
            while (flags.toggleFirstSet()) |index| {
                try writer.print(".{s} = true,", .{attribute_names[index]});
            }
            try writer.print("}},", .{});
        }
        try writer.print("}};", .{});

        try writer.print(
            \\pub fn attributes(self: @This()) Attributes {{
            \\return attribute_table[@intFromEnum(self)];
            \\}}
        , .{});
    }

    // happiness()
    {
        try writer.print("pub const happiness_table = [_]u8 {{", .{});
        for (tiles.items) |tile| {
            try writer.print("{},", .{tile.happiness});
        }
        try writer.print("}};", .{});

        try writer.print(
            \\pub fn happiness(self: @This()) u8 {{
            \\return happiness_table[@intFromEnum(self)];
            \\}}
        , .{});
    }

    try util.endStructEnumUnion(writer);

    {
        try writer.print(
            \\pub const TerrainUnpacked = struct {{
            \\base: Base,
            \\feature: ?Feature = null,
            \\vegetation: ?Vegetation = null,
            \\river: bool = false,
            \\freshwater: bool = false,
            \\
            \\const map = foundation.comptime_hash_map.AutoComptimeHashMap(@This(), Terrain, .{{
        , .{});

        const river_attribute_index = maps.attributes.get("river").?;
        const freshwater_attribute_index = maps.attributes.get("freshwater").?;

        const base_names = maps.bases.indices.keys();
        const feature_names = maps.features.indices.keys();
        const vegetation_names = maps.vegetation.indices.keys();
        for (tiles.items[0..32]) |tile| {
            try writer.print(".{{.{{.base = .{s},", .{base_names[tile.base]});
            if (tile.feature) |feature| try writer.print(".feature = .{s},", .{feature_names[feature]});
            if (tile.vegetation) |vegetation| try writer.print(".vegetation = .{s},", .{vegetation_names[vegetation]});
            try writer.print(".river = {},", .{tile.attributes.isSet(river_attribute_index)});
            try writer.print(".freshwater = {},", .{tile.attributes.isSet(freshwater_attribute_index)});
            try writer.print("}}, .{s}, }},", .{tile.name});
        }

        try writer.print(
            \\}});
            \\pub fn pack(self: @This()) ?Terrain {{
            \\return map.get(self);
            \\}}
        , .{});
        try util.endStructEnumUnion(writer);
    }

    return .{
        .tiles = try tiles.toOwnedSlice(),
        .maps = .{
            .bases = maps.bases,
            .features = maps.features,
            .vegetation = maps.vegetation,
            .attributes = maps.attributes,
        },
        .arena = arena,
    };
}
