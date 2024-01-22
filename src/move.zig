const World = @import("World.zig");
const Unit = @import("Unit.zig");
const Idx = @import("Grid.zig").Idx;
const std = @import("std");
pub const MoveCostAmt = f32;
const MoveCostRes = union(enum) {
    disallowed: void,
    allowed: MoveCostAmt,
    allowed_final: void, // ends move after
    embarkation: void,
};

pub fn setPosition(dest: Idx, unit: Unit, world: *World) void {
    world.pushUnit(dest, unit);
}

pub fn changePosition(src: Idx, dest: Idx, stack_depth: usize, world: *World) void {
    const unit = world.removeNthStackedUnit(src, stack_depth) orelse return;
    setPosition(dest, unit, world);
}

pub fn moveUnit(src: Idx, dest: Idx, stack_depth: usize, world: *World) bool {
    const uc = world.getNthStackedPtr(src, stack_depth) orelse return false;
    const mc = moveCost(dest, src, uc.unit, world);

    if (uc.unit.movement <= 0) return false;

    switch (mc) {
        .allowed => |c| uc.unit.movement = @max(0, uc.unit.movement - c),
        .allowed_final => uc.unit.movement = 0,
        .embarkation => {
            uc.unit.embarked = true;
            uc.unit.movement = 0;
        },
        else => return false,
    }

    const target_uc = world.topUnitContainerPtr(dest);
    if (target_uc != null) {
        Unit.tryBattle(src, dest, world);
        if (target_uc.?.unit.hit_points == 0) {
            _ = world.removeNthStackedUnit(dest, 0);
        }
        if (uc.unit.hit_points == 0) {
            _ = world.removeNthStackedUnit(src, 0);
        }
    }

    _ = world.getNthStackedPtr(src, stack_depth) orelse return false;

    if (world.getNthStackedPtr(dest, stack_depth) == null) {
        changePosition(src, dest, stack_depth, world);
    }
    return true;
}

pub fn moveCost(dest: Idx, src: Idx, unit: Unit, world: *World) MoveCostRes {
    if (dest == src) return .disallowed;
    const terrain = world.terrain[dest];
    const improvements = world.improvements[dest];
    const edge = world.grid.edgeBetween(src, dest) orelse return .disallowed;
    const is_river = world.rivers.contains(edge);
    const attributes = terrain.attributes(world.rules);
    const has_road = improvements.transport == .road and !improvements.pillaged_transport;
    const has_rail = improvements.transport == .rail and !improvements.pillaged_transport;

    if (!world.grid.adjacentTo(src, dest)) return .disallowed;

    var cost: f32 = 1;
    if (is_river) return .allowed_final;
    cost += if (attributes.is_rough) 1 else 0;

    //if (is_water) return .embarkation;
    if (attributes.is_impassable) return .disallowed;

    if (has_road or has_rail) cost = 0.5; // changed with machinery to 1/3.
    if (has_rail) cost = @min(cost, unit.maxMovement() / 10.0); // risk of float_rounding error :/

    return .{ .allowed = cost };
}
