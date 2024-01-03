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
    , .{ name, bitsFittingMax(num_elements - 1) });
}

pub fn endStructEnumUnion(writer: anytype) !void {
    try writer.print("}};\n\n", .{});
}

pub fn emitYieldsFunc(
    comptime T: type,
    arr: []const T,
    allocator: std.mem.Allocator,
    writer: anytype,
    include_none: bool,
) !void {
    const indices = try allocator.alloc(u16, arr.len);
    defer allocator.free(indices);

    for (0..indices.len) |i| {
        indices[i] = @truncate(i);
    }

    std.sort.pdq(u16, indices, arr, struct {
        pub fn lessThan(context: []const T, a_idx: u16, b_idx: u16) bool {
            const a = context[a_idx].yields;
            const b = context[b_idx].yields;
            if (a.food != b.food) return a.food < b.food;
            if (a.production != b.production) return a.production < b.production;
            if (a.gold != b.gold) return a.gold < b.gold;
            if (a.culture != b.culture) return a.culture < b.culture;
            if (a.science != b.science) return a.science < b.science;
            return a.faith < b.faith;
        }
    }.lessThan);
    try writer.print(
        \\pub fn addYield(self: @This(), yield: *Yield) void {{
        \\switch(self) {{
    , .{});
    var current_yields = arr[indices[0]].yields;
    for (indices) |i| {
        const e = arr[@intCast(i)];
        const new_yields = e.yields;
        if (!std.meta.eql(current_yields, new_yields)) {
            try writer.print("=> {{", .{});
            if (current_yields.food != 0) try writer.print("yield.food += {};", .{current_yields.food});
            if (current_yields.production != 0) try writer.print("yield.production += {};", .{current_yields.production});
            if (current_yields.gold != 0) try writer.print("yield.gold += {};", .{current_yields.gold});
            if (current_yields.culture != 0) try writer.print("yield.culture += {};", .{current_yields.culture});
            if (current_yields.science != 0) try writer.print("yield.science += {};", .{current_yields.science});
            if (current_yields.faith != 0) try writer.print("yield.faith += {};", .{current_yields.faith});
            try writer.print("}},", .{});
            current_yields = new_yields;
        }
        try writer.print(".{s},", .{e.name});
    }
    try writer.print("=> {{", .{});
    if (current_yields.food != 0) try writer.print("yield.food += {};", .{current_yields.food});
    if (current_yields.production != 0) try writer.print("yield.production += {};", .{current_yields.production});
    if (current_yields.gold != 0) try writer.print("yield.gold += {};", .{current_yields.gold});
    if (current_yields.culture != 0) try writer.print("yield.culture += {};", .{current_yields.culture});
    if (current_yields.science != 0) try writer.print("yield.science += {};", .{current_yields.science});
    if (current_yields.faith != 0) try writer.print("yield.faith += {};", .{current_yields.faith});
    try writer.print("}},", .{});

    if (include_none) try writer.print("else => {{}},", .{});
    try writer.print(
        \\}}
        \\}}
    , .{});
}
