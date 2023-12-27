const Terrain = @import("World.zig").Terrain;
pub const Yield = packed struct {
    production: u5 = 0,
    food: u5 = 0,
    gold: u5 = 0,
    culture: u5 = 0,
    faith: u5 = 0,
    science: u5 = 0,
};

pub const YieldAccumulator = packed struct {
    production: u32 = 0,
    food: u32 = 0,
    gold: u32 = 0,
    culture: u32 = 0,
    faith: u32 = 0,
    science: u32 = 0,
};

pub const terrain_base_yield: [26]Yield = blk: {
    var ys: [26]Yield = [_]Yield{Yield{}} ** 26;

    for (0..26) |i| {
        ys[i] = Yield{ .production = 1, .food = 1 };
        if (i == @as(usize, Terrain.desert)) {
            ys[i] = Yield{};
        }
        if (i == @as(usize, Terrain.desert_hill)) {
            ys[i] = Yield{ .production = 2 };
        }
    }

    break :blk ys;
};
