const std = @import("std");
const Self = @This();
const World = @import("World.zig");
const Grid = @import("Grid.zig");
const Idx = Grid.Idx;
const Edge = Grid.Edge;

const Rules = @import("Rules.zig");
const Yield = Rules.Yield;
const Terrain = Rules.Terrain;
const Improvements = Rules.Improvements;
const Resource = Rules.Resource;

const hex_set = @import("hex_set.zig");

const InViewHexSet = hex_set.HexSet(8);
const ExploredHexSet = hex_set.HexSet(0);

in_view: InViewHexSet, // tracks number of units which can see,
explored: ExploredHexSet,

last_seen_yields: []Yield,
last_seen_terrain: []Terrain,
last_seen_improvements: []Improvements,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, grid: *const Grid) !Self {
    const last_seen_yields = try allocator.alloc(Yield, grid.len);
    errdefer allocator.free(last_seen_yields);

    const last_seen_terrain = try allocator.alloc(Terrain, grid.len);
    errdefer allocator.free(last_seen_terrain);

    const last_seen_improvements = try allocator.alloc(Improvements, grid.len);
    errdefer allocator.free(last_seen_improvements);

    return .{
        .in_view = InViewHexSet.init(allocator),
        .explored = ExploredHexSet.init(allocator),
        .last_seen_yields = last_seen_yields,
        .last_seen_terrain = last_seen_terrain,
        .last_seen_improvements = last_seen_improvements,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.last_seen_improvements);
    self.allocator.free(self.last_seen_terrain);
    self.allocator.free(self.last_seen_yields);

    self.in_view.deinit();
    self.explored.deinit();
}

pub fn addVision(self: *Self, idx: Idx) !void {
    try self.in_view.inc(idx);
    try self.explored.add(idx);
}

pub fn removeVision(self: *Self, idx: Idx, world: *const World, rules: *const Rules) !void {
    self.update(idx, world, rules);
    try self.in_view.dec(idx);
}

pub fn addVisionSet(self: *Self, vision: hex_set.HexSet(0)) !void {
    for (vision.indices()) |idx| try self.addVision(idx);
}

pub fn removeVisionSet(self: *Self, vision: hex_set.HexSet(0), world: *const World) void {
    for (vision.indices()) |idx| self.removeVision(idx, world);
}

pub fn viewYield(self: *const Self, idx: Idx, world: *const World, rules: *const Rules) ?Yield {
    if (!self.explored.contains(idx)) return null;
    if (!self.in_view.contains(idx)) return self.last_seen_yields[idx];
    return world.tileYield(idx, rules);
}

pub fn viewTerrain(self: *const Self, idx: Idx, world: *const World) ?Terrain {
    if (!self.explored.contains(idx)) return null;
    if (!self.in_view.contains(idx)) return self.last_seen_terrain[idx];
    return world.terrain[idx];
}

pub fn viewImprovements(self: *const Self, idx: Idx, world: *const World) ?Improvements {
    if (!self.explored.contains(idx)) return null;
    if (!self.in_view.contains(idx)) return self.last_seen_improvements[idx];
    return world.improvements[idx];
}

pub fn viewRiver(self: *const Self, edge: Edge, world: *const World) bool {
    blk: {
        if (self.explored.contains(edge.low)) break :blk;
        if (self.explored.contains(edge.high)) break :blk;

        return false;
    }

    return world.rivers.contains(edge);
}

pub fn update(self: *Self, idx: Idx, world: *const World, rules: *const Rules) void {
    self.last_seen_terrain[idx] = world.terrain[idx];
    self.last_seen_improvements[idx] = world.improvements[idx];
    self.last_seen_yields[idx] = world.tileYield(idx, rules);
}

pub fn unsetAllVisible(self: *Self, world: *const World, rules: *const Rules) void {
    for (0..world.grid.len) |idx| {
        if (!self.in_view.contains(@intCast(idx))) continue;
        self.update(@intCast(idx), world, rules);
        self.in_view.remove(@intCast(idx));
    }
}

pub fn visibility(self: *const Self, idx: Idx) enum { visible, hidden, fov } {
    if (!self.explored.contains(idx)) return .hidden;
    if (!self.in_view.contains(idx)) return .fov;
    return .visible;
}

pub fn newResource(self: *Self, resource: Resource, world: *const World) void {
    for (world.resources.values(), world.resources.keys()) |r, idx| {
        if (r.type == resource) {
            const old_yield = self.last_seen_yields[idx];
            const new_yield = old_yield.add(r.type.yield(world.rules));
            self.last_seen_yields[idx] = new_yield;
        }
    }
}
