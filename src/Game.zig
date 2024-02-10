const std = @import("std");

const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

const Rules = @import("Rules.zig");
const World = @import("World.zig");
const Units = @import("Units.zig");
const City = @import("City.zig");

const View = @import("View.zig");

const Self = @This();

pub const Action = union(Type) {
    move_unit: struct {
        ref: Units.Reference,
        to: Idx,
    },
    attack: struct {
        attacker: Units.Reference,
        to: Idx,
    },

    pub const Type = enum(u8) {
        move_unit = 0,
        attack = 1,
    };
};

civ_id: World.CivilizationID,
world: World,

pub fn host(
    width: u32,
    height: u32,
    wrap_around: bool,
    player_count: u8,
    rules: *const Rules,
    allocator: std.mem.Allocator,
) !Self {
    var self: Self = undefined;
    self.civ_id = @enumFromInt(0);

    self.world = try World.init(
        allocator,
        width,
        height,
        wrap_around,
        player_count,
        rules,
    );
    errdefer self.world.deinit();

    return self;
}

pub fn getView(self: *const Self) *const View {
    return &self.world.views[@intFromEnum(self.civ_id)];
}

pub fn deinit(self: *Self) void {
    self.world.deinit();
}

pub fn canPerformAction(self: *const Self, action: Action) bool {
    switch (action) {
        .move_unit => |info| {
            const unit = self.world.units.deref(info.ref) orelse return false;

            if (unit.faction_id != self.civ_id.toFactionID()) return false;

            if (self.world.moveCost(info.ref, info.to) == .disallowed) return false;
        },
        .attack => |info| {
            const unit = self.world.units.deref(info.attacker) orelse return false;

            if (unit.faction_id != self.civ_id.toFactionID()) return false;

            if (!try self.world.canAttack(info.attacker, info.to)) return false;
        },
    }

    return true;
}

pub fn performAction(self: *Self, action: Action) !bool {
    return try self.execAction(self.civ_id, action);
}

fn execAction(self: *Self, civ_id: World.CivilizationID, action: Action) !bool {
    var view_update: bool = false;
    switch (action) {
        .move_unit => |info| {
            const unit = self.world.units.deref(info.ref) orelse return false;

            if (unit.faction_id != civ_id.toFactionID()) return false;

            if (!try self.world.move(info.ref, info.to)) return false;

            view_update = true;
        },
        .attack => |info| {
            const unit = self.world.units.deref(info.attacker) orelse return false;

            if (unit.faction_id != civ_id.toFactionID()) return false;

            if (!try self.world.attack(info.attacker, info.to)) return false;

            view_update = true;
        },
    }

    if (view_update) self.world.fullUpdateViews();

    return true;
}

// Debug function to test using different players
pub fn nextPlayer(self: *Self) void {
    const next_int_id = @intFromEnum(self.civ_id) + 1;
    self.civ_id = if (next_int_id == self.world.views.len - 1) @enumFromInt(0) else @enumFromInt(next_int_id);
}
