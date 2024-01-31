const std = @import("std");
const Self = @This();
/// THE NEW GRID MIND(MELT)SET
/// The Idx is king! A hex has an index, each index MIGHT be representated
/// as multiple diffrent coordinates in the other representation (still
/// there is a cannonical version for each coordinate type).
/// The GAME STATE should only ever hold Idx:es.
pub const Idx = usize;
pub const uCoord = u16;
pub const iCoord = i16;

pub const CoordXY = struct {
    x: iCoord,
    y: iCoord,

    //   |x,y|1,0|2,0|3,0|4,0|
    //    \ / \ / \ / \ / \ / \
    //     |0,1|1,1|2,1|3,1|4,1|
    //    / \ / \ / \ / \ / \ /
    //   |0,2|1,2|2,2|3,2|4,2|

    pub fn canonize(self: CoordXY, grid: Self) ?CoordXY {
        const wrap_x: iCoord =
            if (grid.wrap_around) @mod(self.x, @as(iCoord, @intCast(grid.width))) else self.x;
        return .{
            .x = if (wrap_x >= 0 and wrap_x < grid.width) wrap_x else return null,
            .y = if (self.y >= 0 and self.y < grid.height) self.y else return null,
        };
    }

    pub fn toIdx(self: CoordXY, grid: Self) ?Idx {
        const canon = self.canonize(grid) orelse return null;
        const idx: Idx = @intCast(canon.x + canon.y * @as(iCoord, @intCast(grid.width)));
        std.debug.assert(idx < grid.len);
        return idx;
    }

    pub fn fromIdx(idx: Idx, grid: Self) CoordXY {
        return .{
            .x = @intCast(idx % grid.width),
            .y = @intCast(idx / grid.width),
        };
    }
};

pub const CoordQRS = struct {
    q: iCoord,
    r: iCoord,
    /// s is implicit (s=-q-r)
    pub fn s(self: CoordQRS) iCoord {
        return -self.q - self.r;
    }

    //   |q,r|1,0|2,0|3,0|4,0|
    //    \ / \ / \ / \ / \ / \
    //     |0,1|1,1|2,1|3,1|4,1|
    //    / \ / \ / \ / \ / \ / \
    //   -1,2|0,2|1,2|2,2|3,2|4,2|

    pub fn canonize(self: CoordQRS, grid: Self) ?CoordQRS {
        var wrap_q: iCoord = self.q;
        if (grid.wrap_around) {
            wrap_q += @divFloor(self.r, 2);
            wrap_q = @mod(wrap_q, @as(iCoord, @intCast(grid.width)));
            wrap_q -= @divFloor(self.r, 2);
        }

        wrap_q += @divFloor(self.r, 2);
        return .{
            .q = if (wrap_q >= 0 and wrap_q < grid.width) wrap_q else return null,
            .r = if (self.r >= 0 and self.r < grid.height) self.r else return null,
        };
    }

    pub fn toIdx(self: CoordQRS, grid: Self) ?Idx {
        const canon = self.canonize(grid) orelse return null;
        const idx = canon.q + canon.r * @as(iCoord, @intCast(grid.width));
        std.debug.assert(idx < grid.len);
        return @intCast(idx);
    }

    pub fn fromIdx(idx: Idx, grid: Self) CoordQRS {
        const r: iCoord = @intCast(idx / grid.width);
        return .{
            .q = @as(iCoord, @intCast(idx % grid.width)) - @divFloor(r, 2),
            .r = @intCast(r),
        };
    }

    pub fn add(self: CoordQRS, other: CoordQRS) CoordQRS {
        return self.addQR(other.q, other.r);
    }

    pub fn sub(self: CoordQRS, other: CoordQRS) CoordQRS {
        return self.addQR(-other.q, -other.r);
    }

    pub fn addQR(self: CoordQRS, qd: iCoord, rd: iCoord) CoordQRS {
        return .{ .q = self.q + qd, .r = self.r + rd };
    }
};

/// The lowest index is always in low :))
pub const Edge = struct {
    low: Idx,
    high: Idx,

    /// OBS! Does not garuantee the tiles are adjacent
    fn between(a: Idx, b: Idx) ?Edge {
        if (a == b) return null;
        return Edge{
            .low = @min(a, b),
            .high = @max(a, b),
        };
    }
};

width: usize,
height: usize,
wrap_around: bool,
len: usize,

pub fn init(width: usize, height: usize, wrap_around: bool) Self {
    return Self{
        .width = width,
        .height = height,
        .len = width * height,
        .wrap_around = wrap_around,
    };
}

pub fn idxFromCoords(self: Self, x: usize, y: usize) Idx {
    return y * self.width + x;
}

pub fn xFromIdx(self: Self, idx: Idx) usize {
    return idx % self.width;
}

pub fn yFromIdx(self: Self, idx: Idx) usize {
    return idx / self.width;
}

pub fn contains(self: Self, idx: Idx) bool {
    return idx < self.len;
}

pub fn distance(self: Self, a: Idx, b: Idx) u8 {
    var qrs_a = CoordQRS.fromIdx(a, self);
    var qrs_b = CoordQRS.fromIdx(b, self);
    var max = @max(@abs(qrs_a.r - qrs_b.r), @max(@abs(qrs_a.q - qrs_b.q), @abs(qrs_a.s() - qrs_b.s())));

    if (self.wrap_around) {
        const shift: iCoord = @intCast(self.width / 2);
        qrs_a = qrs_a.addQR(shift, 0).canonize(self) orelse unreachable;
        qrs_b = qrs_b.addQR(shift, 0).canonize(self) orelse unreachable;
        const wrap_max = @max(@abs(qrs_a.r - qrs_b.r), @max(@abs(qrs_a.q - qrs_b.q), @abs(qrs_a.s() - qrs_b.s())));
        max = @min(max, wrap_max);
    }
    return @intCast(max);
}

pub fn isNeighbour(self: Self, src: Idx, dest: Idx) bool {
    return distance(self, src, dest) == 1;
}

pub fn neighbours(self: Self, src: Idx) [6]?Idx {
    const rqs = CoordQRS.fromIdx(src, self);
    return .{
        rqs.addQR(1, 0).toIdx(self),  rqs.addQR(0, 1).toIdx(self),  rqs.addQR(-1, 0).toIdx(self), //
        rqs.addQR(0, -1).toIdx(self), rqs.addQR(1, -1).toIdx(self), rqs.addQR(-1, 1).toIdx(self),
    };
}

pub fn edgeBetween(self: Self, a: Idx, b: Idx) ?Edge {
    if (!self.isNeighbour(a, b)) return null;
    return Edge.between(a, b);
}

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
pub const FloatXY = struct {
    x: f32,
    y: f32,

    pub fn roundToIdx(self: FloatXY, grid: Self, radius: f32) ?Idx {
        _ = self; // autofix
        _ = grid; // autofix
        _ = radius; // autofix

        //
    }
    pub fn fromIdx(idx: Idx, grid: Self, radius: f32) FloatXY {
        const hex = @import("gui/hex_util.zig");
        const xy = CoordXY.fromIdx(idx, grid);

        return .{
            .x = hex.tilingX(@intCast(xy.x), @intCast(xy.y), radius),
            .y = hex.tilingY(@intCast(xy.y), radius),
        };
    }
    pub fn roundToIdxShakey(self: FloatXY, grid: Self) [2]?Idx {
        const v1: FloatXY = .{ .x = self.x + 0.000001, .y = self.y + 0.000001 };
        const v2: FloatXY = .{ .x = self.x - 0.000001, .y = self.y - 0.000001 };
        return .{ v1.roundToIdx(grid), v2.roundToIdx(grid) };
    }
    pub fn raylibVector2(self: FloatXY, radius: f32) raylib.Vector2 {
        return .{
            .x = @sqrt(3.0) * radius * (0.5 + self.x),
            .y = (0.5 + self.y) * radius * 1.5,
        };
    }
    pub fn add(self: FloatXY, other: FloatXY) FloatXY {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
    pub fn sub(self: FloatXY, other: FloatXY) FloatXY {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }
    pub fn scale(self: FloatXY, s: f32) FloatXY {
        return .{ .x = self.x * s, .y = self.y * s };
    }
    pub fn lerp(p1: FloatXY, p2: FloatXY, t: f32) FloatXY {
        return p1.add((p2.sub(p1)).scale(t));
    }
};

/// LERP
pub fn nthLerp(self: Self, dist: u8, n: u8, idx1: Idx, idx2: Idx) FloatXY {
    var t: f32 = @floatFromInt(n);
    t /= @floatFromInt(dist);
    const lerp_float_xy = FloatXY.lerp(
        FloatXY.fromIdx(idx1, self, 1),
        FloatXY.fromIdx(idx2, self, 1),
        t,
    );
    return lerp_float_xy;
}
