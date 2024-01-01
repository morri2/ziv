const Self = @This();
const std = @import("std");
const hex = @import("../hex.zig");
const perlin_noice = @import("perlin.zig");
const math = std.math;
const HexGrid = hex.HexGrid(f32);

values: HexGrid,
application_mode: Mode,
allocator: std.mem.Allocator,

pub const Mode = enum {
    set,
    add,
    sub,
    mul,
    avg,
    max,
    min,
};

pub fn mode(self: *Self, m: Mode) *Self {
    self.application_mode = m;
    return self;
}

pub fn init(width: usize, height: usize, wrap_around: bool, allocator: std.mem.Allocator) !Self {
    const values = try HexGrid.init(width, height, wrap_around, allocator);
    for (0..values.len) |i| values.hex_data[i] = 0;
    return Self{
        .application_mode = .set,
        .values = values,
        .allocator = allocator,
    };
}

pub fn clone(self: Self) !Self {
    const new_clone = Self{
        .application_mode = self.application_mode,
        .values = try HexGrid.init(self.values.width, self.values.height, self.values.wrap_around, self.allocator),
        .allocator = self.allocator,
    };
    std.mem.copyForwards(f32, new_clone.values.hex_data, self.values.hex_data);
    return new_clone;
}

fn apply(self: *Self, i: usize, v: f32) void {
    switch (self.application_mode) {
        .set => self.values.hex_data[i] = v,
        .add => self.values.hex_data[i] += v,
        .sub => self.values.hex_data[i] -= v,
        .mul => self.values.hex_data[i] *= v,
        .max => self.values.hex_data[i] = @max(self.values.get(i), v),
        .min => self.values.hex_data[i] = @min(self.values.get(i), v),
        .avg => self.values.hex_data[i] = (self.values.get(i) + v) / 2.0,
    }
}

pub fn perlin(self: *Self, args: struct { scale: f32 = 0.2, max: f32 = 1.0, min: f32 = 0.0 }, seed: u64) void {
    for (0..self.values.len) |i| {
        const x = self.values.idxToX(i);
        const y = self.values.idxToY(i);

        const pos_x = hex.tilingPosX(x, y, args.scale);
        const pos_y = hex.tilingPosY(y, args.scale);

        const noice = perlin_noice.perlin(pos_x, pos_y, seed);

        self.apply(i, noice * (args.max - args.min) + args.min);
    }
}

pub fn random(self: *Self, args: struct { max: f32 = 1.0, min: f32 = 0.0 }, seed: u64) void {
    var rand = std.rand.DefaultPrng.init(seed);
    for (0..self.values.len) |i| {
        const noice: f32 = rand.random().float(f32);
        self.apply(i, noice * (args.max - args.min) + args.min);
    }
}

pub fn isAbove(self: *Self, bound: f32) void {
    for (0..self.values.len) |i| {
        self.values.hex_data[i] = @floatFromInt(@intFromBool(self.values.hex_data[i] > bound));
    }
}

pub fn isBellow(self: *Self, bound: f32) void {
    for (0..self.values.len) |i| {
        self.values.hex_data[i] = @floatFromInt(@intFromBool(self.values.hex_data[i] < bound));
    }
}

pub fn isBetween(self: *Self, low_bound: f32, high_bound: f32) void {
    for (0..self.values.len) |i| {
        self.values.hex_data[i] = @floatFromInt(@intFromBool(self.values.hex_data[i] < high_bound and self.values.hex_data[i] > low_bound));
    }
}

pub fn trunc(self: *Self, low_bound: f32, high_bound: f32) void {
    for (0..self.values.len) |i| {
        self.values.hex_data[i] = @max(self.values.hex_data[i], low_bound);
        self.values.hex_data[i] = @min(self.values.hex_data[i], high_bound);
    }
}

pub fn applySelf(self: *Self) void {
    applyOther(self, self.*);
}

pub fn applyOther(self: *Self, other: Self) void {
    for (0..self.values.len) |i| {
        self.apply(i, other.values.get(i));
    }
}

pub fn applyConst(self: *Self, c: f32) void {
    for (0..self.values.len) |i| {
        self.apply(i, c);
    }
}

/// latetude of hex -1 to 1
pub fn latetudeMap(self: *Self) void {
    for (0..self.values.len) |i| {
        const lat: f32 = (@as(f32, @floatFromInt(
            self.values.idxToY(i),
        )) / @as(f32, @floatFromInt(
            self.values.height - 1,
        ))) * 2.0 - 1;

        self.apply(i, std.math.sin(lat * (std.math.pi / 2.0)));
        //self.apply(i, lat); // more even spread
    }
}

pub fn blur(self: *Self, blur_amt: f32) !void {
    const old: []f32 = try self.allocator.alloc(f32, self.values.len);
    errdefer self.allocator.free(old);
    @memcpy(old, self.values.hex_data);

    const keep_amt = 1.0 - blur_amt * 6;
    if (keep_amt < 0) unreachable;
    for (0..self.values.len) |i| {
        const ns = self.values.neighbours(i);
        self.values.hex_data[i] *= keep_amt;
        for (ns) |n_op| {
            const n = n_op orelse {
                self.values.hex_data[i] += blur_amt * old[i];
                continue;
            };
            self.values.hex_data[i] += blur_amt * old[n];
        }
    }
}

pub fn weightedBlur(self: *Self, blur_amt: f32, weight_map: Self) !void {
    const old: []f32 = try self.allocator.alloc(f32, self.values.len);
    errdefer self.allocator.free(old);
    @memcpy(old, self.values.hex_data);

    for (0..self.values.len) |i| {
        const ns = self.values.neighbours(i);
        var keep_amt: f32 = 1.0;
        self.values.hex_data[i] = 0;
        for (ns) |n_op| {
            const n = n_op orelse continue;
            const weighted_blur_amt = blur_amt * weight_map.values.get(n);
            keep_amt -= weighted_blur_amt;
            self.values.hex_data[i] += weighted_blur_amt * old[n];
        }
        self.values.hex_data[i] += keep_amt * old[i];
    }
}

/// used for toPercentileMap
fn lessThan(context: *Self, lhs: hex.HexIdx, rhs: hex.HexIdx) bool {
    return context.values.get(lhs) < context.values.get(rhs);
}

pub fn toPercentileMap(self: *Self) !void {
    const sorted: []hex.HexIdx = try self.allocator.alloc(hex.HexIdx, self.values.len);
    errdefer self.allocator.free(sorted);
    for (0..self.values.len) |i| {
        sorted[i] = i;
    }

    std.sort.insertion(hex.HexIdx, sorted, self, lessThan);

    for (0.., sorted) |n, idx| {
        self.values.set(idx, @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(self.values.len)));
    }
}

pub fn sum(self: *const Self) f32 {
    var acc: f32 = 0;
    for (0..self.values.len) |i| {
        acc += self.values.get(i);
    }
    return acc;
}
pub fn invertNormal(self: *Self) void {
    self.mode(.mul).applyConst(-1.0);
    self.mode(.add).applyConst(1);
}

pub fn maxValue(self: *const Self) f32 {
    var max: f32 = self.values.get(0);
    for (0..self.values.len) |i| {
        const val = self.values.get(i);
        max = @max(max, val);
    }
    return max;
}

pub fn minValue(self: *const Self) f32 {
    var min: f32 = self.values.get(0);
    for (0..self.values.len) |i| {
        const val = self.values.get(i);
        min = @min(min, val);
    }
    return min;
}

pub fn avgValue(self: *const Self) f32 {
    return self.sum() / @as(f32, @floatFromInt(self.values.len));
}

pub fn function(self: *Self, func: *const fn (f32) f32) void {
    for (0..self.values.len) |i| {
        self.values.set(i, func(self.values.get(i)));
    }
}

/// sets highest value to 1 and lowest to 0
pub fn normalize(self: *Self) void {
    const min = self.minValue();
    self.mode(.sub).applyConst(min);

    const max = self.maxValue();
    self.mode(.mul).applyConst(1.0 / (max));
}
