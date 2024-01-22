const Self = @This();
const std = @import("std");
const Rules = @import("Rules.zig");
const World = @import("World.zig");
const Idx = @import("Grid.zig").Idx;
const move = @import("move.zig");

const Terrain = Rules.Terrain;
const Improvements = Rules.Improvements;
const PromotionBitSet = Rules.PromotionBitSet;
const UnitType = Rules.UnitType;
const UnitEffect = Rules.UnitEffect;

type: UnitType,
hit_points: u8 = 100, // All units have 100 HP
prepared: bool = false,
embarked: bool = false,
fortified: bool = false,
promotions: PromotionBitSet = PromotionBitSet.initEmpty(),
movement: f32 = 0,

pub fn new(unit_type: UnitType) Self {
    var unit = Self{ .type = unit_type };
    unit.promotions = unit_type.baseStats().promotions;
    unit.movement = unit.maxMovement();
    return unit;
}

pub fn maxMovement(self: Self) f32 {
    const move_mod = cumPromotionValues(self.promotions, .ModifyMovement);
    return @as(f32, @floatFromInt(move_mod)) + @as(f32, @floatFromInt(self.type.baseStats().moves));
}

/// Slot type when not embarked
pub fn defaultSlot(self: Self) World.UnitSlot {
    // PLACEHOLDER CIVILIAN UNITS ARE NOT A THING YET, will need reworking when the rapture comes
    if (self.type.baseStats().domain == .SEA) {
        if (self.type == .work_boat) return .civilian;
        return .naval;
    }
    if (self.type.baseStats().domain == .LAND) {
        if (self.type == .worker or self.type == .settler) return .civilian;

        return .military;
    }
    unreachable;
}

pub fn slotAfterMove(self: *Self, cost: move.MoveCost) World.UnitSlot {
    if (cost == .disembarkation) return self.defaultSlot();
    if (cost == .embarkation or self.embarked) return .embarked;
    return self.defaultSlot();
}

// restore movement
pub fn refresh(self: *Self) void {
    self.movement = self.maxMovement();
}

/// returns a bitset for the promotions that grant the effect :)
pub fn effectPromotions(effect: UnitEffect) PromotionBitSet {
    var bitset = PromotionBitSet.initEmpty();
    for (Rules.effect_promotions(effect)) |variant| {
        bitset = bitset.unionWith(variant.promotions);
    }
    return bitset;
}

/// returns a bitset for the promotions that grant the effect :)
pub fn grantsEffect(promotions: PromotionBitSet, effect: UnitEffect) bool {
    for (Rules.effect_promotions(effect)) |variant| {
        const u = variant.promotions.intersectWith(promotions);
        if (u.mask != 0) return true;
    }
    return false;
}

/// returns the sum of the values of all the promotions.
pub fn cumPromotionValues(promotions: PromotionBitSet, effect: UnitEffect) i32 {
    var cum: i32 = 0;
    for (Rules.effect_promotions(effect)) |variant| {
        const u = variant.promotions.intersectWith(promotions);
        cum += @as(i32, @intCast(u.count())) * @as(i32, @intCast(variant.value.?));
    }
    return cum;
}

const CombatContext = struct {
    target_terrain: Terrain = @enumFromInt(0),

    river_crossing: bool = false,
};

pub fn tryBattle(src: Idx, dest: Idx, world: *World) void {
    const attacker = world.getFirstUnitPtr(src) orelse return;
    const defender = world.getFirstUnitPtr(dest) orelse return;

    const context: CombatContext = .{
        .target_terrain = world.terrain[src],
    };
    battle(attacker, defender, false, context, world.rules, true);
}

/// battle sim
pub fn battle(attacker: *Self, defender: *Self, range: bool, context: CombatContext, rules: *const Rules, log: bool) void {
    std.debug.print("\n### BATTLE BATTLE BATTLE ###\n", .{});

    std.debug.print("\n# ATTACKER #\n", .{});
    const attacker_str = calculateStr(attacker, true, range, context, log, rules);
    std.debug.print("\n# DEFENDER #\n", .{});
    const defend_str = calculateStr(defender, false, range, context, log, rules);

    const ratio = attacker_str / defend_str;
    const attacker_dmg: u8 = if (!range) @intFromFloat(1 / ratio * 35) else 0;
    const defender_dmg: u8 = @intFromFloat(ratio * 35);

    std.debug.print("\nCOMBAT RATIO: {d:.2}\n", .{ratio});
    std.debug.print("DEFENDER TAKES {d:.0} damage\n", .{defender_dmg});
    if (!range) std.debug.print("ATTACKER TAKES {d:.0} damage\n", .{attacker_dmg});

    attacker.hit_points -|= attacker_dmg;
    defender.hit_points -|= defender_dmg;
}

pub fn calculateStr(unit: *Self, is_attacker: bool, is_range: bool, context: CombatContext, log: bool, rules: *const Rules) f32 {
    var str: f32 = @floatFromInt(unit.type.baseStats().melee);
    if (log) std.debug.print("  Base strength: {d:.0}\n", .{str});

    var unit_mod: i32 = 100;

    {
        const mod = cumPromotionValues(unit.promotions, .CombatBonus);

        if (log and mod > 0) std.debug.print("    Combat bonus: +{}%\n", .{mod});
        unit_mod += mod;
    }

    if (is_attacker) {
        const mod = cumPromotionValues(unit.promotions, .CombatBonusAttacking);
        if (log and mod > 0) std.debug.print("    Attacking bonus: +{}%\n", .{mod});
        unit_mod += mod;
    }

    if (context.target_terrain.attributes(rules).is_rough) {
        const mod = cumPromotionValues(unit.promotions, .RoughTerrainBonus);
        if (log and mod > 0) std.debug.print("    Rough terrain bonus: +{}%\n", .{mod});
        unit_mod += mod;
    }
    if (!context.target_terrain.attributes(rules).is_rough) {
        const mod = cumPromotionValues(unit.promotions, .OpenTerrainBonus);
        if (log and mod > 0) std.debug.print("    Open terrain bonus: +{}%\n", .{mod});
        unit_mod += mod;
    }

    if (context.target_terrain.attributes(rules).is_rough and is_range) {
        const mod = cumPromotionValues(unit.promotions, .RoughTerrainBonusRange);
        if (log and mod > 0) std.debug.print("    Rough terrain bonus: +{}%\n", .{mod});
        unit_mod += mod;
    }

    if (!context.target_terrain.attributes(rules).is_rough and is_range) {
        const mod = cumPromotionValues(unit.promotions, .OpenTerrainBonusRange);
        if (log and mod > 0) std.debug.print("    Open terrain bonus: +{}%\n", .{mod});
        unit_mod += mod;
    }

    if (log and unit_mod > 0) std.debug.print("    STR MOD: {}%\n", .{unit_mod});

    // add bonus from terrain :))
    // if terrain and !is_attacker -> terrain mod

    str *= @as(f32, @floatFromInt(unit_mod)) / 100.0;
    if (log) std.debug.print("  TOTAL STRENGTH: {d:.0}", .{str});

    return str;
}
