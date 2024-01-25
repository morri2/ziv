const Self = @This();
const std = @import("std");

const Rules = @import("Rules.zig");
const Yield = @import("yield.zig").Yield;
const Terrain = Rules.Terrain;
const Resource = Rules.Resource;
const Building = Rules.Building;
const Transport = Rules.Transport;
const Improvements = Rules.Improvements;
const City = @import("City.zig");
const UnitMap = @import("UnitMap.zig");

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

unit_map: UnitMap,

pub fn addCity(self: *Self, city: *City, idx: Idx) void {
    const adjacent = self.grid.neighbours(idx);
    city.position = idx;

    for (adjacent) |i| {
        if (i == null) continue;
        _ = city.claimTile(i.?);
    }

    // remove forest
    self.cities.put(self.allocator, idx, city.*) catch unreachable;
}

pub fn tileYield(self: *const Self, idx: Idx) Yield {
    const terrain = self.terrain[idx];
    const resource = self.resources.get(idx);

    var yield = terrain.yield(self.rules);

    if (resource != null) {
        yield = yield.add(resource.?.type.yield(self.rules));
    }

    // city yeilds
    if (self.cities.contains(idx)) {
        yield.production = @max(yield.production, 1);
        yield.food = @max(yield.food, 2);
    }

    return yield;
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

    return Self{
        .allocator = allocator,
        .grid = grid,
        .terrain = terrain,
        .improvements = improvements,
        .resources = .{},
        .work_in_progress = .{},
        .rivers = .{},

        .cities = .{},
        .rules = rules,
        .unit_map = UnitMap.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.rivers.deinit(self.allocator);
    self.work_in_progress.deinit(self.allocator);
    self.resources.deinit(self.allocator);

    self.unit_map.deinit();

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
