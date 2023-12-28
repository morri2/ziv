const std = @import("std");
const util = @import("util.zig");

const Yields = util.Yields;

const FlagIndexMap = @import("FlagIndexMap.zig");
const Flags = FlagIndexMap.Flags;

const Improvement = struct {
    name: []const u8,
    build_turns: u8,
    dont_clear: []const []const u8 = &.{},
    allow_on: struct {
        resources: []const []const u8 = &.{},
        bases: []struct {
            name: []const u8,
            no_feature: bool = false,
            need_freshwater: bool = false,
        } = &.{},
        features: []struct {
            name: []const u8,
            need_freshwater: bool = false,
        } = &.{},
        vegetation: []struct {
            name: []const u8,
            need_freshwater: bool = false,
        } = &.{},
    },
};

const Removal = struct {
    vegetation: []const u8,
    yields: Yields = .{},
};

pub fn parseAndOutput(
    text: []const u8,
    flag_index_map: *FlagIndexMap,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    _ = flag_index_map;
    const parsed = try std.json.parseFromSlice(struct {
        improvements: []Improvement,
    }, allocator, text, .{});
    defer parsed.deinit();

    const improvements = parsed.value;

    try writer.print("\npub const ImprovementAllowed = enum {{ not_allowed, allowed, allowed_after_clear }};\n", .{});

    try util.startEnum(
        "ImprovementType",
        improvements.improvements.len,
        writer,
    );

    for (improvements.improvements) |improvement| {
        try writer.print("{s},\n", .{improvement.name});
    }

    // connects resource function
    try writer.print(
        \\
        \\pub fn connectsResource(self: @This(), resource: Resource) bool {{
        \\ return switch (self) {{
        \\
    , .{});

    for (improvements.improvements) |imp| {
        try writer.print(".{s} => switch (resource) {{", .{imp.name});
        for (imp.allow_on.resources) |res| {
            try writer.print(".{s}, ", .{res});
        }
        if (imp.allow_on.resources.len > 0) {
            try writer.print("=> true,", .{});
        }
        try writer.print("else => false, }},\n     ", .{});
    }

    try writer.print(
        \\
        \\  }};
        \\}}
        \\
    , .{});

    // public check allow function
    try writer.print(
        \\
        \\pub fn checkAllowedOn(self: @This(), terrain: Terrain, freshwater: bool) ImprovementAllowed  {{
        \\  var res: ImprovementAllowed  = false;
        \\  res = switch (self) {{
        \\
    , .{});

    for (improvements.improvements) |imp| {
        try writer.print(".{s} => {s}AllowedOn(terrain, freshwater), \n", .{ imp.name, imp.name });
    }

    try writer.print(
        \\
        \\   }};
        \\   return res;
        \\ }}
        \\
    , .{});

    // check allow for specific improvement :))
    for (improvements.improvements) |imp| {
        try writer.print(
            \\
            \\fn {s}AllowedOn(terrain: Terrain, freshwater: bool) ImprovementAllowed  {{
            \\  if (freshwater and false) {{}} // STUPID, but needed
            \\  const feature = terrain.feature();
            \\  const base = terrain.base();
            \\  const vegetation = terrain.vegetation();
            \\  var ok = false;
            \\  
        , .{imp.name});

        try writer.print(
            \\ 
            \\  ok = switch (base) {{ // check if base makes valid
            \\
        , .{});

        for (imp.allow_on.bases) |base| {
            try writer.print(".{s} => true ", .{base.name});
            if (base.need_freshwater) {
                try writer.print("and freshwater ", .{});
            }
            if (base.no_feature) {
                try writer.print(" and feature == .none", .{});
            }
            try writer.print(",\n", .{});
        }

        try writer.print(
            \\      else => false,   
            \\  }};
            \\
        , .{});

        try writer.print(
            \\  
            \\  ok = ok or switch (feature) {{ // check if feature makes valid
            \\
        , .{});

        for (imp.allow_on.features) |feature| {
            try writer.print(".{s} => true ", .{feature.name});
            if (feature.need_freshwater) {
                try writer.print(" and freshwater ", .{});
            }
            try writer.print(",\n", .{});
        }

        try writer.print(
            \\      else => false,   
            \\  }};
        , .{});

        // ADD RESOURCE CHECK HERE!! - WHEN TILE IS ARGUMENT
        // maybe disallow non relavant improvements?
        // try writer.print(
        //     \\
        //     \\  ok = ok or self.connectsResource(resource);
        //     \\
        // , .{});
        // END RESOURCE THING

        try writer.print(
            \\
            \\  const veg_ok = switch (vegetation) {{// vegetation?
            \\
        , .{});

        for (imp.allow_on.vegetation) |vegetation| {
            try writer.print(".{s} => true ", .{vegetation.name});
            if (vegetation.need_freshwater) {
                try writer.print(" and freshwater ", .{});
            }
            try writer.print(",\n", .{});
        }

        try writer.print(
            \\      else => false,   
            \\  }};
            \\
        , .{});

        try writer.print(
            \\  if (veg_ok or (ok and vegetation == .none)) {{
            \\      return .allowed;
            \\    }} else if (ok) {{
            \\      return .allowed_after_clear;
            \\    }} else {{ return .not_allowed; }}
            \\
            \\  }}
            \\
        , .{});
    }

    try util.endStructEnumUnion(writer);
}
