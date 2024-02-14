const std = @import("std");

const Rules = @import("Rules.zig");

const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

const World = @import("World.zig");
const Units = @import("Units.zig");
const City = @import("City.zig");

pub const Action = union(Type) {
    next_turn: void,
    move_unit: struct {
        ref: Units.Reference,
        to: Idx,
    },
    attack: struct {
        attacker: Units.Reference,
        to: Idx,
    },
    set_city_production: struct {
        city_idx: Idx,
        production: City.ProductionTarget,
    },
    settle_city: Units.Reference,
    unset_worked: struct {
        city_idx: Idx,
        idx: Idx,
    },
    set_worked: struct {
        city_idx: Idx,
        idx: Idx,
    },

    promote_unit: struct {
        unit: Units.Reference,
        promotion: Rules.Promotion,
    },

    tile_work: struct {
        unit: Units.Reference,
        work: World.TileWork,
    },

    add_unit: struct {
        unit_type: Rules.UnitType,
        idx: Idx,
        faction_id: World.FactionID,
    },

    pub const Type = enum(u8) {
        // Zero is reserved for ping packet
        next_turn = 1,
        move_unit = 2,
        attack = 3,
        set_city_production = 4,
        settle_city = 5,
        unset_worked = 6,
        set_worked = 7,
        promote_unit = 8,
        tile_work = 9,
        add_unit = 10,
    };

    pub const Result = struct {
        view_change: bool = false,

        pub fn unionWith(self: Result, other: Result) Result {
            return .{
                .view_change = self.view_change or other.view_change,
            };
        }
    };

    pub fn possible(self: Action, faction_id: World.FactionID, world: *const World, rules: *const Rules) bool {
        switch (self) {
            .next_turn => {},
            .move_unit => |info| {
                const unit = world.units.deref(info.ref) orelse return false;

                if (unit.faction_id != faction_id) return false;

                if (world.moveCost(info.ref, info.to, rules) == .disallowed) return false;
            },
            .attack => |info| {
                const unit = world.units.deref(info.attacker) orelse return false;

                if (unit.faction_id != faction_id) return false;

                if (!try world.canAttack(info.attacker, info.to, rules)) return false;
            },
            .set_city_production => |info| {
                const city = world.cities.get(info.city_idx) orelse return false;
                if (city.faction_id != faction_id) return false;
            },
            .settle_city => |settler_ref| {
                const unit = world.units.deref(settler_ref) orelse return false;

                if (unit.faction_id != faction_id) return false;

                if (!Rules.Promotion.Effect.settle_city.in(unit.promotions, rules)) return false;

                if (!world.canSettleCityAt(settler_ref.idx, faction_id, rules)) return false;
            },
            .unset_worked => |info| {
                const city = world.cities.get(info.city_idx) orelse return false;
                if (!city.worked.contains(info.idx)) return false;
            },
            .set_worked => |info| {
                const city = world.cities.get(info.city_idx) orelse return false;

                if (city.unassignedPopulation() == 0) return false;

                if (!city.claimed.contains(info.idx)) return false;

                if (city.worked.contains(info.idx)) return false;
            },
            .promote_unit => |info| {
                _ = world.units.deref(info.unit) orelse return false;
            },
            .tile_work => |info| {
                return world.canDoImprovementWork(info.unit, info.work, rules);
            },
            .add_unit => |info| if (world.units.hasOtherFaction(info.idx, info.faction_id)) return false,
        }

        return true;
    }

    pub fn exec(self: Action, faction_id: World.FactionID, world: *World, rules: *const Rules) !?Result {
        if (!self.possible(faction_id, world, rules)) return null;

        var result = Result{};
        switch (self) {
            .next_turn => {
                const turn_result = try world.nextTurn(rules);
                result.view_change = turn_result.view_change;
            },
            .move_unit => |info| {
                if (!try world.move(info.ref, info.to, rules)) unreachable;

                result.view_change = true;
            },
            .attack => |info| {
                if (!try world.attack(info.attacker, info.to, rules)) unreachable;

                result.view_change = true;
            },
            .set_city_production => |info| {
                const city = world.cities.getPtr(info.city_idx) orelse unreachable;

                _ = city.startConstruction(info.production, rules);
            },
            .settle_city => |settler_ref| {
                if (!try world.settleCity(settler_ref, rules)) unreachable;

                result.view_change = true;
            },
            .unset_worked => |info| {
                const city = world.cities.getPtr(info.city_idx) orelse unreachable;

                if (!city.unsetWorked(info.idx)) unreachable;
            },
            .set_worked => |info| {
                const city = world.cities.getPtr(info.city_idx) orelse unreachable;

                if (!try city.setWorkedWithAutoReassign(info.idx, world, rules)) unreachable;
            },
            .promote_unit => |info| {
                var unit = world.units.derefToPtr(info.unit) orelse unreachable;
                unit.promotions.set(@intFromEnum(info.promotion));

                result.view_change = true;
            },
            .tile_work => |info| {
                if (!world.doImprovementWork(info.unit, info.work, rules)) unreachable;

                result.view_change = true;
            },
            .add_unit => |info| {
                if (!try world.addUnit(info.idx, info.unit_type, info.faction_id, rules)) unreachable;

                result.view_change = true;
            },
        }

        return result;
    }
};
