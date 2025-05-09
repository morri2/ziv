const std = @import("std");

const Rules = @This();

arena: std.heap.ArenaAllocator,

base_count: u32,
feature_count: u32,
vegetation_count: u32,
base_names: []const u16,
feature_names: []const u16,
vegetation_names: []const u16,
terrain_strings: []const u8,

terrain_count: u32,
terrain_bases: []const Terrain.Base,
terrain_features: []const Terrain.Feature,
terrain_vegetation: []const Terrain.Vegetation,
terrain_attributes: []const Terrain.Attributes,
terrain_yields: []const Yield,
terrain_happiness: []const u8,
terrain_combat_bonus: []const i8,
terrain_no_vegetation: []const Terrain,
terrain_unpacked_map: std.AutoHashMapUnmanaged(Terrain.Unpacked, Terrain),
terrain_names: []const u16,

resource_count: u32,
resource_kinds: []const Resource.Kind,
resource_yields: []const Yield,
resource_names: []const u16,
resource_strings: []const u8,

improvement_count: u32,
improvement_yields: []const Yield,
improvement_allowed_map: std.AutoHashMapUnmanaged(struct {
    improvement: Improvement,
    terrain: Terrain,
}, Improvement.Allowed),
improvement_resource_connectors: std.AutoHashMapUnmanaged(struct {
    improvement: Improvement,
    resource: Resource,
}, void),

improvement_resource_yields: std.AutoHashMapUnmanaged(struct {
    improvement: Improvement,
    resource: Resource,
}, Yield),
improvement_names: []const u16,
improvement_strings: []const u8,

promotion_count: u32,
promotion_prerequisites: []const u16,
promotion_storage: []const Promotion,

promotion_names: []const u16,
promotion_strings: []const u8,

effects: [std.meta.fields(Promotion.Effect).len + 1]u16,
effect_promotions: []const Promotion.Set, // TODO: compress bit field
effect_values: []const u32,

unit_type_count: u32,
unit_type_stats: []const UnitType.Stats,
unit_type_is_military: std.DynamicBitSetUnmanaged,

unit_type_names: []const u16,
unit_type_strings: []const u8,

pub const parse = @import("RuleGen.zig").parse;

pub fn deinit(self: *Rules) void {
    self.arena.deinit();
}

pub const Yield = packed struct {
    pub const Integer = @typeInfo(Yield).Struct.backing_integer.?;

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

    pub const Attributes = packed struct(u10) {
        pub const Integer = @typeInfo(Attributes).@"struct".backing_integer.?;

        is_water: bool = false,
        is_deep_water: bool = false,
        is_freshwater: bool = false,
        is_impassable: bool = false,
        is_rough: bool = false,
        is_wonder: bool = false,
        has_river: bool = false,
        has_freshwater: bool = false,
        is_elevated: bool = false,
        is_obscuring: bool = false,

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

    pub fn withoutVegetation(self: Terrain, rules: *const Rules) Terrain {
        return rules.terrain_no_vegetation[@intFromEnum(self)];
    }

    pub fn name(self: Terrain, rules: *const Rules) []const u8 {
        const start = rules.terrain_names[@intFromEnum(self)];
        const end = rules.terrain_names[@intFromEnum(self) + 1];
        return rules.terrain_strings[start..end];
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

    pub fn name(self: Resource, rules: *const Rules) []const u8 {
        const start = rules.resource_names[@intFromEnum(self)];
        const end = rules.resource_names[@intFromEnum(self) + 1];
        return rules.resource_strings[start..end];
    }
};

pub const Improvement = enum(u8) {
    none = 0,
    _,

    pub const Allowed = enum(u8) {
        not_allowed = 0,
        allowed = 1,
        allowed_after_clear = 2,
        allowed_if_resource = 3,
        allowed_after_clear_if_resource = 4,
    };

    pub fn yield(self: Improvement, resource: ?Resource, rules: *const Rules) Yield {
        var y = self.improvementYield(rules);
        if (resource) |r| y = y.add(self.improvedResourceYield(r, rules));
        return y;
    }

    pub fn improvementYield(self: Improvement, rules: *const Rules) Yield {
        return rules.improvement_yields[@intFromEnum(self)];
    }

    pub fn improvedResourceYield(self: Improvement, resource: Resource, rules: *const Rules) Yield {
        return rules.improvement_resource_yields.get(.{
            .improvement = self,
            .resource = resource,
        }) orelse .{};
    }

    pub fn allowedOn(
        self: Improvement,
        terrain: Terrain,
        rules: *const Rules,
    ) Allowed {
        return rules.improvement_allowed_map.get(.{
            .terrain = terrain,
            .improvement = self,
        }) orelse .not_allowed;
    }

    pub fn connectsResource(self: Improvement, resource: Resource, rules: *const Rules) bool {
        return rules.improvement_resource_connectors.contains(.{
            .improvement = self,
            .resource = resource,
        });
    }

    pub fn name(self: Improvement, rules: *const Rules) []const u8 {
        const start = rules.improvement_names[@intFromEnum(self)];
        const end = rules.improvement_names[@intFromEnum(self) + 1];
        return rules.improvement_strings[start..end];
    }
};

pub const Transport = enum(u2) {
    none = 0,
    road = 1,
    rail = 2,
};

pub const Improvements = packed struct(u12) {
    improvement: Improvement = .none,
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
        can_cross_ocean = 17,
        rough_terrain_penalty = 18,
        no_terrain_defense = 19,
        charge = 20, // #charges
        charge_to_improve = 21,

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

        pub fn promotionsSum(self: Effect, promotions: Promotion.Set, rules: *const Rules) u32 {
            var sum: u32 = 0;
            var effect_promotions_it = Promotion.Effect.Iterator.init(self);
            while (effect_promotions_it.next(rules)) |variant| {
                const u = variant.promotions.intersectWith(promotions);
                sum += @as(u32, @truncate(u.count())) * variant.value;
            }
            return sum;
        }

        pub fn promotionsWith(self: Effect, rules: *const Rules) Promotion.Set {
            var promotions = Promotion.Set.initEmpty();
            var effect_promotions_it = Promotion.Effect.Iterator.init(self);
            while (effect_promotions_it.next(rules)) |variant| {
                promotions = promotions.unionWith(variant.promotions);
            }
            return promotions;
        }

        pub fn in(self: Effect, promotions: Promotion.Set, rules: *const Rules) bool {
            var effect_promotions_it = Promotion.Effect.Iterator.init(self);
            while (effect_promotions_it.next(rules)) |variant| {
                if (promotions.intersectWith(variant.promotions).count() != 0) return true;
            }
            return false;
        }
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

    pub const ResourceCost = struct {
        resource: Resource,
        amount: u32 = 0,
    };

    pub const Domain = enum(u1) {
        land = 0,
        sea = 1,
    };

    pub const Type = enum(u1) {
        civilian = 0,
        military = 1,
    };

    pub const Stats = struct {
        production: u16, // Max cost, Nuclear Missile 1000
        resource_cost: []const ResourceCost,
        moves: u8, // Max movement, Nuclear Sub etc. 6
        melee: u8, // Max combat strength, Giant Death Robot 150
        ranged: u8,
        range: u8, // Max range, Nuclear Missile 12
        sight: u8, // Max 10 = 2 + 4 promotions + 1 scout + 1 nation + 1 Exploration + 1 Great Lighthouse
        domain: Domain,
        promotions: Promotion.Set,
    };

    pub fn stats(self: UnitType, rules: *const Rules) Stats {
        return rules.unit_type_stats[@intFromEnum(self)];
    }

    pub fn ty(self: UnitType, rules: *const Rules) Type {
        return if (rules.unit_type_is_military.isSet(@intFromEnum(self))) .military else .civilian;
    }

    pub fn name(self: UnitType, rules: *const Rules) []const u8 {
        const start = rules.unit_type_names[@intFromEnum(self)];
        const end = rules.unit_type_names[@intFromEnum(self) + 1];
        return rules.unit_type_strings[start..end];
    }
};

const rules_serialization = @import("serialization.zig").customSerialization(&.{
    // Terrain
    .{ .name = "base_count" },
    .{ .name = "base_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "base_count",
        .extra = 1,
    } } },
    .{ .name = "feature_count" },
    .{ .name = "feature_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "feature_count",
        .extra = 1,
    } } },
    .{ .name = "vegetation_count" },
    .{ .name = "vegetation_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "vegetation_count",
        .extra = 1,
    } } },

    .{ .name = "terrain_count" },
    .{ .name = "terrain_bases", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_features", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_vegetation", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_attributes", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_yields", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_happiness", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_combat_bonus", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_no_vegetation", .ty = .{ .slice_with_len = "terrain_count" } },
    .{ .name = "terrain_unpacked_map", .ty = .{ .hash_map_with_len = "terrain_count" } },
    .{ .name = "terrain_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "terrain_count",
        .extra = 1,
    } } },
    .{ .name = "terrain_strings" },

    // Resources
    .{ .name = "resource_count" },
    .{ .name = "resource_kinds", .ty = .{ .slice_with_len = "resource_count" } },
    .{ .name = "resource_yields", .ty = .{ .slice_with_len = "resource_count" } },
    .{ .name = "resource_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "resource_count",
        .extra = 1,
    } } },
    .{ .name = "resource_strings" },

    // Improvements
    .{ .name = "improvement_count" },
    .{ .name = "improvement_yields", .ty = .{ .slice_with_len = "improvement_count" } },
    .{ .name = "improvement_allowed_map", .ty = .hash_map },
    .{ .name = "improvement_resource_connectors", .ty = .hash_set },
    .{ .name = "improvement_resource_yields", .ty = .hash_map },
    .{ .name = "improvement_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "improvement_count",
        .extra = 1,
    } } },
    .{ .name = "improvement_strings" },

    // Promotions
    .{ .name = "promotion_count" },
    .{ .name = "promotion_prerequisites", .ty = .{ .slice_with_len_extra = .{
        .len_name = "promotion_count",
        .extra = 1,
    } } },
    .{ .name = "promotion_storage" },
    .{ .name = "promotion_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "promotion_count",
        .extra = 1,
    } } },
    .{ .name = "promotion_strings" },

    // Effects
    .{ .name = "effects" },
    .{ .name = "effect_promotions" },
    .{ .name = "effect_values" },

    // Unit types
    .{ .name = "unit_type_count" },
    .{ .name = "unit_type_stats", .ty = .{ .slice_with_len = "unit_type_count" } },
    .{ .name = "unit_type_is_military", .ty = .dynamic_bit_set_unmanaged },
    .{ .name = "unit_type_names", .ty = .{ .slice_with_len_extra = .{
        .len_name = "unit_type_count",
        .extra = 1,
    } } },
    .{ .name = "unit_type_strings" },
}, Rules);

pub fn serialize(self: Rules, writer: anytype) !void {
    try rules_serialization.serialize(writer, self);
}

pub fn deserialize(reader: anytype, allocator: std.mem.Allocator) !Rules {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    var self = try rules_serialization.deserializeAlloc(reader, arena.allocator());
    self.arena = arena;
    return self;
}
