const Self = @This();
const std = @import("std");
const PlayerView = @import("PlayerView.zig");
const Grid = @import("Grid.zig");

pub const FactionID = u8;

id: u8,
view: PlayerView,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, id: u8, grid: *const Grid) !Self {
    return .{
        .id = id,
        .allocator = allocator,
        .view = try PlayerView.init(allocator, grid),
    };
}

pub fn deinit(self: *Self) void {
    self.view.deinit();
}
