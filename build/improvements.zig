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
            required_attributes: []const []const u8 = &.{},
        } = &.{},
        features: []struct {
            name: []const u8,
            required_attributes: []const []const u8 = &.{},
        } = &.{},
        vegetation: []struct {
            name: []const u8,
            required_attributes: []const []const u8 = &.{},
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
    terrain: *const Terrain,
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
        \\pub fn allowedOn(self: @This(), tile: Tile, maybe_resource: ?Resource) ImprovementAllowed  {{
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
                flags.set(terrain.maps.vegetation.get(vegetation.name) orelse return error.UnknownVegetation);
            }
            break :blk flags;
        };

        const Tag = enum {
            allowed,
            allowed_after_clear,
            has_vegetation_resource,
        };

        var found = std.ArrayList(struct {
            name: []const u8,
            tag: Tag,
        }).init(allocator);
        defer found.deinit();

        terrain_loop: for (terrain.tiles) |tile| {
            const tag: Tag = if (tile.vegetation) |veg| if (veg_flags.isSet(veg)) .allowed else .allowed_after_clear else .allowed;

            for (imp.allow_on.bases) |base| {
                const base_index = terrain.maps.bases.get(base.name) orelse return error.UnknownBase;
                if (tile.base != base_index) continue;

                if (base.no_feature and tile.feature != null) continue;

                const required_attributes = terrain.maps.attributes.flagsFromKeys(base.required_attributes);
                if (!tile.attributes.intersectWith(required_attributes).eql(required_attributes)) continue;

                try found.append(.{
                    .name = tile.name,
                    .tag = tag,
                });

                continue :terrain_loop;
            }

            for (imp.allow_on.features) |feature| {
                const feature_index = terrain.maps.features.get(feature.name) orelse return error.UnknownFeature;
                if (tile.feature == null) continue;
                if (tile.feature != feature_index) continue;

                const required_attributes = terrain.maps.attributes.flagsFromKeys(feature.required_attributes);
                if (!tile.attributes.intersectWith(required_attributes).eql(required_attributes)) continue;

                try found.append(.{
                    .name = tile.name,
                    .tag = tag,
                });
                continue :terrain_loop;
            }

            for (imp.allow_on.vegetation) |vegetation| {
                const vegetation_index = terrain.maps.vegetation.get(vegetation.name) orelse return error.UnknownVegetation;
                if (tile.vegetation == null) continue;
                if (tile.vegetation != vegetation_index) continue;

                const required_attributes = terrain.maps.attributes.flagsFromKeys(vegetation.required_attributes);

                if (!tile.attributes.intersectWith(required_attributes).eql(required_attributes)) continue;
                try found.append(.{
                    .name = tile.name,
                    .tag = .allowed,
                });

                continue :terrain_loop;
            }

            if (tile.vegetation != null and imp.allow_on.resources.len != 0) {
                try found.append(.{
                    .name = tile.name,
                    .tag = .has_vegetation_resource,
                });
            }
        }

        inline for (&.{
            .allowed,
            .allowed_after_clear,
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
                    .allowed => try writer.print(".allowed,", .{}),
                    .allowed_after_clear => try writer.print(".allowed_after_clear,", .{}),
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
        if (found.items.len != terrain.tiles.len) {
            try writer.print("else =>", .{});

            if (imp.allow_on.resources.len != 0) {
                try writer.print(
                    \\if(maybe_resource) |resource| switch(resource) {{
                , .{});
                for (imp.allow_on.resources) |resource| {
                    try writer.print(".{s},", .{resource});
                }
                try writer.print(
                    \\=> .allowed,
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

    try util.emitYieldsFunc(Improvement, improvements.improvements, allocator, writer, true);

    try util.endStructEnumUnion(writer);
}
