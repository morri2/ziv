pub const Yield = packed struct {
    food: u5 = 0,
    production: u5 = 0,
    gold: u5 = 0,
    culture: u5 = 0,
    faith: u5 = 0,
    science: u5 = 0,
};

/// Atomic effects of promotions
pub const UnitEffect = enum {
    CombatBonusAttacking, // +(value)%
    CombatBonus, // +(value)%
    RoughTerrainBonus, // +(value)%
    RoughTerrainBonusRange,
    OpenTerrainBonus, // +(value)%
    OpenTerrainBonusRange,
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
}

