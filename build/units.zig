const std = @import("std");
const util = @import("util.zig");
const foundation = @import("../foundation/lib.zig");

const Effect = foundation.UnitEffect;
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

const EffectValue = struct {
    effect: Effect,
    value: ?u32 = null,
};

const Promotion = struct {
    name: []const u8,
    requires: []const []const u8 = &.{}, // Seem to only be either of the listed, never 2 different
    effects: []const EffectValue = &.{},
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

    try writer.print("\npub const PromotionBitSet: type = std.bit_set.IntegerBitSet({});\n", .{promotions.len});

    try util.startEnum("Promotion", promotions.len, writer);
    for (promotions) |promotion| {
        try writer.print("\n {s},", .{promotion.name});
        _ = try flag_index_map.add(promotion.name);
    }

    // Build prereq table :))

    try writer.print("\npub const promotion_prereqs = [{}]?PromotionBitSet {{\n", .{promotions.len});

    for (promotions) |promotion| {
        var bit_flags: Flags = flag_index_map.flagsFromKeys(promotion.requires);
        var bits: u256 = 0;
        while (bit_flags.toggleFirstSet()) |bit_pos| {
            bits |= (@as(u256, 1) << @intCast(bit_pos));
        }
        if (bits == 0) {
            try writer.print("\n null,", .{});
        } else {
            try writer.print("\n .{{ .mask =  0b{b} }},", .{bits});
        }
    }

    try writer.print("}};\n", .{});

    try util.endStructEnumUnion(writer);

    // Parse promotion effects

    var effect_hash = std.AutoArrayHashMap(EffectValue, u256).init(allocator);

    for (promotions) |promotion| {
        for (promotion.effects) |effect| {
            var bit_flags = flag_index_map.flagsFromKeys(&.{promotion.name}).mask;
            if (effect_hash.get(effect)) |prev_bits| {
                bit_flags ^= prev_bits;
            }
            try effect_hash.put(effect, bit_flags);
        }
    }

    try writer.print(
        \\ 
        \\ pub fn effect_promotions(effect: foundation.Effect) []struct {{promotions: PromotionBitSet,value: ?u32}} {{
        \\ return switch (effect) {{
    , .{});

    inline for (@typeInfo(Effect).Enum.fields) |effect| {
        try writer.print(".{s} => .{{ \n", .{effect.name});
        for (effect_hash.keys(), effect_hash.values()) |effect_val, bits| {
            if (@intFromEnum(effect_val.effect) == effect.value) {
                try writer.print(".{{.promotions = 0b{b}, .value = {?} }},", .{ bits, effect_val.value });
            }
        }

        try writer.print("}},\n", .{});
    }

    try writer.print("}}; }}\n", .{});
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

    const units = parsed.value;

    try writer.print(
        \\pub const UnitStats = packed struct {{
        \\    production: u16, // Max cost, Nuclear Missile 1000
        \\    moves: u8, // Max movement, Nuclear Sub etc. 6
        \\    melee: u8, // Max combat strength, Giant Death Robot 150
        \\    ranged: u8,
        \\    range: u8, // Max range, Nuclear Missile 12
        \\    sight: u8, // Max 10 = 2 + 4 promotions + 1 scout + 1 nation + 1 Exploration + 1 Great Lighthouse
        \\    domain: UnitType.Domain,
        \\    promotions: PromotionBitSet,
        \\
        \\    pub fn init(production: u16, moves: u8, melee:u8, ranged:u8,range: u8,sight:u8,domain: UnitType.Domain, promotions: PromotionBitSet) UnitStats {{
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
    , .{});

    var domains = std.StringArrayHashMap(void).init(allocator);
    defer domains.deinit();

    try util.startEnum(
        "UnitType",
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
        \\ pub fn baseStats(unit_type: UnitType) UnitStats {{
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
