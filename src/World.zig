const Self = @This();
const std = @import("std");

const rules = @import("rules");
const Terrain = rules.Terrain;
const Improvements = rules.Improvements;

const Transport = rules.Transport;
const Resource = rules.Resource;

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const Idx = Grid.Idx;
const HexDir = Grid.Dir;

const Unit = @import("Unit.zig");

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

pub const ResourceAndAmount = packed struct {
    type: Resource,
    amount: u8,
};

allocator: std.mem.Allocator,

grid: Grid,

// Per tile data
terrain: []Terrain,
improvements: []Improvements,

// Tile lookup data
resources: std.AutoArrayHashMapUnmanaged(Idx, ResourceAndAmount),
work_in_progress: std.AutoArrayHashMapUnmanaged(Idx, WorkInProgress),

// Tile edge data
rivers: std.AutoArrayHashMapUnmanaged(Edge, void),

unit_idx: usize = 0,
unit_map: []?UnitContainer,
unit_stack: std.AutoArrayHashMapUnmanaged(usize, UnitContainer),

pub const UnitContainer = struct { unit: Unit, stacked_key: ?usize };

pub fn topUnitContainerPtr(self: *Self, idx: Idx) ?*UnitContainer {
    return &(self.unit_map[idx] orelse return null);
}

pub fn nextUnitContainerPtr(self: *Self, unit_container: *UnitContainer) ?*UnitContainer {
    const next_uc = self.unit_stack.getPtr(unit_container.stacked_key orelse return null);

    return next_uc;
}

pub fn secoundToLastUnitContainer(self: *Self, idx: Idx) ?*UnitContainer {
    var secound_to_last_uc: ?*UnitContainer = null;
    var last_uc = topUnitContainerPtr(self, idx) orelse return null;
    while (last_uc.stacked_key != null) {
        secound_to_last_uc = last_uc;
        last_uc = nextUnitContainerPtr(self, last_uc);
    }
    return secound_to_last_uc;
}

pub fn insertUnitAfter(self: *Self, pred: *UnitContainer, unit: Unit) void {
    const next_key = pred.stacked_key;
    self.unit_stack.put(
        self.allocator,
        self.unit_idx,
        .{ .unit = unit, .stacked_key = next_key },
    ) catch unreachable; // should probably check for clobber :)
    pred.stacked_key = self.unit_idx;
    self.unit_idx +%= 1;
}

pub fn removeUnitAfter(self: *Self, prev: *UnitContainer) ?Unit {
    const next_key = prev.stacked_key orelse return null;
    const entry = self.unit_stack.fetchSwapRemove(next_key) orelse unreachable;
    prev.stacked_key = entry.value.stacked_key;
    return entry.value.unit;
}

pub fn getNthStackedPtr(self: *Self, idx: Idx, n: usize) ?*UnitContainer {
    var last_uc = topUnitContainerPtr(self, idx) orelse return null;
    for (0..n) |_| last_uc = nextUnitContainerPtr(self, last_uc) orelse return null;
    return last_uc;
}

pub fn removeNthStackedUnit(self: *Self, idx: Idx, n: usize) ?Unit {
    var last_uc = topUnitContainerPtr(self, idx) orelse return null;
    if (n == 0) {
        const uc = last_uc.*;
        self.unit_map[idx] = null;
        return uc.unit;
    }
    for (0..(n - 1)) |_| {
        last_uc = self.nextUnitContainerPtr(last_uc) orelse return null;
    }
    return self.removeUnitAfter(last_uc);
}

// Need to give a unit layer (eg civilian, military etc)

pub fn lastUnitContainer(self: *Self, idx: Idx) ?*UnitContainer {
    var last_uc = topUnitContainerPtr(self, idx) orelse return null;
    while (last_uc.stacked_key != null) last_uc = nextUnitContainerPtr(self, last_uc) orelse unreachable;
    return last_uc;
}

pub fn pushUnit(self: *Self, idx: Idx, unit: Unit) void {
    const last = self.lastUnitContainer(idx) orelse {
        self.unit_map[idx] = .{ .unit = unit, .stacked_key = null };
        return;
    };
    std.debug.print("last: {}\n", .{last.unit.type});
    self.insertUnitAfter(last, unit);
    std.debug.print("last: {?}\n", .{last.stacked_key});
}

pub fn popFirstUnit(self: *Self, idx: Idx) ?Unit {
    const uc = self.unit_map[idx] orelse return null;
    const next_uc = self.removeUnitAfter(uc);
    self.unit_map[idx] = next_uc;
    return uc.unit;
}

pub fn refreshUnits(self: *Self) void {
    for (0..self.grid.len) |i| {
        var uc: ?*UnitContainer = &(self.unit_map[i] orelse continue);
        while (uc != null) {
            uc.?.unit.refresh();
            uc = self.nextUnitContainerPtr(uc.?);
        }
    }
}

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

    const unit_map = try allocator.alloc(?UnitContainer, grid.len);
    errdefer allocator.free(unit_map);
    @memset(unit_map, null);

    return Self{
        .allocator = allocator,
        .grid = grid,
        .terrain = terrain,
        .improvements = improvements,
        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},
        .unit_map = unit_map,
        .unit_stack = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);
    self.allocator.free(self.improvements);
    self.allocator.free(self.terrain);
}

pub fn saveToFile(self: *Self, path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    var writer = file.writer();

    for (0..self.grid.len) |i| {
        const terrain_bytes: [@sizeOf(Terrain)]u8 = std.mem.asBytes(&self.terrain[i]).*;
        _ = try file.write(&terrain_bytes);
    }

    _ = try writer.writeInt(usize, self.resources.count(), .little); // write len
    for (self.resources.keys()) |key| {
        const value = self.resources.get(key) orelse unreachable;
        _ = try writer.writeInt(usize, key, .little);
        _ = try writer.writeStruct(value);
    }

    file.close();
}

pub fn loadFromFile(self: *Self, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    var reader = file.reader();
    for (0..self.grid.len) |i| {
        const terrain_bytes = try reader.readBytesNoEof(@sizeOf(Terrain));

        const terrain: *const Terrain = @ptrCast(&terrain_bytes);
        self.terrain[i] = terrain.*;
    }
    blk: {
        const len = reader.readInt(usize, .little) catch {
            std.debug.print("\nEarly return in loadFromFile\n", .{});
            break :blk;
        };
        for (0..len) |_| {
            const k = try reader.readInt(usize, .little);

            const v = try reader.readStruct(ResourceAndAmount);
            try self.resources.put(self.allocator, k, v);
        }
    }

    file.close();
}
