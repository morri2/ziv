const std = @import("std");
const Self = @This();
/// THE NEW GRID MIND(MELT)SET
/// The Idx is king! A hex has an index, each index MIGHT be representated
/// as multiple diffrent coordinates in the other representation (still
/// there is a cannonical version for each coordinate type).
/// The GAME STATE should only ever hold Idx:es.
pub const Idx = u32;
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
    /// diffrence in coordinates considering wraparound, null if no index corresponds
    pub fn diffTo(self: CoordQRS, dest: CoordQRS, grid: Self) ?CoordQRS {
        var qd = dest.q - self.q;
        if (grid.wrap_around) {
            const width = @as(iCoord, @intCast(grid.width));

            if (qd > width - qd) qd = width - qd;
            if (-qd > width + qd) qd = width + qd;
        }
        const rd = dest.r - self.r;
        return .{ .q = qd, .r = rd };
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
    /// For comparisons where the index might be invalid, obs! Not canonized, so same idx wont nesseserily be equal.
    pub fn eq(self: CoordQRS, other: CoordQRS) bool {
        return self.q == other.q and self.r == other.r;
    }

    pub fn maxAbs(self: CoordQRS) uCoord {
        return @max(@abs(self.q), @max(@abs(self.r), @abs(self.s())));
    }
    pub fn minAbs(self: CoordQRS) uCoord {
        return @min(@abs(self.q), @min(@abs(self.r), @abs(self.s())));
    }
};

/// The lowest index is always in low :))
pub const Edge = packed struct {
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

width: u32,
height: u32,
wrap_around: bool,
len: u32,

pub fn init(width: u32, height: u32, wrap_around: bool) Self {
    return Self{
        .width = width,
        .height = height,
        .len = width * height,
        .wrap_around = wrap_around,
    };
}

pub fn idxFromCoords(self: Self, x: u32, y: u32) Idx {
    return y * self.width + x;
}

pub fn xFromIdx(self: Self, idx: Idx) u32 {
    return idx % self.width;
}

pub fn yFromIdx(self: Self, idx: Idx) u32 {
    return idx / self.width;
}

pub fn contains(self: Self, idx: Idx) bool {
    return idx < self.len;
}
/// true if a and b share an axis (are on a straight line)
pub fn areAxial(self: Self, a: Idx, b: Idx) bool {
    self.distanceOffAxial(a, b) == 0;
}

pub fn areDiagonal(self: Self, a: Idx, b: Idx) bool {
    2 * self.distanceOffAxial(a, b) == self.distance(a, b);
}

pub fn distanceOffAxial(self: Self, a: Idx, b: Idx) u8 {
    var qrs_a = CoordQRS.fromIdx(a, self);
    var qrs_b = CoordQRS.fromIdx(b, self);
    var min = @min(@abs(qrs_a.r - qrs_b.r), @min(@abs(qrs_a.q - qrs_b.q), @abs(qrs_a.s() - qrs_b.s())));

    if (self.wrap_around) {
        const shift: iCoord = @intCast(self.width / 2);
        qrs_a = qrs_a.addQR(shift, 0).canonize(self) orelse unreachable;
        qrs_b = qrs_b.addQR(shift, 0).canonize(self) orelse unreachable;
        const wrap_min = @min(@abs(qrs_a.r - qrs_b.r), @min(@abs(qrs_a.q - qrs_b.q), @abs(qrs_a.s() - qrs_b.s())));
        min = @min(min, wrap_min);
    }
    return @intCast(min);
}

pub fn distance(self: Self, a: Idx, b: Idx) u8 {
    const qrs_a = CoordQRS.fromIdx(a, self);
    const qrs_b = CoordQRS.fromIdx(b, self);
    const diff = qrs_a.diffTo(qrs_b, self) orelse std.debug.panic("Non valid distance {} to {}", .{ a, b });
    return @intCast(diff.maxAbs());
}

pub fn isNeighbour(self: Self, src: Idx, dest: Idx) bool {
    return distance(self, src, dest) == 1;
}

pub const Direction = enum(u3) {
    pub const directions: [6]@This() = [_]@This(){ .East, .NorthEast, .NorthWest, .West, .SouthWest, .SouthEast };

    East = 0,
    NorthEast = 1,
    NorthWest = 2,
    West = 3,
    SouthWest = 4,
    SouthEast = 5,

    pub fn rotateCC(self: @This(), n: u8) @This() {
        var next: u8 = @intFromEnum(self) + n;
        next %= 6;
        return @enumFromInt(next);
    }
    pub fn offsetQRS(self: @This()) CoordQRS {
        return self.nOffsetQRS(1);
    }
    pub fn nOffsetQRS(self: @This(), n: iCoord) CoordQRS {
        return switch (self) {
            .East => .{ .q = n, .r = 0 },
            .NorthEast => .{ .q = n, .r = -n },
            .NorthWest => .{ .q = 0, .r = -n },
            .West => .{ .q = -n, .r = 0 },
            .SouthWest => .{ .q = -n, .r = n },
            .SouthEast => .{ .q = 0, .r = n },
        };
    }
};

pub fn neighbours(self: Self, src: Idx) [6]?Idx {
    const rqs = CoordQRS.fromIdx(src, self);
    var ns: [6]?Idx = undefined;
    for (Direction.directions, 0..) |dir, i| ns[i] = rqs.add(dir.offsetQRS()).toIdx(self);

    return ns;
}

pub fn edgeBetween(self: Self, a: Idx, b: Idx) ?Edge {
    if (!self.isNeighbour(a, b)) return null;
    return Edge.between(a, b);
}

// returns edge direction (low -> high)
pub fn edgeDirection(self: Self, edge: Edge) ?Direction {
    if (!self.isNeighbour(edge.low, edge.high)) return null;
    for (self.neighbours(edge.low), 0..) |maybe_n, i| if (maybe_n) |n| {
        if (n == edge.high) return Direction.directions[i];
    };
    unreachable;
}

pub const SpiralIterator = struct {
    radius: u8,
    center: Idx,
    current_ring: u8,
    ring_iter: RingIterator,

    pub fn new(center: Idx, radius: u8, grid: Self) @This() {
        return newFrom(center, 1, radius, grid);
    }

    pub fn newFrom(center: Idx, start: u8, radius: u8, grid: Self) @This() {
        std.debug.assert(radius > 0);
        const ring_iter: RingIterator = RingIterator.new(center, start, grid);
        return .{ .radius = radius, .current_ring = start, .ring_iter = ring_iter, .center = center };
    }

    pub fn next(self: *@This(), grid: Self) ?Idx {
        const maybe_idx = self.ring_iter.next(grid);
        if (maybe_idx == null) {
            self.current_ring += 1;
            if (self.current_ring > self.radius) return null;
            self.ring_iter = RingIterator.new(self.center, self.current_ring, grid);

            return self.next(grid);
        }
        return maybe_idx.?;
    }
};

pub const RingIterator = struct {
    const start_dir = Direction.East.rotateCC(2);
    const inital_offset_dir = Direction.East;
    at: CoordQRS,
    center: Idx,
    radius: u8,
    dir: Direction,

    steps: u8 = 0,

    pub fn new(center: Idx, radius: u8, grid: Self) @This() {
        std.debug.assert(radius > 0);
        const center_qrs = CoordQRS.fromIdx(center, grid);
        const at = center_qrs.add(inital_offset_dir.nOffsetQRS(radius));
        const dir = start_dir;
        return .{
            .at = at,
            .center = center,
            .dir = dir,
            .radius = radius,
            .steps = 0,
        };
    }

    pub fn next(self: *@This(), grid: Self) ?Idx {
        var idx: ?Idx = null;

        while (idx == null) {
            if (self.steps == self.radius) {
                self.steps = 0;
                self.dir = self.dir.rotateCC(1);
                if (self.dir == start_dir) return null;
            }

            idx = self.at.toIdx(grid);

            self.at = self.at.add(self.dir.offsetQRS());
            self.steps += 1;
        }

        return idx;
    }
};
