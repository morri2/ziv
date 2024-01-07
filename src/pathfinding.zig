const World = @import("World.zig");
const hex = @import("hex.zig");
const Edge = hex.Edge;
const HexIdx = hex.HexIdx;
const HexGrid = hex.HexGrid(f32);
const Unit = @import("Unit.zig");
const BaseUnit = Unit.BaseUnit;

// const MoveCost = struct {
//     turns: u8,
//     movement_remaining: f32,
//     pub fn metric(self: MoveCost) f32 {
//         return @as(f32, @floatFromInt(self.turns)) * 256.0 - self.movement_remaining; //256 is probs larger than any movement dist
//     }
// };

pub const MoveCost = f32;
pub const CheckMoveResult = union(enum) {
    disallowed: void,
    allowed: MoveCost,
    embarkation: void,
};

pub fn checkMove(src: HexIdx, dest: HexIdx, world: *World) CheckMoveResult {
    const tile = world.tiles.get(dest);
    const edge = world.tiles.getEdgeBetween(src, dest) orelse return .disallowed;
    const is_river = world.rivers.contains(edge);
    const is_rough = tile.terrain.attributes().rough;
    const is_water = tile.terrain.attributes().water;
    const has_road = tile.transport == .road and !tile.pillaged_transport;
    const has_rail = tile.transport == .rail and !tile.pillaged_transport;

    var cost: f32 = 1;
    cost += if (is_river) 99 else 0; // river ends movement (unless ignored)
    cost += if (is_rough) 1 else 0;

    //if (is_water) return .embarkation;
    if (is_water) return .disallowed;
    if (has_road or has_rail) cost = 0.5; // changed with machinery to 1/3.
    if (has_rail) cost = @min(cost, 0.3); // actually dependent on movement points

    return .{ .allowed = cost };
}
