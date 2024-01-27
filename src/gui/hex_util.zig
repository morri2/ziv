const std = @import("std");

pub fn widthFromRadius(radius: f32) f32 {
    return radius * @sqrt(3.0);
}

pub fn heightFromRadius(radius: f32) f32 {
    return radius * 2.0;
}

pub fn tilingX(x: usize, y: usize, radius: f32) f32 {
    const fx: f32 = @floatFromInt(x);
    const y_odd: f32 = @floatFromInt(y & 1);

    return widthFromRadius(radius) * fx + widthFromRadius(radius) * 0.5 * y_odd;
}

pub fn tilingY(y: usize, radius: f32) f32 {
    const fy: f32 = @floatFromInt(y);
    return fy * radius * 1.5;
}

pub fn tilingWidth(map_width: usize, radius: f32) f32 {
    const fwidth: f32 = @floatFromInt(map_width);
    return widthFromRadius(radius) * fwidth + widthFromRadius(radius) * 0.5;
}

pub fn tilingHeight(map_height: usize, radius: f32) f32 {
    const fheight: f32 = @floatFromInt(map_height);
    return radius * 1.5 * (fheight - 1.0) + heightFromRadius(radius);
}
