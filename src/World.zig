const Self = @This();
const std = @import("std");

const Rules = @import("Rules.zig");
const Yield = Rules.Yield;
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
    amount: u8 = 1,
};

allocator: std.mem.Allocator,

rules: *const Rules,

grid: Grid,

players: []Player,
player_count: u8,

turn: u32,

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

pub fn init(
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    wrap_around: bool,
    player_count: u8,
    rules: *const Rules,
) !Self {
    std.debug.assert(player_count >= 1);
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
        .turn = 1,
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

pub fn nextTurn(self: *Self) !void {
    for (self.cities.keys(), self.cities.values()) |idx, *city| {
        const ya = city.getWorkedTileYields(self);

        _ = city.processYields(&ya);
        const growth_res = city.checkGrowth(self);
        _ = growth_res;

        var update_view = city.checkExpansion();
        const production_result = try city.checkProduction();
        switch (production_result) {
            .done => |project| switch (project) {
                .unit => |unit_type| {
                    try self.addUnit(idx, unit_type, city.faction_id);
                    update_view = true;
                },
                else => unreachable, // TODO
            },
            else => {},
        }

        if (update_view) self.fullUpdateViews();
    }

    self.units.refresh();

    self.turn += 1;
}

pub fn addCity(self: *Self, idx: Idx, faction_id: Player.FactionID) !void {
    const city = City.new(idx, faction_id, self);
    try self.cities.put(self.allocator, idx, city);
}

pub fn addUnit(self: *Self, idx: Idx, unit_temp: Rules.UnitType, faction: Player.FactionID) !void {
    const unit = Unit.new(unit_temp, faction, self.rules);
    try self.units.putOrStackAutoSlot(idx, unit);
}

pub fn claimed(self: *const Self, idx: Idx) bool {
    for (self.cities.values()) |city| if (city.claimed.contains(idx) or city.position == idx) return true;
    return false;
}

pub fn claimedFaction(self: *const Self, idx: Idx) ?Player.FactionID {
    for (self.cities.values()) |city| if (city.claimed.contains(idx) or city.position == idx) return city.faction_id;
    return null;
}

pub fn canSettleCityAt(self: *const Self, idx: Idx, faction: Player.FactionID) bool {
    if (self.claimedFaction(idx)) |claimed_by| {
        if (claimed_by != faction) return false;
    }
    for (self.cities.keys()) |city_idx| if (self.grid.distance(idx, city_idx) < 3) return false;
    if (self.terrain[idx].attributes(self.rules).is_impassable) return false;
    if (self.terrain[idx].attributes(self.rules).is_wonder) return false;
    if (self.terrain[idx].attributes(self.rules).is_water) return false;
    return true;
}

pub fn settleCity(self: *Self, idx: Idx, refrence: Units.Reference) !bool {
    const unit = self.units.deref(refrence) orelse return false;
    if (!self.canSettleCityAt(idx, unit.faction_id)) return false;
    if (!Rules.Promotion.Effect.in(.settle_city, unit.promotions, self.rules)) return false;
    if (refrence.idx != idx) return false;
    if (unit.movement <= 0) return false;

    try self.addCity(idx, unit.faction_id);
    self.units.removeReference(refrence); // will this fuck up the refrence held by controll?

    return true;
}

pub fn recalculateWaterAccess(self: *Self) !void {
    var new_terrain = try self.allocator.alloc(Rules.Terrain.Unpacked, self.grid.len);
    defer self.allocator.free(new_terrain);

    for (0..self.grid.len) |idx| {
        const terrain = self.terrain[idx];
        new_terrain[idx] = .{
            .base = terrain.base(self.rules),
            .feature = terrain.feature(self.rules),
            .vegetation = terrain.vegetation(self.rules),
            .has_freshwater = false,
            .has_river = false,
        };
    }

    for (0..self.grid.len) |idx_us| {
        const idx: u32 = @intCast(idx_us);

        const terrain = self.terrain[idx];
        if (terrain.attributes(self.rules).is_freshwater) {
            new_terrain[idx].has_freshwater = true;
            for (self.grid.neighbours(idx)) |maybe_n_idx|
                if (maybe_n_idx) |n_idx| {
                    new_terrain[n_idx].has_freshwater = true;
                };
        }
    }

    for (self.rivers.keys()) |edge| {
        new_terrain[edge.low].has_freshwater = true;
        new_terrain[edge.high].has_freshwater = true;
        new_terrain[edge.low].has_river = true;
        new_terrain[edge.high].has_river = true;
    }

    for (0..self.grid.len) |idx_us| {
        const idx: u32 = @intCast(idx_us);
        if (self.terrain[idx].attributes(self.rules).is_water) {
            new_terrain[idx].has_freshwater = false;
        }
    }

    for (0..self.grid.len) |idx| self.terrain[idx] = new_terrain[idx].pack(self.rules) orelse
        std.debug.panic("Failed to pack tile", .{});
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

pub fn moveCost(
    self: *const Self,
    reference: Units.Reference,
    to: Idx,
) Unit.MoveCost {
    if (!self.grid.isNeighbour(reference.idx, to)) return .disallowed;

    if (self.units.get(to, reference.slot) != null) return .disallowed;

    const unit = self.units.deref(reference) orelse return .disallowed;

    // Check if tile is already occupied
    {
        var maybe_ref = self.units.firstReference(to);
        const initial: ?Units.Slot = if (maybe_ref) |ref| ref.slot else null;
        loop: while (maybe_ref) |ref| {
            const to_unit = self.units.deref(ref) orelse unreachable;
            switch (ref.slot) {
                .trade => if (reference.slot == .trade) return .disallowed,
                else => if (to_unit.faction_id != unit.faction_id) return .disallowed,
            }
            maybe_ref = self.units.nextReference(ref);
            if (initial.? == maybe_ref.?.slot) break :loop;
        }
    }

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

pub fn canAttack(self: *const Self, attacker: Units.Reference, to: Idx) !bool {
    if (!self.grid.isNeighbour(attacker.idx, to)) return false;

    const attacker_unit = self.units.deref(attacker) orelse return false;

    const terrain = self.terrain[to];
    const river_crossing = if (self.grid.edgeBetween(attacker.idx, to)) |edge| self.rivers.contains(edge) else false;
    const improvements = self.improvements[to];

    const cost = attacker_unit.moveCost(.{
        .target_terrain = terrain,
        .river_crossing = river_crossing,
        .transport = if (improvements.pillaged_transport) .none else improvements.transport,
        .embarked = attacker.slot == .embarked,
        .city = self.cities.contains(to),
    }, self.rules);

    if (!cost.allowsAttack()) return false;

    if (Rules.Promotion.Effect.cannot_melee.in(attacker_unit.promotions, self.rules)) return false;

    const defender = self.units.firstReference(to) orelse return false;
    const defender_unit = self.units.deref(defender) orelse return false;

    if (attacker_unit.faction_id == defender_unit.faction_id) return false;

    return true;
}

pub fn attack(self: *Self, attacker: Units.Reference, to: Idx) !bool {
    if (!try self.canAttack(attacker, to)) return false;

    const attacker_unit = self.units.derefToPtr(attacker) orelse return false;

    const defender = self.units.firstReference(to) orelse return false;
    const defender_unit = self.units.derefToPtr(defender) orelse return false;

    // Check if this is a capture
    if (attacker.slot.isMilitary() and defender.slot.isCivilian()) {
        defender_unit.faction_id = attacker_unit.faction_id;
        _ = try self.move(attacker, to);
        return true;
    }

    const terrain = self.terrain[to];
    const river_crossing = if (self.grid.edgeBetween(attacker.idx, to)) |edge| self.rivers.contains(edge) else false;

    // TODO: Implement ranged combat
    const attacker_strength = attacker_unit.strength(.{
        .is_attacker = true,
        .target_terrain = terrain,
        .river_crossing = river_crossing,
        .is_ranged = false,
    }, self.rules);

    const defender_strength = defender_unit.strength(.{
        .is_attacker = false,
        .target_terrain = terrain,
        .river_crossing = river_crossing,
        .is_ranged = false,
    }, self.rules);

    const ratio = attacker_strength.total / defender_strength.total;
    const attacker_damage: u8 = @intFromFloat(1.0 / ratio * 35.0);
    const defender_damage: u8 = @intFromFloat(ratio * 35.0);

    const attacker_higher_hp = attacker_unit.hit_points > defender_unit.hit_points;
    attacker_unit.hit_points -|= attacker_damage;
    defender_unit.hit_points -|= defender_damage;

    if (attacker_unit.hit_points == 0 and defender_unit.hit_points == 0) {
        if (attacker_higher_hp)
            attacker_unit.hit_points = 1
        else
            defender_unit.hit_points = 1;
    }

    if (attacker_unit.hit_points == 0) {
        self.units.removeReference(attacker);
    } else if (defender_unit.hit_points == 0) {
        self.units.removeReference(defender);
        var ref = defender;
        while (self.units.nextReference(ref)) |next_ref| {
            ref = next_ref;
            const unit = self.units.derefToPtr(ref) orelse unreachable;
            switch (ref.slot) {
                .civilian_land,
                .civilian_sea,
                => unit.faction_id = attacker_unit.faction_id,
                .embarked => self.units.removeReference(ref),
                .trade => {},
                .military_land,
                .military_sea,
                => unreachable,
            }
        }
        _ = try self.move(attacker, to);
    }

    return true;
}

pub fn unitFOV(self: *const Self, unit: *const Unit, src: Idx) HexSet {
    const vision_range = Rules.Promotion.Effect.promotionsSum(.modify_sight_range, unit.promotions, self.rules);
    return self.fov(@intCast(vision_range + 2), src);
}

/// Gets FOV from a tile as HexSet, caller must DEINIT! TODO double check behaviour with civ proper. Diagonals might be impact
/// fov too much and axials might have too small an impact. works great as vision range 2, ok at 3, poor at 4+,
/// TODO check if land is obscuring for embarked/naval units...
pub fn fov(self: *const Self, vision_range: u8, src: Idx) HexSet {
    const elevated = self.terrain[src].attributes(self.rules).is_elevated;

    var spiral_iter =
        Grid.SpiralIterator.newFrom(src, 2, vision_range, self.grid);
    var fov_set = HexSet.init(self.allocator);
    fov_set.add(src);
    fov_set.addAdjacent(&self.grid);

    while (spiral_iter.next(self.grid)) |idx| {
        var max_off_axial: u8 = 0;
        var visable = false;

        for (self.grid.neighbours(idx)) |maybe_n_idx| {
            const n_idx = maybe_n_idx orelse continue;
            if (self.grid.distance(n_idx, src) >= self.grid.distance(idx, src)) continue;

            const off_axial = self.grid.distanceOffAxial(n_idx, src);
            if (off_axial < max_off_axial) continue;

            if (off_axial > max_off_axial) visable = false; // previous should be ignored (equals -> both are viable)
            max_off_axial = off_axial;

            if (!fov_set.contains(n_idx)) continue;
            if (self.terrain[n_idx].attributes(self.rules).is_obscuring and !elevated) continue;
            if (self.terrain[n_idx].attributes(self.rules).is_impassable) continue; // impassible ~= mountain
            visable = true;
        }
        if (visable) fov_set.add(idx);
    }
    return fov_set;
}

pub fn fullUpdateViews(self: *Self) void {
    var iter //
        = self.units.iterator();

    for (self.players, 0..) |_, i| {
        self.players[i].view.unsetAllVisable(self);
    }

    while (iter.next()) |item| {
        var vision = self.unitFOV(&item.unit, item.idx);
        defer vision.deinit();
        const player_id = item.unit.faction_id;

        self.players[player_id].view.addVisionSet(vision);
    }

    for (self.cities.values()) |city| {
        var vision = HexSet.init(self.allocator);
        defer vision.deinit();
        vision.add(city.position);
        vision.addOther(&city.claimed);
        vision.addOther(&city.adjacent);

        const player_id = city.faction_id;
        self.players[player_id].view.addVisionSet(vision);
    }
}

pub fn saveToFile(self: *Self, path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    var writer = file.writer();

    for (0..self.grid.len) |i| {
        const terrain_bytes: [@sizeOf(Terrain)]u8 = std.mem.asBytes(&self.terrain[i]).*;
        _ = try file.write(&terrain_bytes);
    }

    _ = try writer.writeInt(u32, @intCast(self.resources.count()), .little); // write len
    for (self.resources.keys()) |key| {
        const value = self.resources.get(key) orelse unreachable;
        _ = try writer.writeInt(Idx, key, .little);
        _ = try writer.writeStruct(value);
    }

    _ = try writer.writeInt(u32, @intCast(self.rivers.count()), .little);
    for (self.rivers.keys()) |edge| {
        try writer.writeStruct(edge);
    }

    file.close();
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
        const len = reader.readInt(u32, .little) catch {
            std.debug.print("\nEarly return in loadFromFile\n", .{});
            break :blk;
        };
        for (0..len) |_| {
            const k = try reader.readInt(Idx, .little);

            const v = try reader.readStruct(ResourceAndAmount);
            try self.resources.put(self.allocator, @intCast(k), v);
        }
    }

    blk: {
        const len = reader.readInt(u32, .little) catch {
            std.debug.print("\nEarly return in loadFromFile\n", .{});
            break :blk;
        };
        for (0..len) |_| {
            const edge = try reader.readStruct(Grid.Edge);
            try self.rivers.put(self.allocator, edge, {});
        }
    }

    file.close();
}
