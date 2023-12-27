const Self = @This();
const std = @import("std");

pub const HexIdx = usize;

width: usize, // <= 128
height: usize, // <= 80
wrap_around: bool = false,

tiles: []Tile,

// the global shit
resources: std.AutoArrayHashMap(HexIdx, Resource),
wonders: std.AutoArrayHashMap(HexIdx, NaturalWonder),
work_in_progress: std.AutoArrayHashMap(HexIdx, WorkInProgress),
rivers: std.AutoArrayHashMap(Edge, void),

pub fn coordToIdx(self: Self, x: usize, y: usize) HexIdx {
    return y * self.width + x;
}
//   ----HOW TO COORDS----
//   |0,0|1,0|2,0|3,0|4,0|
//    \ / \ / \ / \ / \ / \
//     |0,1|1,1|2,1|3,1|4,1|
//    / \ / \ / \ / \ / \ /
//   |0,2|1,2|2,2|3,2|4,2|

/// The lowest index is always in low :))
pub const Edge = struct {
    low: HexIdx,
    high: HexIdx,
};

pub const WorkInProgress = struct {
    work_type: union(enum) {
        build_improvement: Improvement,
        remove_vegetation_build_improvement: Improvement,
        build_transport: Transport,
        remove_fallout,
        repair,
        remove_vegetation,
    },

    progress: u8,
};

pub const NaturalWonder = enum {
    cerro_de_potosi,
    el_dorado,
    fountain_of_youth,
    king_solomons_mines,
    krakatoa,
    lake_victoria,
    mt_fuji,
    mt_kailash,
    mt_kilimanjaro,
    mt_sinai,
    old_faithful,
    rock_of_gibraltar,
    sri_pada,
    the_barringer_crater,
    the_grand_mesa,
    the_great_barrier_reef,
    uluru,
    belize_barrier_reef,
    chimborazo,
    lake_titicaca,
    mt_tlaloc,
    tsoodzil,
    cappadocia,
    mount_ararat,
    mount_olympus,
    mt_everest, // cut from the real civ. Cool idea: 3 tile faith wonder, give mountain-climbing promotion
};

pub const Resource = struct {
    type: enum(u3) {
        // generic
        bananas,
        bison,
        cattle,
        deer,
        fish,
        sheep,
        stone,
        wheat,
        // stratigic
        aluminum,
        coal,
        horses,
        iron,
        oil,
        uranium,
        // luxaries
        citrus,
        cocoa,
        copper,
        cotton,
        crab,
        dyes,
        furs,
        gems,
        gold,
        incense,
        ivory,
        marble,
        pearls,
        salt,
        silk,
        silver,
        spices,
        sugar,
        truffles,
        whales,
        wine,
        // city-state luxaries
        jewelry,
        porcelain,
        // special luxaries
        nutmeg,
        pepper,
        cloves,
    },
    amount: u8,
};

pub const Tile = packed struct {
    terrain: Terrain,

    freshwater: bool,
    river_access: bool,

    improvement: Improvement,
    transport: Transport,
    pillaged_improvements: bool,
    pillaged_transport: bool,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 2);
    }
};
pub const Terrain = enum(u5) {
    ocean = 0,
    coast = 1,
    lake = 2,
    desert = 3,
    plains = 4,
    grassland = 5,
    tundra = 6,
    snow = 7,
    mountain = 8,
    desert_hill = 9,
    plains_hill = 10,
    grassland_hill = 11,
    tundra_hill = 12,
    snow_hill = 13,
    desert_oasis = 14,
    ocean_ice = 15,
    coast_ice = 16,
    lake_ice = 17,
    ocean_atoll = 18,
    plains_forest = 19,
    grassland_forest = 20,
    tundra_forest = 21,
    plains_hill_forest = 22,
    grassland_hill_forest = 23,
    tundra_hill_forest = 24,
    plains_jungle = 23,
    plains_hill_jungle = 24,
    grassland_marsh = 25,
};
const Improvement = enum(u5) {
    none,
    farm,
    mine,
    pasture,
};

const Transport = enum(u2) {
    none,
    road,
    rail,
};
