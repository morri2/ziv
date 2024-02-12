const std = @import("std");

const Grid = @import("Grid.zig");
const Idx = Grid.Idx;

pub fn HexSet(comptime bits: u16) type {
    return struct {
        const Self = @This();

        pub const Integer = std.meta.Int(.unsigned, bits);
        pub const Map = std.AutoArrayHashMap(Idx, Integer);

        hexes: Map,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .hexes = Map.init(allocator) };
        }

        pub fn initFloodFill(idx: Idx, steps: u32, grid: *const Grid, allocator: std.mem.Allocator) !Self {
            var self = Self.init(allocator);
            errdefer self.deinit();
            try self.floodFillFrom(idx, steps, grid);
            return self;
        }

        pub fn initAdjacent(other: *const Self, grid: *const Grid) !Self {
            var self = try other.clone();
            errdefer self.deinit();
            try self.addAdjacent(grid);
            self.subtractOther(other);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.hexes.deinit();
        }

        pub fn clone(other: *const Self) !Self {
            return .{
                .hexes = try other.hexes.clone(),
            };
        }

        pub fn clear(self: *Self) void {
            self.hexes.clearRetainingCapacity();
        }

        pub fn contains(self: *const Self, idx: Idx) bool {
            return self.hexes.contains(idx);
        }

        pub fn count(self: *const Self) usize {
            return self.hexes.count();
        }

        pub fn indices(self: *const Self) []Idx {
            return self.hexes.keys();
        }

        pub fn values(self: *const Self) []Integer {
            return self.hexes.values();
        }

        pub fn set(self: *Self, idx: Idx, val: Integer) !void {
            try self.hexes.put(idx, val);
        }

        pub fn add(self: *Self, idx: Idx) !void {
            comptime std.debug.assert(bits == 0);
            try self.set(idx, 0);
        }

        pub fn remove(self: *Self, idx: Idx) void {
            _ = self.hexes.swapRemove(idx);
        }

        pub fn inc(self: *Self, idx: Idx) !void {
            comptime std.debug.assert(bits != 0);
            const gop = try self.hexes.getOrPut(idx);
            if (gop.found_existing) {
                gop.value_ptr.* += 1;
            } else {
                gop.value_ptr.* = 0;
            }
        }

        pub fn dec(self: *Self, idx: Idx) void {
            comptime std.debug.assert(bits != 0);
            var c = self.hexes.getPtr(idx) orelse return;
            if (c == 0) self.remove(idx) else c -= 1;
        }

        pub fn sub(self: *Self, idx: Idx, value: Integer) void {
            comptime std.debug.assert(bits != 0);
            var c = self.hexes.getPtr(idx) orelse return;
            if (c < value) self.remove(idx) else c -= value;
        }

        pub fn checkDec(self: *Self, idx: Idx) bool {
            if (!self.hexes.contains(idx)) return false;

            self.dec(self, idx);
            return true;
        }

        pub fn checkRemove(self: *Self, idx: Idx) bool {
            return self.hexes.swapRemove(idx);
        }

        pub fn addSlice(self: *Self, idxs: []Idx) !void {
            for (idxs) |idx| try self.add(idx);
        }

        pub fn setSlice(self: *Self, idxs: []Idx, val: Integer) !void {
            for (idxs) |idx| try self.set(idx, val);
        }

        pub fn removeSlice(self: *Self, idxs: []Idx) void {
            for (idxs) |idx| self.remove(idx);
        }

        pub fn incSlice(self: *Self, idxs: []Idx) !void {
            for (idxs) |idx| try self.inc(idx);
        }

        pub fn decSlice(self: *Self, idxs: []Idx) void {
            for (idxs) |idx| self.dec(idx);
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

        pub fn incOtherUncounted(self: *Self, other: *const HexSet) void {
            for (other.indices()) |idx| self.inc(idx);
        }

        pub fn decOtherUncounted(self: *Self, other: *const HexSet) void {
            for (other.indices()) |idx| self.dec(idx);
        }

        /// returns false if at least one is already empty ...
        pub fn decOtherUncountedChecked(self: *Self, other: *const HexSet) bool {
            for (other.indices()) |idx| if (!self.checkDec(idx)) return false;
            return true;
        }

        pub fn addOther(self: *Self, other: *const Self) !void {
            try self.addSlice(other.hexes.keys());
        }

        pub fn sumOther(self: *Self, other: *const Self) !void {
            for (other.indices(), other.values()) |idx, v1| {
                if (self.hexes.get(idx)) |v2| try self.set(idx, v1 + v2 + 1);
            }
        }

        pub fn subtractOther(self: *Self, other: *const Self) void {
            for (other.indices(), other.values()) |idx, v1| {
                if (bits != 0) self.sub(idx, v1 + 1) else self.remove(idx);
            }
        }

        pub fn floodFillFrom(self: *Self, idx: Idx, steps: u32, grid: *const Grid) !void {
            try self.add(idx);
            var current_set_index: usize = self.count() - 1;
            for (0..steps) |_| {
                const next_set_index = self.count();
                try self.addAdjacentInner(current_set_index, grid);
                current_set_index = next_set_index;
            }
        }

        pub fn addAdjacent(self: *Self, grid: *const Grid) !void {
            if (self.count() == 0) return;
            try self.addAdjacentInner(0, grid);
        }

        pub fn addAdjacentFromOther(self: *Self, other: *const Self, grid: *const Grid) !void {
            for (other.indices()) |idx| {
                const neighbours = grid.neighbours(idx);
                for (neighbours) |maybe_neighbour_idx| {
                    if (maybe_neighbour_idx) |neighbour_index| try self.add(neighbour_index);
                }
            }
        }

        fn addAdjacentInner(self: *Self, start: usize, grid: *const Grid) !void {
            const end = self.count();
            for (start..end) |i| {
                const current_idx = self.indices()[i];
                const neighbours = grid.neighbours(current_idx);
                for (neighbours) |maybe_neighbour_idx| {
                    if (maybe_neighbour_idx) |neighbour_index| try self.add(neighbour_index);
                }
            }
        }
    };
}
