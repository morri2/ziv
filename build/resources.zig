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
        "Resource",
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

    try writer.print(
        \\pub const Kind = enum (u2) {{
        \\bonus = 0,
        \\strategic = 1,
        \\luxury = 2,
        \\}};
    , .{});

    try writer.print(
        \\pub fn kind(self: @This()) Kind {{
        \\return switch(self) {{
    , .{});
    inline for ([_][]const u8{ "bonus", "strategic", "luxury" }) |field_name| {
        for (@field(resources, field_name)) |resource| {
            try writer.print(".{s},", .{resource.name});
        }
        try writer.print(
            \\=> .{s},
        , .{field_name});
    }
    try writer.print(
        \\}};
        \\}}
    , .{});

    try util.endStructEnumUnion(writer);
}
