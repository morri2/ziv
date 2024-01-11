const Self = @This();
const std = @import("std");

const rules = @import("rules");
const Tile = rules.Tile;
const Improvement = rules.Improvement;
const Transport = rules.Transport;
const Resource = rules.Resource;

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const HexIdx = Grid.Idx;
const HexDir = Grid.Dir;

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

allocator: std.mem.Allocator,

grid: Grid,

// Per tile data
tiles: []Tile,

// Tile lookup data
resources: std.AutoArrayHashMapUnmanaged(HexIdx, ResourceAndAmount),
work_in_progress: std.AutoArrayHashMapUnmanaged(HexIdx, WorkInProgress),

// Tile edge data
rivers: std.AutoArrayHashMapUnmanaged(Edge, void),

pub fn init(
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    wrap_around: bool,
) !Self {
    const grid = Grid.init(width, height, wrap_around);

    const tiles = try allocator.alloc(Tile, grid.len);
    errdefer allocator.free(tiles);
    @memset(tiles, std.mem.zeroes(Tile));

    return Self{
        .allocator = allocator,

        .grid = grid,

        .tiles = tiles,

        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);
    self.allocator.free(self.tiles);
}
