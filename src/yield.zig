pub const Yield = packed struct {
    food: u5 = 0,
    production: u5 = 0,
    gold: u5 = 0,
    culture: u5 = 0,
    faith: u5 = 0,
    science: u5 = 0,

    pub fn add(self: Yield, other: Yield) Yield {
        return .{
            .food = self.food + other.food,
            .gold = self.gold + other.gold,
            .production = self.production + other.production,
            .culture = self.culture + other.culture,
            .faith = self.faith + other.faith,
            .science = self.science + other.science,
        };
    }
};

pub const YieldAccumulator = packed struct {
    production: u32 = 0,
    food: u32 = 0,
    gold: u32 = 0,
    culture: u32 = 0,
    faith: u32 = 0,
    science: u32 = 0,

    pub fn add(self: *@This(), yield: Yield) void {
        self.production += @intCast(yield.production);
        self.food += @intCast(yield.food);
        self.gold += @intCast(yield.gold);
        self.culture += @intCast(yield.culture);
        self.faith += @intCast(yield.faith);
        self.science += @intCast(yield.science);
    }
};
