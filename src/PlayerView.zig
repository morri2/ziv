const std = @import("std");
const Self = @This();
const HexSet = @import("HexSet.zig");
const CountedHexSet = @import("CountedHexSet.zig");
const World = @import("World.zig");
const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

const Rules = @import("Rules.zig");
const Yield = Rules.Yield;
const Terrain = Rules.Terrain;
const Improvements = Rules.Improvements;
const Resource = Rules.Resource;

in_view: CountedHexSet, // tracks number of units which can see,
explored: HexSet,

last_seen_yields: []Yield,
last_seen_terrain: []Terrain,
last_seen_improvements: []Improvements,
allocator: std.mem.Allocator,

pub fn addVision(self: *Self, idx: Idx) void {
    self.in_view.inc(idx);
    self.explored.add(idx);
}

pub fn removeVision(self: *Self, idx: Idx, world: *const World) void {
    self.update(idx, world);
    self.in_view.dec(idx);
}

pub fn addVisionSet(self: *Self, vision: HexSet) void {
    for (vision.slice()) |idx| self.addVision(idx);
}

pub fn removeVisionSet(self: *Self, vision: HexSet, world: *const World) void {
    for (vision.slice()) |idx| self.removeVision(idx, world);
}

pub fn viewYield(self: *const Self, idx: Idx, world: *const World) ?Yield {
    if (!self.explored.contains(idx)) return null;
    if (!self.in_view.contains(idx)) return self.last_seen_yields[idx];
    return world.tileYield(idx);
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

pub fn init(allocator: std.mem.Allocator, grid: *const Grid) !Self {
    return .{
        .in_view = CountedHexSet.init(allocator),
        .explored = HexSet.init(allocator),
        .last_seen_yields = try allocator.alloc(Yield, grid.len),
        .last_seen_terrain = try allocator.alloc(Terrain, grid.len),
        .last_seen_improvements = try allocator.alloc(Improvements, grid.len),
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

pub fn update(self: *Self, idx: Idx, world: *const World) void {
    self.last_seen_terrain[idx] = world.terrain[idx];
    self.last_seen_improvements[idx] = world.improvements[idx];
    self.last_seen_yields[idx] = world.tileYield(idx);
}

pub fn unsetAllVisable(self: *Self, world: *const World) void {
    for (0..world.grid.len) |idx| {
        if (!self.in_view.contains(@intCast(idx))) continue;
        self.update(@intCast(idx), world);
        self.in_view.remove(@intCast(idx));
    }
}

pub fn visability(self: *const Self, idx: Idx) enum { visable, hidden, fov } {
    if (!self.explored.contains(idx)) return .hidden;
    if (!self.in_view.contains(idx)) return .fov;
    return .visable;
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
