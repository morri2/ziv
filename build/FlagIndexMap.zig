const std = @import("std");

const Self = @This();

const Integer = u256;

pub const Flags = std.bit_set.IntegerBitSet(@bitSizeOf(Integer));

indices: std.StringArrayHashMap(void),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .indices = std.StringArrayHashMap(void).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.indices.deinit();
}

pub fn add(self: *Self, key: []const u8) !usize {
    const gop = try self.indices.getOrPut(key);
    if (gop.found_existing) return error.AlreadyExists;

    return gop.index;
}

pub fn addOrGet(self: *Self, key: []const u8) !usize {
    const gop = try self.indices.getOrPut(key);
    return gop.index;
}

pub fn get(self: Self, key: []const u8) ?usize {
    return self.indices.getIndex(key);
}

pub fn flagsFromKeys(
    self: Self,
    keys: []const []const u8,
) Flags {
    var flags = Flags.initEmpty();
    for (keys) |key| {
        if (self.get(key)) |index| flags.set(index);
    }
    return flags;
}

pub fn addAndGetFlagsFromKeys(
    self: *Self,
    keys: []const []const u8,
) !Flags {
    var flags = Flags.initEmpty();
    for (keys) |key| {
        flags.set(try self.addOrGet(key));
    }
    return flags;
}

pub fn integerFromFlags(flags: Flags) Integer {
    var mut_flags = flags;
    var integer: Integer = 0;
    while (mut_flags.toggleFirstSet()) |index| {
        integer |= @as(Integer, 1) << @truncate(index);
    }
    return integer;
}
