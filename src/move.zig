const World = @import("World.zig");
const Unit = @import("Unit.zig");
const Idx = @import("Grid.zig").Idx;
const std = @import("std");
pub const MoveCostAmt = f32;

const UnitMap = @import("UnitMap.zig");
const UnitSlot = UnitMap.UnitSlot;
const UnitKey = UnitMap.UnitKey;

pub fn tryMoveUnit(unit_key: UnitKey, dest: Idx, world: *World) bool {
    const unit_ptr = world.unit_map.getUnitPtr(unit_key) orelse return false;
    if (!world.grid.adjacentTo(unit_key.idx, dest)) return false;
    const cost = moveCost(dest, unit_key.idx, unit_ptr, world);
    return moveUnit(unit_key, dest, cost, &(world.unit_map));
}

pub fn moveUnit(unit_key: UnitKey, dest: Idx, cost: MoveCost, um: *UnitMap) bool {
    if (cost == .disallowed) return false;
    const unit_ptr = um.getUnitPtr(unit_key) orelse return false;
    if (unit_ptr.movement <= 0 and cost != .cheat_move) return false;

    const dest_slot = unit_ptr.slotAfterMove(cost);

    if (um.getFirstSlotUnitPtr(dest, dest_slot) != null) return false;

    var unit = um.fetchRemoveUnit(unit_key) orelse return false;

    switch (cost) {
        .cheat_move => {}, // no cost
        .allowed => |c| unit.movement = @max(0, unit.movement - c),
        .allowed_final => unit.movement = 0,
        .embarkation => {
            unit.embarked = true;
            unit.movement = 0;
        },
        .disembarkation => {
            unit.embarked = false;
            unit.movement = 0;
        },
        else => unreachable,
    }

    um.putUnit(.{ .idx = dest, .slot = dest_slot }, unit);
    return true;
}

pub const MoveCost = union(enum) {
    cheat_move: void,
    disallowed: void,
    allowed: MoveCostAmt,
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

pub fn moveCost(dest: Idx, src: Idx, unit: *const Unit, world: *const World) MoveCost {
    if (dest == src) return .disallowed;
    const edge = world.grid.edgeBetween(src, dest) orelse return .disallowed;
    const terrain = world.terrain[dest];
    const improvements = world.improvements[dest];

    const is_river = world.rivers.contains(edge);

    if (terrain.attributes(world.rules).is_impassable) return .disallowed;
    if (!world.grid.adjacentTo(src, dest)) return .disallowed;

    if (is_river) return .allowed_final;

    // SEA units
    if (unit.type.baseStats().domain == .SEA) {
        if (!terrain.attributes(world.rules).is_water) {
            return .disallowed;
        } else {
            return .{ .allowed = 1 };
        }
    }

    // LAND units
    var cost_amt: f32 = 1;
    if (terrain.attributes(world.rules).is_rough and !Unit.grantsEffect(unit.promotions, .IgnoreTerrainMove))
        cost_amt += 1;

    if (terrain.attributes(world.rules).is_water and !unit.embarked)
        if (unit.type == .archer) // PLACEHOLDE CHECK TODO FIX
            //if (Unit.grantsEffect(unit.promotions, .CanEmbark)) // REAL CHECK
            return .embarkation
        else
            return .disallowed;

    if (!terrain.attributes(world.rules).is_water and unit.embarked)
        return .disembarkation;

    // ROADS etc
    if (improvements.transport != .none and !improvements.pillaged_transport)
        cost_amt = @min(cost_amt, 0.5); // changed with machinery to 1/3.
    if (improvements.transport == .rail and !improvements.pillaged_transport)
        cost_amt = @min(cost_amt, unit.maxMovement() / 10.0); // risk of float_rounding error :/

    return .{ .allowed = cost_amt };
}
