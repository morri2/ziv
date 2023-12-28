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

pub fn parseAndOutput(
    text: []const u8,
    flag_index_map: *FlagIndexMap,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
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
    for (terrain.features, 0..) |feature, i| {
        try writer.print("{s} = {},", .{ feature.name, i });
    }
    try util.endStructEnumUnion(writer);

    try util.startEnum("Vegetation", terrain.vegetation.len, writer);
    for (terrain.vegetation, 0..) |vegetation, i| {
        try writer.print("{s} = {},", .{ vegetation.name, i });
    }
    try util.endStructEnumUnion(writer);

    const TerrainCombo = struct {
        name: []const u8,
        yields: Yields,
        flags: Flags,
        is_water: bool,
        is_rough: bool,
        is_impassable: bool,
    };

    var terrain_combos = std.ArrayList(TerrainCombo).init(allocator);
    defer terrain_combos.deinit();

    // Add all base tiles to terrain combinations
    for (terrain.bases) |base| {
        const base_index = try flag_index_map.add(base.name);

        var flags = Flags.initEmpty();
        flags.set(base_index);

        try terrain_combos.append(.{
            .name = base.name,
            .yields = base.yields,
            .flags = flags,
            .is_water = base.is_water,
            .is_rough = base.is_rough,
            .is_impassable = base.is_impassable,
        });
    }

    inline for ([_][]const u8{ "features", "vegetation" }) |field_name| {
        for (@field(terrain, field_name)) |feature| {
            const feature_index = try flag_index_map.add(feature.name);

            const allowed_flags = flag_index_map.flagsFromKeys(feature.bases).unionWith(
                flag_index_map.flagsFromKeys(feature.features),
            );

            for (0..terrain_combos.items.len) |combo_index| {
                const combo = terrain_combos.items[combo_index];
                if (!combo.flags.intersectWith(allowed_flags).eql(combo.flags)) continue;

                var new_flags = combo.flags;
                new_flags.set(feature_index);

                try terrain_combos.append(.{
                    .name = try std.mem.concat(arena.allocator(), u8, &.{
                        combo.name,
                        "_",
                        feature.name,
                    }),
                    .yields = feature.yields,
                    .flags = new_flags,
                    .is_water = combo.is_water,
                    .is_rough = combo.is_rough or feature.is_rough,
                    .is_impassable = combo.is_impassable or feature.is_impassable,
                });
            }
        }
    }

    try util.startEnum("Terrain", terrain_combos.items.len, writer);
    for (terrain_combos.items, 0..) |combo, i| {
        try writer.print("{s} = {},", .{ combo.name, i });
    }

    try writer.print("\n\n", .{});
    try util.emitYieldsFunc(TerrainCombo, terrain_combos.items, writer);

    // Emit hasBase, hasFeature, hasVegetation
    inline for (
        [_][]const u8{ "bases", "features", "vegetation" },
        [_][]const u8{ "base", "feature", "vegetation" },
        [_][]const u8{ "Base", "Feature", "Vegetation" },
    ) |field_name, func_name, enum_name| {
        try writer.print(
            \\pub fn {s}(self: @This()) {s} {{
            \\return switch(self) {{
        , .{ func_name, enum_name });
        for (@field(terrain, field_name)) |feature| {
            for (terrain_combos.items) |combo| {
                if (combo.flags.isSet(flag_index_map.get(feature.name).?)) {
                    try writer.print(
                        \\.{s},
                    , .{combo.name});
                }
            }
            try writer.print(
                \\=> .{s},
            , .{feature.name});
        }
        try writer.print(
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
        for (terrain_combos.items) |combo| {
            if (@field(combo, field_name)) {
                try writer.print(".{s},", .{combo.name});
                count += 1;
            }
        }
        if (count != 0) {
            try writer.print("=> true,", .{});
        }
        if (count != terrain_combos.items.len) {
            try writer.print("else => false,", .{});
        }
        try writer.print(
            \\}};
            \\}}
        , .{});
    }

    try util.endStructEnumUnion(writer);
}
