const std = @import("std");

const TextureSet = @import("TextureSet.zig");

const Grid = @import("../Grid.zig");
const Idx = Grid.Idx;

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

const Self = @This();

pub const BoundingBox = struct {
    x_min: usize,
    x_max: usize,
    y_min: usize,
    y_max: usize,

    pub fn contains(self: BoundingBox, x: usize, y: usize) bool {
        return x >= self.x_min and y >= self.y_min and x <= self.x_max and y <= self.y_max;
    }
};

camera: raylib.Camera2D,

pub fn init(screen_width: usize, screen_height: usize) Self {
    return .{
        .camera = .{
            .target = raylib.Vector2{ .x = 0.0, .y = 0.0 },
            .offset = raylib.Vector2{
                .x = @floatFromInt(screen_width / 2),
                .y = @floatFromInt(screen_height / 2),
            },
            .zoom = 0.5,
        },
    };
}

pub fn update(self: *Self, speed: f32) bool {
    const last_zoom = self.camera.zoom;
    const last_target = self.camera.target;

    // Drag controls
    if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_MIDDLE)) {
        const delta = raylib.Vector2Scale(raylib.GetMouseDelta(), -1.0 / self.camera.zoom);

        self.camera.target = raylib.Vector2Add(self.camera.target, delta);
    }

    // Zoom controls
    const wheel = raylib.GetMouseWheelMove();
    if (wheel != 0.0) {
        const world_pos = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), self.camera);

        self.camera.offset = raylib.GetMousePosition();
        self.camera.target = world_pos;

        const zoom_inc = 0.3;
        self.camera.zoom += (wheel * zoom_inc);
        self.camera.zoom = std.math.clamp(self.camera.zoom, 0.3, 3.0);
    }

    // Arrow key controls
    if (raylib.IsKeyDown(raylib.KEY_RIGHT) or raylib.IsKeyDown(raylib.KEY_D)) self.camera.target.x += speed / self.camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_LEFT) or raylib.IsKeyDown(raylib.KEY_A)) self.camera.target.x -= speed / self.camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_UP) or raylib.IsKeyDown(raylib.KEY_W)) self.camera.target.y -= speed / self.camera.zoom;
    if (raylib.IsKeyDown(raylib.KEY_DOWN) or raylib.IsKeyDown(raylib.KEY_S)) self.camera.target.y += speed / self.camera.zoom;

    return self.camera.zoom != last_zoom or raylib.Vector2Equals(self.camera.target, last_target) != 0;
}

pub fn boundingBox(
    self: *const Self,
    tile_width: usize,
    tile_height: usize,
    screen_width: usize,
    screen_height: usize,
    ts: TextureSet,
) BoundingBox {
    // TODO FIX this, Y bounds seem off
    const top_left = raylib.GetScreenToWorld2D(raylib.Vector2{}, self.camera);
    const bottom_right = raylib.GetScreenToWorld2D(raylib.Vector2{
        .x = @floatFromInt(screen_width),
        .y = @as(f32, @floatFromInt(screen_height)),
    }, self.camera);

    const min_x: usize = @intFromFloat(@max(
        0.0,
        @round(top_left.x / ts.hex_width) - 2.0,
    ));
    const max_x: usize = @intFromFloat(@max(
        0.0,
        @round(bottom_right.x / ts.hex_width) + 2.0,
    ));

    const min_y: usize = @intFromFloat(@max(0.0, @round(
        top_left.y / (ts.hex_height),
    ) - 2));
    const max_y: usize = @intFromFloat(@max(0.0, @round(
        bottom_right.y / (ts.hex_height) * 1.5,
    ) + 2));

    return .{
        .x_max = @min(tile_width, max_x),
        .x_min = @min(tile_width, min_x),
        .y_max = @min(tile_height, max_y),
        .y_min = @min(tile_height, min_y),
    };
}

pub fn getMouseTile(
    self: *const Self,
    grid: Grid,
    bounding_box: BoundingBox,
    ts: TextureSet,
) Idx {
    const click_point = raylib.GetScreenToWorld2D(raylib.GetMousePosition(), self.camera);

    return self.getPointIdx(
        click_point.x,
        click_point.y,
        grid,
        bounding_box,
        ts,
    );
}

// TODO Don't loop over bounding box
pub fn getPointIdx(
    _: *const Self,
    xf: f32,
    yf: f32,
    grid: Grid,
    bounding_box: BoundingBox,
    ts: TextureSet,
) Idx {
    var idx: Grid.Idx = 0;

    var min_dist: f32 = std.math.floatMax(f32);
    for (bounding_box.x_min..bounding_box.x_max) |x| {
        for (bounding_box.y_min..bounding_box.y_max) |y| {
            const real_x = ts.tilingX(x, y) + ts.hex_height * 0.5;
            const real_y = ts.tilingY(y) + ts.hex_width * 0.5;
            const dist = std.math.pow(f32, real_x -
                xf, 2) + std.math.pow(f32, real_y - yf, 2);
            if (dist < min_dist) {
                idx = grid.idxFromCoords(x, y);
                min_dist = dist;
            }
        }
    }
    return idx;
}
