const std = @import("std");

pub const Yields = struct {
    food: u8 = 0,
    production: u8 = 0,
    gold: u8 = 0,
    culture: u8 = 0,
    science: u8 = 0,
    faith: u8 = 0,
};

pub fn bitsFittingMax(max: usize) usize {
    const base = std.math.log2(max);
    const upper = (@as(usize, 1) << @truncate(base)) - 1;
    return if (upper >= max) base else base + 1;
}

pub fn startEnum(
    name: []const u8,
    num_elements: usize,
    writer: anytype,
) !void {
    try writer.print(
        \\pub const {s} = enum(u{}) {{
    , .{ name, bitsFittingMax(num_elements) });
}

pub fn endStructEnumUnion(writer: anytype) !void {
    try writer.print("}};\n\n", .{});
}

pub fn emitYieldsFunc(comptime T: type, arr: []const T, writer: anytype) !void {
    try writer.print(
        \\pub fn addYield(self: @This(), yield: *Yield) void {{
        \\switch(self) {{
    , .{});
    for (arr) |e| {
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
        \\}}
        \\}}
    , .{});
}
