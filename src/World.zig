const Self = @This();
const std = @import("std");

const rules = @import("rules");

pub const HexIdx = usize;

pub fn idxX(self: Self, idx: HexIdx) usize {
    return idx % self.width;
}
pub fn idxY(self: Self, idx: HexIdx) usize {
    return idx / self.width;
}

width: usize, // <= 128
height: usize, // <= 80
wrap_around: bool = false,

tiles: []Tile,

allocator: std.mem.Allocator,
// the global shit
resources: std.AutoArrayHashMapUnmanaged(HexIdx, Resource),
wonders: std.AutoArrayHashMapUnmanaged(HexIdx, NaturalWonder),
work_in_progress: std.AutoArrayHashMapUnmanaged(HexIdx, WorkInProgress),
rivers: std.AutoArrayHashMapUnmanaged(Edge, void),

pub fn coordToIdx(self: Self, x: usize, y: usize) HexIdx {
    return y * self.width + x;
}

/// like coordToIdx but takes signed shit and also allows wraparound
pub fn signedCoordToIdx(self: Self, x: isize, y: isize) ?HexIdx {
    const uy: usize = @intCast(@mod(y, @as(isize, @intCast(self.height))));
    const ux: usize = @intCast(@mod(x, @as(isize, @intCast(self.width))));

    // y-wrap around, idk if this is ever needed
    if (y >= self.height or y < 0) return null;

    // x-wrap around, we like doing this
    if ((x >= self.height or x < 0) and !self.wrap_around) return null;

    return uy * self.width + ux;
}

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, wrap_around: bool) !Self {
    return Self{
        .width = width,
        .height = height,
        .resources = .{},
        .rivers = .{},
        .wonders = .{},
        .work_in_progress = .{},
        .wrap_around = wrap_around,
        .tiles = try allocator.alloc(Tile, width * height),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.resources.deinit(self.allocator);
    self.allocator.free(self.tiles);
    self.rivers.deinit(self.allocator);
    self.wonders.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
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

const NE = 0;
const E = 1;
const SE = 2;
const SW = 3;
const W = 4;
const NW = 5;
/// Returns an array of HexIdx:s adjacent to the current tile, will be null if no tile exists in that direction.
/// Index is the direction: 0=NE, 1=E, 2=SE, 3=SW, 4=W, 5=NW
pub fn neighbours(self: Self, src: HexIdx) [6]?HexIdx {
    const x: isize = @intCast(self.idxX(src));
    const y: isize = @intCast(self.idxY(src));

    var ns: [6]?HexIdx = [_]?HexIdx{null} ** 6;

    // we assume wrap around, then yeet them if not
    ns[E] = self.signedCoordToIdx(x + 1, y);
    ns[W] = self.signedCoordToIdx(x - 1, y);

    if (@mod(y, 2) == 0) {
        ns[NE] = self.signedCoordToIdx(x, y - 1);
        ns[SE] = self.signedCoordToIdx(x, y + 1);

        ns[NW] = self.signedCoordToIdx(x - 1, y - 1);
        ns[SW] = self.signedCoordToIdx(x - 1, y + 1);
    } else {
        ns[NW] = self.signedCoordToIdx(x, y - 1);
        ns[SW] = self.signedCoordToIdx(x, y + 1);

        ns[NE] = self.signedCoordToIdx(x + 1, y - 1);
        ns[SE] = self.signedCoordToIdx(x + 1, y + 1);
    }

    return ns;
}

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
    type: rules.ResourceType,
    amount: u8,
};

pub const Tile = packed struct {
    terrain: rules.Terrain,

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

test "neighbour test" {
    var world = try Self.init(std.testing.allocator, 128, 80, true);

    defer world.deinit();
    //try std.testing.expect(false);
    try std.testing.expectEqual(
        world.coordToIdx(1, 0),
        world.neighbours(world.coordToIdx(0, 0))[E].?,
    ); // EAST
    try std.testing.expectEqual(
        world.coordToIdx(127, 0),
        world.neighbours(world.coordToIdx(0, 0))[W].?,
    ); // WEST wrap
    try std.testing.expect(
        null == world.neighbours(world.coordToIdx(0, 0))[NE],
    ); // NE (is null)
    try std.testing.expectEqual(
        world.coordToIdx(0, 1),
        world.neighbours(world.coordToIdx(0, 0))[SE].?,
    ); // SE
    try std.testing.expectEqual(
        world.coordToIdx(127, 1),
        world.neighbours(world.coordToIdx(0, 0))[3].?,
    ); // SW wrap
}
