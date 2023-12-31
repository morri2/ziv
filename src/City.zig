const Self = @This();
const std = @import("std");
const World = @import("World.zig");
const hex = @import("hex.zig");
const HexIdx = hex.HexIdx;
const yield = @import("yield.zig");
const YieldAccumumlator = yield.YieldAccumulator;
//buildings: // bitfield for all buildings in the game?

name: []const u8,

position: HexIdx = 0,
claimed_tiles: []HexIdx = &.{},
worked_tiles: []HexIdx = &.{},
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

pub fn init() Self {
    const name: []const u8 = "Goteborg";
    return Self{ .name = name };
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
    food -= @as(f32, @floatFromInt(self.population)) * 2.0; // consumption - CAN BE MODIFIED (rationalism etc)

    // Building Maintnence

    // apply to stuff
    self.food_stockpile += food;

    if (self.current_production_project != null) {
        self.current_production_project.?.progress += production;
        // spend unspent production
        self.current_production_project.?.progress += self.unspent_production;
        self.unspent_production = 0.0;
    } else {
        // would be nice to allow some part of production to be held over if no project is set.
        self.unspent_production += production * 0.5;
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
pub fn checkGrowth(self: *Self) GrowthResult {
    // new pop
    if (self.food_stockpile >= self.food_til_growth) {
        self.food_stockpile -= self.food_til_growth * (1.0 - self.retained_food_fraction);
        self.food_til_growth *= 1.5; // close but no cigar
        self.population += 1;
        return .growth;
    }
    // dead pop
    if (self.food_stockpile < 0) {
        self.food_til_growth *= @round(self.food_stockpile * 0.666); // :)) shut up ((:
        self.food_stockpile = 0;
        self.population -= 1;
        return .starvation;
    }
    // starvation is also a thing
    return .no_change;
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
