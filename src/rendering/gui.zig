const Camera = @import("Camera.zig");
const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub const SelectWindowOptions = struct {
    ENTRY_HEIGHT: f32 = 100,
    SPACEING: f32 = 5,
    TOP_SPACEING: f32 = 30,
    WIDTH: f32 = 200,
    COLUMNS: u16 = 1,
    MAX_LABEL_LEN: u16 = 64,
    MAX_ITEMS: u16 = 255,
    X_TO_CLOSE: bool = false,
    X_TO_COLLAPSE: bool = true,
    CLOSE_AFTER_SELECT: bool = false,
    NULL_OPTION: bool = false,
    TEXTURE_ENTRY_FRACTION: f32 = 0.75,
};

// Popsup
pub fn SelectWindow(comptime R: type, comptime option: SelectWindowOptions) type {
    return struct {
        const Self = @This();

        const OPTIONS = option;

        should_close: bool = false,
        collapsed: bool = false,
        new_selection: bool = false,
        last_selection: ?R = null,
        last_i: ?u16 = null,

        len: u16,
        items: [OPTIONS.MAX_ITEMS]Item,
        bounds: raylib.Rectangle,

        draging_window: bool = false,

        const Item = struct {
            id: u16,
            value: R,
            label: [OPTIONS.MAX_LABEL_LEN:0]u8,
            texture: ?raylib.Texture2D = null,
        };

        pub fn newEmpty() Self {
            return .{ .len = 0, .items = undefined, .bounds = .{ .x = 10, .y = 10, .width = OPTIONS.WIDTH, .height = OPTIONS.TOP_SPACEING } };
        }

        pub fn new(values: []R) Self {
            var out = newEmpty();
            for (values) |value| {
                out.addItem(value);
            }
            return out;
        }

        pub fn addItem(self: *Self, value: R, label: []const u8) void {
            var buf: [OPTIONS.MAX_LABEL_LEN:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&buf, "{}. {s}", .{ self.len, label }) catch
                std.debug.panic("GUI LABEL TOO LONG!", .{});

            if (self.len < OPTIONS.MAX_ITEMS - 1) {
                self.items[self.len] = .{ .id = self.len, .value = value, .label = buf };
                self.len += 1;
                self.recalculateBounds();
            } else std.debug.panic("GUI LIST IS FULL!", .{});
        }

        pub fn addItemTexture(self: *Self, value: R, label: []const u8, texture: ?raylib.Texture2D) void {
            self.addItem(value, label);
            if (texture) |t| {
                self.items[self.len - 1].texture = t;
            }
        }

        pub fn renderUpdate(self: *Self) void {
            self.handleDrag();

            if (raylib.GuiWindowBox(self.bounds, "SELECT WINDOW") != 0) {
                if (OPTIONS.X_TO_CLOSE) self.should_close = true;
                if (OPTIONS.X_TO_COLLAPSE) self.collapsed = !self.collapsed;
                self.recalculateBounds();
            }

            if (self.collapsed) return;

            for (self.items[0..self.len], 0..) |item, i| {
                const box = self.entryBounds(@intCast(i));
                if (self.last_i) |last| if (last == i) raylib.DrawRectangleRec(box, raylib.BLUE);

                const split_box = splitRectangleHorizontal(box, OPTIONS.TEXTURE_ENTRY_FRACTION);
                if (item.texture) |texture|
                    textureInRectangle(rectanglePadded(split_box.top, OPTIONS.SPACEING), texture);

                if (raylib.GuiButton(rectanglePadded(split_box.bottom, OPTIONS.SPACEING), &item.label) != 0) {
                    self.new_selection = true;
                    self.last_selection = item.value;
                    self.last_i = @intCast(i);
                }
            }

            if (OPTIONS.NULL_OPTION) {
                if (raylib.GuiButton(rectanglePadded(self.entryBounds(self.len), OPTIONS.SPACEING), "None") != 0) {
                    self.new_selection = true;
                    self.last_selection = null;
                    self.last_i = null;
                }
            }
        }

        pub fn fetchSelectedNull(self: *Self, destination: *?R) bool {
            if (!self.new_selection) return false;
            destination.* = self.last_selection;

            self.new_selection = false;
            if (OPTIONS.CLOSE_AFTER_SELECT) self.should_close = true;
            return true;
        }

        pub fn fetchSelected(self: *Self, destination: *R) bool {
            var selected: ?R = null;
            const res = self.fetchSelected(&selected);
            if (selected == null) return false;
            destination = selected.?;
            return res;
        }

        fn entryBounds(self: *const Self, i: u16) raylib.Rectangle {
            const col: f32 = @floatFromInt(i % OPTIONS.COLUMNS);
            const row: f32 = @floatFromInt(i / OPTIONS.COLUMNS);
            const col_width = OPTIONS.WIDTH / OPTIONS.COLUMNS;
            return .{
                .x = self.bounds.x + col_width * col,
                .y = self.bounds.y + OPTIONS.ENTRY_HEIGHT * row + OPTIONS.TOP_SPACEING,
                .width = col_width,
                .height = OPTIONS.ENTRY_HEIGHT,
            };
        }

        pub fn checkMouseCapture(self: *const Self) bool {
            const mouse_pos = raylib.GetMousePosition();
            const delta = raylib.GetMouseDelta();
            const mouse_last = raylib.Vector2Subtract(mouse_pos, delta);
            return (raylib.CheckCollisionPointRec(mouse_pos, self.bounds)) or
                (raylib.CheckCollisionPointRec(mouse_last, self.bounds));
        }

        pub fn handleDrag(self: *Self) void {
            if (!raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT) and raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT)) {
                const mouse_pos = raylib.GetMousePosition();
                const delta = raylib.GetMouseDelta();
                const mouse_last = raylib.Vector2Subtract(mouse_pos, delta);

                var header_rect: raylib.Rectangle = self.bounds;
                header_rect.height = 25; // PLACEHOLDER NUMBER
                if (raylib.CheckCollisionPointRec(mouse_last, header_rect)) {
                    self.bounds.x += delta.x;
                    self.bounds.y += delta.y;
                }
            }
        }

        fn recalculateBounds(self: *Self) void {
            if (self.collapsed) {
                self.bounds.height = 0;
            } else {
                self.bounds.width = @min(OPTIONS.WIDTH, @as(f32, @floatFromInt(self.cols())) * (OPTIONS.WIDTH / OPTIONS.COLUMNS));
                self.bounds.height = OPTIONS.TOP_SPACEING + @as(f32, @floatFromInt(self.rows())) * (OPTIONS.ENTRY_HEIGHT + OPTIONS.SPACEING);
            }
        }

        fn entryCount(self: *const Self) u16 {
            return self.len + @intFromBool(OPTIONS.NULL_OPTION);
        }

        fn rows(self: *const Self) u16 {
            return @divFloor(self.entryCount(), OPTIONS.COLUMNS) +
                @intFromBool(self.entryCount() % OPTIONS.COLUMNS != 0);
        }

        fn cols(self: *const Self) u16 {
            return @min(self.entryCount(), OPTIONS.COLUMNS);
        }
    };
}

pub fn rectanglePadded(rect: raylib.Rectangle, padding: f32) raylib.Rectangle {
    return .{ .x = rect.x + padding, .y = rect.y + padding, .width = @max(0, rect.width - 2 * padding), .height = @max(0, rect.height - 2 * padding) };
}

pub fn textureInRectangle(rect: raylib.Rectangle, texture: raylib.Texture2D) void {
    const width: f32 = @as(f32, @floatFromInt(texture.width));
    const height: f32 = @as(f32, @floatFromInt(texture.height));

    const scale = @min(rect.width / width, rect.height / height);

    raylib.DrawTextureEx(
        texture,
        .{ .y = rect.y, .x = rect.x + rect.width / 2 - width * scale / 2 },
        0,
        scale,
        raylib.WHITE,
    );
}

pub fn splitRectangleHorizontal(rect: raylib.Rectangle, t: f32) struct { top: raylib.Rectangle, bottom: raylib.Rectangle } {
    const top: raylib.Rectangle = .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = rect.height * t };
    const bottom: raylib.Rectangle = .{ .x = rect.x, .y = rect.y + top.height, .width = rect.width, .height = rect.height * (1 - t) };
    return .{ .top = top, .bottom = bottom };
}
