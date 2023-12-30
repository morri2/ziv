const std = @import("std");

pub fn hexWidth(radius: f32) f32 {
    return radius * @sqrt(3.0);
}

pub fn hexHeight(radius: f32) f32 {
    return radius * 2.0;
}

pub fn tilingPosX(x: usize, y: usize, radius: f32) f32 {
    const fx: f32 = @floatFromInt(x);
    const y_odd: f32 = @floatFromInt(y & 1);

    return hexWidth(radius) * fx + hexWidth(radius) * 0.5 * y_odd;
}

pub fn tilingPosY(y: usize, radius: f32) f32 {
    const fy: f32 = @floatFromInt(y);
    return fy * radius * 1.5;
}

pub fn tilingWidth(map_width: usize, radius: f32) f32 {
    const fwidth: f32 = @floatFromInt(map_width);
    return hexWidth(radius) * fwidth + hexWidth(radius) * 0.5;
}

pub fn tilingHeight(map_height: usize, radius: f32) f32 {
    const fheight: f32 = @floatFromInt(map_height);
    return radius * 1.5 * (fheight - 1.0) + hexHeight(radius);
}
pub const HexIdx = usize;

/// The lowest index is always in low :))
pub const Edge = struct {
    low: HexIdx,
    high: HexIdx,
};

pub const HexDir = enum(u3) {
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

/// Struct for storing data for each hex in a HexGrid
pub fn HexGrid(comptime T: type) type {

    //   ----HOW TO COORDS----
    //   |0,0|1,0|2,0|3,0|4,0|
    //    \ / \ / \ / \ / \ / \
    //     |0,1|1,1|2,1|3,1|4,1|
    //    / \ / \ / \ / \ / \ /
    //   |0,2|1,2|2,2|3,2|4,2|

    return struct {
        const Self = @This();

        hex_data: []T,
        width: usize,
        height: usize,
        wrap_around: bool,
        allocator: ?std.mem.Allocator,

        pub fn init(
            width: usize,
            height: usize,
            wrap_around: bool,
            allocator: std.mem.Allocator,
        ) !Self {
            const hex_data = try allocator.alloc(T, width * height);
            errdefer allocator.free(hex_data);
            @memset(hex_data, .{});

            return Self{
                .width = width,
                .height = height,
                .wrap_around = wrap_around,
                .hex_data = hex_data,
                .allocator = null,
            };
        }

        /// DO NOT USE FOR NON DEBUG PURPOSES!
        /// A potentialy wasteful version of init, do not use for anything performance sensetive.
        pub fn new(
            width: usize,
            height: usize,
            wrap_around: bool,
        ) !Self {
            const big_wasteful_array: [128 * 80]T = undefined; // defines maximum possible map size
            const hex_data: []T = &big_wasteful_array;
            @memset(hex_data, .{});

            return Self{
                .hexWidth = width,
                .height = height,
                .wrap_around = wrap_around,
                .hex_data = hex_data,
                .allocator = null,
            };
        }

        pub fn deinit(self: *Self) void {
            const allocator = self.allocator orelse unreachable;
            allocator.free(self.hex_data);
        }

        pub fn coordToIdx(self: Self, x: usize, y: usize) HexIdx {
            return y * self.width + x;
        }
        pub fn idxToX(self: Self, idx: HexIdx) usize {
            return idx % self.width;
        }
        pub fn idxToY(self: Self, idx: HexIdx) usize {
            return idx / self.width;
        }
        pub fn len(self: Self) usize {
            return self.width * self.height;
        }
        pub fn get(self: Self, idx: HexIdx) T {
            return self.hex_data[idx];
        }
        pub fn getXY(self: Self, x: usize, y: usize) T {
            return self.hex_data[self.coordToIdx(x, y)];
        }
        pub fn set(self: Self, idx: HexIdx, val: T) void {
            self.hex_data[idx] = val;
        }
        pub fn setXY(self: Self, x: usize, y: usize, val: T) void {
            self.hex_data[self.coordToIdx(x, y)] = val;
        }

        /// like coordToIdx but takes signed shit and also allows wraparound
        pub fn xyToIdxSigned(self: Self, x: isize, y: isize) ?HexIdx {
            const uy: usize = @intCast(@mod(y, @as(isize, @intCast(self.height))));
            const ux: usize = @intCast(@mod(x, @as(isize, @intCast(self.hexWidth))));
            // y-wrap around, idk if this is ever needed
            if (y >= self.height or y < 0) return null;
            // x-wrap around, we like doing this
            if ((x >= self.height or x < 0) and !self.wrap_around) return null;
            return uy * self.hexWidth + ux;
        }
        pub fn getNeighbour(self: Self, src: HexIdx, dir: HexDir) ?HexIdx {
            return self.neighbours(src)[dir.int()];
        }

        /// Returns edge "dir" of given hexs
        pub fn getDirEdge(self: Self, src: HexIdx, dir: HexDir) ?Edge {
            const n: HexIdx = self.getNeighbour(src, dir) orelse return null;
            return Edge{
                .low = @min(n, src),
                .high = @max(n, src),
            };
        }

        /// Returns an array of HexIdx:s adjacent to the current tile, will be null if no tile exists in that direction.
        /// Index is the direction: 0=NE, 1=E, 2=SE, 3=SW, 4=W, 5=NW
        pub fn neighbours(self: Self, src: HexIdx) [6]?HexIdx {
            const x: isize = @intCast(self.idxToX(src));
            const y: isize = @intCast(self.idxToY(src));

            var ns: [6]?HexIdx = [_]?HexIdx{null} ** 6;

            // we assume wrap around, then yeet them if not
            ns[HexDir.E.int()] = self.xyToIdxSigned(x + 1, y);
            ns[HexDir.W.int()] = self.xyToIdxSigned(x - 1, y);

            if (@mod(y, 2) == 0) {
                ns[HexDir.NE.int()] = self.xyToIdxSigned(x, y - 1);
                ns[HexDir.SE.int()] = self.xyToIdxSigned(x, y + 1);

                ns[HexDir.NW.int()] = self.xyToIdxSigned(x - 1, y - 1);
                ns[HexDir.SW.int()] = self.xyToIdxSigned(x - 1, y + 1);
            } else {
                ns[HexDir.NW.int()] = self.xyToIdxSigned(x, y - 1);
                ns[HexDir.SW.int()] = self.xyToIdxSigned(x, y + 1);

                ns[HexDir.NE.int()] = self.xyToIdxSigned(x + 1, y - 1);
                ns[HexDir.SE.int()] = self.xyToIdxSigned(x + 1, y + 1);
            }

            return ns;
        }
    };
}
