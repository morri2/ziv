const std = @import("std");
const World = @import("World.zig");
const Idx = @import("Grid.zig").Idx;
const HexSet = @import("HexSet.zig");
const Unit = @import("Unit.zig");
const Player = @import("Player.zig");

const Rules = @import("Rules.zig");
const Yield = Rules.Yield;

const Self = @This();

pub const YieldAccumulator = struct {
    production: u32 = 0,
    food: u32 = 0,
    gold: u32 = 0,
    culture: u32 = 0,
    faith: u32 = 0,
    science: u32 = 0,

    pub fn add(self: *@This(), yield: Yield) void {
        self.production += @intCast(yield.production);
        self.food += @intCast(yield.food);
        self.gold += @intCast(yield.gold);
        self.culture += @intCast(yield.culture);
        self.faith += @intCast(yield.faith);
        self.science += @intCast(yield.science);
    }
};

//buildings: // bitfield for all buildings in the game?

faction_id: Player.FactionID,

name: []const u8 = "shithole",
city_id: usize,
position: Idx = 0,
claimed: HexSet,
worked: HexSet,
max_expansion: HexSet, // all hexes in the
max_workable: HexSet,
adjacent: HexSet,

population: u8 = 1,

// these sould all be floats :'(
food_stockpile: f32 = 0.0,
unspent_production: f32 = 0.0, // producrtion
unused_city_culture: f32 = 0.0,

retained_food_fraction: f32 = 0.0, // from aquaduct etc

food_mult: f32 = 1.0,
production_mult: f32 = 1.0,
culture_mult: f32 = 1.0,
gold_mult: f32 = 1.0,
science_mult: f32 = 1.0,
faith_mult: f32 = 1.0,

culture_til_expansion: f32 = 10, // random placeholder value

current_production_project: ?WorkInProgressProductionProject = null,
halted_production_projects: []WorkInProgressProductionProject = &.{},

allocator: std.mem.Allocator,

pub fn new(position: Idx, player_id: Player.FactionID, world: *const World) Self {
    var claimed = HexSet.init(world.allocator);
    claimed.add(position);
    claimed.addAdjacent(&world.grid);

    var max_workable = HexSet.init(world.allocator);
    max_workable.add(position);
    for (0..3) |_| max_workable.addAdjacent(&world.grid);

    var max_expansion = HexSet.init(world.allocator);
    max_expansion.add(position);
    for (0..5) |_|
        max_expansion.addAdjacent(&world.grid);

    const adjacent = claimed.initExternalAdjacent(&world.grid);

    claimed.remove(position);

    const out: Self = .{
        .faction_id = player_id,
        .city_id = (world.turn_counter << 16) & (position & 0xffff), // id will be unique, use for loging etc
        .name = "Goteborg",
        .position = position,
        .max_expansion = max_expansion,
        .max_workable = max_workable,
        .worked = HexSet.init(world.allocator),
        .claimed = claimed,
        .population = 1,
        .adjacent = adjacent,
        .allocator = world.allocator,
    };

    return out;
}

pub fn deinit(self: *Self) void {
    //self.allocator.free(self.name);
    self.worked.deinit();
    self.claimed.deinit();
    self.max_expansion.deinit();
    self.max_workable.deinit();
    self.adjacent.deinit();
}

pub fn setWorked(self: *Self, idx: Idx) bool {
    if (self.unassignedPopulation() < 1) return false;
    if (self.worked.contains(idx)) return false;
    self.worked.add(idx);
    return true;
}

pub fn setWorkedWithAutoReassign(self: *Self, idx: Idx, world: *const World) bool {
    if (self.unassignedPopulation() < 1) {
        const worst_idx = self.worstWorkedTile(world) orelse return false;
        if (!self.unsetWorked(worst_idx)) unreachable;
    }
    return self.setWorked(idx);
}

pub fn unsetWorked(self: *Self, idx: Idx) bool {
    return self.worked.checkRemove(idx);
}

pub fn getWorkedTileYields(self: *const Self, world: *const World) YieldAccumulator {
    var ya: YieldAccumulator = .{};
    for (self.worked.slice()) |worked_idx| {
        ya.add(world.tileYield(worked_idx));
    }
    ya.add(world.tileYield(self.position));
    ya.production += self.unassignedPopulation() * 1; // 2 prod in Tak?
    return ya;
}

pub fn processYields(self: *Self, tile_yields: *const YieldAccumulator) YieldAccumulator {
    // yields from tiles
    var food: f32 = @as(f32, @floatFromInt(tile_yields.food));
    var production: f32 = @as(f32, @floatFromInt(tile_yields.production));
    var culture: f32 = @as(f32, @floatFromInt(tile_yields.culture));
    var gold: f32 = @as(f32, @floatFromInt(tile_yields.gold));
    var science: f32 = @as(f32, @floatFromInt(tile_yields.science));
    var faith: f32 = @as(f32, @floatFromInt(tile_yields.faith));

    // modifiers from buildings :))
    // TODO!

    // multiplier
    food *= self.food_mult;
    production *= self.production_mult;
    culture *= self.culture_mult;
    gold *= self.gold_mult;
    science *= self.science_mult;
    faith *= self.faith_mult;

    // Continual production - should this be modified by production or gold modifier?
    if (self.current_production_project != null) {
        switch (self.current_production_project.?.project) {
            .Perpetual => |perp_proj| switch (perp_proj) {
                .money_making => gold += production / 2.0,
                .research => science += production / 2.0,
            },
            else => {},
        }
    }
    // food consumption
    food -= self.foodConsumption();
    // Building Maintnence
    //TODO

    // apply to stuff
    self.food_stockpile += food;

    if (self.current_production_project != null) {
        self.current_production_project.?.progress += production;
        // spend unspent production
        self.current_production_project.?.progress += self.unspent_production;
        self.unspent_production = 0.0;
    } else {
        // would be nice to allow some part of production to be held over if no project is set.
        self.unspent_production += production * 0.5; // idk how real civ does it
    }

    self.unused_city_culture += culture;

    // Global yields (real global ones)
    return YieldAccumulator{
        // production and food are discarded
        .science = @intFromFloat(science),
        .culture = @intFromFloat(culture),
        .gold = @intFromFloat(gold),
        .faith = @intFromFloat(faith),
    };
}

pub fn expansionHeuristic(self: *const Self, idx: Idx, world: *const World) u32 {
    const resource_value: u32 = blk: {
        const res = world.resources.get(idx) orelse {
            // for (world.grid.neighbours(idx)) |n_idx| {
            //     if (world.resources.contains(n_idx orelse continue) and
            //         !self.claimed.contains(n_idx orelse continue))
            //         break :blk 1;
            // }
            break :blk 0;
        };

        switch (res.type.kind(world.rules)) {
            .luxury => break :blk 4,
            .strategic => break :blk 3,
            .bonus => break :blk 2,
        }
    };
    //const workable_mod: u32 = @intFromBool(self.max_workable.contains(idx));

    const dist: u32 = @intCast(world.grid.distance(idx, self.position));
    return 30 + 10 * resource_value - dist * dist;
}

fn bestExpansionTile(self: *const Self, world: *const World) ?Idx {
    var best: u32 = 0;
    var best_idx: ?Idx = null;
    for (self.adjacent.slice()) |idx| {
        if (!self.canClaimTile(idx, world)) continue;
        const val = self.expansionHeuristic(idx, world);
        if (val >= best) {
            best = val;
            best_idx = idx;
        }
    }
    return best_idx;
}

///
pub fn expandBorder(self: *Self, world: *const World) bool {
    const idx = self.bestExpansionTile(world) orelse return false;
    return claimTile(self, idx, world);
}

/// Can claim tile
pub fn canClaimTile(self: *const Self, idx: Idx, world: *const World) bool {
    if (world.claimed(idx)) return false;
    if (!self.adjacent.contains(idx)) return false;
    if (!self.max_expansion.contains(idx)) return false;
    return true;
}

/// Claim tile
pub fn claimTile(self: *Self, idx: Idx, world: *const World) bool {
    if (!self.canClaimTile(idx, world)) return false;

    self.claimed.add(idx);
    self.adjacent.deinit();
    self.adjacent = self.claimed.initExternalAdjacent(&world.grid);
    return true;
}

/// checks and updates the city if it is growing or starving
pub fn checkGrowth(self: *Self, world: *const World) GrowthResult {
    // new pop
    if (self.food_stockpile >= self.foodTilGrowth()) {
        self.food_stockpile -= self.food_stockpile * (1.0 - self.retained_food_fraction);
        self.populationGrowth(1, world);
        return .growth;
    }
    // dead pop
    if (self.food_stockpile < 0) {
        self.food_stockpile = 0;
        self.populationStavation(1, world);
        return .starvation;
    }
    // starvation is also a thing
    return .no_change;
}

pub fn foodConsumption(self: *const Self) f32 {
    // consumption - CAN BE MODIFIED (rationalism etc) TODO! fix
    return @as(f32, @floatFromInt(self.population)) * 2.0;
}
/// equals number of labourers :)
pub fn unassignedPopulation(self: *const Self) u8 {
    return self.population -| @as(u8, @intCast(self.worked.count())); // should not underflow, but seems to when pop starves, TODO: investigate
}

pub fn populationGrowth(self: *Self, amt: u8, world: *const World) void {
    self.population += amt;
    for (0..amt) |_| {
        const best_idx = self.bestUnworkedTile(world) orelse continue;
        self.worked.add(best_idx);
    }
}

pub fn foodTilGrowth(self: *const Self) f32 {
    const pop: f32 = @floatFromInt(self.population - 1);
    return 15 + 8 * pop + std.math.pow(f32, pop, 1.5);
}

pub fn populationStavation(self: *Self, amt: u8, world: *const World) void {
    self.population -|= amt;
    for (0..amt) |_| {
        const worst_idx = self.worstWorkedTile(world) orelse continue;
        self.worked.remove(worst_idx);
    }
}
pub fn workHeuristic(self: *const Self, idx: Idx, world: *const World) u32 {
    const y = world.tileYield(idx);
    var value: u32 = 0;
    value += y.production * 10;
    value += y.food * 9;
    if (self.foodConsumption() + 2 > @as(f32, @floatFromInt(self.getWorkedTileYields(world).food)))
        value += @as(u32, y.food) * 13; // if starving more food
    if (self.population < 3)
        value += y.food * 3; // if small, more food
    value += (y.faith + y.gold + y.science + y.culture) * 4;
    return value;
}

pub fn bestUnworkedTile(self: *Self, world: *const World) ?Idx {
    var best: u32 = 0;
    var best_idx: ?Idx = null;
    for (self.claimed.slice()) |idx| {
        if (self.worked.contains(idx)) continue;
        const val = self.workHeuristic(idx, world);
        if (val >= best) {
            best = val;
            best_idx = idx;
        }
    }
    return best_idx;
}

pub fn worstWorkedTile(self: *Self, world: *const World) ?Idx {
    var worst: u32 = std.math.maxInt(u32);
    var worst_idx: ?Idx = null;
    for (self.claimed.slice()) |idx| {
        if (!self.worked.contains(idx)) continue;
        const val = self.workHeuristic(idx, world);
        if (val < worst) {
            worst = val;
            worst_idx = idx;
        }
    }
    return worst_idx;
}

/// check if production project is done
pub fn checkProduction(self: *Self, world: *World) !ProductionResult {
    if (self.current_production_project == null) return .none_selected;
    const work = self.current_production_project.?;
    if (work.project == .Perpetual) return .perpetual;

    if (work.progress >= work.production_needed) {
        // If its a new unit, can we place it?
        switch (work.project) {
            .UnitType => |ty| try self.createUnit(world, ty),
            .Building => unreachable,
            .Perpetual => unreachable,
        }

        // save overproduction :)
        self.unspent_production = self.current_production_project.?.progress - self.current_production_project.?.production_needed;
        const completed_project = self.current_production_project.?.project;
        self.current_production_project = null;

        return .{ .done = completed_project };
    }
    return .not_done;
}

pub fn createUnit(self: *Self, world: *World, unit_type: Rules.UnitType) !void {
    const new_unit = Unit.new(unit_type, self.faction_id, world.rules);
    try world.units.putOrStackAutoSlot(self.position, new_unit);
    std.debug.print("UNIT CREATED \n", .{});
    world.units.refresh();
}

/// check if border expansion
pub fn checkExpansion(self: *Self) bool {
    // borders grow
    if (self.unused_city_culture >= self.culture_til_expansion) {
        self.unused_city_culture -= self.culture_til_expansion;
        self.culture_til_expansion *= 1.5;
        return true;
    }

    return false;
}

// TODO
// Add build queue with saved progress

pub const ProductionTarget = union(enum) {
    Building: Rules.Building,
    UnitType: Rules.UnitType,
    Perpetual: union(enum) {
        money_making,
        research,
    },
};

// TODO
// Add pass through from player/civ to check resources
pub fn startConstruction(self: *Self, construction_target: ProductionTarget, rules: *const Rules) bool {
    if (self.current_production_project) |project| {
        if (@intFromEnum(project.project) == @intFromEnum(construction_target)) return true;
    }
    var production_needed: u16 = 0;
    if (construction_target == .UnitType) {
        const stats = construction_target.UnitType.stats(rules);
        // Check Resource requirement
        //for (stats.resource_cost) |resource| {
        //
        //}
        production_needed = stats.production;
    } else if (construction_target == .Building) {}

    // Add or overwrite current project
    self.current_production_project = WorkInProgressProductionProject{
        .progress = self.unspent_production,
        .production_needed = @floatFromInt(production_needed),
        .project = construction_target,
    };
    return false;
}

/// Result of checking if a city is growing
const GrowthResult = enum {
    no_change,
    growth,
    starvation,
};

const ProductionResult = union(enum) {
    done: ProductionTarget,
    not_done: void,
    perpetual: void,
    none_selected: void,
    // add stuff for perpetual, requierments no longer fullfilled etc.
};

const WorkInProgressProductionProject = struct {
    progress: f32,
    production_needed: f32,
    project: ProductionTarget,
};
