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
};

const Feature = struct {
    name: []const u8,
    yields: Yields = .{},

    bases: []const []const u8,

    attributes: []const []const u8 = &.{},
};

const Vegetation = struct {
    name: []const u8,
    yields: Yields = .{},

    bases: []const []const u8,
    features: []const []const u8 = &.{},

    attributes: []const []const u8 = &.{},
};

const ExtraAttribute = struct {
    name: []const u8,
    @"or": []const []const u8 = &.{},
    @"and": []const []const u8 = &.{},
};

pub const Tile = struct {
    name: []const u8,
    yields: Yields,
    happiness: u8,

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
            .name = base.name,
            .yields = base.yields,
            .happiness = base.happiness,
            .base = base_index,
            .attributes = try maps.attributes.addAndGetFlagsFromKeys(base.attributes),
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
    try util.emitYieldsFunc(Tile, tiles.items, allocator, writer, false);

    // Emit base(), feature(), vegetation()
    {
        inline for (
            [_][]const u8{ "base", "feature", "vegetation" },
            [_][]const u8{ "bases", "features", "vegetation" },
            [_][]const u8{ "Base", "Feature", "Vegetation" },
            0..,
        ) |name, field_name, enum_name, i| {
            try writer.print(
                \\pub fn {s}(self: @This()) {s} {{
                \\return switch(self) {{
            , .{ name, enum_name });
            for (@field(terrain, field_name)) |e| {
                for (tiles.items) |tile| {
                    if (@field(tile, name) != @field(maps, field_name).get(e.name).?) continue;

                    try writer.print(
                        \\.{s},
                    , .{tile.name});
                }
                try writer.print(
                    \\=> .{s},
                , .{e.name});
            }
            if (i != 0) try writer.print("else => .none,", .{});
            try writer.print(
                \\}};
                \\}}
            , .{});
        }
    }

    // Emit attributes()
    {
        const indices = try allocator.alloc(u16, tiles.items.len);
        defer allocator.free(indices);

        for (0..indices.len) |i| {
            indices[i] = @truncate(i);
        }

        std.sort.pdq(u16, indices, tiles.items, struct {
            pub fn lessThan(context: []const Tile, a: u16, b: u16) bool {
                const a_bits = FlagIndexMap.integerFromFlags(context[a].attributes);
                const b_bits = FlagIndexMap.integerFromFlags(context[b].attributes);
                return a_bits < b_bits;
            }
        }.lessThan);

        try writer.print(
            \\pub fn attributes(self: @This()) Attributes {{
            \\return switch(self) {{
        , .{});
        const attribute_names = maps.attributes.indices.keys();

        var current_flags = tiles.items[indices[0]].attributes;
        for (indices) |i| {
            const tile = tiles.items[@intCast(i)];
            const new_flags = tile.attributes;
            if (!new_flags.eql(current_flags)) {
                if (current_flags.count() != 0) {
                    try writer.print(
                        \\=> .{{
                    , .{});
                    while (current_flags.toggleFirstSet()) |index| {
                        try writer.print(".{s} = true,", .{attribute_names[index]});
                    }
                    try writer.print("}},", .{});
                }
                current_flags = new_flags;
            }
            try writer.print(
                \\.{s},
            , .{tile.name});
        }

        try writer.print(
            \\=> .{{
        , .{});
        while (current_flags.toggleFirstSet()) |index| {
            try writer.print(".{s} = true,", .{attribute_names[index]});
        }
        try writer.print("}},", .{});

        try writer.print(
        //\\else => .{{}}, // Yeet, because all cases handled :)
            \\}};
            \\}}
        , .{});
    }

    // happiness()
    {
        try writer.print(
            \\pub fn happiness(self: @This()) u8 {{
            \\return switch(self) {{
        , .{});
        for (tiles.items) |tile| {
            if (tile.happiness == 0) continue;

            try writer.print(".{s} => {},", .{ tile.name, tile.happiness });
        }
        try writer.print(
            \\else => 0,
            \\}};
            \\}}
        , .{});
    }

    try util.endStructEnumUnion(writer);

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
