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

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const Idx = Grid.Idx;
const Dir = Grid.Dir;

const Units = @import("Units.zig");

const Unit = @import("Unit.zig");

const hex_set = @import("hex_set.zig");

const View = @import("View.zig");

pub const FactionID = enum(u8) {
    civilization_0 = 0,
    city_state_0 = 32,
    barbarian = 255,
    _,

    pub fn toCivilizationID(self: FactionID) ?CivilizationID {
        if (@intFromEnum(self) >= @intFromEnum(FactionID.city_state_0)) return null;
        return @enumFromInt(@intFromEnum(self));
    }
};

pub const CivilizationID = enum(u5) {
    _,

    pub fn toFactionID(self: CivilizationID) FactionID {
        return @enumFromInt(@intFromEnum(self));
    }
};

pub const WorkInProgress = struct {
    work_type: TileWork,
    progress: u8,
};

pub const TileWork = union(TileWorkType) {
    building: Building,
    remove_vegetation_building: Building,
    transport: Transport,
    remove_fallout,
    repair,
    remove_vegetation,

    pub const TileWorkType = enum(u8) {
        building = 0,
        remove_vegetation_building = 1,
        transport = 2,
        remove_fallout = 3,
        repair = 4,
        remove_vegetation = 5,
    };
};

pub const ResourceAndAmount = packed struct {
    type: Resource,
    amount: u8 = 1,
};

pub const Step = struct {
    idx: Idx,
    cost: f32,
};

allocator: std.mem.Allocator,

grid: Grid,

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
) !Self {
    const grid = Grid.init(width, height, wrap_around);

    const terrain = try allocator.alloc(Terrain, grid.len);
    errdefer allocator.free(terrain);
    @memset(terrain, std.mem.zeroes(Terrain));

    const improvements = try allocator.alloc(Improvements, grid.len);
    errdefer allocator.free(improvements);
    @memset(improvements, std.mem.zeroes(Improvements));

    return Self{
        .allocator = allocator,
        .grid = grid,
        .terrain = terrain,
        .improvements = improvements,
        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},
        .turn = 1,
        .cities = .{},
        .units = Units.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);

    self.units.deinit(self.allocator);

    self.allocator.free(self.improvements);
    self.allocator.free(self.terrain);

    for (self.cities.values()) |*city| city.deinit();
    self.cities.deinit(self.allocator);
}

pub fn nextTurn(self: *Self, rules: *const Rules) !struct {
    view_change: bool,
} {
    var view_change = false;
    for (self.cities.keys(), self.cities.values()) |idx, *city| {
        const ya = city.getWorkedTileYields(self, rules);

        _ = city.processYields(&ya);
        const growth_res = try city.checkGrowth(self, rules);
        _ = growth_res;

        view_change = view_change or city.checkExpansion();
        const production_result = try city.checkProduction();
        switch (production_result) {
            .done => |project| switch (project) {
                .unit => |unit_type| {
                    if (!try self.addUnit(idx, unit_type, city.faction_id, rules)) unreachable;
                    view_change = true;
                },
                else => unreachable, // TODO
            },
            else => {},
        }
    }

    self.units.refresh(rules);

    self.turn += 1;

    return .{
        .view_change = view_change,
    };
}

pub fn canAddCity(self: *const Self, idx: Idx, faction: FactionID, rules: *const Rules) bool {
    if (self.claimedFaction(idx)) |claimed_by| {
        if (claimed_by != faction) return false;
    }
    for (self.cities.keys()) |city_idx| if (self.grid.distance(idx, city_idx) < 3) return false;
    if (self.terrain[idx].attributes(rules).is_impassable) return false;
    if (self.terrain[idx].attributes(rules).is_wonder) return false;
    if (self.terrain[idx].attributes(rules).is_water) return false;
    return true;
}

pub fn addCity(self: *Self, idx: Idx, faction_id: FactionID, rules: *const Rules) !bool {
    if (!self.canAddCity(idx, faction_id, rules)) return false;
    const city = try City.new(idx, faction_id, self);
    try self.cities.put(self.allocator, idx, city);
    return true;
}

pub fn addUnit(self: *Self, idx: Idx, unit_temp: Rules.UnitType, faction: FactionID, rules: *const Rules) !bool {
    const unit = Unit.new(unit_temp, faction, rules);
    return try self.units.putOrStackAutoSlot(idx, unit, rules);
}

pub fn claimed(self: *const Self, idx: Idx) bool {
    for (self.cities.values()) |city| if (city.claimed.contains(idx) or city.position == idx) return true;
    return false;
}

pub fn claimedFaction(self: *const Self, idx: Idx) ?FactionID {
    for (self.cities.values()) |city|
        if (city.claimed.contains(idx) or city.position == idx) return city.faction_id;
    return null;
}

pub fn canSettleCity(self: *const Self, reference: Units.Reference, rules: *const Rules) bool {
    const unit = self.units.deref(reference) orelse return false;
    if (!Rules.Promotion.Effect.in(.settle_city, unit.promotions, rules)) return false;
    if (unit.movement <= 0) return false;
    if (!self.canAddCity(reference.idx, unit.faction_id, rules)) return false;
    return true;
}

pub fn settleCity(self: *Self, reference: Units.Reference, rules: *const Rules) !bool {
    if (!self.canSettleCity(reference, rules)) return false;
    const unit = self.units.deref(reference) orelse unreachable;

    if (!try self.addCity(reference.idx, unit.faction_id, rules)) unreachable;
    self.units.removeReference(reference);

    return true;
}

pub fn recalculateWaterAccess(self: *Self, rules: *const Rules) !void {
    var new_terrain = try self.allocator.alloc(Rules.Terrain.Unpacked, self.grid.len);
    defer self.allocator.free(new_terrain);

    for (0..self.grid.len) |idx| {
        const terrain = self.terrain[idx];
        new_terrain[idx] = .{
            .base = terrain.base(rules),
            .feature = terrain.feature(rules),
            .vegetation = terrain.vegetation(rules),
            .has_freshwater = false,
            .has_river = false,
        };
    }

    for (0..self.grid.len) |idx_us| {
        const idx: u32 = @intCast(idx_us);

        const terrain = self.terrain[idx];
        if (terrain.attributes(rules).is_freshwater) {
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
        if (self.terrain[idx].attributes(rules).is_water) {
            new_terrain[idx].has_freshwater = false;
        }
    }

    for (0..self.grid.len) |idx|
        self.terrain[idx] = new_terrain[idx].pack(rules) orelse std.debug.panic("Failed to pack tile", .{});
}

pub fn tileYield(self: *const Self, idx: Idx, rules: *const Rules) Yield {
    const terrain = self.terrain[idx];
    const maybe_resource: ?Rules.Resource = if (self.resources.get(idx)) |r| r.type else null;

    var yield = terrain.yield(rules);

    if (maybe_resource) |resource| yield = yield.add(resource.yield(rules));

    const imp_y = self.improvements[idx].building.yield(maybe_resource, rules);
    yield = yield.add(imp_y);

    // City yields
    if (self.cities.contains(idx)) {
        yield.production = @max(yield.production, 1);
        yield.food = @max(yield.food, 2);
    }

    return yield;
}

pub fn workAllowedOn(self: *const Self, idx: Idx, work: TileWork, rules: *const Rules) bool {
    if (self.cities.contains(idx)) return false;
    if (self.terrain[idx].attributes(rules).is_wonder) return false;
    if (self.terrain[idx].attributes(rules).is_impassable) return false;

    switch (work) {
        .building => |b| {
            const a = Rules.Building.allowedOn(b, self.terrain[idx], rules);
            switch (a) {
                .allowed_if_resource => {
                    return b.connectsResource((self.resources.get(idx) orelse return false).type, rules);
                },
                .allowed => return true,
                else => return false,
            }
        },
        .remove_vegetation_building => |b| {
            if (!self.workAllowedOn(idx, .remove_vegetation, rules)) return false;
            switch (Rules.Building.allowedOn(b, self.terrain[idx], rules)) {
                .allowed_after_clear_if_resource => {
                    return b.connectsResource((self.resources.get(idx) orelse return false).type, rules);
                },
                .allowed_after_clear => return true,
                else => return false,
            }
        },
        .transport => |_| {
            return !self.terrain[idx].attributes(rules).is_water;
        },
        .remove_vegetation => {
            if (self.terrain[idx].vegetation(rules) == .none) return false;
            return true;
        },

        else => return false,
    }
}

pub fn canDoImprovementWork(self: *const Self, unit_ref: Units.Reference, work: TileWork, rules: *const Rules) bool {
    if (!self.workAllowedOn(unit_ref.idx, work, rules)) return false;

    const unit = self.units.deref(unit_ref) orelse return false;
    if (unit.movement <= 0) return false;

    switch (work) {
        .building,
        .remove_vegetation_building,
        .remove_vegetation,
        => if (!Rules.Promotion.Effect.in(.build_improvement, unit.promotions, rules)) return false,
        .transport => |t| {
            if (t == .road and !Rules.Promotion.Effect.in(.build_roads, unit.promotions, rules)) return false;
            if (t == .rail and !Rules.Promotion.Effect.in(.build_rail, unit.promotions, rules)) return false;
        },
        else => return false, // TODO
    }
    return true;
}

pub fn doImprovementWork(self: *Self, unit_ref: Units.Reference, work: TileWork, rules: *const Rules) bool {
    if (!self.canDoImprovementWork(unit_ref, work, rules)) return false;
    const unit = self.units.derefToPtr(unit_ref) orelse return false;
    progress_blk: {
        if (self.work_in_progress.getPtr(unit_ref.idx)) |wip| {
            if (@intFromEnum(wip.work_type) == @intFromEnum(work)) {
                if (switch (wip.work_type) {
                    .building => |b| b == work.building,
                    .transport => |t| t == work.transport,
                    .remove_vegetation_building => |b| b == work.remove_vegetation_building,
                    else => true,
                }) {
                    wip.progress += 1;
                    break :progress_blk;
                }
            }
        }

        self.work_in_progress.put(self.allocator, unit_ref.idx, .{ .work_type = work, .progress = 1 }) catch undefined;
    }
    if (self.work_in_progress.get(unit_ref.idx)) |wip| {
        if (wip.progress >= 3) // TODO progress needed should be dependent on project
        {
            _ = self.work_in_progress.swapRemove(unit_ref.idx);
            switch (wip.work_type) {
                .building => |b| self.improvements[unit_ref.idx].building = b,
                .remove_vegetation => self.terrain[unit_ref.idx] = self.terrain[unit_ref.idx].withoutVegetation(rules),
                .remove_vegetation_building => |b| {
                    self.terrain[unit_ref.idx] = self.terrain[unit_ref.idx].withoutVegetation(rules);
                    self.work_in_progress.put(self.allocator, unit_ref.idx, .{ .work_type = .{ .building = b }, .progress = 0 }) catch unreachable;
                },
                .transport => |t| self.improvements[unit_ref.idx].transport = t,
                else => {
                    std.debug.print("UNIMPLEMENTED!\n", .{});
                },
            }
        }
    } else unreachable;
    unit.movement = 0;
    // YEET EM BOATS
    if (Rules.Promotion.Effect.charge_to_improve.in(unit.promotions, rules)) {
        if (unit.useCharge(rules)) self.units.removeReference(unit_ref);
    }

    return true;
}

pub fn stepCost(
    self: *const Self,
    reference: Units.Reference,
    to: Idx,
    rules: *const Rules,
) Unit.StepCost {
    if (!self.grid.isNeighbour(reference.idx, to)) return .disallowed;

    if (self.units.get(to, reference.slot) != null) return .disallowed;

    const unit = self.units.deref(reference) orelse return .disallowed;

    return self.stepCostFrom(
        reference.idx,
        to,
        unit,
        reference.slot,
        rules,
        null,
    );
}

pub fn stepCostFrom(
    self: *const Self,
    from: Idx,
    to: Idx,
    unit: Unit,
    slot: Units.Slot,
    rules: *const Rules,
    maybe_view: ?*const View,
) Unit.StepCost {
    // Check if tile is already occupied
    {
        var maybe_ref = self.units.firstReference(to);
        const initial: ?Units.Slot = if (maybe_ref) |ref| ref.slot else null;
        loop: while (maybe_ref) |ref| {
            const to_unit = self.units.deref(ref) orelse unreachable;
            switch (ref.slot) {
                .trade => if (slot == .trade) return .disallowed,
                else => if (to_unit.faction_id != unit.faction_id) return .disallowed,
            }
            maybe_ref = self.units.nextReference(ref);
            if (initial.? == maybe_ref.?.slot) break :loop;
        }
    }

    const terrain, const improvements, const river_crossing = if (maybe_view) |view| .{
        view.viewTerrain(to, self),
        view.viewImprovements(to, self) orelse Improvements{},
        if (self.grid.edgeBetween(from, to)) |edge| view.viewRiver(edge, self) else false,
    } else .{
        self.terrain[to],
        self.improvements[to],
        if (self.grid.edgeBetween(from, to)) |edge| self.rivers.contains(edge) else false,
    };

    return unit.stepCost(.{
        .target_terrain = terrain,
        .river_crossing = river_crossing,
        .transport = if (improvements.pillaged_transport) .none else improvements.transport,
        .embarked = slot == .embarked,
        .city = self.cities.contains(to),
    }, rules);
}

pub fn step(self: *Self, reference: Units.Reference, to: Idx, rules: *const Rules) !bool {
    const cost = self.stepCost(reference, to, rules);

    if (cost == .disallowed) return false;

    var unit = self.units.deref(reference) orelse unreachable;

    self.units.removeReference(reference);

    unit.step(cost);

    switch (cost) {
        .disallowed => unreachable,
        .allowed,
        .allowed_final,
        => if (!try self.units.putNoStack(to, unit, reference.slot)) unreachable,
        .embarkation => if (!try self.units.putNoStack(to, unit, .embarked)) unreachable,
        .disembarkation => if (!try self.units.putNoStackAutoSlot(to, unit, rules)) unreachable,
    }
    return true;
}

pub fn movePath(
    self: *Self,
    reference: Units.Reference,
    to: Idx,
    rules: *const Rules,
    path: *std.ArrayList(Step),
    maybe_view: ?*const View,
) !bool {
    if (reference.idx == to) return true;

    const unit = self.units.deref(reference) orelse return false;
    const max_movement = unit.maxMovement(rules);

    var visited_set = std.AutoHashMap(Idx, f32).init(self.allocator);
    defer visited_set.deinit();
    try visited_set.ensureUnusedCapacity(150);

    var prev = std.AutoHashMap(Idx, struct {
        from: Idx,
        cost: f32,
    }).init(self.allocator);
    defer prev.deinit();
    try prev.ensureUnusedCapacity(150);

    const Node = struct {
        weight: f32,
        idx: Idx,
        slot: Units.Slot,
    };

    var queue = std.PriorityQueue(Node, void, struct {
        fn cmp(context: void, a: Node, b: Node) std.math.Order {
            _ = context;
            return std.math.order(a.weight, b.weight);
        }
    }.cmp).init(self.allocator, {});
    defer queue.deinit();
    try queue.ensureUnusedCapacity(100);

    try queue.add(.{
        .weight = 0.0,
        .idx = reference.idx,
        .slot = reference.slot,
    });

    while (queue.removeOrNull()) |node| {
        if (node.idx == to) break;
        const neighbours = self.grid.neighbours(node.idx);
        for (neighbours) |maybe_neighbour| {
            if (maybe_neighbour) |neighbour| {
                const new_weight, const new_slot = switch (self.stepCostFrom(
                    node.idx,
                    neighbour,
                    unit,
                    node.slot,
                    rules,
                    maybe_view,
                )) {
                    .allowed => |cost| .{
                        node.weight + cost,
                        node.slot,
                    },
                    .allowed_final => .{
                        node.weight + max_movement - @mod(node.weight, max_movement),
                        node.slot,
                    },
                    .embarkation => .{
                        node.weight + max_movement - @mod(node.weight, max_movement),
                        .embarked,
                    },
                    .disembarkation => .{
                        node.weight + max_movement - @mod(node.weight, max_movement),
                        Units.slotFromUnitType(unit.type, rules),
                    },
                    .disallowed => continue,
                };

                const old_weight = visited_set.get(neighbour) orelse std.math.inf(f32);

                if (new_weight < old_weight) {
                    try queue.add(.{
                        .idx = neighbour,
                        .weight = new_weight,
                        .slot = new_slot,
                    });
                    try prev.put(neighbour, .{
                        .from = node.idx,
                        .cost = new_weight - node.weight,
                    });
                    try visited_set.put(neighbour, node.weight);
                }
            }
        }
    }

    // Reconstruct path
    {
        var current = to;
        while (current != reference.idx) {
            const next_step = prev.get(current) orelse return false;
            try path.append(.{
                .idx = current,
                .cost = next_step.cost,
            });
            current = next_step.from;
        }
    }

    std.mem.reverse(Step, path.items);

    return true;
}

pub fn canAttack(self: *const Self, attacker: Units.Reference, to: Idx, rules: *const Rules) !bool {
    if (!self.grid.isNeighbour(attacker.idx, to)) return false;

    const attacker_unit = self.units.deref(attacker) orelse return false;

    const terrain = self.terrain[to];
    const river_crossing = if (self.grid.edgeBetween(attacker.idx, to)) |edge| self.rivers.contains(edge) else false;
    const improvements = self.improvements[to];

    const cost = attacker_unit.stepCost(.{
        .target_terrain = terrain,
        .river_crossing = river_crossing,
        .transport = if (improvements.pillaged_transport) .none else improvements.transport,
        .embarked = attacker.slot == .embarked,
        .city = self.cities.contains(to),
    }, rules);

    if (!cost.allowsAttack()) return false;

    if (Rules.Promotion.Effect.cannot_melee.in(attacker_unit.promotions, rules)) return false;

    const defender = self.units.firstReference(to) orelse return false;
    const defender_unit = self.units.deref(defender) orelse return false;

    if (attacker_unit.faction_id == defender_unit.faction_id) return false;

    return true;
}

pub fn attack(self: *Self, attacker: Units.Reference, to: Idx, rules: *const Rules) !bool {
    if (!try self.canAttack(attacker, to, rules)) return false;

    const attacker_unit = self.units.derefToPtr(attacker) orelse return false;

    const defender = self.units.firstReference(to) orelse return false;
    const defender_unit = self.units.derefToPtr(defender) orelse return false;

    // Check if this is a capture
    if (attacker.slot.isMilitary() and defender.slot.isCivilian()) {
        defender_unit.faction_id = attacker_unit.faction_id;
        _ = try self.step(attacker, to, rules);
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
    }, rules);

    const defender_strength = defender_unit.strength(.{
        .is_attacker = false,
        .target_terrain = terrain,
        .river_crossing = river_crossing,
        .is_ranged = false,
    }, rules);

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
        _ = try self.step(attacker, to, rules);
        attacker_unit.movement = 0.0;
    } else {
        attacker_unit.movement = 0.0;
    }

    return true;
}

pub fn unitFov(self: *const Self, unit: *const Unit, src: Idx, set: *hex_set.HexSet(0), rules: *const Rules) !void {
    const vision_range = Rules.Promotion.Effect.promotionsSum(.modify_sight_range, unit.promotions, rules);
    try self.fov(@intCast(vision_range + 2), src, set, rules);
}

/// TODO double check behaviour with civ proper. Diagonals might be impact
/// fov too much and axials might have too small an impact. works great as vision range 2, ok at 3, poor at 4+,
/// TODO check if land is obscuring for embarked/naval units...
pub fn fov(self: *const Self, vision_range: u8, src: Idx, set: *hex_set.HexSet(0), rules: *const Rules) !void {
    const elevated = self.terrain[src].attributes(rules).is_elevated;

    try set.floodFillFrom(src, 1, &self.grid);

    var spiral_iter = Grid.SpiralIterator.newFrom(src, 2, vision_range, self.grid);
    while (spiral_iter.next(self.grid)) |idx| {
        var max_off_axial: u8 = 0;
        var visible = false;

        for (self.grid.neighbours(idx)) |maybe_n_idx| {
            const n_idx = maybe_n_idx orelse continue;
            if (self.grid.distance(n_idx, src) >= self.grid.distance(idx, src)) continue;

            const off_axial = self.grid.distanceOffAxial(n_idx, src);
            if (off_axial < max_off_axial) continue;

            if (off_axial > max_off_axial) visible = false; // previous should be ignored (equals -> both are viable)
            max_off_axial = off_axial;

            if (!set.contains(n_idx)) continue;
            if (self.terrain[n_idx].attributes(rules).is_obscuring and !elevated) continue;
            if (self.terrain[n_idx].attributes(rules).is_impassable) continue; // impassible ~= mountain
            visible = true;
        }
        if (visible) try set.add(idx);
    }
}

const terrain_serialization = @import("serialization.zig").customSerialization(&.{
    .{ .name = "grid" },
    .{ .name = "terrain" },
    .{ .name = "resources", .ty = .hash_map },
    .{ .name = "rivers", .ty = .hash_set },
}, Self);

pub fn serializeTerrain(self: Self, writer: anytype) !void {
    try terrain_serialization.serialize(writer, self);
}

pub fn deserializeTerrain(reader: anytype, allocator: std.mem.Allocator) !Self {
    var self = try terrain_serialization.deserializeAlloc(reader, allocator);
    errdefer {
        self.resources.deinit(allocator);
        self.rivers.deinit(allocator);
        allocator.free(self.terrain);
    }
    self.allocator = allocator;
    self.improvements = try allocator.alloc(Improvements, self.grid.len);
    errdefer allocator.free(self.improvements);
    @memset(self.improvements, std.mem.zeroes(Improvements));

    self.work_in_progress = .{};
    self.cities = .{};
    self.turn = 1;
    self.units = Units.init(allocator);
    return self;
}
