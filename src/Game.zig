const std = @import("std");

const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

const Rules = @import("Rules.zig");
const World = @import("World.zig");
const Units = @import("Units.zig");
const City = @import("City.zig");
const View = @import("View.zig");

const Action = @import("action.zig").Action;

const Socket = @import("Socket.zig");

const hex_set = @import("hex_set.zig");
const serialization = @import("serialization.zig");

const Self = @This();

pub const Player = struct {
    civ_id: World.CivilizationID,
    socket: Socket,
};

// Host specific
is_host: bool,
players: []Player,

views: []View,

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
        rules,
    );
    errdefer self.world.deinit();

    self.views = try allocator.alloc(View, civ_count);
    errdefer allocator.free(self.views);

    for (self.views) |*view| view.* = try View.init(allocator, &self.world.grid);
    errdefer for (self.views) |*view| view.deinit();

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
        rules,
    );
    errdefer self.world.deinit();

    self.views = try allocator.alloc(View, civ_count);
    errdefer allocator.free(self.views);

    for (self.views) |*view| view.* = try View.init(allocator, &self.world.grid);
    errdefer for (self.views) |*view| view.deinit();

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
    for (self.views) |*view| view.deinit();
    self.allocator.free(self.views);
    self.world.deinit();
}

pub fn getView(self: *const Self) *const View {
    return &self.views[@intFromEnum(self.civ_id)];
}

// Debug function to test using different players
pub fn nextPlayer(self: *Self) void {
    const next_int_id = @intFromEnum(self.civ_id) + 1;
    self.civ_id = if (next_int_id == self.views.len) @enumFromInt(0) else @enumFromInt(next_int_id);
}

pub fn nextTurn(self: *Self) !?Action.Result {
    return try self.performAction(.next_turn);
}

pub fn move(self: *Self, reference: Units.Reference, to: Idx) !?Action.Result {
    return try self.performAction(.{
        .move_unit = .{
            .ref = reference,
            .to = to,
        },
    });
}

pub fn attack(self: *Self, attacker: Units.Reference, to: Idx) !?Action.Result {
    return try self.performAction(.{
        .attack = .{
            .attacker = attacker,
            .to = to,
        },
    });
}

pub fn setCityProduction(self: *Self, city_idx: Idx, production: City.ProductionTarget) !?Action.Result {
    return try self.performAction(.{
        .set_city_production = .{
            .city_idx = city_idx,
            .production = production,
        },
    });
}

pub fn settleCity(self: *Self, settler_reference: Units.Reference) !?Action.Result {
    return try self.performAction(.{ .settle_city = settler_reference });
}

pub fn unsetWorked(self: *Self, city_idx: Idx, idx: Idx) !?Action.Result {
    return try self.performAction(.{
        .unset_worked = .{
            .city_idx = city_idx,
            .idx = idx,
        },
    });
}

pub fn setWorked(self: *Self, city_idx: Idx, idx: Idx) !?Action.Result {
    return try self.performAction(.{
        .set_worked = .{
            .city_idx = city_idx,
            .idx = idx,
        },
    });
}

pub fn promoteUnit(self: *Self, unit_ref: Units.Reference, promotion: Rules.Promotion) !?Action.Result {
    return try self.performAction(.{ .promote_unit = .{ .unit = unit_ref, .promotion = promotion } });
}

pub fn tileWork(self: *Self, ref: Units.Reference, work: World.TileWork) !?Action.Result {
    return try self.performAction(.{
        .tile_work = .{
            .unit = ref,
            .work = work,
        },
    });
}

pub fn update(self: *Self) !Action.Result {
    const result = if (self.is_host) try self.hostUpdate() else try self.clientUpdate();
    if (result.view_change) try self.updateViews();
    return result;
}

pub fn updateViews(self: *Self) !void {
    for (self.views) |*view| view.unsetAllVisable(&self.world);

    // Add unit vision
    {
        var vision_set = hex_set.HexSet(0).init(self.allocator);
        defer vision_set.deinit();

        var iter = self.world.units.iterator();
        while (iter.next()) |item| {
            if (item.unit.faction_id.toCivilizationID()) |civ_id| {
                try self.world.unitFov(&item.unit, item.idx, &vision_set);
                try self.views[@intFromEnum(civ_id)].addVisionSet(vision_set);
                vision_set.clear();
            }
        }
    }

    for (self.world.cities.values()) |city| {
        if (city.faction_id.toCivilizationID()) |civ_id| {
            try self.views[@intFromEnum(civ_id)].addVision(city.position);
            try self.views[@intFromEnum(civ_id)].addVisionSet(city.claimed);
            try self.views[@intFromEnum(civ_id)].addVisionSet(city.adjacent);
        }
    }
}

fn performAction(self: *Self, action: Action) !?Action.Result {
    var result: ?Action.Result = Action.Result{};
    if (self.is_host) {
        const faction_id = self.civ_id.toFactionID();
        result = try action.exec(faction_id, &self.world) orelse return null;

        if (result.?.view_change) try self.updateViews();

        // Broadcast action to all players
        for (self.players) |player| {
            const writer = player.socket.writer();
            try writer.writeByte(@intFromEnum(faction_id));
            try serialization.serialize(writer, action);
        }
    } else {
        if (!action.possible(self.civ_id.toFactionID(), &self.world)) return null;
        try serialization.serialize(self.socket.writer(), action);
    }
    return result;
}

fn hostUpdate(self: *Self) !Action.Result {
    var result = Action.Result{};
    for (self.players) |player| {
        const faction_id = player.civ_id.toFactionID();
        while (try player.socket.hasData()) {
            try player.socket.setBlocking(true);
            const action = try serialization.deserialize(player.socket.reader(), Action);
            if (try action.exec(faction_id, &self.world)) |exec_result| {
                for (self.players) |p| {
                    const writer = p.socket.writer();
                    try writer.writeByte(@intFromEnum(faction_id));
                    try serialization.serialize(writer, action);
                }
                result = result.unionWith(exec_result);
            } else {
                // TODO: Resync
                std.debug.panic("Failed to execute action: {s}", .{@tagName(std.meta.activeTag(action))});
            }

            try player.socket.setBlocking(false);
        }
    }
    return result;
}

fn clientUpdate(self: *Self) !Action.Result {
    var result = Action.Result{};
    while (try self.socket.hasData()) {
        try self.socket.setBlocking(true);
        const reader = self.socket.reader();
        const faction_id: World.FactionID = @enumFromInt(try reader.readByte());

        const action = try serialization.deserialize(self.socket.reader(), Action);
        if (try action.exec(faction_id, &self.world)) |exec_result| {
            result = result.unionWith(exec_result);
        } else {
            // TODO: Resync
            std.debug.panic("Failed to execute action: {s}", .{@tagName(std.meta.activeTag(action))});
        }

        try self.socket.setBlocking(false);
    }
    return result;
}
