pub fn width(radius: f32) f32 {
    return radius * @sqrt(3.0);
}

pub fn height(radius: f32) f32 {
    return radius * 2.0;
}

pub fn tilingPosX(x: usize, y: usize, radius: f32) f32 {
    const fx: f32 = @floatFromInt(x);
    const y_odd: f32 = @floatFromInt(y & 1);

    return width(radius) * fx + width(radius) * 0.5 * y_odd;
}

pub fn tilingPosY(y: usize, radius: f32) f32 {
    const fy: f32 = @floatFromInt(y);
    return fy * radius * 1.5;
}

pub fn tilingWidth(map_width: usize, radius: f32) f32 {
    const fwidth: f32 = @floatFromInt(map_width);
    return width(radius) * fwidth + width(radius) * 0.5;
}

pub fn tilingHeight(map_height: usize, radius: f32) f32 {
    const fheight: f32 = @floatFromInt(map_height);
    return radius * 1.5 * (fheight - 1.0) + height(radius);
}
