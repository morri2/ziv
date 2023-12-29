const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;

const Self = @This();

const FlagIndexMap = @import("FlagIndexMap.zig");

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

fn readAndHash(
    dir: std.fs.Dir,
    sub_path: []const u8,
    hasher: *std.crypto.hash.blake2.Blake2b384,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const file = try dir.openFile(sub_path, .{});
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(text);
    hasher.update(text);
    return text;
}

/// Internal build function.
fn make(step: *Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    const b = step.owner;
    const self = @fieldParentPtr(Self, "step", step);
    const cwd = std.fs.cwd();

    // Read all JSON files
    const terrain_text, const resources_text, const improvements_text, const natural_wonders_text, const promotion_text, const hash = blk: {
        var rules_dir = try cwd.openDir(self.rules_path.getPath(b), .{});
        defer rules_dir.close();

        var hasher = std.crypto.hash.blake2.Blake2b384.init(.{});

        const terrain = try readAndHash(rules_dir, "terrain.json", &hasher, b.allocator);
        errdefer b.allocator.free(terrain);

        const resources = try readAndHash(rules_dir, "resources.json", &hasher, b.allocator);
        errdefer b.allocator.free(resources);

        const improvements = try readAndHash(rules_dir, "improvements.json", &hasher, b.allocator);
        errdefer b.allocator.free(improvements);

        const natural_wonders = try readAndHash(rules_dir, "natural_wonders.json", &hasher, b.allocator);
        errdefer b.allocator.free(improvements);

        const promotions = try readAndHash(rules_dir, "promotions.json", &hasher, b.allocator);
        errdefer b.allocator.free(promotions);

        break :blk .{
            terrain,
            resources,
            improvements,
            natural_wonders,
            promotions,
            digest(&hasher),
        };
    };
    defer b.allocator.free(resources_text);
    defer b.allocator.free(terrain_text);
    defer b.allocator.free(improvements_text);
    defer b.allocator.free(natural_wonders_text);
    defer b.allocator.free(promotion_text);

    const rules_zig_dir = try b.cache_root.join(
        b.allocator,
        &.{ "rules", &hash },
    );
    const rules_out_path = try std.fs.path.join(
        b.allocator,
        &.{ rules_zig_dir, "rules.zig" },
    );

    // // uncomment when the gen code is done ish
    // cache_check: {
    //     std.fs.accessAbsolute(rules_out_path, .{}) catch |err| switch (err) {
    //         error.FileNotFound => break :cache_check,
    //         else => |e| return e,
    //     };
    //     self.generated_file.path = rules_out_path;
    //     return;
    // }

    try cwd.makePath(rules_zig_dir);

    var rules_zig_contents = std.ArrayList(u8).init(b.allocator);
    defer rules_zig_contents.deinit();

    const writer = rules_zig_contents.writer();

    // Output base stuff
    {
        try writer.print(
            \\const std = @import("std");
            \\
            \\pub const Yield = packed struct {{
            \\    food: u5 = 0,
            \\    production: u5 = 0,
            \\    gold: u5 = 0,
            \\    culture: u5 = 0,
            \\    faith: u5 = 0,
            \\    science: u5 = 0,
            \\}};
            \\
            \\pub const Transport = enum(u2) {{
            \\    none,
            \\    road,
            \\    rail,
            \\}};
            \\
            \\pub const Tile = packed struct {{
            \\    terrain: Terrain = @enumFromInt(0),
            \\    freshwater: bool = false,
            \\    river_access: bool = false,
            \\    improvement: Improvement = .none,
            \\    transport: Transport = .none,
            \\    pillaged_improvements: bool = false,
            \\    pillaged_transport: bool = false,
            \\
            \\    comptime {{
            \\        std.debug.assert(@sizeOf(@This()) == 2);
            \\    }}
            \\}};
        , .{});
    }

    var flag_index_map = try FlagIndexMap.init(b.allocator);
    defer flag_index_map.deinit();

    const terrain = try @import("terrain.zig").parseAndOutput(
        terrain_text,
        &flag_index_map,
        writer,
        b.allocator,
    );

    try @import("resources.zig").parseAndOutput(
        resources_text,
        &flag_index_map,
        writer,
        b.allocator,
    );

    try @import("improvements.zig").parseAndOutput(
        improvements_text,
        terrain,
        &flag_index_map,
        writer,
        b.allocator,
    );

    try @import("natural_wonders.zig").parseAndOutput(
        natural_wonders_text,
        &flag_index_map,
        writer,
        b.allocator,
    );

    var prom_flag_map = try FlagIndexMap.init(b.allocator);
    defer prom_flag_map.deinit();

    const unit_module = @import("units.zig");
    try unit_module.parseAndOutputPromotions(
        promotion_text,
        &prom_flag_map,
        writer,
        b.allocator,
    );

    try rules_zig_contents.append(0);
    const src = rules_zig_contents.items[0 .. rules_zig_contents.items.len - 1 :0];
    const tree = try std.zig.Ast.parse(b.allocator, src, .zig);
    if (tree.errors.len != 0) {
        const stderr = std.io.getStdErr();
        const stderr_writer = stderr.writer();
        for (tree.errors) |err| {
            const location = tree.tokenLocation(0, err.token);
            try stderr_writer.print("{}:{}: error: ", .{ location.line, location.column });
            try tree.renderError(err, stderr_writer);
            try stderr_writer.writeByte('\n');
        }
        return error.ZigSyntaxError;
    }
    const formatted = try tree.render(b.allocator);
    defer b.allocator.free(formatted);

    std.debug.print("{s}", .{formatted});

    try cwd.writeFile(rules_out_path, formatted);
    self.generated_file.path = rules_out_path;
}
