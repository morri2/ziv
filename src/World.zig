const Self = @This();
const std = @import("std");
const hex = @import("hex.zig");
const rules = @import("rules");

const Tile = rules.Tile;
const Improvement = rules.Improvement;
const Transport = rules.Transport;
const Resource = rules.Resource;

const Edge = hex.Edge;
const HexIdx = hex.HexIdx;
const HexDir = hex.HexDir;
const HexGrid = hex.HexGrid(Tile);

/// The lowest index is always in low :))
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

pub const ResourceAndAmount = struct {
    type: Resource,
    amount: u8,
};

width: usize, // <= 128
height: usize, // <= 80
wrap_around: bool = false,

allocator: std.mem.Allocator,

// Per tile data
tiles: HexGrid,

// Tile lookup data
resources: std.AutoArrayHashMapUnmanaged(HexIdx, ResourceAndAmount),
work_in_progress: std.AutoArrayHashMapUnmanaged(HexIdx, WorkInProgress),

// Tile edge data
rivers: std.AutoArrayHashMapUnmanaged(Edge, void),

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, wrap_around: bool) !Self {
    return Self{
        .width = width,
        .height = height,
        .wrap_around = wrap_around,

        .allocator = allocator,

        .tiles = try HexGrid.init(width, height, wrap_around, allocator),

        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);
    self.tiles.deinit();
}
test "neighbour test" {
    var world = try Self.init(std.testing.allocator, 128, 80, true);

    defer world.deinit();
    //try std.testing.expect(false);
    try std.testing.expectEqual(
        world.coordToIdx(1, 0),
        world.neighbours(world.coordToIdx(0, 0))[HexDir.E.int()].?,
    ); // EAST
    try std.testing.expectEqual(
        world.coordToIdx(127, 0),
        world.neighbours(world.coordToIdx(0, 0))[HexDir.W.int()].?,
    ); // WEST wrap
    try std.testing.expect(
        null == world.neighbours(world.coordToIdx(0, 0))[HexDir.NE.int()],
    ); // NE (is null)
    try std.testing.expectEqual(
        world.coordToIdx(0, 1),
        world.neighbours(world.coordToIdx(0, 0))[HexDir.SE.int()].?,
    ); // SE
    try std.testing.expectEqual(
        world.coordToIdx(127, 1),
        world.neighbours(world.coordToIdx(0, 0))[HexDir.SW.int()].?,
    ); // SW wrap
}
