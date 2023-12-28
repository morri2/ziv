const std = @import("std");
const util = @import("util.zig");

const Terrain = @import("terrain.zig").Terrain;

const Yields = util.Yields;

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

const Improvement = struct {
    name: []const u8,
    build_turns: u8,
    dont_clear: []const []const u8 = &.{},
    allow_on: struct {
        resources: []const []const u8 = &.{},
        bases: []struct {
            name: []const u8,
            no_feature: bool = false,
            need_freshwater: bool = false,
        } = &.{},
        features: []struct {
            name: []const u8,
            need_freshwater: bool = false,
        } = &.{},
        vegetation: []struct {
            name: []const u8,
            need_freshwater: bool = false,
        } = &.{},
    },
};

const Removal = struct {
    vegetation: []const u8,
    yields: Yields = .{},
};

pub fn parseAndOutput(
    text: []const u8,
    terrain: []const Terrain,
    flag_index_map: *const FlagIndexMap,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    const parsed = try std.json.parseFromSlice(struct {
        improvements: []Improvement,
    }, allocator, text, .{});
    defer parsed.deinit();

    const improvements = parsed.value;

    try writer.print("\npub const ImprovementAllowed = enum {{ not_allowed, allowed, allowed_after_clear }};\n", .{});

    try util.startEnum(
        "ImprovementType",
        improvements.improvements.len,
        writer,
    );

    for (improvements.improvements) |improvement| {
        try writer.print("{s},\n", .{improvement.name});
    }

    // connects resource function
    try writer.print(
        \\
        \\pub fn connectsResource(self: @This(), resource: Resource) bool {{
        \\ return switch (self) {{
        \\
    , .{});

    for (improvements.improvements) |imp| {
        try writer.print(".{s} => switch (resource) {{", .{imp.name});
        for (imp.allow_on.resources) |res| {
            try writer.print(".{s}, ", .{res});
        }
        if (imp.allow_on.resources.len > 0) {
            try writer.print("=> true,", .{});
        }
        try writer.print("else => false, }},\n     ", .{});
    }

    try writer.print(
        \\
        \\  }};
        \\}}
        \\
    , .{});

    // public check allow function
    try writer.print(
        \\
        \\pub fn checkAllowedOn(self: @This(), terrain: Terrain, freshwater: bool) ImprovementAllowed  {{
        \\  var res: ImprovementAllowed  = false;
        \\  res = switch (self) {{
        \\
    , .{});

    for (improvements.improvements) |imp| {
        try writer.print(".{s} => {s}AllowedOn(terrain, freshwater), \n", .{ imp.name, imp.name });
    }

    try writer.print(
        \\
        \\   }};
        \\   return res;
        \\ }}
        \\
    , .{});

    // check allow for specific improvement :))
    for (improvements.improvements) |imp| {
        try writer.print(
            \\
            \\fn {s}AllowedOn(terrain: Terrain, freshwater: bool) ImprovementAllowed  {{
            \\if (freshwater and false) {{}} // STUPID, but needed
            \\return switch(terrain) {{ 
        , .{imp.name});

        const veg_flags = blk: {
            var flags = Flags.initEmpty();
            for (imp.allow_on.vegetation) |vegetation| {
                flags.set(flag_index_map.get(vegetation.name) orelse return error.UnknownVegetation);
            }
            break :blk flags;
        };

        terrain_loop: for (terrain) |terr| {
            for (imp.allow_on.bases) |base| {
                const base_flag = flag_index_map.get(base.name) orelse return error.UnknownBase;
                if (!terr.flags.isSet(base_flag)) continue;

                if (terr.has_feature and base.no_feature) continue;

                try writer.print(".{s} => ", .{terr.name});
                if (base.need_freshwater) try writer.print("if(freshwater) ", .{});

                const has_allowed_vegegation = veg_flags.intersectWith(terr.flags).count() != 0;
                if (terr.has_vegetation and !has_allowed_vegegation) {
                    try writer.print(".allowed_after_clear,", .{});
                } else {
                    try writer.print(".allowed,", .{});
                }

                continue :terrain_loop;
            }

            for (imp.allow_on.features) |feature| {
                const feature_flag = flag_index_map.get(feature.name) orelse return error.UnknownFeature;
                if (!terr.flags.isSet(feature_flag)) continue;

                try writer.print(".{s} => ", .{terr.name});
                if (feature.need_freshwater) try writer.print("if(freshwater) ", .{});
                const has_allowed_vegegation = veg_flags.intersectWith(terr.flags).count() != 0;
                if (terr.has_vegetation and !has_allowed_vegegation) {
                    try writer.print(".allowed_after_clear,", .{});
                } else {
                    try writer.print(".allowed,", .{});
                }
                continue :terrain_loop;
            }

            for (imp.allow_on.vegetation) |vegetation| {
                const vegetation_flag = flag_index_map.get(vegetation.name) orelse return error.UnknownFeature;
                if (!terr.flags.isSet(vegetation_flag)) continue;

                try writer.print(".{s} => ", .{terr.name});
                if (vegetation.need_freshwater) try writer.print("if(freshwater) ", .{});
                try writer.print(".allowed,", .{});

                continue :terrain_loop;
            }
        }
        try writer.print("else => .not_allowed,", .{});

        try writer.print(
            \\}};
            \\}}
        , .{});
    }

    try util.endStructEnumUnion(writer);
}
