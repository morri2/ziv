const std = @import("std");
const flag_index_map = @import("flag_index_map.zig");

const Rules = @This();

arena: std.heap.ArenaAllocator,

base_count: usize,
feature_count: usize,
vegetation_count: usize,
base_names: [*]const u16,
feature_names: [*]const u16,
vegetation_names: [*]const u16,
terrain_strings: []const u8,

terrain_count: usize,
terrain_bases: [*]const Terrain.Base,
terrain_features: [*]const Terrain.Feature,
terrain_vegetation: [*]const Terrain.Vegetation,
terrain_attributes: [*]const Terrain.Attributes,
terrain_yields: [*]const Yield,
terrain_happiness: [*]const u8,
terrain_combat_bonus: [*]const i8,
terrain_unpacked_map: std.AutoHashMapUnmanaged(Terrain.Unpacked, Terrain),

resource_count: usize,
resource_kinds: [*]const Resource.Kind,
resource_yields: [*]const Yield,
resource_connectors: [*]const Building,
resource_names: [*]const u16,
resource_strings: []const u8,

building_count: usize,
building_yields: [*]const Yield,
building_allowed_map: std.AutoHashMapUnmanaged(struct {
    building: Building,
    terrain: Terrain,
}, Building.Allowed),
building_names: [*]const u16,
building_strings: []const u8,

promotion_count: usize,
promotion_prerequisites: [*]const u16,
promotion_storage: [*]const Promotion,

promotion_names: [*]const u16,
promotion_strings: []const u8,

effects: [std.meta.fields(Promotion.Effect).len + 1]u16,
effect_promotions: [*]const Promotion.Set, // TODO: compress bit field
effect_values: [*]const u32,

unit_type_count: usize,
unit_type_stats: [*]const UnitType.Stats,

unit_type_names: [*]const u16,
unit_type_strings: []const u8,

pub fn deinit(self: *Rules) void {
    self.arena.deinit();
}

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

pub const Terrain = enum(u8) {
    _,

    pub const Base = enum(u8) {
        _,

        pub fn name(self: Base, rules: *const Rules) []const u8 {
            const start = rules.base_names[@intFromEnum(self)];
            const end = rules.base_names[@intFromEnum(self) + 1];
            return rules.terrain_strings[start..end];
        }
    };

    pub const Feature = enum(u8) {
        none = 0,
        _,

        pub fn name(self: Feature, rules: *const Rules) []const u8 {
            const start = rules.feature_names[@intFromEnum(self)];
            const end = rules.feature_names[@intFromEnum(self) + 1];
            return rules.terrain_strings[start..end];
        }
    };

    pub const Vegetation = enum(u8) {
        none = 0,
        _,

        pub fn name(self: Vegetation, rules: *const Rules) []const u8 {
            const start = rules.vegetation_names[@intFromEnum(self)];
            const end = rules.vegetation_names[@intFromEnum(self) + 1];
            return rules.terrain_strings[start..end];
        }
    };

    pub const Attributes = packed struct(u7) {
        pub const Integer = @typeInfo(Attributes).Struct.backing_integer.?;

        is_water: bool = false,
        is_freshwater: bool = false,
        is_impassable: bool = false,
        is_rough: bool = false,
        is_wonder: bool = false,
        has_river: bool = false,
        has_freshwater: bool = false,

        pub fn eql(self: Attributes, other: Attributes) bool {
            const self_int: Integer = @bitCast(self);
            const other_int: Integer = @bitCast(other);
            return self_int == other_int;
        }

        pub fn count(self: Attributes) usize {
            const self_int: Integer = @bitCast(self);
            return @popCount(self_int);
        }

        pub fn intersectWith(self: Attributes, other: Attributes) Attributes {
            const self_int: Integer = @bitCast(self);
            const other_int: Integer = @bitCast(other);
            return @bitCast(self_int & other_int);
        }

        pub fn unionWith(self: Attributes, other: Attributes) Attributes {
            const self_int: Integer = @bitCast(self);
            const other_int: Integer = @bitCast(other);
            return @bitCast(self_int | other_int);
        }
    };

    pub const Unpacked = struct {
        base: Base,
        feature: Feature = .none,
        vegetation: Vegetation = .none,
        has_river: bool = false,
        has_freshwater: bool = false,

        pub fn pack(self: Unpacked, rules: *const Rules) ?Terrain {
            return rules.terrain_unpacked_map.get(self);
        }
    };

    pub fn base(self: Terrain, rules: *const Rules) Base {
        return rules.terrain_bases[@intFromEnum(self)];
    }

    pub fn feature(self: Terrain, rules: *const Rules) Feature {
        return rules.terrain_features[@intFromEnum(self)];
    }

    pub fn vegetation(self: Terrain, rules: *const Rules) Vegetation {
        return rules.terrain_vegetation[@intFromEnum(self)];
    }

    pub fn attributes(self: Terrain, rules: *const Rules) Attributes {
        return rules.terrain_attributes[@intFromEnum(self)];
    }

    pub fn yield(self: Terrain, rules: *const Rules) Yield {
        return rules.terrain_yields[@intFromEnum(self)];
    }

    pub fn happiness(self: Terrain, rules: *const Rules) u8 {
        return rules.terrain_happiness[@intFromEnum(self)];
    }

    pub fn combatBonus(self: Terrain, rules: *const Rules) i8 {
        return rules.terrain_combat_bonus[@intFromEnum(self)];
    }
};

pub const Resource = enum(u6) {
    _,

    pub const Kind = enum(u8) {
        bonus = 0,
        strategic = 1,
        luxury = 2,
    };

    pub fn kind(self: Resource, rules: *const Rules) Kind {
        return rules.resource_kinds[@intFromEnum(self)];
    }

    pub fn yield(self: Resource, rules: *const Rules) Yield {
        return rules.resource_yields[@intFromEnum(self)];
    }

    pub fn connectedBy(self: Resource, rules: *const Rules) Building {
        return rules.resource_connectors[@intFromEnum(self)];
    }

    pub fn name(self: Resource, rules: *const Rules) []const u8 {
        const start = rules.resource_names[@intFromEnum(self)];
        const end = rules.resource_names[@intFromEnum(self) + 1];
        return rules.resource_strings[start..end];
    }
};

pub const Building = enum(u8) {
    none = 0,
    _,

    pub const Allowed = enum(u8) {
        not_allowed = 0,
        allowed = 1,
        allowed_after_clear = 2,
        allowed_if_resource = 3,
        allowed_after_clear_if_resource = 4,
    };

    pub fn yield(self: Building, rules: *const Rules) Yield {
        return rules.building_yields[@intFromEnum(self)];
    }

    pub fn allowedOn(
        self: Building,
        terrain: Terrain,
        resource: ?Resource,
        rules: *const Rules,
    ) Allowed {
        return rules.building_allowed_map.get(.{
            .terrain = terrain,
            .building = self,
            .resource = resource,
        }) orelse .not_allowed;
    }

    pub fn name(self: Building, rules: *const Rules) []const u8 {
        const start = rules.building_names[@intFromEnum(self)];
        const end = rules.building_names[@intFromEnum(self) + 1];
        return rules.building_strings[start..end];
    }
};

pub const Transport = enum(u2) {
    none = 0,
    road = 1,
    rail = 2,
};

pub const Improvements = packed struct(u12) {
    building: Building = .none,
    transport: Transport = .none,
    pillaged_improvements: bool = false,
    pillaged_transport: bool = false,
};

pub const Promotion = enum(u8) {
    _,

    pub const Set: type = std.bit_set.IntegerBitSet(256);

    pub const Effect = enum(u8) {
        combat_bonus_attacking = 0, // +(value)%
        combat_bonus = 1, // +(value)%
        rough_terrain_bonus = 2, // +(value)%
        rough_terrain_bonus_range = 3, // +(value)%
        open_terrain_bonus = 4, // +(value)%
        open_terrain_bonus_range = 5, // +(value)%
        settle_city = 6,
        can_fortify = 7,
        build_roads = 8,
        build_rail = 9,
        build_improvement = 10,
        modify_attack_range = 11, // +(value)
        modify_movement = 12, // +(value)
        modify_sight_range = 13, // +(value)
        ignore_terrain_move = 14,
        can_embark = 15,
        cannot_melee = 16,

        pub const Iterator = struct {
            effect: Effect,
            index: usize = 0,

            pub fn init(effect: Effect) Iterator {
                return .{ .effect = effect };
            }

            pub fn next(self: *Iterator, rules: *const Rules) ?struct {
                value: u32,
                promotions: Promotion.Set,
            } {
                const start = rules.effects[@intFromEnum(self.effect)];
                const end = rules.effects[@intFromEnum(self.effect) + 1];
                const real_index = start + self.index;
                if (real_index >= end) return null;
                self.index += 1;

                return .{
                    .value = rules.effect_values[real_index],
                    .promotions = rules.effect_promotions[real_index],
                };
            }

            pub fn totalLen(self: *Iterator, rules: *const Rules) usize {
                const start = rules.effects[@intFromEnum(self.effect)];
                const end = rules.effects[@intFromEnum(self.effect) + 1];
                return end - start;
            }
        };
    };

    pub fn prerequisites(self: Promotion, rules: *const Rules) []const Promotion {
        const start = rules.promotion_prerequisites[@intFromEnum(self)];
        const end = rules.promotion_prerequisites[@intFromEnum(self) + 1];
        return rules.promotion_prerequisite_storage[start..end];
    }

    pub fn prerequisitesSet(self: Promotion, rules: *const Rules) Set {
        const prereqs = self.prerequisites(rules);
        var set = Set.initEmpty();
        for (prereqs) |prereq| {
            set.set(@intFromEnum(prereq));
        }
        return set;
    }

    pub fn name(self: Promotion, rules: *const Rules) []const u8 {
        const start = rules.promotion_names[@intFromEnum(self)];
        const end = rules.promotion_names[@intFromEnum(self) + 1];
        return rules.promotion_strings[start..end];
    }
};

pub const UnitType = enum(u8) {
    _,

    pub const Domain = enum(u1) {
        land = 0,
        sea = 1,
    };

    pub const Stats = struct {
        production: u16, // Max cost, Nuclear Missile 1000
        moves: u8, // Max movement, Nuclear Sub etc. 6
        melee: u8, // Max combat strength, Giant Death Robot 150
        ranged: u8,
        range: u8, // Max range, Nuclear Missile 12
        sight: u8, // Max 10 = 2 + 4 promotions + 1 scout + 1 nation + 1 Exploration + 1 Great Lighthouse
        domain: Domain,
        promotions: Promotion.Set,

        pub fn init(
            production: u16,
            moves: u8,
            melee: u8,
            ranged: u8,
            range: u8,
            sight: u8,
            domain: Domain,
            promotions: Promotion.Set,
        ) Stats {
            return Stats{
                .production = production,
                .moves = moves,
                .melee = melee,
                .ranged = ranged,
                .range = range,
                .sight = sight,
                .domain = domain,
                .promotions = promotions,
            };
        }
    };

    pub fn stats(self: UnitType, rules: *const Rules) Stats {
        return rules.unit_type_stats[@intFromEnum(self)];
    }

    pub fn name(self: UnitType, rules: *const Rules) []const u8 {
        const start = rules.unit_type_names[@intFromEnum(self)];
        const end = rules.unit_type_names[@intFromEnum(self) + 1];
        return rules.unit_type_strings[start..end];
    }
};

// Parsing

const Tile = struct {
    unpacked: Terrain.Unpacked,

    attributes: Terrain.Attributes,
    yield: Yield,
    happiness: u8,
    combat_bonus: i8,

    pub fn normalize(self: *Tile) void {
        self.attributes.has_river =
            self.attributes.has_river or
            self.unpacked.has_river;

        self.attributes.has_freshwater =
            self.attributes.has_freshwater or
            self.unpacked.has_freshwater or
            self.attributes.has_river;

        self.unpacked.has_river = self.attributes.has_river;
        self.unpacked.has_freshwater = self.attributes.has_freshwater;
    }
};

const TerrainMaps = struct {
    pub const FlagIndexMap = flag_index_map.FlagIndexMap(32);

    base: FlagIndexMap,
    feature: FlagIndexMap,
    vegetation: FlagIndexMap,

    pub fn init(allocator: std.mem.Allocator) TerrainMaps {
        return .{
            .base = FlagIndexMap.init(allocator),
            .feature = FlagIndexMap.init(allocator),
            .vegetation = FlagIndexMap.init(allocator),
        };
    }

    pub fn deinit(self: *TerrainMaps) void {
        self.vegetation.deinit();
        self.feature.deinit();
        self.base.deinit();
    }
};

pub fn parse(rules_dir: std.fs.Dir, allocator: std.mem.Allocator) !Rules {
    var rules: Rules = undefined;

    rules.arena = std.heap.ArenaAllocator.init(allocator);
    errdefer rules.arena.deinit();

    var terrain_file = try rules_dir.openFile("terrain.json", .{});
    defer terrain_file.close();

    var terrain = try parseTerrain(terrain_file, &rules, allocator);
    defer {
        terrain.maps.deinit();
        allocator.free(terrain.tiles);
    }

    var resources_file = try rules_dir.openFile("resources.json", .{});
    defer resources_file.close();

    var resource_map = try parseResources(resources_file, &rules, allocator);
    defer resource_map.deinit();

    var improvements_file = try rules_dir.openFile("improvements.json", .{});
    defer improvements_file.close();

    try parseImprovements(
        improvements_file,
        &rules,
        terrain.tiles,
        &terrain.maps,
        &resource_map,
        allocator,
    );

    var promotions_file = try rules_dir.openFile("promotions.json", .{});
    defer promotions_file.close();

    var promotion_map = try parsePromotions(promotions_file, &rules, allocator);
    defer promotion_map.deinit();

    var units_file = try rules_dir.openFile("units.json", .{});
    defer units_file.close();

    try parseUnits(units_file, &rules, &promotion_map, allocator);

    return rules;
}

fn parseTerrain(
    file: std.fs.File,
    rules: *Rules,
    allocator: std.mem.Allocator,
) !struct {
    tiles: []const Tile,
    maps: TerrainMaps,
} {
    const JsonBase = struct {
        name: []const u8,
        yield: Yield = .{},
        happiness: u8 = 0,

        attributes: Terrain.Attributes = .{},
        combat_bonus: i8 = 0,
    };

    const JsonFeature = struct {
        name: []const u8,
        yield: Yield = .{},

        bases: []const []const u8,

        attributes: Terrain.Attributes = .{},
        combat_bonus: i8 = 0,
    };

    const JsonVegetation = struct {
        name: []const u8,
        yield: Yield = .{},

        bases: []const []const u8,
        features: []const []const u8 = &.{},

        attributes: Terrain.Attributes = .{},
        combat_bonus: i8 = 0,
    };

    const JsonOverride = struct {
        name: ?[]const u8 = null,
        yield: ?Yield = null,
        happiness: u8 = 0,

        base: []const u8,
        feature: ?[]const u8 = null,
        vegetation: ?[]const u8 = null,

        attributes: Terrain.Attributes = .{},
        combat_bonus: i8 = 0,
    };

    const json_text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(json_text);

    const parsed = try std.json.parseFromSlice(struct {
        bases: []const JsonBase,
        features: []const JsonFeature,
        vegetation: []const JsonVegetation,
        overrides: []const JsonOverride,
    }, allocator, json_text, .{});
    defer parsed.deinit();

    const terrain = parsed.value;

    const arena_allocator = rules.arena.allocator();

    rules.base_count = terrain.bases.len;
    rules.feature_count = terrain.features.len + 1; // +1 = none
    rules.vegetation_count = terrain.vegetation.len + 1; // +1 = none

    const strings_len = blk: {
        var strings_len: usize = 0;
        for (terrain.bases) |base| {
            strings_len += base.name.len;
        }

        for (terrain.features) |feature| {
            strings_len += feature.name.len;
        }

        for (terrain.vegetation) |vegetation| {
            strings_len += vegetation.name.len;
        }
        break :blk strings_len;
    };

    std.debug.assert(strings_len <= std.math.maxInt(u16));

    const terrain_strings = try arena_allocator.alloc(u8, strings_len);
    const base_names = try arena_allocator.alloc(u16, rules.base_count + 1);
    const feature_names = try arena_allocator.alloc(u16, rules.feature_count + 1);
    const vegetation_names = try arena_allocator.alloc(u16, rules.vegetation_count + 1);
    {
        var i: usize = 0;
        for (terrain.bases, 0..) |base, base_index| {
            std.mem.copyForwards(u8, terrain_strings[i..(i + base.name.len)], base.name);
            base_names[base_index] = @truncate(i);
            i += base.name.len;
        }
        base_names[base_names.len - 1] = @truncate(i);

        feature_names[0] = @truncate(i);
        for (terrain.features, 1..) |feature, feature_index| {
            std.mem.copyForwards(u8, terrain_strings[i..(i + feature.name.len)], feature.name);
            feature_names[feature_index] = @truncate(i);
            i += feature.name.len;
        }
        feature_names[feature_names.len - 1] = @truncate(i);

        vegetation_names[0] = @truncate(i);
        for (terrain.vegetation, 1..) |vegetation, vegetation_index| {
            std.mem.copyForwards(u8, terrain_strings[i..(i + vegetation.name.len)], vegetation.name);
            vegetation_names[vegetation_index] = @truncate(i);
            i += vegetation.name.len;
        }
        vegetation_names[vegetation_names.len - 1] = @truncate(i);
    }

    rules.terrain_strings = terrain_strings;
    rules.base_names = base_names.ptr;
    rules.feature_names = feature_names.ptr;
    rules.vegetation_names = vegetation_names.ptr;

    var tiles = std.ArrayListUnmanaged(Tile){};
    errdefer tiles.deinit(allocator);

    var maps = TerrainMaps.init(allocator);
    errdefer maps.deinit();

    // Add base tiles
    for (terrain.bases, 0..) |base, base_index| {
        const base_enum: Terrain.Base = @enumFromInt(base_index);
        _ = try maps.base.add(base_enum.name(rules));
        try tiles.append(allocator, .{
            .unpacked = .{
                .base = @enumFromInt(base_index),
                .has_river = base.attributes.has_river,
                .has_freshwater = base.attributes.has_freshwater or base.attributes.has_river,
            },
            .attributes = base.attributes,
            .yield = base.yield,
            .happiness = base.happiness,
            .combat_bonus = base.combat_bonus,
        });
    }

    // Add feature tiles
    {
        _ = try maps.feature.add("none");
        const tiles_len = tiles.items.len;
        for (terrain.features, 1..) |feature, feature_index| {
            const feature_enum: Terrain.Feature = @enumFromInt(feature_index);
            _ = try maps.feature.add(feature_enum.name(rules));
            const allowed_bases = maps.base.flagsFromKeys(feature.bases);
            for (0..tiles_len) |tile_index| {
                const tile = tiles.items[tile_index];
                if (!allowed_bases.isSet(@intFromEnum(tile.unpacked.base))) continue;

                var new_tile = tile;
                new_tile.unpacked.feature = @enumFromInt(feature_index);
                inline for (@typeInfo(Terrain.Attributes).Struct.fields) |field| {
                    @field(new_tile.attributes, field.name) =
                        @field(tile.attributes, field.name) or
                        @field(feature.attributes, field.name);
                }
                new_tile.normalize();
                new_tile.yield = feature.yield;
                new_tile.unpacked.feature = @enumFromInt(feature_index);
                new_tile.combat_bonus = feature.combat_bonus;
                try tiles.append(allocator, new_tile);
            }
        }
    }

    // Add vegetation tiles
    {
        _ = try maps.vegetation.add("none");
        const tiles_len = tiles.items.len;
        for (terrain.vegetation, 1..) |vegetation, vegetation_index| {
            const vegetation_enum: Terrain.Vegetation = @enumFromInt(vegetation_index);
            _ = try maps.vegetation.add(vegetation_enum.name(rules));

            const allowed_bases = maps.base.flagsFromKeys(vegetation.bases);
            const allowed_features = maps.feature.flagsFromKeys(vegetation.features);

            for (0..tiles_len) |tile_index| {
                const tile = tiles.items[tile_index];
                if (!allowed_bases.isSet(@intFromEnum(tile.unpacked.base))) continue;
                if (tile.unpacked.feature != .none and !allowed_features.isSet(@intFromEnum(tile.unpacked.feature))) continue;

                var new_tile = tile;
                new_tile.unpacked.vegetation = @enumFromInt(vegetation_index);
                inline for (@typeInfo(Terrain.Attributes).Struct.fields) |field| {
                    @field(new_tile.attributes, field.name) =
                        @field(tile.attributes, field.name) or
                        @field(vegetation.attributes, field.name);
                }
                new_tile.normalize();
                new_tile.yield = vegetation.yield;
                new_tile.unpacked.vegetation = @enumFromInt(vegetation_index);
                new_tile.combat_bonus = vegetation.combat_bonus;
                try tiles.append(allocator, new_tile);
            }
        }
    }

    // Add river and freshwater attribute tiles
    {
        for (0..tiles.items.len) |tile_index| {
            const tile = tiles.items[tile_index];
            if (tile.attributes.is_water or (tile.attributes.has_river and tile.attributes.has_freshwater)) continue;

            var new_tile = tile;
            new_tile.attributes.has_river = true;
            new_tile.attributes.has_freshwater = true;
            new_tile.normalize();
            try tiles.append(allocator, new_tile);
        }

        for (0..tiles.items.len) |tile_index| {
            const tile = tiles.items[tile_index];
            if (tile.attributes.is_water or tile.attributes.has_freshwater) continue;

            var new_tile = tile;
            new_tile.attributes.has_freshwater = true;
            new_tile.normalize();
            try tiles.append(allocator, new_tile);
        }
    }

    std.debug.assert(tiles.items.len <= 256);

    rules.terrain_count = tiles.items.len;
    const terrain_bases = try arena_allocator.alloc(Terrain.Base, tiles.items.len);
    const terrain_features = try arena_allocator.alloc(Terrain.Feature, tiles.items.len);
    const terrain_vegetation = try arena_allocator.alloc(Terrain.Vegetation, tiles.items.len);
    const terrain_yields = try arena_allocator.alloc(Yield, tiles.items.len);
    const terrain_attributes = try arena_allocator.alloc(Terrain.Attributes, tiles.items.len);
    const terrain_happiness = try arena_allocator.alloc(u8, tiles.items.len);
    const terrain_combat_bonus = try arena_allocator.alloc(i8, tiles.items.len);
    var terrain_unpacked_map: @TypeOf(rules.terrain_unpacked_map) = .{};
    try terrain_unpacked_map.ensureUnusedCapacity(arena_allocator, @intCast(rules.terrain_count));
    for (tiles.items, 0..) |tile, tile_index| {
        terrain_bases[tile_index] = tile.unpacked.base;
        terrain_features[tile_index] = tile.unpacked.feature;
        terrain_vegetation[tile_index] = tile.unpacked.vegetation;
        terrain_yields[tile_index] = tile.yield;
        terrain_attributes[tile_index] = tile.attributes;
        terrain_happiness[tile_index] = tile.happiness;
        terrain_combat_bonus[tile_index] = tile.combat_bonus;
        terrain_unpacked_map.putAssumeCapacity(tile.unpacked, @enumFromInt(tile_index));
    }

    rules.terrain_bases = terrain_bases.ptr;
    rules.terrain_features = terrain_features.ptr;
    rules.terrain_vegetation = terrain_vegetation.ptr;
    rules.terrain_yields = terrain_yields.ptr;
    rules.terrain_attributes = terrain_attributes.ptr;
    rules.terrain_happiness = terrain_happiness.ptr;
    rules.terrain_combat_bonus = terrain_combat_bonus.ptr;
    rules.terrain_unpacked_map = terrain_unpacked_map;

    return .{
        .tiles = try tiles.toOwnedSlice(allocator),
        .maps = maps,
    };
}

fn parseResources(
    file: std.fs.File,
    rules: *Rules,
    allocator: std.mem.Allocator,
) !std.StringArrayHashMap(Resource) {
    const JsonResource = struct {
        name: []const u8,
        yield: Yield = .{},
        bases: []const []const u8 = &.{},
        features: []const []const u8 = &.{},
        vegetation: []const []const u8 = &.{},
    };

    const json_text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(json_text);

    const parsed = try std.json.parseFromSlice(struct {
        bonus: []const JsonResource,
        strategic: []const JsonResource,
        luxury: []const JsonResource,
    }, allocator, json_text, .{});
    defer parsed.deinit();

    const resources = parsed.value;

    const arena_allocator = rules.arena.allocator();

    rules.resource_count =
        resources.bonus.len +
        resources.strategic.len +
        resources.luxury.len;

    std.debug.assert(rules.resource_count <= 256);

    const resource_kinds = try arena_allocator.alloc(Resource.Kind, rules.resource_count);
    const resource_yields = try arena_allocator.alloc(Yield, rules.resource_count);
    const resource_names = try arena_allocator.alloc(u16, rules.resource_count + 1);

    const strings_len = blk: {
        var strings_len: usize = 0;
        for (resources.bonus) |resource| {
            strings_len += resource.name.len;
        }

        for (resources.strategic) |resource| {
            strings_len += resource.name.len;
        }

        for (resources.luxury) |resource| {
            strings_len += resource.name.len;
        }
        break :blk strings_len;
    };

    std.debug.assert(strings_len <= std.math.maxInt(u16));
    const resource_strings = try arena_allocator.alloc(u8, strings_len);

    var resource_map = std.StringArrayHashMap(Resource).init(allocator);
    errdefer resource_map.deinit();
    try resource_map.ensureUnusedCapacity(rules.resource_count);

    {
        var string_index: usize = 0;
        var resource_index: usize = 0;
        for (resources.bonus) |resource| {
            const name = resource_strings[string_index..(string_index + resource.name.len)];
            std.mem.copyForwards(
                u8,
                name,
                resource.name,
            );
            resource_names[resource_index] = @truncate(string_index);
            string_index += resource.name.len;

            resource_map.putAssumeCapacity(name, @enumFromInt(resource_index));
            resource_yields[resource_index] = resource.yield;
            resource_kinds[resource_index] = .bonus;

            resource_index += 1;
        }

        for (resources.strategic) |resource| {
            const name = resource_strings[string_index..(string_index + resource.name.len)];
            std.mem.copyForwards(
                u8,
                name,
                resource.name,
            );
            resource_names[resource_index] = @truncate(string_index);
            string_index += resource.name.len;

            resource_map.putAssumeCapacity(name, @enumFromInt(resource_index));
            resource_yields[resource_index] = resource.yield;
            resource_kinds[resource_index] = .strategic;

            resource_index += 1;
        }

        for (resources.luxury) |resource| {
            const name = resource_strings[string_index..(string_index + resource.name.len)];
            std.mem.copyForwards(
                u8,
                name,
                resource.name,
            );
            resource_names[resource_index] = @truncate(string_index);
            string_index += resource.name.len;

            resource_map.putAssumeCapacity(name, @enumFromInt(resource_index));
            resource_yields[resource_index] = resource.yield;
            resource_kinds[resource_index] = .luxury;

            resource_index += 1;
        }
        resource_names[resource_names.len - 1] = @truncate(string_index);
    }

    rules.resource_kinds = resource_kinds.ptr;
    rules.resource_yields = resource_yields.ptr;
    rules.resource_names = resource_names.ptr;
    rules.resource_strings = resource_strings;

    return resource_map;
}

fn parseImprovements(
    file: std.fs.File,
    rules: *Rules,
    terrain_tiles: []const Tile,
    terrain_maps: *const TerrainMaps,
    resource_map: *const std.StringArrayHashMap(Resource),
    allocator: std.mem.Allocator,
) !void {
    const JsonBuilding = struct {
        name: []const u8,
        build_turns: u8,
        allow_on: struct {
            resources: []const []const u8 = &.{},
            bases: []struct {
                name: []const u8,
                no_feature: bool = false,
                required_attributes: Terrain.Attributes = .{},
            } = &.{},
            features: []struct {
                name: []const u8,
                required_attributes: Terrain.Attributes = .{},
            } = &.{},
            vegetation: []struct {
                name: []const u8,
                required_attributes: Terrain.Attributes = .{},
            } = &.{},
        },
        yield: Yield = .{},
    };

    const json_text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(json_text);

    const parsed = try std.json.parseFromSlice(struct {
        buildings: []const JsonBuilding,
    }, allocator, json_text, .{});
    defer parsed.deinit();

    const buildings = parsed.value.buildings;

    const arena_allocator = rules.arena.allocator();

    std.debug.assert(buildings.len <= 256);

    rules.building_count = buildings.len + 1;

    const building_yields = try arena_allocator.alloc(Yield, rules.building_count);
    const building_names = try arena_allocator.alloc(u16, rules.building_count + 1);

    const strings_len = blk: {
        var strings_len: usize = 0;
        for (buildings) |building| {
            strings_len += building.name.len;
        }
        break :blk strings_len;
    };

    std.debug.assert(strings_len <= std.math.maxInt(u16));
    const building_strings = try arena_allocator.alloc(u8, strings_len);

    const resource_connectors = try arena_allocator.alloc(Building, rules.resource_count);
    {
        var string_index: usize = 0;
        building_names[0] = @truncate(string_index);
        for (buildings, 1..) |building, building_index| {
            std.mem.copyForwards(
                u8,
                building_strings[string_index..(string_index + building.name.len)],
                building.name,
            );
            building_names[building_index] = @truncate(string_index);
            string_index += building.name.len;

            building_yields[building_index] = building.yield;

            // TODO: Make sure each resource only has one connector building
            for (building.allow_on.resources) |resource_name| {
                const resource = resource_map.get(resource_name) orelse return error.UnknownResource;
                resource_connectors[@intFromEnum(resource)] = @enumFromInt(building_index);
            }
        }
        building_names[building_names.len - 1] = @truncate(string_index);
    }

    rules.building_strings = building_strings;
    rules.building_yields = building_yields.ptr;
    rules.building_names = building_names.ptr;
    rules.resource_connectors = resource_connectors.ptr;

    var allowed_on_map: @TypeOf(rules.building_allowed_map) = .{};
    defer allowed_on_map.deinit(allocator);

    for (buildings, 0..) |building, building_index| {
        const building_enum: Building = @enumFromInt(building_index + 1);

        const veg_flags = blk: {
            var flags = TerrainMaps.FlagIndexMap.Flags.initEmpty();
            for (building.allow_on.vegetation) |vegetation| {
                flags.set(terrain_maps.vegetation.get(vegetation.name) orelse return error.UnknownVegetation);
            }
            break :blk flags;
        };

        terrain_loop: for (terrain_tiles, 0..) |tile, terrain_index| {
            const terrain: Terrain = @enumFromInt(terrain_index);

            const tag: Building.Allowed = if (veg_flags.isSet(@intFromEnum(tile.unpacked.vegetation))) .allowed else .allowed_after_clear;

            for (building.allow_on.bases) |base| {
                const base_enum: Terrain.Base = @enumFromInt(
                    terrain_maps.base.get(base.name) orelse return error.UnknownBase,
                );
                if (tile.unpacked.base != base_enum) continue;

                if (base.no_feature and tile.unpacked.feature != .none) continue;

                if (!tile.attributes.intersectWith(base.required_attributes).eql(base.required_attributes)) continue;

                try allowed_on_map.put(allocator, .{
                    .building = building_enum,
                    .terrain = terrain,
                }, tag);

                continue :terrain_loop;
            }

            for (building.allow_on.features) |feature| {
                if (tile.unpacked.feature == .none) continue;

                const feature_enum: Terrain.Feature = @enumFromInt(
                    terrain_maps.feature.get(feature.name) orelse return error.UnknownFeature,
                );
                if (tile.unpacked.feature != feature_enum) continue;

                if (!tile.attributes.intersectWith(feature.required_attributes).eql(feature.required_attributes)) continue;

                try allowed_on_map.put(allocator, .{
                    .building = building_enum,
                    .terrain = terrain,
                }, tag);
                continue :terrain_loop;
            }

            for (building.allow_on.vegetation) |vegetation| {
                const vegetation_enum: Terrain.Vegetation = @enumFromInt(
                    terrain_maps.vegetation.get(vegetation.name) orelse return error.UnknownVegetation,
                );
                if (tile.unpacked.vegetation == .none) continue;
                if (tile.unpacked.vegetation != vegetation_enum) continue;

                if (!tile.attributes.intersectWith(vegetation.required_attributes).eql(vegetation.required_attributes)) continue;

                try allowed_on_map.put(allocator, .{
                    .building = building_enum,
                    .terrain = terrain,
                }, .allowed);

                continue :terrain_loop;
            }

            if (tile.unpacked.vegetation != .none and building.allow_on.resources.len != 0) {
                try allowed_on_map.put(allocator, .{
                    .building = building_enum,
                    .terrain = terrain,
                }, switch (tag) {
                    .allowed => .allowed_if_resource,
                    .allowed_after_clear => .allowed_after_clear_if_resource,
                    else => unreachable,
                });
            }
        }
    }

    rules.building_allowed_map = try allowed_on_map.clone(arena_allocator);
}

fn parsePromotions(
    file: std.fs.File,
    rules: *Rules,
    allocator: std.mem.Allocator,
) !flag_index_map.FlagIndexMap(256) {
    const Effect = struct {
        effect: Promotion.Effect,
        value: u32 = 0,
    };

    const JsonPromotion = struct {
        name: []const u8,
        requires: []const []const u8 = &.{}, // Seem to only be either of the listed, never 2 different
        effects: []const Effect = &.{},
    };

    const json_text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(json_text);

    const parsed = try std.json.parseFromSlice(struct {
        promotions: []const JsonPromotion,
    }, allocator, json_text, .{});
    defer parsed.deinit();

    const promotions = parsed.value.promotions;

    rules.promotion_count = promotions.len;

    std.debug.assert(rules.promotion_count <= 256);

    const arena_allocator = rules.arena.allocator();

    var promotion_map = flag_index_map.FlagIndexMap(256).init(allocator);
    errdefer promotion_map.deinit();

    const strings_len = blk: {
        var strings_len: usize = 0;
        for (promotions) |promotion| {
            strings_len += promotion.name.len;
        }
        break :blk strings_len;
    };

    const promotion_strings = try arena_allocator.alloc(u8, strings_len);
    const promotion_names = try arena_allocator.alloc(u16, rules.promotion_count + 1);

    {
        var string_index: usize = 0;
        for (promotions, 0..) |promotion, promotion_index| {
            const name = promotion_strings[string_index..(string_index + promotion.name.len)];
            std.mem.copyForwards(
                u8,
                name,
                promotion.name,
            );
            promotion_names[promotion_index] = @truncate(string_index);
            _ = try promotion_map.add(name);
            string_index += promotion.name.len;
        }
        promotion_names[promotion_names.len - 1] = @truncate(string_index);
    }

    {
        const promotion_storage = try arena_allocator.alloc(Promotion, blk: {
            var promotion_storage_len: usize = 0;
            for (promotions) |promotion| {
                promotion_storage_len += promotion.requires.len;
            }
            break :blk promotion_storage_len;
        });

        var promotion_storage_index: usize = 0;

        const promotion_prerequisites = try arena_allocator.alloc(u16, rules.promotion_count + 1);

        for (promotions, 0..) |promotion, promotion_index| {
            promotion_prerequisites[promotion_index] = @truncate(promotion_storage_index);
            for (promotion.requires) |prereq| {
                const prereq_promotion = promotion_map.get(prereq) orelse return error.UnknownPromotion;

                promotion_storage[promotion_storage_index] = @enumFromInt(prereq_promotion);
                promotion_storage_index += 1;
            }
        }
        promotion_prerequisites[promotion_prerequisites.len - 1] = @truncate(promotion_storage_index);

        rules.promotion_prerequisites = promotion_prerequisites.ptr;
        rules.promotion_storage = promotion_storage.ptr;
    }

    {
        var effects = [_]std.ArrayListUnmanaged(struct {
            value: u32,
            promotions: Promotion.Set = Promotion.Set.initEmpty(),
        }){.{}} ** std.meta.fields(Promotion.Effect).len;
        defer {
            for (&effects) |*effect| {
                effect.deinit(allocator);
            }
        }

        var storage_required: usize = 0;
        for (promotions, 0..) |promotion, promotion_index| {
            effects_loop: for (promotion.effects) |effect| {
                const effect_variants = &effects[@intFromEnum(effect.effect)];
                for (effect_variants.items) |*variant| {
                    if (variant.value != effect.value) continue;

                    variant.promotions.set(promotion_index);
                    continue :effects_loop;
                }

                try effect_variants.append(allocator, .{ .value = effect.value });
                effect_variants.items[effect_variants.items.len - 1].promotions.set(promotion_index);
                storage_required += 1;
            }
        }

        const effect_promotions = try arena_allocator.alloc(Promotion.Set, storage_required);
        const effect_values = try arena_allocator.alloc(u32, storage_required);

        var storage_index: usize = 0;
        for (effects, 0..) |effect, effect_index| {
            rules.effects[effect_index] = @truncate(storage_index);
            for (effect.items) |promotions_value| {
                effect_values[storage_index] = promotions_value.value;
                effect_promotions[storage_index] = promotions_value.promotions;
                storage_index += 1;
            }
        }
        rules.effects[rules.effects.len - 1] = @truncate(storage_index);

        rules.effect_values = effect_values.ptr;
        rules.effect_promotions = effect_promotions.ptr;
    }

    return promotion_map;
}

fn parseUnits(
    file: std.fs.File,
    rules: *Rules,
    promotion_map: *const flag_index_map.FlagIndexMap(256),
    allocator: std.mem.Allocator,
) !void {
    const JsonUnitType = struct {
        name: []const u8,
        production_cost: u16, // Max cost, Nuclear Missile 1000
        moves: u8, // Max movement, Nuclear Sub etc. 6
        combat_strength: u8 = 0, // Max combat strength, Giant Death Robot 150
        ranged_strength: u8 = 0,
        range: u8 = 0, // Max range, Nuclear Missile 12
        sight: u8 = 2, // Max 10 = 2 + 4 promotions + 1 scout + 1 nation + 1 Exploration + 1 Great Lighthouse
        domain: UnitType.Domain,
        starting_promotions: []const []const u8 = &.{},
    };

    const json_text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(json_text);

    const parsed = try std.json.parseFromSlice(struct {
        civilian: []const JsonUnitType,
        land: []const JsonUnitType,
        naval: []const JsonUnitType,
    }, allocator, json_text, .{});
    defer parsed.deinit();

    const units = parsed.value;

    rules.unit_type_count = units.civilian.len + units.land.len + units.naval.len;

    std.debug.assert(rules.unit_type_count <= 256);

    const arena_allocator = rules.arena.allocator();

    const strings_len = blk: {
        var strings_len: usize = 0;
        for (units.civilian) |unit| {
            strings_len += unit.name.len;
        }
        for (units.land) |unit| {
            strings_len += unit.name.len;
        }
        for (units.naval) |unit| {
            strings_len += unit.name.len;
        }
        break :blk strings_len;
    };

    const unit_strings = try arena_allocator.alloc(u8, strings_len);
    const unit_names = try arena_allocator.alloc(u16, rules.unit_type_count + 1);
    const unit_stats = try arena_allocator.alloc(UnitType.Stats, rules.unit_type_count);

    {
        var string_index: usize = 0;
        var unit_index: usize = 0;
        inline for (&[_][]const u8{ "civilian", "land", "naval" }) |field_name| {
            for (@field(units, field_name)) |promotion| {
                const name = unit_strings[string_index..(string_index + promotion.name.len)];
                std.mem.copyForwards(
                    u8,
                    name,
                    promotion.name,
                );

                unit_stats[unit_index] = .{
                    .production = promotion.production_cost,
                    .moves = promotion.moves,
                    .melee = promotion.combat_strength,
                    .ranged = promotion.ranged_strength,
                    .range = promotion.range,
                    .sight = promotion.sight,
                    .domain = promotion.domain,
                    .promotions = promotion_map.flagsFromKeys(promotion.starting_promotions),
                };

                unit_names[unit_index] = @truncate(string_index);
                string_index += promotion.name.len;
                unit_index += 1;
            }
        }

        unit_names[unit_names.len - 1] = @truncate(string_index);
    }

    rules.unit_type_stats = unit_stats.ptr;
    rules.unit_type_names = unit_names.ptr;
    rules.unit_type_strings = unit_strings;
}
