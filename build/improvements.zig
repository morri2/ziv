const std = @import("std");
const util = @import("util.zig");

const Terrain = @import("terrain.zig").Terrain;

const Yields = util.Yields;

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

const Improvement = struct {
    name: []const u8,
    build_turns: u8,
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
    yields: Yields = .{},
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
        "Improvement",
        improvements.improvements.len,
        writer,
    );

    try writer.print("none,\n", .{});

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
        \\pub fn checkAllowedOn(self: @This(), tile: Tile, maybe_resource: ?Resource) ImprovementAllowed  {{
        \\  return switch (self) {{
        \\
    , .{});

    for (improvements.improvements) |imp| {
        try writer.print(".{s} => {s}AllowedOn(tile, maybe_resource), \n", .{ imp.name, imp.name });
    }

    try writer.print(
        \\       .none => unreachable, 
        \\   }};
        \\ }}
        \\
    , .{});

    // check allow for specific improvement :))
    for (improvements.improvements) |imp| {
        try writer.print(
            \\
            \\fn {s}AllowedOn(tile: Tile, maybe_resource: ?Resource) ImprovementAllowed  {{
            \\if(maybe_resource) |_| {{}}
            \\return switch(tile.terrain) {{ 
        , .{imp.name});

        const veg_flags = blk: {
            var flags = Flags.initEmpty();
            for (imp.allow_on.vegetation) |vegetation| {
                flags.set(flag_index_map.get(vegetation.name) orelse return error.UnknownVegetation);
            }
            break :blk flags;
        };

        var found = std.ArrayList(struct {
            name: []const u8,
            tag: enum {
                allowed,
                allowed_after_clear,
                allowed_if_freshwater,
                allowed_after_clear_if_freshwater,
                has_vegetation_resource,
            },
        }).init(allocator);
        defer found.deinit();

        terrain_loop: for (terrain) |terr| {
            for (imp.allow_on.bases) |base| {
                const base_flag = flag_index_map.get(base.name) orelse return error.UnknownBase;
                if (!terr.flags.isSet(base_flag)) continue;

                if (terr.has_feature and base.no_feature) continue;

                const has_allowed_vegegation = veg_flags.intersectWith(terr.flags).count() != 0;
                if (terr.has_vegetation and !has_allowed_vegegation) {
                    try found.append(.{
                        .name = terr.name,
                        .tag = if (base.need_freshwater) .allowed_after_clear_if_freshwater else .allowed_after_clear,
                    });
                } else {
                    try found.append(.{
                        .name = terr.name,
                        .tag = if (base.need_freshwater) .allowed_if_freshwater else .allowed,
                    });
                }

                continue :terrain_loop;
            }

            for (imp.allow_on.features) |feature| {
                const feature_flag = flag_index_map.get(feature.name) orelse return error.UnknownFeature;
                if (!terr.flags.isSet(feature_flag)) continue;

                const has_allowed_vegegation = veg_flags.intersectWith(terr.flags).count() != 0;
                if (terr.has_vegetation and !has_allowed_vegegation) {
                    try found.append(.{
                        .name = terr.name,
                        .tag = if (feature.need_freshwater) .allowed_after_clear_if_freshwater else .allowed_after_clear,
                    });
                } else {
                    try found.append(.{
                        .name = terr.name,
                        .tag = if (feature.need_freshwater) .allowed_if_freshwater else .allowed,
                    });
                }
                continue :terrain_loop;
            }

            for (imp.allow_on.vegetation) |vegetation| {
                const vegetation_flag = flag_index_map.get(vegetation.name) orelse return error.UnknownFeature;
                if (!terr.flags.isSet(vegetation_flag)) continue;

                try found.append(.{
                    .name = terr.name,
                    .tag = if (vegetation.need_freshwater) .allowed_if_freshwater else .allowed,
                });

                continue :terrain_loop;
            }

            if (terr.has_vegetation and imp.allow_on.resources.len != 0) {
                try found.append(.{
                    .name = terr.name,
                    .tag = .has_vegetation_resource,
                });
            }
        }

        inline for (&.{
            .allowed,
            .allowed_after_clear,
            .allowed_if_freshwater,
            .allowed_after_clear_if_freshwater,
            .has_vegetation_resource,
        }) |tag| {
            var count: usize = 0;
            for (found.items) |f| {
                if (f.tag != tag) continue;
                try writer.print(".{s},", .{f.name});
                count += 1;
            }

            if (count != 0) {
                try writer.print("=>", .{});
                switch (tag) {
                    .allowed_if_freshwater,
                    .allowed_after_clear_if_freshwater,
                    => try writer.print("if(tile.freshwater)", .{}),
                    else => {},
                }
                switch (tag) {
                    .allowed_if_freshwater,
                    .allowed,
                    => try writer.print(".allowed,", .{}),
                    .allowed_after_clear_if_freshwater,
                    .allowed_after_clear,
                    => try writer.print(".allowed_after_clear,", .{}),
                    .has_vegetation_resource => {
                        try writer.print(
                            \\if(maybe_resource) |resource| switch(resource) {{
                        , .{});
                        for (imp.allow_on.resources) |resource| {
                            try writer.print(".{s},", .{resource});
                        }
                        try writer.print(
                            \\=> .allowed_after_clear,
                            \\else => .not_allowed,
                            \\}} else .not_allowed,
                        , .{});
                    },
                    else => {},
                }
            }
        }
        if (found.items.len != terrain.len) {
            try writer.print("else =>", .{});

            if (imp.allow_on.resources.len != 0) {
                try writer.print(
                    \\if(maybe_resource) |resource| switch(resource) {{
                , .{});
                for (imp.allow_on.resources) |resource| {
                    try writer.print(".{s},", .{resource});
                }
                try writer.print(
                    \\=> .allowed_after_clear,
                    \\else => .not_allowed,
                    \\}} else .not_allowed,
                , .{});
            } else {
                try writer.print(".not_allowed,", .{});
            }
        }

        try writer.print(
            \\}};
            \\}}
        , .{});
    }

    try writer.print(
        \\pub fn addYield(self: @This(), yield: *Yield) void {{
        \\switch(self) {{
    , .{});
    for (improvements.improvements) |e| {
        try writer.print(".{s} => {{", .{e.name});
        if (e.yields.food != 0) try writer.print("yield.food += {};", .{e.yields.food});
        if (e.yields.production != 0) try writer.print("yield.production += {};", .{e.yields.production});
        if (e.yields.gold != 0) try writer.print("yield.gold += {};", .{e.yields.gold});
        if (e.yields.culture != 0) try writer.print("yield.culture += {};", .{e.yields.culture});
        if (e.yields.science != 0) try writer.print("yield.science += {};", .{e.yields.science});
        if (e.yields.faith != 0) try writer.print("yield.faith += {};", .{e.yields.faith});
        try writer.print("}},", .{});
    }
    try writer.print(
        \\.none => .{{}},
        \\}}
        \\}}
    , .{});

    try util.endStructEnumUnion(writer);
}
