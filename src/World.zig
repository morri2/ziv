const Self = @This();
const std = @import("std");

const rules = @import("rules");
const Terrain = rules.Terrain;
const Improvements = rules.Improvements;

const Transport = rules.Transport;
const Resource = rules.Resource;

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const HexIdx = Grid.Idx;
const HexDir = Grid.Dir;

/// The lowest index is always in low :))
pub const WorkInProgress = struct {
    work_type: union(enum) {
        building: Improvements.Building,
        remove_vegetation_building: Improvements.Building,
        transport: Improvements.Transport,
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
terrain: []Terrain,
improvements: []Improvements,

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

    const terrain = try allocator.alloc(Terrain, grid.len);
    errdefer allocator.free(terrain);
    @memset(terrain, std.mem.zeroes(Terrain));

    const improvements = try allocator.alloc(Improvements, grid.len);
    errdefer allocator.free(terrain);
    @memset(improvements, std.mem.zeroes(Improvements));

    return Self{
        .allocator = allocator,

        .grid = grid,

        .terrain = terrain,
        .improvements = improvements,

        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);
    self.allocator.free(self.improvements);
    self.allocator.free(self.terrain);
}
