const Self = @This();
const std = @import("std");
const HexSet = @import("HexSet.zig");
const Yield = @import("yield.zig").Yield;
const Terrain = @import("Rules.zig").Terrain;
const Improvements = @import("Rules.zig").Improvements;
const Resource = @import("Rules.zig").Resource;
const World = @import("World.zig");
const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

fog_of_war: HexSet,
explored: HexSet,

last_seen_yields: []Yield,
last_seen_terrain: []Terrain,
last_seen_improvements: []Improvements,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, grid: *const Grid) !Self {
    return .{
        .fog_of_war = HexSet.init(allocator),
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

    self.fog_of_war.deinit();
    self.explored.deinit();
}

pub fn update(self: *Self, idx: Idx, world: *const World) void {
    self.last_seen_terrain[idx] = world.terrain[idx];
    self.last_seen_improvements[idx] = world.improvements[idx];
    self.last_seen_yields[idx] = world.tileYield(idx);
}

pub fn discover(self: *Self, idx: Idx, world: *const World) void {
    self.update(idx, world);
    self.explored.add(idx);
    self.fog_of_war.add(idx);
}

pub fn setVisable(self: *Self, idx: Idx, world: *const World) void {
    self.discover(idx, world);
    self.fog_of_war.remove(idx);
}

pub fn unsetVisable(self: *Self, idx: Idx, world: *const World) void {
    self.update(idx, world);
    self.fog_of_war.add(idx);
}

pub fn unsetAllVisable(self: *Self, world: *const World) void {
    for (0..world.grid.len) |i| self.unsetVisable(i, world);
}

pub fn visability(self: *const Self, idx: Idx) enum { visable, hidden, fov } {
    if (!self.explored.contains(idx)) return .hidden;
    if (self.fog_of_war.contains(idx)) return .fov;
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
