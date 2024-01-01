const Self = @This();
const std = @import("std");

fn lerp(a: f32, b: f32, t: f32) f32 {
    if (t >= 1.0) return b;
    if (t <= 0.0) return a;
    //return (b - a) * t + a; // lerp

    return (b - a) * (3.0 - t * 2.0) * t * t + a; // extra smooth (nlerp)

}

const Vec2 = struct { x: f32, y: f32 };
fn randomGrad(ix: usize, iy: usize, seed: u64) Vec2 {
    const w: u64 = 8 * @sizeOf(usize);
    const s: u64 = w / 2; // rotation width
    var a: u64 = ix ^ seed;
    var b: u64 = iy ^ seed;

    a = a *% 3284157443;
    b ^= a << s | a >> (w - s);
    b = b *% 1911520717;
    a ^= b << s | b >> (w - s);
    a = a *% 2048419325;

    var rand = std.rand.DefaultPrng.init(a);
    const angle = rand.random().float(f32) * std.math.pi;

    return Vec2{ .x = std.math.cos(angle), .y = std.math.sin(angle) };
}

fn dotWithGrad(ix: usize, iy: usize, x: f32, y: f32, seed: u64) f32 {

    // Get gradient from integer coordinates
    const grad = randomGrad(ix, iy, seed);

    // Compute the distance vector
    const dx = x - @as(f32, @floatFromInt(ix));
    const dy = y - @as(f32, @floatFromInt(iy));

    // Compute the dot-product
    return (dx * grad.x + dy * grad.y);
}

// Compute Perlin noise at coordinates x, y
pub fn perlin(x: f32, y: f32, seed: u64) f32 {

    // Determine grid cell coordinates
    const x0: usize = @intFromFloat(x);
    const x1: usize = x0 + 1;
    const y0: usize = @intFromFloat(y);
    const y1: usize = y0 + 1;

    // Determine interpolation weights
    // Could also use higher order polynomial/s-curve here
    const sx: f32 = x - @as(f32, @floatFromInt(x0));
    const sy: f32 = y - @as(f32, @floatFromInt(y0));
    // Interpolate between grid point gradients

    var n0: f32 = dotWithGrad(x0, y0, x, y, seed);
    var n1: f32 = dotWithGrad(x1, y0, x, y, seed);
    const ix0: f32 = lerp(n0, n1, sx);

    n0 = dotWithGrad(x0, y1, x, y, seed);
    n1 = dotWithGrad(x1, y1, x, y, seed);
    const ix1: f32 = lerp(n0, n1, sx);

    const value = lerp(ix0, ix1, sy);
    return value * 0.5 + 0.5;
}
