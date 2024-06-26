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
    military_land = 0,
    military_sea = 1,
    civilian_land = 2,
    civilian_sea = 3,
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

    pub fn isCivilian(self: Slot) bool {
        return switch (self) {
            .civilian_land,
            .civilian_sea,
            => true,
            .military_land,
            .military_sea,
            .embarked,
            .trade,
            => false,
        };
    }

    pub fn isMilitary(self: Slot) bool {
        return switch (self) {
            .military_land,
            .military_sea,
            => true,
            .civilian_land,
            .civilian_sea,
            .embarked,
            .trade,
            => false,
        };
    }
};

pub const Storage = struct {
    unit: Unit,
    stacked: Stacked.Key = .none,
};

pub const Stacked = struct {
    pub const Key = enum(u32) {
        none = 0,
        _,
    };

    idx: Idx,
    slot: Slot,
    storage: Storage,
};

pub const Reference = struct {
    idx: Idx,
    slot: Slot,
    stacked: Stacked.Key = .none,
};

allocator: std.mem.Allocator,

stacked_key: Stacked.Key = @enumFromInt(1),
maps: [Slot.len()]std.AutoArrayHashMapUnmanaged(Idx, Storage) = [_]std.AutoArrayHashMapUnmanaged(Idx, Storage){.{}} ** Slot.len(),
stacked: std.AutoHashMapUnmanaged(Stacked.Key, Stacked) = .{},

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
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

pub fn putNoStack(self: *Self, idx: Idx, unit: Unit, slot: Slot) !bool {
    if (self.hasOtherFaction(idx, unit.faction_id)) return false;
    const gop = try self.maps[@intFromEnum(slot)].getOrPut(self.allocator, idx);

    if (gop.found_existing) return false;

    gop.value_ptr.* = .{ .unit = unit };
    return true;
}

pub fn putNoStackAutoSlot(self: *Self, idx: Idx, unit: Unit, rules: *const Rules) !bool {
    return try self.putNoStack(
        idx,
        unit,
        slotFromUnitType(unit.type, rules),
    );
}

pub fn putOrStack(self: *Self, idx: Idx, unit: Unit, slot: Slot) !bool {
    if (self.hasOtherFaction(idx, unit.faction_id)) return false;
    const gop = try self.maps[@intFromEnum(slot)].getOrPut(self.allocator, idx);

    if (!gop.found_existing) {
        gop.value_ptr.* = .{ .unit = unit };
        return true;
    }

    const stacked_key = self.nextStackedKey();
    try self.stacked.put(self.allocator, stacked_key, .{
        .idx = idx,
        .slot = slot,
        .storage = .{ .unit = unit },
    });

    var unit_storage = gop.value_ptr;
    while (unit_storage.stacked != .none) {
        unit_storage = &(self.stacked.getPtr(unit_storage.stacked) orelse unreachable).storage;
    }
    unit_storage.stacked = stacked_key;
    return true;
}

pub fn putOrStackAutoSlot(self: *Self, idx: Idx, unit: Unit, rules: *const Rules) !bool {
    return try self.putOrStack(
        idx,
        unit,
        slotFromUnitType(unit.type, rules),
    );
}

pub fn hasOtherFaction(self: *const Self, idx: Idx, faction_id: World.FactionID) bool {
    var slot = Slot.first();
    while (true) {
        if (self.maps[@intFromEnum(slot)].get(idx)) |unit|
            if (slot != .trade and unit.unit.faction_id != faction_id) return true;
        if (!slot.next()) break;
    }
    return false;
}

pub fn remove(self: *Self, idx: Idx, slot: Slot) void {
    const ptr = self.maps[@intFromEnum(slot)].getPtr(idx) orelse unreachable;
    if (ptr.stacked != .none) {
        ptr.* = (self.stacked.fetchRemove(ptr.stacked) orelse unreachable).value.storage;
    } else {
        _ = self.maps[@intFromEnum(slot)].swapRemove(idx);
    }
}

pub fn removeStacked(self: *Self, idx: Idx, stacked: Stacked.Key) void {
    var ptr = &(self.stacked.getPtr(stacked) orelse unreachable).storage;
    while (ptr.stacked != stacked) {
        ptr = &(self.stacked.getPtr(ptr.stacked) orelse unreachable).storage;
    }
    const removed_stacked = self.stacked.fetchRemove(stacked) orelse unreachable;
    std.debug.assert(removed_stacked.value.idx == idx);
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
        if (reference.stacked != .none) {
            const stacked = self.stacked.get(reference.stacked) orelse break :blk;
            if (stacked.idx != reference.idx) break :blk;
            if (stacked.slot != reference.slot) break :blk;

            if (stacked.storage.stacked != .none) return .{
                .idx = reference.idx,
                .slot = reference.slot,
                .stacked = stacked.storage.stacked,
            };
        } else if (self.maps[@intFromEnum(reference.slot)].get(reference.idx)) |storage| {
            if (storage.stacked != .none) return .{
                .idx = reference.idx,
                .slot = reference.slot,
                .stacked = storage.stacked,
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
        if (slot == initial) return null;
        slot.nextLoop();
    }
}

pub fn deref(self: *const Self, reference: Reference) ?Unit {
    if (reference.stacked != .none) {
        const stacked = self.stacked.get(reference.stacked) orelse return null;
        if (stacked.idx != reference.idx) return null;
        if (stacked.slot != reference.slot) return null;
        return stacked.storage.unit;
    }

    const storage = self.maps[@intFromEnum(reference.slot)].get(reference.idx) orelse return null;
    return storage.unit;
}

pub fn derefToPtr(self: *Self, reference: Reference) ?*Unit {
    if (reference.stacked != .none) {
        const stacked = self.stacked.getPtr(reference.stacked) orelse return null;
        if (stacked.idx != reference.idx) return null;
        if (stacked.slot != reference.slot) return null;
        return &stacked.storage.unit;
    }

    const storage = self.maps[@intFromEnum(reference.slot)].getPtr(reference.idx) orelse return null;
    return &storage.unit;
}

pub fn removeReference(self: *Self, reference: Reference) void {
    if (reference.stacked != .none) {
        const stacked = self.stacked.get(reference.stacked) orelse return;
        if (stacked.idx != reference.idx) return;
        if (stacked.slot != reference.slot) return;
        self.removeStacked(reference.idx, reference.stacked);
        return;
    }

    if (!self.maps[@intFromEnum(reference.slot)].contains(reference.idx)) return;

    self.remove(reference.idx, reference.slot);
}

pub fn refresh(self: *Self, rules: *const Rules) void {
    for (&self.maps) |*map| {
        for (map.values()) |*storage| {
            storage.unit.refresh(rules);
        }
    }
}

pub fn iterator(self: *const Self) struct {
    const Iterator = @This();
    units: *const Self,
    slot: Slot = Slot.first(),
    index: usize = 0,
    next_depth: u8 = 0,
    next_stacked: Stacked.Key = .none,

    pub fn next(iter: *Iterator) ?struct {
        idx: Idx,
        slot: Slot,
        depth: u8,
        unit: Unit,
        stacked: Stacked.Key,
    } {
        if (iter.next_stacked != .none) {
            const stacked = iter.units.stacked.get(iter.next_stacked) orelse unreachable;
            const depth = iter.next_depth;
            const stacked_key = iter.next_stacked;
            if (stacked.storage.stacked != .none) {
                iter.next_stacked = stacked.storage.stacked;
                iter.next_depth += 1;
            } else {
                iter.index += 1;
                iter.next_depth = 0;
                iter.next_stacked = .none;
            }
            return .{
                .idx = stacked.idx,
                .slot = stacked.slot,
                .depth = depth,
                .unit = stacked.storage.unit,
                .stacked = stacked_key,
            };
        }

        if (iter.index >= iter.units.maps[@intFromEnum(iter.slot)].count()) {
            while (iter.slot.next()) {
                if (iter.units.maps[@intFromEnum(iter.slot)].count() != 0) break;
            } else return null;
            iter.index = 0;
        }

        const map = &iter.units.maps[@intFromEnum(iter.slot)];
        const storage = map.values()[iter.index];
        const idx = map.keys()[iter.index];
        if (storage.stacked != .none) {
            iter.next_stacked = storage.stacked;
            iter.next_depth += 1;
        } else {
            iter.index += 1;
        }

        return .{
            .slot = iter.slot,
            .unit = storage.unit,
            .idx = idx,
            .depth = 0,
            .stacked = .none,
        };
    }
} {
    return .{ .units = self };
}

fn nextStackedKey(self: *Self) Stacked.Key {
    const key = self.stacked_key;
    self.stacked_key = @enumFromInt(@intFromEnum(self.stacked_key) + 1);
    return key;
}

pub fn slotFromUnitType(unit_type: UnitType, rules: *const Rules) Slot {
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
