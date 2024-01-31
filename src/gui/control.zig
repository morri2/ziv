const Rules = @import("../Rules.zig");
const Terrain = Rules.Terrain;
const Grid = @import("../Grid.zig");
const hex = @import("hex_util.zig");
const Idx = @import("../Grid.zig").Idx;
const World = @import("../World.zig");
const Unit = @import("../Unit.zig");
const render = @import("render.zig");
const std = @import("std");
const TextureSet = @import("TextureSet.zig");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub fn cameraRenderBoundBox(camera: raylib.Camera2D, grid: *Grid, screen_width: usize, screen_height: usize, ts: TextureSet) BoundBox {
    const min_x, const min_y, const max_x, const max_y = blk: {
        const top_left = raylib.GetScreenToWorld2D(raylib.Vector2{}, camera);
        const bottom_right = raylib.GetScreenToWorld2D(raylib.Vector2{
            .x = @floatFromInt(screen_width),
            .y = @as(f32, @floatFromInt(screen_height)),
        }, camera);

        const fwidth: f32 = @floatFromInt(grid.width);
        const fheight: f32 = @floatFromInt(grid.height);

        const min_x: usize = @intFromFloat(std.math.clamp(
            @round(top_left.x / hex.widthFromRadius(ts.hex_radius)) - 2.0,
            0.0,
            fwidth,
        ));
        const max_x: usize = @intFromFloat(std.math.clamp(
            @round(bottom_right.x / hex.widthFromRadius(ts.hex_radius)) + 2.0,
            0.0,
            fwidth,
        ));

        const min_y: usize = @intFromFloat(std.math.clamp(
            @round(top_left.y / (ts.hex_radius * 1.5)) - 2.0,
            0.0,
            fheight,
        ));
        const max_y: usize = @intFromFloat(std.math.clamp(
            @round(bottom_right.y / (ts.hex_radius * 1.5)) + 2.0,
            0.0,
            fheight,
        ));

        break :blk .{ min_x, min_y, max_x, max_y };
    };
    return BoundBox{
        .xmax = max_x,
        .xmin = min_x,
        .ymax = max_y,
        .ymin = min_y,
        .grid = grid,
    };
}

/// VERY PLACEHOLDER AND SHIT
pub fn getMouseTile(
    camera: *raylib.Camera2D,
    grid: Grid,
    ts: TextureSet,
) usize {
    const click_point = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), camera.*);
    const click_x: f32 = click_point.x;
    const click_y: f32 = click_point.y;
    var click_idx: Grid.Idx = 0; // = world.tiles.coordToIdx(click_x, click_y);

    var min_dist: f32 = std.math.floatMax(f32);
    for (0..grid.width) |x| {
        for (0..grid.height) |y| {
            const real_x = hex.tilingX(x, y, ts.hex_radius) + hex.heightFromRadius(ts.hex_radius) * 0.5;
            const real_y = hex.tilingY(y, ts.hex_radius) + hex.widthFromRadius(ts.hex_radius) * 0.5;
            const dist = std.math.pow(f32, real_x - click_x, 2) + std.math.pow(f32, real_y - click_y, 2);
            if (dist < min_dist) {
                click_idx = grid.idxFromCoords(x, y);
                min_dist = dist;
            }
        }
    }
    return click_idx;
}

pub fn getPointIdx(
    xf: f32,
    yf: f32,
    grid: Grid,
    ts: TextureSet,
) usize {
    var click_idx: Grid.Idx = 0;

    var min_dist: f32 = std.math.floatMax(f32);
    for (0..grid.width) |x| {
        for (0..grid.height) |y| {
            const real_x = hex.tilingX(x, y, ts.hex_radius) + hex.heightFromRadius(ts.hex_radius) * 0.5;
            const real_y = hex.tilingY(y, ts.hex_radius) + hex.widthFromRadius(ts.hex_radius) * 0.5;
            const dist = std.math.pow(f32, real_x -
                xf, 2) + std.math.pow(f32, real_y - yf, 2);
            if (dist < min_dist) {
                click_idx = grid.idxFromCoords(x, y);
                min_dist = dist;
            }
        }
    }
    return click_idx;
}

pub fn updateCamera(camera: *raylib.Camera2D, speed: f32) bool {
    const last_zoom = camera.zoom;
    const last_target = camera.target;

    // Drag controls
    if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_MIDDLE)) {
        const delta = raylib.Vector2Scale(raylib.GetMouseDelta(), -1.0 / camera.zoom);

        camera.target = raylib.Vector2Add(camera.target, delta);
    }

    // Zoom controls
    const wheel = raylib.GetMouseWheelMove();
    if (wheel != 0.0) {
        const world_pos = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), camera.*);

        camera.offset = raylib.GetMousePosition();
        camera.target = world_pos;

        const zoom_inc = 0.3;
        camera.zoom += (wheel * zoom_inc);
        camera.zoom = std.math.clamp(camera.zoom, 0.3, 3.0);
    }

    // Arrow key controls
    if (raylib.IsKeyDown(raylib.KEY_RIGHT) or raylib.IsKeyDown(raylib.KEY_D)) camera.target.x += speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_LEFT) or raylib.IsKeyDown(raylib.KEY_A)) camera.target.x -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_UP) or raylib.IsKeyDown(raylib.KEY_W)) camera.target.y -= speed / camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_DOWN) or raylib.IsKeyDown(raylib.KEY_S)) camera.target.y += speed / camera.zoom;

    return camera.zoom != last_zoom or raylib.Vector2Equals(camera.target, last_target) != 0;
}

pub const BoundBox = struct {
    xmin: usize,
    xmax: usize,
    ymin: usize,
    ymax: usize,
    grid: *const Grid,

    iter: ?Idx = null,

    pub fn iterNext(self: *BoundBox) ?Idx {
        if (self.iter == null) {
            self.iter = self.grid.idxFromCoords(self.xmin, self.ymin);
        } else {
            self.iter = self.iter.? + 1;
            const x = self.grid.xFromIdx(self.iter.?);
            const y = self.grid.yFromIdx(self.iter.?);
            if (x >= self.xmax) self.iter = self.grid.idxFromCoords(self.xmin, y + 1);
        }
        if (!self.grid.contains(self.iter.?)) self.iter = null;
        return self.iter;
    }

    pub fn restart(self: *BoundBox) void {
        self.iter = null;
    }

    pub fn contains(self: *const BoundBox, idx: Idx) bool {
        const x = self.grid.xFromIdx(idx);
        const y = self.grid.yFromIdx(idx);
        return x < self.xmax and y < self.ymax and x >= self.xmin and y >= self.ymin;
    }
};
