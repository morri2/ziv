const Self = @This();

pub const Idx = usize;

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

pub const Dir = enum(u3) {
    NE = 0,
    E = 1,
    SE = 2,
    SW = 3,
    W = 4,
    NW = 5,

    pub inline fn int(self: @This()) usize {
        return @intFromEnum(self);
    }
};

width: usize,
height: usize,
wrap_around: bool,
len: usize,

pub fn init(
    width: usize,
    height: usize,
    wrap_around: bool,
) Self {
    return Self{
        .width = width,
        .height = height,
        .len = width * height,
        .wrap_around = wrap_around,
    };
}

//   ----HOW TO COORDS----
//   |0,0|1,0|2,0|3,0|4,0|
//    \ / \ / \ / \ / \ / \
//     |0,1|1,1|2,1|3,1|4,1|
//    / \ / \ / \ / \ / \ /
//   |0,2|1,2|2,2|3,2|4,2|

pub fn coordToIdx(self: Self, x: usize, y: usize) Idx {
    return y * self.width + x;
}

pub fn idxToX(self: Self, idx: Idx) usize {
    return idx % self.width;
}

pub fn idxToY(self: Self, idx: Idx) usize {
    return idx / self.width;
}

/// like coordToIdx but takes signed shit and also allows wraparound
pub fn xyToIdxSigned(self: Self, x: isize, y: isize) ?Idx {
    const uy: usize = @intCast(@mod(y, @as(isize, @intCast(self.height))));
    const ux: usize = @intCast(@mod(x, @as(isize, @intCast(self.width))));
    // y-wrap around, idk if this is ever needed
    if (y >= self.height or y < 0) return null;
    // x-wrap around, we like doing this
    if ((x >= self.height or x < 0) and !self.wrap_around) return null;
    return uy * self.width + ux;
}

pub fn getNeighbour(self: Self, src: Idx, dir: Dir) ?Idx {
    return self.neighbours(src)[dir.int()];
}

/// Returns edge "dir" of given hexs
pub fn getDirEdge(self: Self, src: Idx, dir: Dir) ?Edge {
    const n: Idx = self.getNeighbour(src, dir) orelse return null;
    return Edge{
        .low = @min(n, src),
        .high = @max(n, src),
    };
}

/// Returns edge between a and b
pub fn getEdgeBetween(self: Self, a: Idx, b: Idx) ?Edge {
    const src_neighbours = self.neighbours(a);
    var are_neighbours = false;
    for (0..6) |i| are_neighbours = are_neighbours or src_neighbours[i] == b;
    if (!are_neighbours) return null;
    return Edge.between(a, b);
}

/// Returns an array of Idx:s adjacent to the current tile, will be null if no tile exists in that direction.
/// Index is the direction: 0=NE, 1=E, 2=SE, 3=SW, 4=W, 5=NW
pub fn neighbours(self: Self, src: Idx) [6]?Idx {
    const x: isize = @intCast(self.idxToX(src));
    const y: isize = @intCast(self.idxToY(src));

    var ns: [6]?Idx = [_]?Idx{null} ** 6;

    // we assume wrap around, then yeet them if not
    ns[Dir.E.int()] = self.xyToIdxSigned(x + 1, y);
    ns[Dir.W.int()] = self.xyToIdxSigned(x - 1, y);

    if (@mod(y, 2) == 0) {
        ns[Dir.NE.int()] = self.xyToIdxSigned(x, y - 1);
        ns[Dir.SE.int()] = self.xyToIdxSigned(x, y + 1);

        ns[Dir.NW.int()] = self.xyToIdxSigned(x - 1, y - 1);
        ns[Dir.SW.int()] = self.xyToIdxSigned(x - 1, y + 1);
    } else {
        ns[Dir.NW.int()] = self.xyToIdxSigned(x, y - 1);
        ns[Dir.SW.int()] = self.xyToIdxSigned(x, y + 1);

        ns[Dir.NE.int()] = self.xyToIdxSigned(x + 1, y - 1);
        ns[Dir.SE.int()] = self.xyToIdxSigned(x + 1, y + 1);
    }

    return ns;
}
