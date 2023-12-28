const std = @import("std");
const util = @import("util.zig");

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

// Universal Unit parameters
// Excluding Trade, Airplanes as of now
const UnitType = struct {
    name: []const u8,
    production_cost: u16, // Max cost, Nuclear Missile 1000
    move_points: u8, // Max movement, Nuclear Sub etc. 6
    combat_strength: u8, // Max combat strength, Giant Death Robot 150
    ranged_strength: u8,
    range: u8, // Max range, Nuclear Missile 12
    sight: u8, // Max 10 = 2 + 4 promotions + 1 scout + 1 nation + 1 Exploration + 1 Great Lighthouse
    domain: []const []const u8 = &.{},
    possible_promotions: []const []const u8 = &.{},
    starting_promotions: []const []const u8 = &.{},
};

const Promotion = struct {
    name: []const u8,
    requires: []const []const u8 = &.{}, // Seem to only be either of the listed, never 2 different
    replaces: ?[]const u8 = null,
};

pub fn parseAndOutputPromotions(
    text: []const u8,
    flag_index_map: *FlagIndexMap,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    const parsed = try std.json.parseFromSlice(
        struct { promotions: []const Promotion },
        allocator,
        text,
        .{},
    );
    defer parsed.deinit();

    const promotions = parsed.value.promotions;

    try util.startEnum("Promotion", promotions.len, writer);
    for (promotions) |promotion| {
        try writer.print("\n {s},", .{promotion.name});
        _ = try flag_index_map.add(promotion.name);
    }

    // Add prereq. function
    try writer.print(
        \\ pub fn hasRequired(new_promotion: Promotion,
        \\ promotion_flags: u{}) bool {{ return switch (new_promotion) {{
    , .{promotions.len});

    for (promotions) |promotion| {
        var bit_flags: Flags = flag_index_map.flagsFromKeys(promotion.requires);
        var bits: u256 = 0;
        while (bit_flags.toggleFirstSet()) |bit_pos| {
            bits |= (@as(u256, 1) << @intCast(bit_pos));
        }
        if (bits == 0) {
            try writer.print("\n .{s} => true,", .{promotion.name});
        } else {
            try writer.print("\n .{s} => ((0b{b} & promotion_flags) != 0),", .{ promotion.name, bits });
        }
    }

    try writer.print("\n }}; }}", .{});

    // Add upgrade function, Does not handle availability check, see above
    try writer.print(
        \\ pub fn addPromotion(new_promotion: Promotion,
        \\ promotion_flags: u{}) u{} {{ const promotions = switch (new_promotion) {{
    , .{ promotions.len, promotions.len });

    for (promotions) |promotion| {
        if (promotion.replaces) |replaced| {
            if (flag_index_map.get(replaced)) |flag_idx| {
                const old_flag = @as(u256, 1) << @intCast(flag_idx);
                try writer.print("\n .{s} => (0b{b} ^ promotion_flags),", .{
                    promotion.name,
                    old_flag,
                });
            } else unreachable;
        }
    }
    try writer.print("\n else => promotion_flags,}}; \n return (1 << @intFromEnum(new_promotion)) & promotions; }}", .{});
    try util.endStructEnumUnion(writer);
}

pub fn parseAndOutputUnits(
    text: []const u8,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    const parsed = try std.json.parseFromSlice(
        struct {
            civilian: []const UnitType,
            land: []const UnitType,
            naval: []const UnitType,
        },
        allocator,
        text,
        .{},
    );
    defer parsed.deinit();

    const promotions = parsed.value.promotions;

    try util.startEnum("UnitType", promotions.len, writer);
    for (promotions) |promotion| {
        try writer.print("\n {s},", .{promotion.name});
    }

    try util.endStructEnumUnion(writer);
}
