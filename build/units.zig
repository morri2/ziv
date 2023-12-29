const std = @import("std");
const util = @import("util.zig");

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

// Universal Unit parameters
// Excluding Trade, Airplanes as of now
const UnitType = struct {
    name: []const u8,
    production_cost: u16, // Max cost, Nuclear Missile 1000
    moves: u8, // Max movement, Nuclear Sub etc. 6
    combat_strength: u8 = 0, // Max combat strength, Giant Death Robot 150
    ranged_strength: u8 = 0,
    range: u8 = 0, // Max range, Nuclear Missile 12
    sight: u8 = 2, // Max 10 = 2 + 4 promotions + 1 scout + 1 nation + 1 Exploration + 1 Great Lighthouse
    domain: []const u8 = &.{},
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
        \\ 
        \\ pub fn bitflags(promotions: []const Promotion) u{} {{
        \\     var flags = 0;
        \\     for (promotions) |promotion|{{
        \\         flags &= (1 << @intFromEnum(promotion));
        \\     }}
        \\     return flags;
        \\}}
        \\
    , .{promotions.len});

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
            try writer.print("\n .{s} => (.bitflags(.{s}) ^ promotion_flags),", .{
                promotion.name,
                replaced,
            });
        }
    }
    try writer.print("\n else => promotion_flags,}}; \n return .bitflag(new_promotion) & promotions; }}", .{});
    try util.endStructEnumUnion(writer);
}

pub fn parseAndOutputUnits(
    text: []const u8,
    promotion_flag_map: *FlagIndexMap,
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

    const promotion_bits = promotion_flag_map.indices.count();

    const units = parsed.value;

    try writer.print(
        \\const UnitStats = packed struct {{
        \\    production: u16, // Max cost, Nuclear Missile 1000
        \\    moves: u8, // Max movement, Nuclear Sub etc. 6
        \\    melee: u8, // Max combat strength, Giant Death Robot 150
        \\    ranged: u8,
        \\    range: u8, // Max range, Nuclear Missile 12
        \\    sight: u8, // Max 10 = 2 + 4 promotions + 1 scout + 1 nation + 1 Exploration + 1 Great Lighthouse
        \\    domain: Unit.Domain,
        \\    promotions: u{},
        \\
        \\    pub fn init(production: u16, moves: u8, melee:u8, ranged:u8,range: u8,sight:u8,domain: Unit.Domain, promotions: u{}) UnitStats {{
        \\      return UnitStats {{
        \\          .production = production,
        \\          .moves = moves,
        \\          .melee = melee,
        \\          .ranged = ranged,
        \\          .range = range,
        \\          .sight = sight,
        \\          .domain = domain,
        \\          .promotions = promotions,
        \\      }};
        \\    }}
        \\}};
    , .{ promotion_bits, promotion_bits });

    var domains = std.StringArrayHashMap(void).init(allocator);
    defer domains.deinit();

    try util.startEnum(
        "Unit",
        units.civilian.len + units.land.len + units.naval.len,
        writer,
    );

    // TODO!, make this split meaningful
    const all_units = try std.mem.concat(allocator, UnitType, &.{
        units.civilian,
        units.land,
        units.naval,
    });
    defer allocator.free(all_units);

    for (all_units) |unit| {
        try writer.print("{s},", .{unit.name});
        _ = try domains.getOrPut(unit.domain);
    }

    try writer.print("\n \n ", .{});

    try util.startEnum("Domain", domains.count(), writer);

    for (domains.keys()) |domain| {
        try writer.print("{s},", .{domain});
    }

    try util.endStructEnumUnion(writer);

    try writer.print(
        \\
        \\ pub fn baseStats(unit_type: Unit) UnitStats {{
        \\        return switch (unit_type) {{
    , .{});

    for (all_units) |unit| {
        var bit_flags: Flags = promotion_flag_map.flagsFromKeys(unit.starting_promotions);
        var bits: u256 = 0;
        while (bit_flags.toggleFirstSet()) |bit_pos| {
            bits |= (@as(u256, 1) << @intCast(bit_pos));
        }
        try writer.print(".{s} => UnitStats.init({d},{d},{d},{d},{d},{d},.Domain.{s},0b{b}),", .{
            unit.name,
            unit.production_cost,
            unit.moves,
            unit.combat_strength,
            unit.ranged_strength,
            unit.range,
            unit.sight,
            unit.domain,
            bits,
        });
    }

    try writer.print("\n }}; }}", .{});

    try util.endStructEnumUnion(writer);
}
