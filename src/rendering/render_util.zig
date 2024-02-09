const std = @import("std");

const Grid = @import("../Grid.zig");
const Idx = Grid.Idx;

const TextureSet = @import("TextureSet.zig");

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub const RenderTextureArgs = struct {
    scale: f32 = 1.0,
    rotation: f32 = 0.0, // unstable? might fuck up with anything other than top_left
    tint: raylib.Color = raylib.WHITE,
    anchor: Anchor = .center,
};

pub const RenderTextArgs = struct {
    font: ?raylib.Font = null, // null -> ts default font
    font_size: f32 = 10,
    spaceing: f32 = 0.0,
    rotation: f32 = 0.0, // unstable? might fuck up with anything other than left anchor
    tint: raylib.Color = raylib.WHITE,
    anchor: Anchor = .center,
};

pub const CircleBarArgs = struct {
    bar_part: f32 = 0.2,
    radius: f32 = 0.2,
    anchor: Anchor = .center,
    bar_color: raylib.Color = raylib.GREEN,
    center_color: raylib.Color = raylib.GRAY,
};

pub const Anchor = enum {
    top_left,
    top_right,
    top_center,
    right,
    left,
    center,
    bottom_left,
    bottom_right,
    bottom_center,

    pub fn getOffset(self: @This(), width: f32, height: f32) raylib.Vector2 {
        const x: f32 = switch (self) {
            .top_left, .left, .bottom_left => -width / 2,
            .top_right, .right, .bottom_right => width / 2,
            else => 0.0,
        };

        const y: f32 = switch (self) {
            .top_left, .top_center, .top_right => -height / 2,
            .bottom_left, .bottom_center, .bottom_right => height / 2,
            else => 0.0,
        };

        return .{ .x = x, .y = y };
    }

    pub fn getOffsetRelative(self: @This(), width: f32, height: f32, ref: @This()) raylib.Vector2 {
        return raylib.Vector2Subtract(
            self.getOffset(width, height),
            ref.getOffset(width, height),
        );
    }
};

pub fn renderChargeCircleInHex(tile_idx: Idx, grid: Grid, fill_up: f32, off_x: f32, off_y: f32, args: CircleBarArgs, ts: TextureSet) void {
    renderChargeCircle(posInHex(tile_idx, grid, off_x, off_y, ts), fill_up, args, ts);
}
pub fn renderChargeCircle(pos: raylib.Vector2, fill_up: f32, args: CircleBarArgs, ts: TextureSet) void {
    const radius = args.radius * ts.unit;
    const pos_anchor = raylib.Vector2Add(pos, args.anchor.getOffsetRelative(
        radius * 2,
        radius * 2,
        .center,
    ));

    raylib.DrawCircleSector(pos_anchor, radius, 0, fill_up * 360, 32, args.bar_color);
    raylib.DrawCircleV(pos_anchor, radius * (1 - args.bar_part), args.center_color);
}

pub fn renderTextureInHexSeries(tile_idx: Idx, grid: Grid, texture: raylib.Texture2D, repeats: u8, off_x_start: f32, off_y: f32, spaceing: f32, args: RenderTextureArgs, ts: TextureSet) f32 {
    const step_off = (@as(f32, @floatFromInt(texture.width)) * args.scale / ts.unit + spaceing);
    for (0..repeats) |i| {
        const tot_off_x = off_x_start + @as(f32, @floatFromInt(i)) * step_off;
        renderTextureInHex(tile_idx, grid, texture, tot_off_x, off_y, args, ts);
    }
    return off_x_start + @as(f32, @floatFromInt(repeats)) * step_off;
}

/// Format print can do UP TO 31 characters
pub fn renderFormatHexAuto(idx: Idx, grid: Grid, comptime fmt: []const u8, fmt_args: anytype, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) void {
    const l = fmt.len;
    blk: {
        renderFormatHex(4 * l, idx, grid, //
            fmt, fmt_args, off_x, off_y, args, ts) catch break :blk;
        return;
    }
    blk: {
        renderFormatHex(16 * l, idx, grid, //
            fmt, fmt_args, off_x, off_y, args, ts) catch break :blk;
        return;
    }
    blk: {
        renderFormatHex(64 * l, idx, grid, //
            fmt, fmt_args, off_x, off_y, args, ts) catch break :blk;
        return;
    }
    renderFormatHex(1 << 16, idx, grid, //
        fmt, fmt_args, off_x, off_y, args, ts) catch
        @panic("Failed auto format.");
}

pub fn renderFormatHex(comptime buflen: comptime_int, idx: Idx, grid: Grid, comptime fmt: []const u8, fmt_args: anytype, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) !void {
    var buf: [buflen]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buf, fmt, fmt_args);
    renderTextInHex(idx, grid, text, off_x, off_y, args, ts);
}

/// Render text in hex. Render text with a relative position form tile center (offset messured in hex radius)
pub fn renderTextInHex(idx: Idx, grid: Grid, text: []const u8, off_x: f32, off_y: f32, args: RenderTextArgs, ts: TextureSet) void {
    const pos = posInHex(idx, grid, off_x, off_y, ts);
    renderText(text, args.font orelse ts.font, pos, args, ts);
}

/// Render texture
pub fn renderTextureHex(idx: Idx, grid: Grid, texture: raylib.Texture2D, args: RenderTextureArgs, ts: TextureSet) void {
    const pos = posInHex(idx, grid, 0, 0, ts);
    renderTexture(texture, pos, args);
}

/// Render texture in hex . Render text with a relative position form tile center (offset messured in hex radius)
pub fn renderTextureInHex(idx: Idx, grid: Grid, texture: raylib.Texture2D, off_x: f32, off_y: f32, args: RenderTextureArgs, ts: TextureSet) void {
    const pos = posInHex(idx, grid, off_x, off_y, ts);
    renderTexture(texture, pos, args);
}

/// returns the point relative to the center of a hex
pub fn posInHex(idx: Idx, grid: Grid, off_x: f32, off_y: f32, ts: TextureSet) raylib.Vector2 {
    const x = grid.xFromIdx(idx);
    const y = grid.yFromIdx(idx);
    const center_x = ts.tilingX(x, y) + ts.hex_width / 2.0;
    const center_y = ts.tilingY(y) + ts.hex_height / 2.0;

    return .{ .x = center_x + off_x * ts.hex_width / 2, .y = center_y + off_y * ts.hex_height / 2 };
}

/// Render text in hex. Render text with a relative position form tile center (offset messured in hex radius)
fn renderText(text: []const u8, font: raylib.Font, pos: raylib.Vector2, args: RenderTextArgs, ts: TextureSet) void {
    const font_size = args.font_size * ts.unit / 50;
    const text_messurements =
        raylib.MeasureTextEx(font, text.ptr, font_size, args.spaceing);

    const pos_anchor = raylib.Vector2Add(pos, args.anchor.getOffsetRelative(
        text_messurements.x,
        text_messurements.y,
        .bottom_right, // .center, //.top_left,
    ));

    raylib.DrawTextEx(font, text.ptr, pos_anchor, font_size, args.spaceing, args.tint);
}

fn renderTexture(texture: raylib.Texture2D, pos: raylib.Vector2, args: RenderTextureArgs) void {
    const pos_anchor = raylib.Vector2Add(pos, args.anchor.getOffsetRelative(
        @as(f32, @floatFromInt(texture.width)) * args.scale,
        @as(f32, @floatFromInt(texture.height)) * args.scale,
        .bottom_right, // .center, //.top_left,
    ));

    raylib.DrawTextureEx(texture, pos_anchor, args.rotation, args.scale, args.tint);
}
