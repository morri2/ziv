const std = @import("std");
const Idx = @import("Grid.zig").Idx;
const Rules = @import("Rules.zig");

const Terrain = Rules.Terrain;
const Transport = Rules.Transport;
const Promotion = Rules.Promotion;
const UnitType = Rules.UnitType;
const UnitEffect = Rules.UnitEffect;
const Player = @import("Player.zig");

const Self = @This();

pub const CombatContext = struct {
    is_ranged: bool,
    is_attacker: bool,
    target_terrain: Terrain,
    river_crossing: bool,
};

pub const StrengthSummary = struct {
    total: f32,
    base: u32,
    combat_bonus: u32,
    attacker_bonus: u32,
    rough_terrain_bonus: u32,
    open_terrain_bonus: u32,
};

pub const MoveContext = struct {
    target_terrain: Terrain,
    river_crossing: bool,
    transport: Transport,
    embarked: bool,
    city: bool,
};

pub const MoveCost = union(enum) {
    disallowed: void,
    allowed: f32,
    allowed_final: void, // ends move after
    embarkation: void,
    disembarkation: void,

    pub fn allowsAttack(self: MoveCost) bool {
        return switch (self) {
            .allowed, .allowed_final, .disembarkation => true,
            else => false,
        };
    }
};

type: UnitType,
hit_points: u8 = 100, // All units have 100 HP
prepared: bool = false,
fortified: bool = false,
promotions: Promotion.Set = Promotion.Set.initEmpty(),
faction: Player.Faction,
movement: f32 = 0,

pub fn new(unit_type: UnitType, player_id: Player.PlayerID, rules: *const Rules) Self {
    var unit = Self{ .faction = .{ .player = player_id }, .type = unit_type };
    unit.promotions = unit_type.stats(rules).promotions;
    unit.movement = unit.maxMovement(rules);
    return unit;
}

pub fn maxMovement(self: Self, rules: *const Rules) f32 {
    const move_mod = Promotion.Effect.modify_movement.promotionsSum(self.promotions, rules);
    return @as(f32, @floatFromInt(move_mod)) + @as(f32, @floatFromInt(self.type.stats(rules).moves));
}

pub fn refresh(self: *Self, rules: *const Rules) void {
    self.movement = self.maxMovement(rules);
}

pub fn strength(
    unit: *Self,
    context: CombatContext,
    rules: *const Rules,
) StrengthSummary {
    const base = unit.type.stats(rules).melee;

    const combat_bonus = Promotion.Effect.combat_bonus.promotionsSum(unit.promotions, rules);

    const attacker_bonus = if (context.is_attacker) Promotion.Effect.combat_bonus_attacking.promotionsSum(
        unit.promotions,
        rules,
    ) else 0;

    const target_attributes = context.target_terrain.attributes(rules);
    const is_rough = target_attributes.is_rough;

    var rough_bonus = if (is_rough) Promotion.Effect.rough_terrain_bonus.promotionsSum(
        unit.promotions,
        rules,
    ) else 0;

    rough_bonus += if (is_rough and context.is_ranged) Promotion.Effect.rough_terrain_bonus_range.promotionsSum(
        unit.promotions,
        rules,
    ) else 0;

    var open_bonus = if (!is_rough) Promotion.Effect.open_terrain_bonus.promotionsSum(
        unit.promotions,
        rules,
    ) else 0;

    open_bonus += if (!is_rough and context.is_ranged) Promotion.Effect.open_terrain_bonus_range.promotionsSum(
        unit.promotions,
        rules,
    ) else 0;

    const mod: f32 = @floatFromInt(base + combat_bonus + attacker_bonus + rough_bonus + open_bonus + 100);

    return .{
        .total = mod * 0.01,
        .base = base,
        .combat_bonus = combat_bonus,
        .attacker_bonus = attacker_bonus,
        .rough_terrain_bonus = rough_bonus,
        .open_terrain_bonus = open_bonus,
    };
}

pub fn moveCost(self: Self, context: MoveContext, rules: *const Rules) MoveCost {
    const stats = self.type.stats(rules);
    const terrain_attributes = context.target_terrain.attributes(rules);

    if (self.movement <= 0) return .disallowed;

    // Sea units should not be embarked
    std.debug.assert(!(context.embarked and stats.domain == .sea));

    if (terrain_attributes.is_impassable) return .disallowed;

    if (terrain_attributes.is_deep_water and !Promotion.Effect.can_cross_ocean.in(
        self.promotions,
        rules,
    )) return .disallowed;

    if (context.river_crossing) return .allowed_final;

    if (context.city) return .{ .allowed = 1 }; // obs! should be after river crossing check

    const cost: MoveCost = switch (stats.domain) {
        .sea => blk: {
            if (!terrain_attributes.is_water) break :blk .disallowed;

            break :blk .{ .allowed = 1 };
        },
        .land => blk: {
            var cost_amt: f32 = 1;
            if (terrain_attributes.is_rough and !Promotion.Effect.ignore_terrain_move.in(
                self.promotions,
                rules,
            )) cost_amt += 1;

            // Check if trying to embark and if unit can embark
            if (terrain_attributes.is_water and !context.embarked) return if (Promotion.Effect.can_embark.in(
                self.promotions,
                rules,
            )) .embarkation else .disallowed;

            if (!terrain_attributes.is_water and context.embarked) return .disembarkation;

            cost_amt = switch (context.transport) {
                .none => cost_amt,
                .road => @min(cost_amt, 0.5), // changed with machinery to 1/3.
                .rail => @min(cost_amt, self.maxMovement(rules) / 10.0), // risk of float_rounding error :/
            };

            break :blk .{ .allowed = cost_amt };
        },
    };

    return cost;
}

pub fn performMove(self: *Self, cost: MoveCost) void {
    switch (cost) {
        .allowed => |c| self.movement = @max(0.0, self.movement - c),
        .allowed_final,
        .embarkation,
        .disembarkation,
        => self.movement = 0.0,
        else => unreachable,
    }
}

// pub fn tryBattle(from: Idx, target: Idx, world: *World) void {
//     const a_key = world.unit_map.firstOccupiedKey(from) orelse return;
//     const d_key = world.unit_map.firstOccupiedKey(target) orelse return;
//     const attacker = world.unit_map.getUnitPtr(a_key) orelse return;
//     const defender = world.unit_map.getUnitPtr(d_key) orelse return;

//     const mc = move.moveCost(target, from, attacker, world);

//     if (!mc.allowsAttack()) return;

//     const context: CombatContext = .{
//         .target_terrain = world.terrain[target],
//     };
//     battle(attacker, defender, false, context, world.rules, true);

//     const attacker_alive = !(attacker.hit_points <= 0);
//     const defender_alive = !(defender.hit_points <= 0);

//     if (!attacker_alive) _ = world.unit_map.fetchRemoveUnit(a_key);
//     if (!defender_alive) _ = world.unit_map.fetchRemoveUnit(d_key);
//     if (!defender_alive and attacker_alive) _ = move.tryMoveUnit(a_key, target, world);

//     if (attacker_alive) attacker.movement = 0;
// }

// /// battle sim
// pub fn battle(attacker: *Self, defender: *Self, range: bool, context: CombatContext, rules: *const Rules, log: bool) void {
//     std.debug.print("\n### BATTLE BATTLE BATTLE ###\n", .{});

//     std.debug.print("\n# ATTACKER #\n", .{});
//     const attacker_str = calculateStr(attacker, true, range, context, log, rules);
//     std.debug.print("\n# DEFENDER #\n", .{});
//     const defend_str = calculateStr(defender, false, range, context, log, rules);

//     const ratio = attacker_str / defend_str;
//     const attacker_dmg: u8 = if (!range) @intFromFloat(1 / ratio * 35) else 0;
//     const defender_dmg: u8 = @intFromFloat(ratio * 35);

//     std.debug.print("\nCOMBAT RATIO: {d:.2}\n", .{ratio});
//     std.debug.print("DEFENDER TAKES {d:.0} damage\n", .{defender_dmg});
//     if (!range) std.debug.print("ATTACKER TAKES {d:.0} damage\n", .{attacker_dmg});

//     const attacker_higher_hp = attacker.hit_points > defender.hit_points;
//     attacker.hit_points -|= attacker_dmg;
//     defender.hit_points -|= defender_dmg;

//     if (attacker.hit_points == 0 and defender.hit_points == 0) {
//         if (attacker_higher_hp)
//             attacker.hit_points = 1
//         else
//             defender.hit_points = 1;
//     }
// }
