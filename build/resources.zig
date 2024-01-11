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
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
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

    // Yields
    try util.emitYieldTable(Resource, all_resources, writer);

    try writer.print(
        \\pub const Kind = enum (u2) {{
        \\bonus = 0,
        \\strategic = 1,
        \\luxury = 2,
        \\}};
    , .{});

    try writer.print("pub const kind_table = [_]Kind {{", .{});
    for (0..resources.bonus.len) |_| {
        try writer.print(".bonus,", .{});
    }
    for (0..resources.luxury.len) |_| {
        try writer.print(".luxury,", .{});
    }
    for (0..resources.strategic.len) |_| {
        try writer.print(".strategic,", .{});
    }
    try writer.print("}};", .{});

    try writer.print(
        \\pub fn kind(self: @This()) Kind {{
        \\return kind_table[@intFromEnum(self)];
        \\}}
    , .{});

    try util.endStructEnumUnion(writer);
}
