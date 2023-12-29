const std = @import("std");
const util = @import("util.zig");

const Terrain = @import("terrain.zig").Terrain;

const Yields = util.Yields;

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

const NaturalWonder = struct {
    name: []const u8,
    bases: []const []const u8 = &.{},
    yields: Yields = .{},
    happiness: u8 = 0,
};

pub fn parseAndOutput(
    text: []const u8,
    flag_index_map: *const FlagIndexMap,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    _ = flag_index_map;
    const parsed = try std.json.parseFromSlice(struct {
        natural_wonders: []const NaturalWonder,
    }, allocator, text, .{});
    defer parsed.deinit();

    const wonders = parsed.value.natural_wonders;

    try util.startEnum("NaturalWonder", wonders.len, writer);

    for (wonders, 0..) |wonder, i| {
        try writer.print("{s} = {},", .{ wonder.name, i });
    }

    try writer.print(
        \\pub fn happiness(self: @This()) u8 {{
        \\return switch(self) {{
    , .{});

    for (wonders) |wonder| {
        if (wonder.happiness != 0) try writer.print(".{s} => {},", .{ wonder.name, wonder.happiness });
    }
    try writer.print("else => 0,", .{});

    try writer.print(
        \\}};
        \\}}
    , .{});

    try util.emitYieldsFunc(NaturalWonder, wonders, writer);

    try util.endStructEnumUnion(writer);
}
