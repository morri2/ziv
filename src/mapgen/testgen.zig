const std = @import("std");
const rules = @import("../rules");
const hex = @import("../hex.zig");
const ScalarMap = @import("ScalarMap.zig");
const nature = @import("nature.zig");

const BiomeIndex = struct {
    temperature_categories: [32]f32 = [_]f32{9999} ** 32,
    rainfall_categories: [32]f32 = [_]f32{-420.0} ** 32,
    biome: [32 * 32]u8 = [_]u8{'x'} ** (32 * 32),
    too_cold: u8 = 'i', //

    pub fn getBiome(self: BiomeIndex, temp: f32, rain: f32) u8 {
        var temp_idx: usize = 0;
        var rain_idx: usize = 0;
        while (temp > self.temperature_categories[temp_idx]) temp_idx += 1;
        while (rain < self.rainfall_categories[rain_idx + 1]) rain_idx += 1;

        return self.biome[32 * rain_idx + temp_idx];
    }
};

pub fn constructBiomeIndex(
    file_path: []const u8,
) !BiomeIndex {
    const temprature_step = 5.0;

    var bi = BiomeIndex{};
    bi.too_cold = 'i';
    const file = try std.fs.cwd().openFile(file_path, .{});
    const reader = file.reader();

    var buf: [255]u8 = undefined;
    var r: usize = 0;
    var line: []u8 = buf[0..0];
    line = try reader.readUntilDelimiter(buf[0..], '\n');
    while (line.len > 0) {
        var i: usize = 0;
        for (line) |char| {
            if (r == 0) bi.temperature_categories[i] = @as(f32, @floatFromInt(i)) * temprature_step - 20.0;

            i += 1;
            if (char == '.') continue;
            if (char == ' ') break;

            bi.biome[r * 32 + i] = char;
        }
        const rainfall_category: f32 = try std.fmt.parseFloat(f32, line[i..]);
        bi.rainfall_categories[r] = rainfall_category;

        r += 1;
        line = try reader.readUntilDelimiter(buf[0..], '\n'); // CAUSES MEMORY LEAK!!! VERY LONG ERROR MESSAGE

    }
    file.close();
    return bi;
}

pub fn generate(width: usize, height: usize, allocator: std.mem.Allocator) !GenLogList {
    const Seed = struct {
        num: u64,
        pub fn next(self: *@This()) u64 {
            self.num += 1;
            return self.num;
        }
    };
    var seed = Seed{ .num = 94998 };
    var gls = GenLogList{};
    var blank = try ScalarMap.init(width, height, true, allocator); // For cloning

    // Generation parameters
    // =====================
    const SEA_LEVEL: f32 = 0.40;

    // // TERRAIN TEIR CUTOFFS
    // const T1_CUTOFF: f32 = 0.027; // around 35 % of land
    // const T2_CUTOFF: f32 = 0.115; // around 50 % ...
    // const T3_CUTOFF: f32 = 0.175; // around 10 % ...

    // Eleveation generation
    // =====================
    gls.scale = .fraction;

    var elevation = try blank.clone();
    elevation.perlin(.{ .scale = 0.075, .min = 0.0, .max = 1.0 }, seed.next());
    elevation.mode(.mul).applySelf(); // square :)
    elevation.mode(.add).perlin(.{ .scale = 0.2, .min = -0.1, .max = 0.3 }, seed.next());
    elevation.mode(.add).perlin(.{ .scale = 0.5, .min = -0.2, .max = 0.2 }, seed.next());
    try gls.log(elevation);

    var is_land = try elevation.clone();
    is_land.isAbove(SEA_LEVEL);
    try gls.log(is_land);

    var is_water = try is_land.clone();
    is_water.invertNormal();

    var elevation_relative_sea = try elevation.clone();
    elevation_relative_sea.mode(.sub).applyConst(SEA_LEVEL);

    var elevation_above_sea = try elevation_relative_sea.clone();
    elevation_above_sea.mode(.mul).applyOther(is_land);
    try gls.log(elevation_above_sea);

    var sea_depth = try elevation_relative_sea.clone();
    sea_depth.mode(.mul).applyOther(is_water);
    sea_depth.mode(.mul).applyConst(-1);
    try gls.log(sea_depth);

    // Temperature generation
    // ======================
    gls.scale = .temperature;

    var lat_temp = try blank.clone();
    lat_temp.latetudeMap();
    lat_temp.function(nature.tempFromLatitude);
    try gls.log(lat_temp);

    var perlin_temp = try blank.clone();
    perlin_temp.perlin(.{ .scale = 0.10, .min = -10, .max = 25 }, seed.next());
    try gls.log(perlin_temp);

    var base_temprature = try lat_temp.clone();
    base_temprature.mode(.add).applyOther(perlin_temp);
    try gls.log(base_temprature);

    var altitude_temprature = try elevation_above_sea.clone();
    altitude_temprature.function(nature.elevationFromHeightMap);
    altitude_temprature.function(nature.tempFromAltetude);
    try gls.log(altitude_temprature);

    // Water heat dispursion
    // =====================
    gls.scale = .temperature;

    var water_temp = try base_temprature.clone();
    water_temp.mode(.add).applyConst(5);
    water_temp.mode(.mul).applyOther(is_water);
    try gls.log(water_temp);

    // intra water dispursion
    for (0..20) |_| {
        try water_temp.weightedBlur(0.075, is_water);
        water_temp.mode(.mul).applyOther(is_water);
    }
    try gls.log(water_temp);

    // water to land dispursion
    for (0..5) |_| {
        try water_temp.weightedBlur(0.075, is_water);
    }
    try gls.log(water_temp);

    var water_temp_dispursion = try water_temp.clone();
    water_temp_dispursion.mode(.mul).applyOther(is_land);
    try gls.log(water_temp_dispursion);

    var total_temp = try base_temprature.clone();
    total_temp.mode(.add).applyOther(altitude_temprature);
    total_temp.mode(.avg).applyOther(water_temp_dispursion);

    try total_temp.blur(0.1);

    try gls.log(total_temp);

    // Water heat dispursion
    // =====================
    gls.scale = .norm_fraction;

    var rainfall_max = try total_temp.clone();
    rainfall_max.function(nature.maxRainFromTemperature);
    try gls.log(rainfall_max);

    var rainfall_saturation = try blank.clone();
    rainfall_saturation.perlin(.{ .scale = 0.1, .min = 0.0, .max = 1.0 }, seed.next());
    try gls.log(rainfall_saturation);

    var rainfall = try rainfall_saturation.clone();
    rainfall.mode(.mul).applyOther(rainfall_max);
    try gls.log(rainfall);

    // biomes!
    const bi = try constructBiomeIndex("biomes.txt");

    var biome = try blank.clone();
    for (0..biome.values.len) |i| {
        const b = bi.getBiome(total_temp.values.get(i), rainfall.values.get(i));

        biome.values.set(i, @floatFromInt(b));
    }
    gls.scale = .distinct;
    try gls.log(biome);
    biome.mode(.mul).applyOther(is_land);
    try gls.log(biome);

    // print the data :))
    const peek_temp = total_temp.maxValue();
    const low_temp = total_temp.minValue();
    const avg_temp = total_temp.avgValue();

    const peek_rain = rainfall.maxValue();
    const low_rain = rainfall.minValue();
    const avg_rain = rainfall.avgValue();

    std.debug.print("\nTEMP: {d:.1} - {d:.1}  (avg: {d:.1})\n", .{ low_temp, peek_temp, avg_temp });
    std.debug.print("\nRAIN: {d:.1} - {d:.1}  (avg: {d:.1})\n", .{ low_rain, peek_rain, avg_rain });

    return gls;
}

// Log structs

const DrawScale = enum { fraction, temperature, norm_fraction, distinct };
const GenLog = struct {
    map: ScalarMap,
    //step_name: [64:0]u8 = "unnamed",
    substep: bool = false,
    scale: DrawScale = .fraction,

    pub fn new_log(map: ScalarMap) !GenLog {
        const gl = GenLog{
            .map = try map.clone(),
        };
        return gl;
    }
};

const GenLogList = struct {
    logs: [64]?GenLog = [_]?GenLog{null} ** 64,
    i: usize = 0,
    scale: DrawScale = .fraction,

    pub fn log(self: *@This(), map: ScalarMap) !void {
        var gl = try GenLog.new_log(map);
        gl.scale = self.scale;
        self.logs[self.i] = gl;
        self.i += 1;
    }
    pub fn iter_start(self: *@This()) void {
        self.i = 0;
    }
    pub fn next(self: *@This()) void {
        if (self.logs[self.i + 1] != null) {
            self.i += 1;
        }
    }
    pub fn prev(self: *@This()) void {
        self.i -|= 1;
    }
};

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
