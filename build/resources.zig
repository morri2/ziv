const std = @import("std");
const util = @import("util.zig");

const Yields = util.Yields;

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

const Resource = struct {
    name: []const u8,
    yields: Yields = .{},
    bases: []const []const u8 = &.{},
    features: []const []const u8 = &.{},
    vegetation: []const []const u8 = &.{},
};

pub fn parseAndOutput(
    text: []const u8,
    flag_index_map: *FlagIndexMap,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    _ = flag_index_map;
    const parsed = try std.json.parseFromSlice(struct {
        bonus: []const Resource,
        strategic: []const Resource,
        luxury: []const Resource,
    }, allocator, text, .{});
    defer parsed.deinit();

    const resources = parsed.value;

    try util.startEnum(
        "ResourceType",
        resources.bonus.len + resources.strategic.len + resources.luxury.len,
        writer,
    );

    const all_resources = try std.mem.concat(allocator, Resource, &.{
        resources.bonus,
        resources.luxury,
        resources.strategic,
    });
    defer allocator.free(all_resources);

    for (all_resources) |resource| {
        try writer.print("{s},", .{resource.name});
    }

    try util.emitYieldsFunc(Resource, all_resources, writer);

    inline for (
        [_][]const u8{ "bonus", "strategic", "luxury" },
        [_][]const u8{ "isBonus", "isStrategic", "isLuxury" },
    ) |field_name, func_name| {
        try writer.print(
            \\pub fn {s}(self: @This()) bool {{
            \\return switch(self) {{
        , .{func_name});
        for (@field(resources, field_name)) |resource| {
            try writer.print(".{s},", .{resource.name});
        }
        try writer.print(
            \\=> true,
            \\else => false,
            \\}};
            \\}}
        , .{});
    }

    try util.endStructEnumUnion(writer);
}
