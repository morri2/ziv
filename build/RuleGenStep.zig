const std = @import("std");
const Build = std.Build;
const Module = Build.Module;
const LazyPath = Build.LazyPath;

const Self = @This();

const FlagIndexMap = @import("FlagIndexMap.zig");

step: Build.Step,

/// Path to rule files
rules_path: LazyPath,

/// The main Zig file that contains for the rule types
generated_file: Build.GeneratedFile,

foundation: *Build.Module,

print_rules: bool,

pub fn create(
    builder: *Build,
    rules_path: LazyPath,
    print_rules: bool,
    foundation: *Module,
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
        .foundation = foundation,
        .print_rules = print_rules,
        .generated_file = undefined,
    };
    self.generated_file = .{ .step = &self.step };
    return self;
}

/// Returns the shaders module with name.
pub fn getModule(self: *Self) *Build.Module {
    return self.step.owner.createModule(.{
        .source_file = self.getSource(),
        .dependencies = &.{.{
            .name = "foundation",
            .module = self.foundation,
        }},
    });
}

/// Returns the file source for the generated shader resource code.
pub fn getSource(self: *Self) Build.FileSource {
    return .{ .generated = &self.generated_file };
}

fn readAndHash(
    dir: std.fs.Dir,
    sub_path: []const u8,
    hash: *std.Build.Cache.HashHelper,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const file = try dir.openFile(sub_path, .{});
    defer file.close();

    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(text);
    hash.addBytes(text);
    return text;
}

/// Internal build function.
fn make(step: *Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    const b = step.owner;
    const self = @fieldParentPtr(Self, "step", step);
    const cwd = std.fs.cwd();

    var man = b.cache.obtain();
    defer man.deinit();

    // Read all JSON files
    const text = blk: {
        var rules_dir = try cwd.openDir(self.rules_path.getPath(b), .{});
        defer rules_dir.close();

        const terrain = try readAndHash(rules_dir, "terrain.json", &man.hash, b.allocator);
        errdefer b.allocator.free(terrain);

        const resources = try readAndHash(rules_dir, "resources.json", &man.hash, b.allocator);
        errdefer b.allocator.free(resources);

        const improvements = try readAndHash(rules_dir, "improvements.json", &man.hash, b.allocator);
        errdefer b.allocator.free(improvements);

        const promotions = try readAndHash(rules_dir, "promotions.json", &man.hash, b.allocator);
        errdefer b.allocator.free(promotions);

        const units = try readAndHash(rules_dir, "units.json", &man.hash, b.allocator);
        errdefer b.allocator.free(units);

        break :blk .{
            .terrain = terrain,
            .resources = resources,
            .improvements = improvements,
            .promotions = promotions,
            .units = units,
        };
    };
    defer b.allocator.free(text.resources);
    defer b.allocator.free(text.terrain);
    defer b.allocator.free(text.improvements);
    defer b.allocator.free(text.promotions);
    defer b.allocator.free(text.units);

    const cache_hit = try man.hit();

    const hash = man.final();
    const rules_zig_dir = try b.cache_root.join(
        b.allocator,
        &.{ "rules", &hash },
    );
    const rules_out_path = try std.fs.path.join(
        b.allocator,
        &.{ rules_zig_dir, "rules.zig" },
    );

    // uncomment when the gen code is done ish
    self.generated_file.path = rules_out_path;
    if (cache_hit) return;

    try cwd.makePath(rules_zig_dir);

    var rules_zig_contents = std.ArrayList(u8).init(b.allocator);
    defer rules_zig_contents.deinit();

    const writer = rules_zig_contents.writer();

    // Output base stuff
    {
        try writer.print(
            \\const std = @import("std");
            \\const foundation = @import("foundation");
            \\const Yield = foundation.Yield;
        , .{});
    }

    const terrain = try @import("terrain.zig").parseAndOutput(
        text.terrain,
        writer,
        b.allocator,
    );
    defer terrain.arena.deinit();

    try @import("resources.zig").parseAndOutput(
        text.resources,
        writer,
        b.allocator,
    );

    try @import("improvements.zig").parseAndOutput(
        text.improvements,
        &terrain,
        writer,
        b.allocator,
    );

    var prom_flag_map = try FlagIndexMap.init(b.allocator);
    defer prom_flag_map.deinit();

    const unit_module = @import("units.zig");
    try unit_module.parseAndOutputPromotions(
        text.promotions,
        &prom_flag_map,
        writer,
        b.allocator,
    );

    try unit_module.parseAndOutputUnits(
        text.units,
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

        try stderr_writer.writeAll(src);
        try stderr_writer.writeByte('\n');

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

    if (self.print_rules) std.debug.print("{s}", .{formatted});

    try cwd.writeFile(rules_out_path, formatted);
}
