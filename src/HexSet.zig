/// A set of hexes
const Self = @This();
const std = @import("std");
const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

hexes: std.AutoArrayHashMapUnmanaged(Idx, void),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator, .hexes = .{} };
}

pub fn deinit(self: *Self) void {
    self.hexes.deinit(self.allocator);
}

/// remember to deinit :))
pub fn clone(self: *const Self) Self {
    var new = Self.init(self.allocator);
    new.addOther(self);
    return new;
}

/// adds idx, returns true if element was added (not already there)
pub fn checkAdd(self: *Self, idx: Idx) bool {
    if (self.contains(idx)) return false;
    self.add(idx);
    return true;
}

pub fn checkRemove(self: *Self, idx: Idx) bool {
    return self.hexes.swapRemove(idx);
}

pub fn add(self: *Self, idx: Idx) void {
    self.hexes.put(self.allocator, idx, {}) catch unreachable;
}

pub fn addSlice(self: *Self, idxs: []Idx) void {
    for (idxs) |idx| self.add(idx);
}

pub fn removeSlice(self: *Self, idxs: []Idx) void {
    for (idxs) |idx| self.remove(idx);
}

pub fn remove(self: *Self, idx: Idx) void {
    _ = self.hexes.swapRemove(idx);
}

pub fn contains(self: *const Self, idx: Idx) bool {
    return self.hexes.contains(idx);
}

pub fn count(self: *const Self) usize {
    return self.hexes.count();
}

pub fn overlapping(self: *const Self, other: *const Self) bool {
    if (self.count() > other.count()) return overlapping(other, self);
    for (self.hexes.keys()) |idx| if (other.contains(idx)) return true;
    return false;
}

pub fn isSubset(self: *const Self, super: *const Self) bool {
    if (self.count() > super.count()) return false;
    for (self.hexes.keys()) |idx| if (!super.contains(idx)) return false;
    return true;
}

/// removes all elements not in super
pub fn shaveToIntersect(self: *Self, super: *const Self) void {
    for (self.hexes.keys()) |idx| if (!super.contains(idx)) self.remove(idx);
}

pub fn addOther(self: *Self, other: *const Self) void {
    self.addSlice(other.hexes.keys());
}

pub fn subtractOther(self: *Self, other: *const Self) void {
    self.removeSlice(other.hexes.keys());
}

pub fn slice(self: *const Self) []Idx {
    return self.hexes.keys();
}

pub fn addAllAdjacent(self: *Self, grid: *const Grid) void {
    for (self.hexes.keys()) |set_idx| {
        for (grid.neighbours(set_idx)) |n_idx| {
            if (n_idx == null) continue;
            self.add(n_idx.?);
        }
    }
}
