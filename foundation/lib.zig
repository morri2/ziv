const std = @import("std");

pub const comptime_hash_map = @import("comptime_hash_map");

pub const Yield = packed struct {
    food: u5 = 0,
    production: u5 = 0,
    gold: u5 = 0,
    culture: u5 = 0,
    faith: u5 = 0,
    science: u5 = 0,

    pub fn add(self: Yield, other: Yield) Yield {
        return .{
            .food = self.food + other.food,
            .gold = self.gold + other.gold,
            .production = self.production + other.production,
            .culture = self.culture + other.culture,
            .faith = self.faith + other.faith,
            .science = self.science + other.science,
        };
    }
};

/// Atomic effects of promotions
pub const UnitEffect = enum {
    CombatBonusAttacking, // +(value)%
    CombatBonus, // +(value)%
    RoughTerrainBonus, // +(value)%
    RoughTerrainBonusRange, // +(value)%
    OpenTerrainBonus, // +(value)%
    OpenTerrainBonusRange, // +(value)%
    SettleCity,
    CanFortify,
    BuildRoads,
    BuildRail,
    BuildImprovement,
    ModifyAttackRange, // +(value)
    ModifyMovement, // +(value)
    ModifySightRange, // +(value)
    IgnoreTerrainMove,
    CanEmbark,
    CannotMelee,
};
