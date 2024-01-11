const Self = @This();
const std = @import("std");
const rules = @import("rules");
const foundation = @import("foundation");

pub const BaseUnit = packed struct {
    type: rules.UnitType,
    hit_points: u7 = 100, // All units have 100 HP
    prepared: bool = false,
    embarked: bool = false,
    fortified: bool = false,
    promotions: rules.Promotions,
};

/// returns the something
pub fn functionName(effect: foundation.UnitEffect) void {
    _ = effect; // autofix

}
