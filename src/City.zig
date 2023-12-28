const Self = @This();
const std = @import("std");
const World = @import("World.zig");
const HexIdx = World.HexIdx;
const yield = @import("yield.zig");
const YieldAccumumlator = yield.YieldAccumulator;
//buildings: // bitfield for all buildings in the game?

name: [63:0]u8 = "Göteborg",

position: HexIdx,
claimed: []HexIdx,
worked: []HexIdx,
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

food_til_growth: f32 = 10, // random placeholder value
culture_til_expansion: f32 = 10, // random placeholder value

current_production_project: WorkInProgressProductionProject,

halted_production_projects: []WorkInProgressProductionProject,

pub fn processYields(self: Self, tile_yields: *const YieldAccumumlator) void {
    // yields from tiles
    var food: f32 = @as(f32, @floatFromInt(tile_yields.food));

    // ... from buildings (fix in future)

    // mod
    food *= self.food_mult;

    // food consumption
    food -= self.population * 2.0; // consumption - CAN BE MODIFIED (rationalism etc)

    // apply to stuff
    self.food_stockpile += food;
}

/// checks and updates the city if it is growing or starving
pub fn checkGrowth(self: Self) GrowthResult {
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

/// Result of checking if a city is growing
const GrowthResult = enum {
    no_change,
    growth,
    starvation,
};

const WorkInProgressProductionProject = struct {
    progress: u32,
    project: ProductionProject,
};

const ProductionProject = struct {
    production_needed: u32,
    result: union(enum) {
        unit: u32, // placeholder type
        building: u32, // placeholder type
        // continious (gold/research/world fair)
    },
};
