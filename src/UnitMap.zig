const Self = @This();
const std = @import("std");

const Rules = @import("Rules.zig");
const City = @import("City.zig");

const Unit = @import("Unit.zig");
const move = @import("move.zig").MoveCost;

const Grid = @import("Grid.zig");
const Edge = Grid.Edge;
const Idx = Grid.Idx;
const HexDir = Grid.Dir;

units: std.AutoArrayHashMapUnmanaged(UnitKey, Unit),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator, .units = .{} };
}
pub fn deinit(self: *Self) void {
    self.units.deinit(self.allocator);
}

pub fn refreshUnits(self: *Self) void {
    var unit_iter = self.units.iterator();
    while (unit_iter.next()) |e| {
        e.value_ptr.refresh();
    }
}

/// Slot type when not embarked
pub fn defaultSlot(self: Self) UnitSlot {
    // PLACEHOLDER CIVILIAN UNITS ARE NOT A THING YET, will need reworking when the rapture comes
    if (self.type.baseStats().domain == .SEA) {
        if (self.type == .work_boat) return .civilian;
        return .naval;
    }
    if (self.type.baseStats().domain == .LAND) {
        if (self.type == .worker or self.type == .settler) return .civilian;

        return .military;
    }
    unreachable;
}

pub fn slotAfterMove(self: *Self, cost: move.MoveCost) UnitSlot {
    if (cost == .disembarkation) return self.defaultSlot();
    if (cost == .embarkation or self.embarked) return .embarked;
    return self.defaultSlot();
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
    const src_ukey = dest_ukey.nextKeyInStack();
    const kv = self.units.fetchSwapRemove(src_ukey) orelse return;
    self.units.put(self.allocator, dest_ukey, kv.value) catch unreachable;
    self.cascadeUnitStack(src_ukey);
}

/// First unit in a slot
pub fn getFirstSlotUnitPtr(self: *const Self, idx: Idx, slot: UnitSlot) ?*Unit {
    return self.getUnitPtr(.{ .idx = idx, .slot = slot });
}

/// First unit on tile
pub fn getFirstUnitPtr(self: *const Self, idx: Idx) ?*Unit {
    return self.getUnitPtr(self.firstOccupiedKey(idx) orelse return null);
}

/// All unit entries
pub fn getAllUnitPtrBuf(self: *const Self, buf: []*Unit, idx: Idx) []*Unit {
    var i = 0;
    var unit_key = self.firstOccupiedKey(idx);

    while (unit_key != null) {
        buf[i] = self.getUnitPtr(unit_key.?);
        i += 1;
        unit_key = unit_key.?.nextOccupied(self);
        if (i == buf.len) break;
    }

    return buf[0..i];
}

pub fn getAllOccupiedKeysBuf(self: *const Self, buf: []UnitKey, idx: Idx) []UnitKey {
    var i = 0;
    var unit_key = UnitKey.firstOccupied(idx, self);

    while (unit_key != null) {
        buf[i] = unit_key;
        i += 1;
        unit_key = unit_key.?.nextOccupied(self);
        if (i == buf.len) break;
    }
    return buf[0..i];
}

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

pub const UnitKey = struct {
    idx: Idx,
    slot: UnitSlot,
    stack_depth: u8 = 0,
    fn nextKeyInStack(self: UnitKey) UnitKey {
        return .{ .slot = self.slot, .stack_depth = self.stack_depth + 1, .idx = self.idx };
    }
};

/// Start iter through occupied
pub fn firstOccupiedKey(
    self: *const Self,
    idx: Idx,
) ?UnitKey {
    var first = .{ .idx = idx, .slot = UnitSlot.first() };
    while (self.getUnitPtr(first) == null)
        first = .{ .slot = first.slot.next() orelse return null, .idx = first.idx };
    return first;
}

/// Iterate though occupied for a tile
pub fn nextOccupiedKey(self: *const Self, ukey: UnitKey) ?UnitKey {
    var next = ukey.nextKeyInStack();
    while (self.getUnitPtr(next) == null)
        next = .{ .slot = next.slot.next() orelse return null, .idx = ukey.idx };
    return next;
}

/// First free key in a slot
pub fn firstFreeKey(self: *const Self, idx: Idx, slot: UnitSlot) ?UnitKey {
    var key: UnitKey = .{ .idx = idx, .slot = slot, .stack_depth = 0 };
    while (self.getUnitPtr(key) != null) key = key.nextInStack();
    return key;
}
