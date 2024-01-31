/// A set of hexes with counts associated. increment and decrement, 0 --> remove
const Self = @This();
const std = @import("std");
const Grid = @import("Grid.zig");
const Idx = Grid.Idx;
const HexSet = @import("HexSet.zig");

hexes: std.AutoArrayHashMapUnmanaged(Idx, u8),
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

pub fn set(self: *Self, idx: Idx, val: u8) void {
    if (val == 0) {
        self.remove(idx);
        return;
    }
    self.hexes.put(self.allocator, idx, val) catch unreachable;
}

pub fn setSlice(self: *Self, idxs: []Idx, val: u8) void {
    for (idxs) |idx| self.set(idx, val);
}

pub fn inc(self: *Self, idx: Idx) void {
    const c = self.hexes.get(idx) orelse {
        self.hexes.put(self.allocator, idx, 1) catch unreachable;
        return;
    };
    self.hexes.put(self.allocator, idx, c + 1) catch unreachable;
}

pub fn incSlice(self: *Self, idxs: []Idx, val: u8) void {
    for (idxs) |idx| self.inc(idx, val);
}

pub fn decSlice(self: *Self, idxs: []Idx, val: u8) void {
    for (idxs) |idx| self.dec(idx, val);
}

pub fn checkDec(self: *Self, idx: Idx) bool {
    if (!self.hexes.contains(idx)) return false;

    self.dec(self, idx);
    return true;
}

pub fn dec(self: *Self, idx: Idx) void {
    var c = self.hexes.getPtr(idx) orelse {
        return;
    };
    c -= 1;
    if (c == 0) self.hexes.swapRemove(idx);
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

/// BROKEN removes all elements not in super
pub fn shaveToIntersect(self: *Self, super: *const Self) void {
    var to_remove: std.ArrayListUnmanaged(Idx) = .{};
    defer to_remove.deinit(self.allocator);
    for (self.hexes.keys()) |idx|
        if (!super.contains(idx)) to_remove.append(self.allocator, idx);
    for (to_remove.items) |idx| self.remove(idx);
}

pub fn incOtherUncounted(self: *Self, other: *const HexSet) void {
    for (other.slice()) |idx| self.inc(idx);
}

pub fn decOtherUncounted(self: *Self, other: *const HexSet) void {
    for (other.slice()) |idx| self.dec(idx);
}

/// returns false if at least one is already empty ...
pub fn decOtherUncountedChecked(self: *Self, other: *const HexSet) bool {
    for (other.slice()) |idx| if (!self.checkDec(idx)) return false;
    return true;
}

pub fn sumOther(self: *Self, other: *const Self) void {
    for (other.slice(), other.values()) |idx, v1| {
        const v2 = self.hexes.get(idx) orelse 0;
        self.set(idx, v1 + v2);
    }
}

pub fn subtractOther(self: *Self, other: *const Self) void {
    for (other.slice(), other.values()) |idx, v1| {
        const v2 = self.hexes.get(idx) orelse 0;
        self.set(idx, v1 -| v2);
    }
}

pub fn slice(self: *const Self) []Idx {
    return self.hexes.keys();
}

pub fn values(self: *const Self) []u8 {
    return self.hexes.values();
}

pub fn initExternalAdjacent(self: *const Self, grid: *const Grid) Self {
    var out = Self.init(self.allocator);
    for (self.slice()) |set_idx| {
        for (grid.neighbours(set_idx)) |n_idx| {
            if (n_idx == null) continue;
            if (self.contains(n_idx.?)) continue;
            out.add(n_idx.?);
        }
    }
    return out;
}

pub fn addAdjacent(self: *Self, grid: *const Grid) void {
    var adj = initExternalAdjacent(self, grid);
    defer adj.deinit();
    self.addOther(&adj);
}
