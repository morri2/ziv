const Self = @This();
const std = @import("std");
const World = @import("World.zig");
const hex = @import("hex.zig");
const Idx = @import("Grid.zig").Idx;
const yield = @import("yield.zig");
const YieldAccumumlator = yield.YieldAccumulator;
const HexSet = @import("HexSet.zig");

//buildings: // bitfield for all buildings in the game?

name: []const u8 = "shithole",

position: Idx = 0,
claimed: HexSet,
worked: HexSet,
max_expansion: HexSet, // all hexes in the
max_workable: HexSet,

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

food_til_growth: f32 = 10, // random placeholder value
culture_til_expansion: f32 = 10, // random placeholder value

current_production_project: ?WorkInProgressProductionProject = null,
halted_production_projects: []WorkInProgressProductionProject = &.{},

allocator: std.mem.Allocator,

pub fn new(position: Idx, world: *const World) Self {
    var claimed = HexSet.init(world.allocator);
    claimed.add(position);
    claimed.addAllAdjacent(&world.grid);
    claimed.remove(position);

    var max_workable = HexSet.init(world.allocator);
    max_workable.add(position);
    for (0..3) |_| max_workable.addAllAdjacent(&world.grid);

    var max_expansion = HexSet.init(world.allocator);
    max_expansion.add(position);
    for (0..5) |_| max_expansion.addAllAdjacent(&world.grid);

    const out: Self = .{
        .name = "Goteborg",
        .position = position,
        .max_expansion = max_expansion,
        .max_workable = max_workable,
        .worked = HexSet.init(world.allocator),
        .claimed = claimed,
        .population = 1,
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

pub fn getWorkedTileYields(self: *const Self, world: *const World) YieldAccumumlator {
    var ya: YieldAccumumlator = .{};
    for (self.worked.slice()) |worked_idx| {
        ya.add(world.tileYield(worked_idx));
    }
    ya.add(world.tileYield(self.position));
    ya.production += self.unassignedPopulation() * 1; // 2 prod in Tak?
    return ya;
}

pub fn processYields(self: *Self, tile_yields: *const YieldAccumumlator) YieldAccumumlator {
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
        switch (self.current_production_project.?.project.result) {
            .perpetual => |perp_proj| switch (perp_proj) {
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

    // PRINT THE STATUS OF A CITY
    if (true) {
        std.debug.print(
            \\
            \\# {s} (pop. {}) 
            \\  Production: {d:.0}/{d:.0}
            \\  Growth: {d:.0}/{d:.0}
            \\  Culture: {d:.0}/{d:.0}
            \\  Other: +{d:.0} gold, +{d:.0} sci, +{d:.0} faith, 
            \\
        , .{
            self.name,
            self.population,
            if (self.current_production_project != null) self.current_production_project.?.progress else self.unspent_production,
            if (self.current_production_project != null) self.current_production_project.?.project.production_needed else 0.0,
            self.food_stockpile,
            self.food_til_growth,
            self.unused_city_culture,
            self.culture_til_expansion,
            gold,
            science,
            faith,
        });
    }

    // Global yields (real global ones)
    return YieldAccumumlator{
        // production and food are discarded
        .science = @intFromFloat(science),
        .culture = @intFromFloat(culture),
        .gold = @intFromFloat(gold),
        .faith = @intFromFloat(faith),
    };
}

/// checks and updates the city if it is growing or starving
pub fn checkGrowth(self: *Self, world: *const World) GrowthResult {
    // new pop
    if (self.food_stockpile >= self.foodTilGrowth()) {
        self.populationGrowth(1, world);
        return .growth;
    }
    // dead pop
    if (self.food_stockpile < 0) {
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
    return self.population - @as(u8, @intCast(self.worked.count()));
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
pub fn tileValueHeuristic(self: *const Self, idx: Idx, world: *const World) u32 {
    const y = world.tileYield(idx);
    var value: u32 = 0;
    value += y.production * 10;
    value += y.food * 9;
    if (self.foodConsumption() + 2 > @as(f32, @floatFromInt(self.getWorkedTileYields(world).food)))
        value += y.food * 13; // if starving more food
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
        const val = self.tileValueHeuristic(idx, world);
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
        const val = self.tileValueHeuristic(idx, world);
        if (val < worst) {
            worst = val;
            worst_idx = idx;
        }
    }
    return worst_idx;
}

/// check if production project is done
pub fn checkProduction(self: *Self) ProductionResult {
    if (self.current_production_project == null) return .none_selected;
    if (self.current_production_project.?.project.result == .perpetual) return .perpetual;

    if (self.current_production_project.?.progress >= self.current_production_project.?.project.production_needed) {
        self.unspent_production = self.current_production_project.?.progress - self.current_production_project.?.project.production_needed; // save overproduction :)
        const compleated_project = self.current_production_project.?.project;
        self.current_production_project = null;

        return .{ .done = compleated_project };
    }
    return .not_done;
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

/// Result of checking if a city is growing
const GrowthResult = enum {
    no_change,
    growth,
    starvation,
};

const ProductionResult = union(enum) {
    done: ProductionProject,
    not_done: void,
    perpetual: void,
    none_selected: void,
    // add stuff for perpetual, requierments no longer fullfilled etc.
};

const WorkInProgressProductionProject = struct {
    progress: f32,
    project: ProductionProject,
};

const ProductionProject = struct {
    production_needed: f32,
    result: union(enum) {
        unit: u32, // placeholder type
        building: u32, // placeholder type
        perpetual: union(enum) {
            money_making,
            research,
        },
    },
};
