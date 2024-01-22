const Self = @This();
const std = @import("std");

const Rules = @import("Rules.zig");
const Yield = Rules.Yield;
const Terrain = Rules.Terrain;
const Resource = Rules.Resource;
const Building = Rules.Building;
const Transport = Rules.Transport;
const Improvements = Rules.Improvements;
const City = @import("City.zig");

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const Idx = Grid.Idx;
const HexDir = Grid.Dir;

const Unit = @import("Unit.zig");

/// The lowest index is always in low :))
pub const WorkInProgress = struct {
    work_type: union(enum) {
        building: Building,
        remove_vegetation_building: Building,
        transport: Transport,
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

rules: *const Rules,

grid: Grid,

// Per tile data
terrain: []Terrain,
improvements: []Improvements,

// Tile lookup data
resources: std.AutoArrayHashMapUnmanaged(Idx, ResourceAndAmount),
work_in_progress: std.AutoArrayHashMapUnmanaged(Idx, WorkInProgress),

// Tile edge data
rivers: std.AutoArrayHashMapUnmanaged(Edge, void),

cities: std.AutoArrayHashMapUnmanaged(Idx, City),

units: std.AutoArrayHashMapUnmanaged(UnitKey, Unit),

pub const UnitKey = struct {
    idx: Idx,
    slot: UnitSlot,
    stack_depth: u8 = 0,

    pub fn nextInStack(self: UnitKey) UnitKey {
        return .{ .slot = self.slot, .stack_depth = self.stack_depth + 1, .idx = self.idx };
    }

    /// Start iter
    pub fn firstOccupied(idx: Idx, world: *const Self) ?UnitKey {
        var first = .{ .idx = idx, .slot = UnitSlot.first() };
        while (world.getUnitPtr(first) == null)
            first = .{ .slot = first.slot.next() orelse return null, .idx = first.idx };
        return first;
    }

    /// Iterate though occupied for a tile
    pub fn nextOccupied(self: UnitKey, world: *const Self) ?UnitKey {
        var next = self.nextInStack();
        while (world.getUnitPtr(next) == null)
            next = .{ .slot = next.slot.next() orelse return null, .idx = self.idx };
        return next;
    }

    /// First free key in a slot
    pub fn firstFree(idx: Idx, slot: UnitSlot, world: *const Self) ?UnitKey {
        var key: UnitKey = .{ .idx = idx, .slot = slot, .stack_depth = 0 };
        while (world.getUnitPtr(key) != null) key = key.nextInStack();
        return key;
    }
};

pub const UnitSlot = enum {
    civilian,
    military,
    naval,
    embarked,
    trade,
    pub fn first() UnitSlot {
        return @enumFromInt(0);
    }
    pub fn next(self: UnitSlot) ?UnitSlot {
        const next_int = @intFromEnum(self) + 1;
        if (next_int >= @typeInfo(UnitSlot).Enum.fields.len) return null;
        return @enumFromInt(next_int);
    }
};

/// All unit entries
pub fn allUnitsEntries(self: Self, idx: Idx, world: Self) []Unit {
    _ = self; // autofix
    _ = idx; // autofix
    _ = world; // autofix

    //TODO
}

/// First unit in a slot
pub fn getFirstSlotUnitPtr(self: *const Self, idx: Idx, slot: UnitSlot) ?*Unit {
    return self.getUnitPtr(.{ .idx = idx, .slot = slot });
}

/// First unit on tile
pub fn getFirstUnitPtr(self: *const Self, idx: Idx) ?*Unit {
    return self.getUnitPtr(UnitKey.firstOccupied(idx, self) orelse return null);
}

pub fn getUnitPtr(self: *const Self, ukey: UnitKey) ?*Unit {
    return self.units.getPtr(ukey);
}

pub fn putUnitDefaultSlot(self: *Self, idx: Idx, unit: Unit) void {
    self.putUnit(.{ .idx = idx, .slot = unit.defaultSlot() }, unit);
}

pub fn putUnit(self: *Self, ukey: UnitKey, unit: Unit) void {
    var prev_kv = self.units.fetchPut(self.allocator, ukey, unit) catch unreachable;

    if (prev_kv != null) {
        if (!std.meta.eql(prev_kv.?.key, ukey)) unreachable;
        prev_kv.?.key.stack_depth = ukey.stack_depth + 1;
        self.putUnit(prev_kv.?.key, prev_kv.?.value);
    }
}

pub fn fetchRemoveUnit(self: *Self, ukey: UnitKey) ?Unit {
    const unit = self.units.fetchSwapRemove(ukey) orelse return null;
    self.cascadeUnitStack(ukey);
    return unit.value;
}

fn cascadeUnitStack(self: *Self, dest_ukey: UnitKey) void {
    const src_ukey = dest_ukey.nextInStack();
    const kv = self.units.fetchSwapRemove(src_ukey) orelse return;
    self.units.put(self.allocator, dest_ukey, kv.value) catch unreachable;
    self.cascadeUnitStack(src_ukey);
}

pub const UnitContainer = struct { unit: Unit, stacked_key: ?usize };

pub fn addCity(self: *Self, idx: Idx, allocator: std.mem.Allocator) bool {
    self.cities[idx] = City.init(allocator);
}

pub fn refreshUnits(self: *Self) void {
    var unit_iter = self.units.iterator();
    while (unit_iter.next()) |e| {
        e.value_ptr.refresh();
    }
}

pub fn tileYield(self: *Self, idx: Idx) Yield {
    const terrain = self.terrain[idx];
    const resource = self.resources.get(idx);

    var y = terrain.yield(self.rules);

    if (resource != null) {
        y = y.add(resource.?.type.yield(self.rules));
    }
    return y;
}

pub fn init(
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    wrap_around: bool,
    rules: *const Rules,
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
        .units = .{},
        .cities = .{},
        .rules = rules,
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);
    self.units.deinit(self.allocator);

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
