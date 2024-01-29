const std = @import("std");

const Rules = @import("Rules.zig");
const Promotion = Rules.Promotion;
const UnitType = Rules.UnitType;

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const Idx = Grid.Idx;
const Dir = Grid.Dir;

const World = @import("World.zig");

const Unit = @import("Unit.zig");

const Self = @This();

pub const Slot = enum(u3) {
    civilian_land = 0,
    civilian_sea = 1,
    military_land = 2,
    military_sea = 3,
    embarked = 4,
    trade = 5,

    pub fn first() Slot {
        return @enumFromInt(0);
    }

    pub fn last() Slot {
        return @enumFromInt(Slot.len() - 1);
    }

    pub fn len() usize {
        return std.meta.fields(Slot).len;
    }

    pub fn next(self: *Slot) bool {
        if (self.* == Slot.last()) return false;
        self.* = @enumFromInt(@intFromEnum(self.*) + 1);
        return true;
    }

    pub fn nextLoop(self: *Slot) void {
        if (self.* == Slot.last())
            self.* = Slot.first()
        else
            self.* = @enumFromInt(@intFromEnum(self.*) + 1);
    }
};

pub const Storage = struct {
    unit: Unit,
    stacked: ?Stacked.Key = null,
};

pub const Stacked = struct {
    pub const Key = usize;

    idx: Idx,
    slot: Slot,
    storage: Storage,
};

pub const Reference = struct {
    idx: Idx,
    slot: Slot,
    stacked: ?Stacked.Key = null,
};

allocator: std.mem.Allocator,
rules: *const Rules,

stacked_key: Stacked.Key = 0,
maps: [Slot.len()]std.AutoArrayHashMapUnmanaged(Idx, Storage) = [_]std.AutoArrayHashMapUnmanaged(Idx, Storage){.{}} ** Slot.len(),
stacked: std.AutoHashMapUnmanaged(Stacked.Key, Stacked) = .{},

pub fn init(rules: *const Rules, allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .rules = rules,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.stacked.deinit(allocator);
    for (&self.maps) |*map| map.deinit(allocator);
}

pub fn get(self: *const Self, idx: Idx, slot: Slot) ?Unit {
    return (self.maps[@intFromEnum(slot)].get(idx) orelse return null).unit;
}

pub fn getStacked(self: *const Self, idx: Idx, slot: Slot, stacked_key: Stacked.Key) ?Unit {
    const stacked = self.stacked.get(stacked_key) orelse return null;
    std.debug.assert(slot == stacked.slot);
    std.debug.assert(idx == stacked.idx);
    return stacked.storage.unit;
}

pub fn putNoStack(self: *Self, idx: Idx, unit: Unit, slot: Slot) !void {
    const gop = try self.maps[@intFromEnum(slot)].getOrPut(self.allocator, idx);

    if (gop.found_existing) return error.AlreadyOccupied;

    gop.value_ptr.* = .{ .unit = unit };
}

pub fn putNoStackAutoSlot(self: *Self, idx: Idx, unit: Unit) !void {
    return self.putNoStack(
        idx,
        unit,
        slotFromUnitType(unit.type, self.rules),
    );
}

pub fn putOrStack(self: *Self, idx: Idx, unit: Unit, slot: Slot) !void {
    const gop = try self.maps[@intFromEnum(slot)].getOrPut(self.allocator, idx);

    if (!gop.found_existing) {
        gop.value_ptr.* = .{ .unit = unit };
        return;
    }

    const stacked_key = self.stacked_key;
    self.stacked_key += 1;
    try self.stacked.put(self.allocator, stacked_key, .{
        .idx = idx,
        .slot = slot,
        .storage = .{ .unit = unit },
    });

    var unit_storage = gop.value_ptr;
    while (unit_storage.stacked) |key| {
        unit_storage = &(self.stacked.getPtr(key) orelse unreachable).storage;
    }
    unit_storage.stacked = stacked_key;
}

pub fn putOrStackAutoSlot(self: *Self, idx: Idx, unit: Unit) !void {
    try self.putOrStack(
        idx,
        unit,
        slotFromUnitType(unit.type, self.rules),
    );
}

pub fn remove(self: *Self, idx: Idx, slot: Slot) void {
    const ptr = self.maps[@intFromEnum(slot)].getPtr(idx) orelse unreachable;
    if (ptr.stacked) |stacked_key| {
        ptr.* = (self.stacked.fetchRemove(stacked_key) orelse unreachable).value.storage;
    } else {
        _ = self.maps[@intFromEnum(slot)].swapRemove(idx);
    }
}

pub fn removeStacked(self: *Self, idx: Idx, stacked: Stacked.Key) void {
    var ptr = &(self.stacked.getPtr(idx) orelse unreachable).storage;
    while (ptr.stacked != stacked) {
        ptr = &(self.stacked.getPtr(ptr.stacked orelse unreachable) orelse unreachable).storage;
    }
    const removed_stacked = self.stacked.fetchRemove(stacked) orelse unreachable;
    ptr.stacked = removed_stacked.value.storage.stacked;
}

pub fn firstReference(self: *const Self, idx: Idx) ?Reference {
    var slot = Slot.first();
    while (true) {
        if (self.maps[@intFromEnum(slot)].contains(idx)) return .{
            .idx = idx,
            .slot = slot,
        };
        slot.nextLoop();
        if (slot == Slot.first()) return null;
    }
}

pub fn nextReference(self: *const Self, reference: Reference) ?Reference {
    blk: {
        if (reference.stacked) |key| {
            const stacked = self.stacked.get(key) orelse break :blk;
            if (stacked.idx != reference.idx) break :blk;
            if (stacked.slot != reference.slot) break :blk;

            if (stacked.storage.stacked) |child_key| return .{
                .idx = reference.idx,
                .slot = reference.slot,
                .stacked = child_key,
            };
        } else if (self.maps[@intFromEnum(reference.slot)].get(reference.idx)) |storage| {
            if (storage.stacked) |key| return .{
                .idx = reference.idx,
                .slot = reference.slot,
                .stacked = key,
            };
        }
    }

    const initial = reference.slot;
    var slot = initial;
    slot.nextLoop();
    while (true) {
        if (self.maps[@intFromEnum(slot)].contains(reference.idx)) return .{
            .idx = reference.idx,
            .slot = slot,
        };
        slot.nextLoop();
        if (slot == initial) return null;
    }
}

pub fn deref(self: *const Self, reference: Reference) ?Unit {
    if (reference.stacked) |key| {
        const stacked = self.stacked.get(key) orelse return null;
        if (stacked.idx != reference.idx) return null;
        if (stacked.slot != reference.slot) return null;
        return stacked.storage.unit;
    }

    const storage = self.maps[@intFromEnum(reference.slot)].get(reference.idx) orelse return null;
    return storage.unit;
}

pub fn removeReference(self: *Self, reference: Reference) void {
    if (reference.stacked) |key| {
        const stacked = self.stacked.get(key) orelse return;
        if (stacked.idx != reference.idx) return;
        if (stacked.slot != reference.slot) return;
        self.removeStacked(reference.idx, key);
        return;
    }

    if (!self.maps[@intFromEnum(reference.slot)].contains(reference.idx)) return;

    self.remove(reference.idx, reference.slot);
}

pub fn refresh(self: *Self) void {
    for (&self.maps) |*map| {
        for (map.values()) |*storage| {
            storage.unit.refresh(self.rules);
        }
    }
}

pub fn iterator(self: *const Self) struct {
    const Iterator = @This();
    units: *const Self,
    slot: Slot = Slot.first(),
    index: usize = 0,

    pub fn next(iter: *Iterator) ?struct {
        slot: Slot,
        unit: Unit,
        idx: Idx,
    } {
        if (iter.index >= iter.units.maps[@intFromEnum(iter.slot)].count()) {
            while (iter.slot.next()) {
                if (iter.units.maps[@intFromEnum(iter.slot)].count() != 0) break;
            } else return null;
            iter.index = 0;
        }

        const map = &iter.units.maps[@intFromEnum(iter.slot)];
        const unit = map.values()[iter.index].unit;
        const idx = map.keys()[iter.index];
        iter.index += 1;
        return .{
            .slot = iter.slot,
            .unit = unit,
            .idx = idx,
        };
    }
} {
    return .{ .units = self };
}

fn slotFromUnitType(unit_type: UnitType, rules: *const Rules) Slot {
    const stats = unit_type.stats(rules);
    return switch (unit_type.ty(rules)) {
        .civilian => switch (stats.domain) {
            .land => .civilian_land,
            .sea => .civilian_sea,
        },
        .military => switch (stats.domain) {
            .land => .military_land,
            .sea => .military_sea,
        },
    };
}
