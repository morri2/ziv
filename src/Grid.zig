const std = @import("std");

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

pub fn idxFromCoords(self: Self, x: usize, y: usize) Idx {
    return y * self.width + x;
}

pub fn xFromIdx(self: Self, idx: Idx) usize {
    return idx % self.width;
}

pub fn yFromIdx(self: Self, idx: Idx) usize {
    return idx / self.width;
}

/// Returns edge "dir" of given hexs
pub fn dirEdge(self: Self, src: Idx, dir: Dir) ?Edge {
    const n: Idx = self.getNeighbour(src, dir) orelse return null;
    return Edge{
        .low = @min(n, src),
        .high = @max(n, src),
    };
}

pub fn adjacentTo(self: Self, src: Idx, dest: Idx) bool {
    return self.edgeBetween(src, dest) != null;
}

/// Returns edge between a and b
pub fn edgeBetween(self: Self, a: Idx, b: Idx) ?Edge {
    const src_neighbours = self.neighbours(a);
    var are_neighbours = false;
    for (0..6) |i| are_neighbours = are_neighbours or src_neighbours[i] == b;
    if (!are_neighbours) return null;
    return Edge.between(a, b);
}

/// Returns an array of Idx:s adjacent to the current tile, will be null if no tile exists in that direction.
/// Index is the direction: 0=NE, 1=E, 2=SE, 3=SW, 4=W, 5=NW
pub fn neighbours(self: Self, src: Idx) [6]?Idx {
    const x = self.xFromIdx(src);
    const y = self.yFromIdx(src);

    const west, const east = if (self.wrap_around) .{
        if (x == 0) self.width - 1 else x - 1,
        if (x == self.width - 1) 0 else x + 1,
    } else .{
        x -| 1,
        x +| 1,
    };

    const north = y -| 1;
    const south = y +| 1;

    var ns: [6]Idx = undefined;
    // we assume wrap around, then yeet them if not
    ns[Dir.E.int()] = self.idxFromCoords(east, y);
    ns[Dir.W.int()] = self.idxFromCoords(west, y);

    if (@mod(y, 2) == 0) {
        ns[Dir.NE.int()] = self.idxFromCoords(x, north);
        ns[Dir.SE.int()] = self.idxFromCoords(x, south);

        ns[Dir.NW.int()] = self.idxFromCoords(west, north);
        ns[Dir.SW.int()] = self.idxFromCoords(west, south);
    } else {
        ns[Dir.NW.int()] = self.idxFromCoords(x, north);
        ns[Dir.SW.int()] = self.idxFromCoords(x, south);

        ns[Dir.NE.int()] = self.idxFromCoords(east, north);
        ns[Dir.SE.int()] = self.idxFromCoords(east, south);
    }

    var out_ns: [6]?Idx = undefined;
    for (ns, 0..) |n, i| {
        out_ns[i] = if (n == src) null else n;
    }

    return out_ns;
}

test "neighbours with wrap around" {
    const grid = Self.init(100, 50, true);

    const idx = grid.idxFromCoords(0, 4);

    try std.testing.expectEqual([_]?Idx{
        grid.idxFromCoords(0, 3), // NE
        grid.idxFromCoords(1, 4), // E
        grid.idxFromCoords(0, 5), // SE
        grid.idxFromCoords(99, 5), // SW
        grid.idxFromCoords(99, 4), // W
        grid.idxFromCoords(99, 3), // NW
    }, grid.neighbours(idx));
}
