const Self = @This();
const std = @import("std");
const hex = @import("hex.zig");
const rules = @import("rules");
const Unit = @import("Unit.zig");

const Tile = rules.Tile;
const Improvement = rules.Improvement;
const Transport = rules.Transport;
const Resource = rules.Resource;

const Edge = hex.Edge;
const HexIdx = hex.HexIdx;
const HexDir = hex.HexDir;
const TileMap = hex.HexGrid(Tile);

pub const UnitContainer = struct { unit: Unit.BaseUnit, stacked_key: ?usize };

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
tiles: TileMap,

// Tile lookup data
resources: std.AutoArrayHashMapUnmanaged(HexIdx, ResourceAndAmount),
work_in_progress: std.AutoArrayHashMapUnmanaged(HexIdx, WorkInProgress),

// Tile edge data
rivers: std.AutoArrayHashMapUnmanaged(Edge, void),

// Unit map
next_stack_idx: usize = 0,
unit_map: std.AutoArrayHashMapUnmanaged(HexIdx, UnitContainer), // should probably be a HexGrid
unit_stack: std.AutoArrayHashMapUnmanaged(usize, UnitContainer),

pub fn addUnit(self: *Self, idx: HexIdx, unit: Unit.BaseUnit) !void {
    const unit_at = self.unit_map.get(idx);
    if (unit_at != null) {
        try self.unit_stack.put(self.allocator, self.next_stack_idx, unit_at.?);
    }
    const container: UnitContainer = .{ .unit = unit, .stacked_key = if (unit_at != null) self.next_stack_idx else null };
    try self.unit_map.put(self.allocator, idx, container);
    self.next_stack_idx +%= 1;
}

pub fn getUnitPtr(self: *Self, idx: HexIdx) !?*Unit.BaseUnit {
    const unit_at = self.unit_map.getPtr(idx) orelse return null;

    return &unit_at.unit;
}

pub fn getStackedUnitPtr(self: *Self, idx: HexIdx, stack_depth: usize) !?*Unit.BaseUnit {
    var unit = self.unit_map.getPtr(idx) orelse return null;
    for (0..stack_depth) |_| {
        unit = self.unit_stack.getPtr(unit.stacked_key orelse return null) orelse return null;
    }

    return &unit.unit;
}

pub fn popUnit(self: *Self, idx: HexIdx) !?Unit.BaseUnit {
    const unit_at: UnitContainer = self.unit_map.get(idx) orelse return null;
    if (!self.unit_map.swapRemove(idx)) unreachable;
    if (unit_at.stacked_key != null) {
        const stack_unit = self.unit_stack.get(unit_at.stacked_key.?);
        if (stack_unit != null) {
            try self.unit_map.put(self.allocator, idx, stack_unit.?);
        }
    }
    return unit_at.unit;
}

pub fn moveUnit(self: *Self, src: HexIdx, dest: HexIdx) !void {
    const unit = try self.popUnit(src) orelse return;
    try self.addUnit(dest, unit);
}

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, wrap_around: bool) !Self {
    return Self{
        .width = width,
        .height = height,
        .wrap_around = wrap_around,

        .allocator = allocator,

        .tiles = try TileMap.init(width, height, wrap_around, allocator),

        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},

        .unit_map = .{},
        .unit_stack = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);
    self.tiles.deinit();

    self.unit_map.deinit(self.allocator);
    self.unit_stack.deinit(self.allocator);
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
