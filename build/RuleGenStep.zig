const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;

const Self = @This();

step: Build.Step,

/// Path to rule files
rules_path: LazyPath,

/// The main Zig file that contains for the rule types
generated_file: Build.GeneratedFile,

pub fn create(
    builder: *Build,
    rules_path: LazyPath,
) *Self {
    const self = builder.allocator.create(Self) catch unreachable;
    self.* = .{
        .step = Build.Step.init(.{
            .id = .custom,
            .name = "rule_gen",
            .owner = builder,
            .makeFn = make,
        }),
        .rules_path = rules_path,
        .generated_file = undefined,
    };
    self.generated_file = .{ .step = &self.step };
    return self;
}

/// Returns the shaders module with name.
pub fn getModule(self: *Self) *Build.Module {
    return self.step.owner.createModule(.{
        .source_file = self.getSource(),
    });
}

/// Returns the file source for the generated shader resource code.
pub fn getSource(self: *Self) Build.FileSource {
    return .{ .generated = &self.generated_file };
}

/// Create a base-64 hash digest from a hasher, which we can use as file name.
fn digest(hasher: anytype) [64]u8 {
    var hash_digest: [48]u8 = undefined;
    hasher.final(&hash_digest);
    var hash: [64]u8 = undefined;
    _ = std.fs.base64_encoder.encode(&hash, &hash_digest);
    return hash;
}

fn readAndParse(
    comptime T: type,
    dir: std.fs.Dir,
    sub_path: []const u8,
    hasher: *std.crypto.hash.blake2.Blake2b384,
    allocator: std.mem.Allocator,
) !std.json.Parsed(T) {
    const file = try dir.openFile(sub_path, .{});
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(text);
    hasher.update(text);

    return try std.json.parseFromSlice(T, allocator, text, .{});
}

fn bitsFittingMax(max: usize) usize {
    const base = std.math.log2(max);
    const upper = (@as(usize, 1) << @truncate(base)) - 1;
    return if (upper >= max) base else base + 1;
}

const Flags = std.StaticBitSet(128);

const Yields = struct {
    food: u8 = 0,
    production: u8 = 0,
    gold: u8 = 0,
    culture: u8 = 0,
    science: u8 = 0,
    faith: u8 = 0,
};

fn startEnum(
    name: []const u8,
    num_elements: usize,
    writer: anytype,
) !void {
    try writer.print(
        \\pub const {s} = enum(u{}) {{
    , .{ name, bitsFittingMax(num_elements) });
}

fn endStructEnumUnion(writer: anytype) !void {
    try writer.print("}};\n\n", .{});
}

fn emitYieldsFunc(comptime T: type, arr: []const T, writer: anytype) !void {
    try writer.print(
        \\pub fn addYield(self: @This(), yield: *Yield) void {{
        \\switch(self) {{
    , .{});
    for (arr) |e| {
        try writer.print(".{s} => {{", .{e.name});
        if (e.yields.food != 0) try writer.print("yield.food += {};", .{e.yields.food});
        if (e.yields.production != 0) try writer.print("yield.production += {};", .{e.yields.production});
        if (e.yields.gold != 0) try writer.print("yield.gold += {};", .{e.yields.gold});
        if (e.yields.culture != 0) try writer.print("yield.culture += {};", .{e.yields.culture});
        if (e.yields.science != 0) try writer.print("yield.science += {};", .{e.yields.science});
        if (e.yields.faith != 0) try writer.print("yield.faith += {};", .{e.yields.faith});
        try writer.print("}},", .{});
    }
    try writer.print(
        \\}}
        \\}}
    , .{});
}

/// Internal build function.
fn make(step: *Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    const b = step.owner;
    const self = @fieldParentPtr(Self, "step", step);
    const cwd = std.fs.cwd();

    const Base = struct {
        name: []const u8,
        yields: Yields = .{},
        is_water: bool = false,
        is_rough: bool = false,
        is_impassable: bool = false,
    };

    const Feature = struct {
        name: []const u8,
        yields: Yields = .{},
        bases: []const []const u8,
        features: []const []const u8 = &.{},
        is_rough: bool = false,
        is_impassable: bool = false,
    };

    const Resource = struct {
        name: []const u8,
        yields: Yields = .{},
        bases: []const []const u8 = &.{},
        features: []const []const u8 = &.{},
        vegetation: []const []const u8 = &.{},
    };

    // Parse all JSON files and return structures
    const terrain_parsed, const resources_parsed, const hash = blk: {
        var rules_dir = try cwd.openDir(self.rules_path.getPath(b), .{});
        defer rules_dir.close();

        var hasher = std.crypto.hash.blake2.Blake2b384.init(.{});

        const terrain = try readAndParse(struct {
            bases: []const Base,
            features: []const Feature,
            vegetation: []const Feature,
        }, rules_dir, "terrain.json", &hasher, b.allocator);

        const resources = try readAndParse(struct {
            bonus: []const Resource,
            strategic: []const Resource,
            luxury: []const Resource,
        }, rules_dir, "resources.json", &hasher, b.allocator);

        break :blk .{
            terrain,
            resources,
            digest(&hasher),
        };
    };
    defer terrain_parsed.deinit();
    defer resources_parsed.deinit();

    const rules_zig_dir = try b.cache_root.join(
        b.allocator,
        &.{ "rules", &hash },
    );
    const rules_out_path = try std.fs.path.join(
        b.allocator,
        &.{ rules_zig_dir, "rules.zig" },
    );

    cache_check: {
        std.fs.accessAbsolute(rules_out_path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :cache_check,
            else => |e| return e,
        };
        self.generated_file.path = rules_out_path;
        return;
    }
    try cwd.makePath(rules_zig_dir);

    var rules_zig_contents = std.ArrayList(u8).init(b.allocator);
    defer rules_zig_contents.deinit();

    const writer = rules_zig_contents.writer();

    // Output base stuff
    {
        try writer.print(
            \\pub const Yield = packed struct {{
            \\    production: u5 = 0,
            \\    food: u5 = 0,
            \\    gold: u5 = 0,
            \\    culture: u5 = 0,
            \\    faith: u5 = 0,
            \\    science: u5 = 0,
            \\}};
            \\
            \\
        , .{});
    }

    // Parse and output terrain
    {
        const terrain = terrain_parsed.value;

        try startEnum("Bases", terrain.bases.len, writer);
        for (terrain.bases, 0..) |base, i| {
            try writer.print("{s} = {},", .{ base.name, i });
        }
        try endStructEnumUnion(writer);

        try startEnum("Features", terrain.features.len, writer);
        for (terrain.features, 0..) |feature, i| {
            try writer.print("{s} = {},", .{ feature.name, i });
        }
        try endStructEnumUnion(writer);

        try startEnum("Vegetation", terrain.vegetation.len, writer);
        for (terrain.vegetation, 0..) |vegetation, i| {
            try writer.print("{s} = {},", .{ vegetation.name, i });
        }
        try endStructEnumUnion(writer);

        const TerrainCombo = struct {
            name: []const u8,
            yields: Yields,
            flags: Flags,
            is_water: bool,
            is_rough: bool,
            is_impassable: bool,
        };

        var terrain_combos = std.ArrayList(TerrainCombo).init(b.allocator);
        defer terrain_combos.deinit();

        var flag_index_set = std.StringArrayHashMap(void).init(b.allocator);
        defer flag_index_set.deinit();

        // Add all base tiles to terrain combinations
        for (terrain.bases) |base| {
            const gop = try flag_index_set.getOrPut(base.name);
            if (gop.found_existing) return error.DuplicateField;

            const base_index = gop.index;

            var flags = Flags.initEmpty();
            flags.set(base_index);

            try terrain_combos.append(.{
                .name = base.name,
                .yields = base.yields,
                .flags = flags,
                .is_water = base.is_water,
                .is_rough = base.is_rough,
                .is_impassable = base.is_impassable,
            });
        }

        inline for ([_][]const u8{ "features", "vegetation" }) |field_name| {
            for (@field(terrain, field_name)) |feature| {
                const gop = try flag_index_set.getOrPut(feature.name);
                if (gop.found_existing) return error.DuplicateField;

                const allowed_flags = blk: {
                    var flags = Flags.initEmpty();
                    for (feature.bases) |allowed_base| {
                        const index = flag_index_set.getIndex(allowed_base) orelse return error.UnknownName;
                        flags.set(index);
                    }
                    for (feature.features) |allowed_feature| {
                        const index = flag_index_set.getIndex(allowed_feature) orelse return error.UnknownFeature;
                        flags.set(index);
                    }
                    break :blk flags;
                };

                for (0..terrain_combos.items.len) |combo_index| {
                    const combo = terrain_combos.items[combo_index];
                    if (!combo.flags.intersectWith(allowed_flags).eql(combo.flags)) continue;

                    var new_flags = combo.flags;
                    new_flags.set(gop.index);

                    try terrain_combos.append(.{
                        .name = try std.mem.concat(b.allocator, u8, &.{
                            combo.name,
                            "_",
                            feature.name,
                        }),
                        .yields = feature.yields,
                        .flags = new_flags,
                        .is_water = combo.is_water,
                        .is_rough = combo.is_rough or feature.is_rough,
                        .is_impassable = combo.is_impassable or feature.is_impassable,
                    });
                }
            }
        }

        try startEnum("Terrain", terrain_combos.items.len, writer);
        for (terrain_combos.items, 0..) |combo, i| {
            try writer.print("{s} = {},", .{ combo.name, i });
        }

        try writer.print("\n\n", .{});
        try emitYieldsFunc(TerrainCombo, terrain_combos.items, writer);

        // Emit isSomething functions
        inline for (
            [_][]const u8{ "is_water", "is_impassable", "is_rough" },
            [_][]const u8{ "isWater", "isImpassable", "isRough" },
        ) |field_name, func_name| {
            try writer.print(
                \\
                \\
                \\pub fn {s}(self: @This()) bool {{
                \\return switch(self) {{
            , .{func_name});

            var count: usize = 0;
            for (terrain_combos.items) |combo| {
                if (@field(combo, field_name)) {
                    try writer.print(".{s},", .{combo.name});
                    count += 1;
                }
            }
            if (count != 0) {
                try writer.print("=> true,", .{});
            }
            if (count != terrain_combos.items.len) {
                try writer.print("else => false,", .{});
            }
            try writer.print(
                \\}};
                \\}}
            , .{});
        }

        try endStructEnumUnion(writer);
    }

    // Parse and output resources
    {
        const resources = resources_parsed.value;
        try startEnum(
            "ResourceType",
            resources.bonus.len + resources.strategic.len + resources.luxury.len,
            writer,
        );

        const all_resources = try std.mem.concat(b.allocator, Resource, &.{
            resources.bonus,
            resources.luxury,
            resources.strategic,
        });
        defer b.allocator.free(all_resources);

        for (all_resources) |resource| {
            try writer.print("{s},", .{resource.name});
        }

        try writer.print("\n\n", .{});

        try emitYieldsFunc(Resource, all_resources, writer);

        inline for (
            [_][]const u8{ "bonus", "strategic", "luxury" },
            [_][]const u8{ "isBonus", "isStrategic", "isLuxury" },
        ) |field_name, func_name| {
            try writer.print(
                \\
                \\
                \\pub fn {s}(self: @This()) bool {{
                \\return switch(self) {{
            , .{func_name});
            for (@field(resources, field_name)) |resource| {
                try writer.print(".{s},", .{resource.name});
            }
            try writer.print(
                \\=> true,
                \\else => false,
                \\}};
                \\}}
            , .{});
        }

        try endStructEnumUnion(writer);
    }

    try rules_zig_contents.append(0);
    const src = rules_zig_contents.items[0 .. rules_zig_contents.items.len - 1 :0];
    const tree = try std.zig.Ast.parse(b.allocator, src, .zig);
    const formatted = try tree.render(b.allocator);
    defer b.allocator.free(formatted);

    try cwd.writeFile(rules_out_path, formatted);
    self.generated_file.path = rules_out_path;
}
