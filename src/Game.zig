const std = @import("std");

const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

const Rules = @import("Rules.zig");
const World = @import("World.zig");
const Units = @import("Units.zig");
const City = @import("City.zig");
const View = @import("View.zig");

const Socket = @import("Socket.zig");

const Self = @This();

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
    };
};

pub const Player = struct {
    civ_id: World.CivilizationID,
    socket: Socket,
};

// Host specific
is_host: bool,
players: []Player,

// Client specific
socket: Socket,

civ_id: World.CivilizationID,
world: World,

allocator: std.mem.Allocator,

pub fn host(
    width: u32,
    height: u32,
    wrap_around: bool,
    civ_id: World.CivilizationID,
    civ_count: u8,
    players: []Player,
    rules: *const Rules,
    allocator: std.mem.Allocator,
) !Self {
    std.debug.assert(@intFromEnum(civ_id) < civ_count);

    var self: Self = undefined;
    self.allocator = allocator;
    self.is_host = true;
    self.civ_id = civ_id;

    self.players = players;

    self.world = try World.init(
        allocator,
        width,
        height,
        wrap_around,
        civ_count,
        rules,
    );
    errdefer self.world.deinit();

    for (self.players) |player| {
        try player.socket.setBlocking(true);
        const writer = player.socket.writer();
        try writer.writeInt(u32, width, .little);
        try writer.writeInt(u32, height, .little);
        try writer.writeByte(@intFromBool(wrap_around));
        try writer.writeByte(civ_count);
        try writer.writeByte(@intFromEnum(player.civ_id));
        try player.socket.setBlocking(false);
    }

    return self;
}

pub fn connect(socket: Socket, rules: *const Rules, allocator: std.mem.Allocator) !Self {
    var self: Self = undefined;
    self.allocator = allocator;
    self.is_host = false;

    self.socket = socket;
    self.players = &.{};

    try self.socket.setBlocking(true);
    const reader = self.socket.reader();
    const width = try reader.readInt(u32, .little);
    const height = try reader.readInt(u32, .little);
    const wrap_around: bool = @bitCast(@as(u1, @intCast(try reader.readByte())));
    const civ_count = try reader.readByte();
    self.civ_id = @enumFromInt(try reader.readByte());
    try self.socket.setBlocking(false);

    self.world = try World.init(
        allocator,
        width,
        height,
        wrap_around,
        civ_count,
        rules,
    );
    errdefer self.world.deinit();

    return self;
}

pub fn deinit(self: *Self) void {
    if (self.is_host) {
        for (self.players) |player| {
            player.socket.close();
        }
        self.allocator.free(self.players);
    } else {
        self.socket.close();
    }
    self.world.deinit();
}

pub fn getView(self: *const Self) *const View {
    return &self.world.views[@intFromEnum(self.civ_id)];
}

// Debug function to test using different players
pub fn nextPlayer(self: *Self) void {
    const next_int_id = @intFromEnum(self.civ_id) + 1;
    self.civ_id = if (next_int_id == self.world.views.len) @enumFromInt(0) else @enumFromInt(next_int_id);
}

pub fn nextTurn(self: *Self) !bool {
    return try self.performAction(.next_turn);
}

pub fn move(self: *Self, reference: Units.Reference, to: Idx) !bool {
    return try self.performAction(.{
        .move_unit = .{
            .ref = reference,
            .to = to,
        },
    });
}

pub fn attack(self: *Self, attacker: Units.Reference, to: Idx) !bool {
    return try self.performAction(.{
        .attack = .{
            .attacker = attacker,
            .to = to,
        },
    });
}

pub fn setCityProduction(self: *Self, city_idx: Idx, production: City.ProductionTarget) !bool {
    return try self.performAction(.{
        .set_city_production = .{
            .city_idx = city_idx,
            .production = production,
        },
    });
}

pub fn settleCity(self: *Self, settler_reference: Units.Reference) !bool {
    return try self.performAction(.{ .settle_city = settler_reference });
}

pub fn unsetWorked(self: *Self, city_idx: Idx, idx: Idx) !bool {
    return try self.performAction(.{
        .unset_worked = .{
            .city_idx = city_idx,
            .idx = idx,
        },
    });
}

pub fn setWorked(self: *Self, city_idx: Idx, idx: Idx) !bool {
    return try self.performAction(.{
        .set_worked = .{
            .city_idx = city_idx,
            .idx = idx,
        },
    });
}

pub fn promoteUnit(self: *Self, unit_ref: Units.Reference, promotion: Rules.Promotion) !bool {
    return try self.performAction(.{ .promote_unit = .{ .unit = unit_ref, .promotion = promotion } });
}

pub fn canPerformAction(self: *const Self, action: Action) bool {
    switch (action) {
        .next_turn => {},
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
        .set_city_production => |info| {
            const city = self.world.cities.get(info.city_idx) orelse return false;
            if (city.faction_id != self.civ_id.toFactionID()) return false;
        },
        .settle_city => |settler_ref| {
            const unit = self.world.units.deref(settler_ref) orelse return false;

            if (unit.faction_id != self.civ_id.toFactionID()) return false;

            if (!Rules.Promotion.Effect.settle_city.in(unit.promotions, self.world.rules)) return false;

            if (!self.world.canSettleCityAt(settler_ref.idx, self.civ_id.toFactionID())) return false;
        },
        .unset_worked => |info| {
            const city = self.world.cities.get(info.city_idx) orelse return false;
            if (!city.worked.contains(info.idx)) return false;
        },
        .set_worked => |info| {
            const city = self.world.cities.get(info.city_idx) orelse return false;

            if (city.unassignedPopulation() == 0) return false;

            if (!city.claimed.contains(info.idx)) return false;

            if (city.worked.contains(info.idx)) return false;
        },
        .promote_unit => |info| {
            _ = self.world.units.deref(info.unit) orelse return false;
        },
    }

    return true;
}

fn execAction(self: *Self, faction_id: World.FactionID, action: Action) !bool {
    var view_update: bool = false;
    switch (action) {
        .next_turn => try self.world.nextTurn(),
        .move_unit => |info| {
            const unit = self.world.units.deref(info.ref) orelse return false;

            if (unit.faction_id != faction_id) return false;

            if (!try self.world.move(info.ref, info.to)) return false;

            view_update = true;
        },
        .attack => |info| {
            const unit = self.world.units.deref(info.attacker) orelse return false;

            if (unit.faction_id != faction_id) return false;

            if (!try self.world.attack(info.attacker, info.to)) return false;

            view_update = true;
        },
        .set_city_production => |info| {
            const city = self.world.cities.getPtr(info.city_idx) orelse return false;
            if (city.faction_id != faction_id) return false;

            _ = city.startConstruction(info.production, self.world.rules);
        },
        .settle_city => |settler_ref| {
            const unit = self.world.units.deref(settler_ref) orelse return false;

            if (unit.faction_id != faction_id) return false;

            if (!Rules.Promotion.Effect.settle_city.in(unit.promotions, self.world.rules)) return false;

            if (!try self.world.settleCity(settler_ref)) return false;

            view_update = true;
        },
        .unset_worked => |info| {
            const city = self.world.cities.getPtr(info.city_idx) orelse return false;

            if (!city.unsetWorked(info.idx)) return false;
        },
        .set_worked => |info| {
            const city = self.world.cities.getPtr(info.city_idx) orelse return false;

            if (city.unassignedPopulation() == 0) return false;

            if (!city.claimed.contains(info.idx)) return false;

            if (!city.setWorkedWithAutoReassign(info.idx, &self.world)) return false;
        },
        .promote_unit => |info| {
            var unit = self.world.units.derefToPtr(info.unit) orelse return false;
            unit.promotions.set(@intFromEnum(info.promotion));

            view_update = true;
        },
    }

    if (view_update) self.world.fullUpdateViews();

    return true;
}

pub fn performAction(self: *Self, action: Action) !bool {
    if (self.is_host) {
        const faction_id = self.civ_id.toFactionID();
        if (!try self.execAction(faction_id, action)) return false;

        // Broadcast action to all players
        for (self.players) |player| {
            const writer = player.socket.writer();
            try writer.writeByte(@intFromEnum(faction_id));
            try sendAction(writer, action);
        }
    } else {
        if (!self.canPerformAction(action)) return false;
        try sendAction(self.socket.writer(), action);
    }
    return true;
}

pub fn update(self: *Self) !void {
    if (self.is_host) try self.hostUpdate() else try self.clientUpdate();
}

fn hostUpdate(self: *Self) !void {
    for (self.players) |player| {
        const faction_id = player.civ_id.toFactionID();
        while (try player.socket.hasData()) {
            try player.socket.setBlocking(true);
            const action = try recieveAction(player.socket.reader());
            if (try self.execAction(faction_id, action)) {
                for (self.players) |p| {
                    const writer = p.socket.writer();
                    try writer.writeByte(@intFromEnum(faction_id));
                    try sendAction(writer, action);
                }
            }

            try player.socket.setBlocking(false);
        }
    }
}

fn clientUpdate(self: *Self) !void {
    while (try self.socket.hasData()) {
        try self.socket.setBlocking(true);
        const reader = self.socket.reader();
        const faction_id: World.FactionID = @enumFromInt(try reader.readByte());

        const action = try recieveAction(self.socket.reader());

        if (!try self.execAction(faction_id, action)) unreachable;
        try self.socket.setBlocking(false);
    }
}

fn sendAction(writer: Socket.Writer, action: Action) !void {
    switch (action) {
        .next_turn => try writer.writeByte(@intFromEnum(Action.Type.next_turn)),
        .move_unit => |info| {
            try writer.writeByte(@intFromEnum(Action.Type.move_unit));
            try writer.writeInt(Idx, info.ref.idx, .little);
            try writer.writeByte(@intFromEnum(info.ref.slot));
            try writer.writeInt(std.meta.Tag(Units.Stacked.Key), @intFromEnum(info.ref.stacked), .little);
            try writer.writeInt(Idx, info.to, .little);
        },
        .attack => |info| {
            try writer.writeByte(@intFromEnum(Action.Type.attack));
            try writer.writeInt(Idx, info.attacker.idx, .little);
            try writer.writeByte(@intFromEnum(info.attacker.slot));
            try writer.writeInt(std.meta.Tag(Units.Stacked.Key), @intFromEnum(info.attacker.stacked), .little);
            try writer.writeInt(Idx, info.to, .little);
        },
        .set_city_production => |info| {
            try writer.writeByte(@intFromEnum(Action.Type.set_city_production));
            try writer.writeInt(Idx, info.city_idx, .little);
            try writer.writeByte(@intFromEnum(std.meta.activeTag(info.production)));
            switch (info.production) {
                .building => |building| try writer.writeInt(std.meta.Tag(Rules.Building), @intFromEnum(building), .little),
                .unit => |unit_type| try writer.writeInt(std.meta.Tag(Rules.UnitType), @intFromEnum(unit_type), .little),
                .perpetual_money, .perpetual_research => {},
            }
        },
        .settle_city => |settler_ref| {
            try writer.writeByte(@intFromEnum(Action.Type.settle_city));
            try writer.writeInt(Idx, settler_ref.idx, .little);
            try writer.writeByte(@intFromEnum(settler_ref.slot));
            try writer.writeInt(std.meta.Tag(Units.Stacked.Key), @intFromEnum(settler_ref.stacked), .little);
        },
        .unset_worked => |info| {
            try writer.writeByte(@intFromEnum(Action.Type.unset_worked));
            try writer.writeInt(Idx, info.city_idx, .little);
            try writer.writeInt(Idx, info.idx, .little);
        },
        .set_worked => |info| {
            try writer.writeByte(@intFromEnum(Action.Type.set_worked));
            try writer.writeInt(Idx, info.city_idx, .little);
            try writer.writeInt(Idx, info.idx, .little);
        },
        .promote_unit => |info| {
            try writer.writeByte(@intFromEnum(Action.Type.promote_unit));
            try writer.writeInt(Idx, info.unit.idx, .little);
            try writer.writeByte(@intFromEnum(info.unit.slot));
            try writer.writeInt(std.meta.Tag(Units.Stacked.Key), @intFromEnum(info.unit.stacked), .little);
            try writer.writeByte(@intFromEnum(info.promotion));
        },
    }
}

fn recieveAction(reader: Socket.Reader) !Action {
    const action_type: Action.Type = @enumFromInt(try reader.readByte());

    switch (action_type) {
        .next_turn => return .next_turn,
        .move_unit => {
            const idx = try reader.readInt(Idx, .little);
            const slot: Units.Slot = @enumFromInt(try reader.readByte());
            const stacked = try reader.readEnum(Units.Stacked.Key, .little);

            const to = try reader.readInt(Idx, .little);
            return .{
                .move_unit = .{
                    .ref = .{
                        .idx = idx,
                        .slot = slot,
                        .stacked = stacked,
                    },
                    .to = to,
                },
            };
        },
        .attack => {
            const idx = try reader.readInt(Idx, .little);
            const slot: Units.Slot = @enumFromInt(try reader.readByte());
            const stacked = try reader.readEnum(Units.Stacked.Key, .little);

            const to = try reader.readInt(Idx, .little);
            return .{
                .attack = .{
                    .attacker = .{
                        .idx = idx,
                        .slot = slot,
                        .stacked = stacked,
                    },
                    .to = to,
                },
            };
        },
        .set_city_production => {
            const idx = try reader.readInt(Idx, .little);
            const tag: City.ProductionTarget.Type = @enumFromInt(try reader.readByte());
            switch (tag) {
                .building => {
                    const building: Rules.Building = @enumFromInt(try reader.readInt(std.meta.Tag(Rules.Building), .little));
                    return .{
                        .set_city_production = .{
                            .city_idx = idx,
                            .production = .{ .building = building },
                        },
                    };
                },
                .unit => {
                    const unit_type: Rules.UnitType = @enumFromInt(try reader.readInt(std.meta.Tag(Rules.UnitType), .little));
                    return .{
                        .set_city_production = .{
                            .city_idx = idx,
                            .production = .{ .unit = unit_type },
                        },
                    };
                },
                .perpetual_money => return .{ .set_city_production = .{ .city_idx = idx, .production = .perpetual_money } },
                .perpetual_research => return .{ .set_city_production = .{ .city_idx = idx, .production = .perpetual_research } },
            }
        },
        .settle_city => {
            const idx = try reader.readInt(Idx, .little);
            const slot: Units.Slot = @enumFromInt(try reader.readByte());
            const stacked = try reader.readEnum(Units.Stacked.Key, .little);

            return .{
                .settle_city = .{
                    .idx = idx,
                    .slot = slot,
                    .stacked = stacked,
                },
            };
        },
        .unset_worked => {
            const city_idx = try reader.readInt(Idx, .little);
            const idx = try reader.readInt(Idx, .little);

            return .{
                .unset_worked = .{
                    .city_idx = city_idx,
                    .idx = idx,
                },
            };
        },
        .set_worked => {
            const city_idx = try reader.readInt(Idx, .little);
            const idx = try reader.readInt(Idx, .little);

            return .{
                .set_worked = .{
                    .city_idx = city_idx,
                    .idx = idx,
                },
            };
        },
        .promote_unit => {
            const idx = try reader.readInt(Idx, .little);
            const slot: Units.Slot = @enumFromInt(try reader.readByte());
            const stacked = try reader.readEnum(Units.Stacked.Key, .little);
            const promotion: Rules.Promotion = @enumFromInt(try reader.readByte());

            return .{ .promote_unit = .{
                .unit = .{
                    .idx = idx,
                    .slot = slot,
                    .stacked = stacked,
                },
                .promotion = promotion,
            } };
        },
    }
}
