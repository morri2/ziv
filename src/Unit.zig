const Self = @This();
const std = @import("std");
const rules = @import("rules");

pub const BaseUnit = packed struct {
    //type: rules.UnitType,
    hit_points: u8 = 100, // All units have 100 HP
    prepared: bool = false,
    embarked: bool = false,
    fortified: bool = false,
    promotions: u11,
    // promotions: rules.Promotions,
};
