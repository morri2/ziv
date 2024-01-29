const Self = @This();
const std = @import("std");

const Rules = @import("Rules.zig");
const Yield = @import("yield.zig").Yield;
const Terrain = Rules.Terrain;
const Resource = Rules.Resource;
const Building = Rules.Building;
const Transport = Rules.Transport;
const Improvements = Rules.Improvements;
const City = @import("City.zig");
const HexSet = @import("HexSet.zig");
const PlayerView = @import("PlayerView.zig");
const Player = @import("Player.zig");

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const Idx = Grid.Idx;
const Dir = Grid.Dir;

const Units = @import("Units.zig");

const Unit = @import("Unit.zig");

/// The lowest index is always in low :))
pub const WorkInProgress = struct {
    work_type: union(enum) {
        building: Building,
        remove_vegetation_building: Building,
        transport: Transport,
        remove_fallout,
        repair,
        remove_vegetation,
    },

    progress: u8,
};

pub const ResourceAndAmount = packed struct {
    type: Resource,
    amount: u8,
};

allocator: std.mem.Allocator,

rules: *const Rules,

grid: Grid,

players: []Player,
player_count: u8,

turn_counter: usize,

// Per tile data
terrain: []Terrain,
improvements: []Improvements,

// Tile lookup data
resources: std.AutoArrayHashMapUnmanaged(Idx, ResourceAndAmount),
work_in_progress: std.AutoArrayHashMapUnmanaged(Idx, WorkInProgress),

// Tile edge data
rivers: std.AutoArrayHashMapUnmanaged(Edge, void),

units: Units,

cities: std.AutoArrayHashMapUnmanaged(Idx, City),

pub fn claimed(self: *const Self, idx: Idx) bool {
    for (self.cities.values()) |city| if (city.claimed.contains(idx) or city.position == idx) return true;
    return false;
}

pub fn addCity(self: *Self, idx: Idx) !void {
    const city = City.new(idx, 0, self);
    try self.cities.put(self.allocator, idx, city);
}

pub fn tileYield(self: *const Self, idx: Idx) Yield {
    const terrain = self.terrain[idx];
    const resource = self.resources.get(idx);

    var yield = terrain.yield(self.rules);

    if (resource != null) {
        yield = yield.add(resource.?.type.yield(self.rules));
    }

    // city yeilds
    if (self.cities.contains(idx)) {
        yield.production = @max(yield.production, 1);
        yield.food = @max(yield.food, 2);
    }

    return yield;
}

pub fn init(
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    wrap_around: bool,
    player_count: u8,
    rules: *const Rules,
) !Self {
    const grid = Grid.init(width, height, wrap_around);

    const terrain = try allocator.alloc(Terrain, grid.len);
    errdefer allocator.free(terrain);
    @memset(terrain, std.mem.zeroes(Terrain));

    const improvements = try allocator.alloc(Improvements, grid.len);
    errdefer allocator.free(improvements);
    @memset(improvements, std.mem.zeroes(Improvements));

    const players = try allocator.alloc(Player, player_count);
    errdefer allocator.free(players);
    for (0..players.len) |i| players[i] = try Player.init(allocator, @as(u8, @intCast(i)), &grid);

    return Self{
        .player_count = player_count,
        .players = players,
        .allocator = allocator,
        .grid = grid,
        .terrain = terrain,
        .improvements = improvements,
        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},
        .turn_counter = 1,
        .cities = .{},
        .rules = rules,
        .units = Units.init(rules, allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);

    self.units.deinit(self.allocator);

    self.allocator.free(self.improvements);
    self.allocator.free(self.terrain);

    for (self.cities.keys()) |city_key| self.cities.getPtr(city_key).?.deinit();
    for (0..self.players.len) |i| self.players[i].deinit();

    self.allocator.free(self.players);
    self.cities.deinit(self.allocator);
}

pub fn moveCost(
    self: *const Self,
    reference: Units.Reference,
    to: Idx,
) Unit.MoveCost {
    if (!self.grid.adjacentTo(reference.idx, to)) return .disallowed;

    if (self.units.get(to, reference.slot) != null) return .disallowed;

    const unit = self.units.deref(reference) orelse return .disallowed;

    const terrain = self.terrain[to];
    const improvements = self.improvements[to];

    return unit.moveCost(.{
        .target_terrain = terrain,
        .river_crossing = if (self.grid.edgeBetween(reference.idx, to)) |edge| self.rivers.contains(edge) else false,
        .transport = if (improvements.pillaged_transport) .none else improvements.transport,
        .embarked = reference.slot == .embarked,
        .city = self.cities.contains(to),
    }, self.rules);
}

pub fn move(self: *Self, reference: Units.Reference, to: Idx) !bool {
    const cost = self.moveCost(reference, to);

    if (cost == .disallowed) return false;

    var unit = self.units.deref(reference) orelse unreachable;

    self.units.removeReference(reference);

    unit.performMove(cost);

    switch (cost) {
        .disallowed => unreachable,
        .allowed,
        .allowed_final,
        => try self.units.putNoStack(to, unit, reference.slot),
        .embarkation => try self.units.putNoStack(to, unit, .embarked),
        .disembarkation => try self.units.putNoStackAutoSlot(to, unit),
    }
    return true;
}

pub fn saveToFile(self: *Self, path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    var writer = file.writer();

    for (0..self.grid.len) |i| {
        const terrain_bytes: [@sizeOf(Terrain)]u8 = std.mem.asBytes(&self.terrain[i]).*;
        _ = try file.write(&terrain_bytes);
    }

    _ = try writer.writeInt(usize, self.resources.count(), .little); // write len
    for (self.resources.keys()) |key| {
        const value = self.resources.get(key) orelse unreachable;
        _ = try writer.writeInt(usize, key, .little);
        _ = try writer.writeStruct(value);
    }

    file.close();
}

pub fn fullUpdateViews(self: *Self) void {
    for (self.players, 0..) |player, i| {
        self.players[i].view.unsetAllVisable(self);

        var iter = self.units.iterator();
        while (iter.next()) |unit| {
            if (unit.unit.faction.player != player.id) continue;

            var flow = HexSet.init(self.allocator);
            defer flow.deinit();
            flow.add(unit.idx);
            flow.addAdjacent(&self.grid);
            flow.addAdjacent(&self.grid);

            for (flow.slice()) |idx_adj| self.players[i].view.setVisable(idx_adj, self);
        }

        for (self.cities.values()) |city| {
            if (city.faction.player != player.id) continue;
            self.players[i].view.setVisable(city.position, self);

            for (city.claimed.slice()) |idx_c|
                self.players[i].view.setVisable(idx_c, self);

            for (city.adjacent.slice()) |idx_adj|
                self.players[i].view.setVisable(idx_adj, self);
        }
    }
}

pub fn loadFromFile(self: *Self, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    var reader = file.reader();
    for (0..self.grid.len) |i| {
        const terrain_bytes = try reader.readBytesNoEof(@sizeOf(Terrain));

        const terrain: *const Terrain = @ptrCast(&terrain_bytes);
        self.terrain[i] = terrain.*;
    }
    blk: {
        const len = reader.readInt(usize, .little) catch {
            std.debug.print("\nEarly return in loadFromFile\n", .{});
            break :blk;
        };
        for (0..len) |_| {
            const k = try reader.readInt(usize, .little);

            const v = try reader.readStruct(ResourceAndAmount);
            try self.resources.put(self.allocator, k, v);
        }
    }

    file.close();
}
