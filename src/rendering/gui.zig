const Camera = @import("Camera.zig");
const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub const InfoWindowOptions = struct {
    LINE_HEIGHT: f32 = 20,

    SPACEING: f32 = 5,
    TOP_SPACEING: f32 = 30,
    WIDTH: f32 = 200,

    MAX_LINES: u16 = 255,
    X_TO_CLOSE: bool = false,
    X_TO_COLLAPSE: bool = true,

    START_COLLAPSED: bool = true,
    COLLAPSED_HEIGHT: f32 = 50, // should always be > 2x window top bar size
};

pub fn InfoWindow(options: InfoWindowOptions) type {
    return struct {
        const Self = @This();

        const OPTIONS = options;

        name: [255:0]u8 = undefined,

        should_close: bool = false,
        collapsed: bool,

        len: u16,
        lines: [OPTIONS.MAX_LINES]Line,

        bounds: raylib.Rectangle,

        draging_window: bool = false,

        const Line = struct {
            id: u16,
            value: [255:0]u8,
            category_header: bool = false,
        };

        pub fn newEmpty() Self {
            var out: Self = .{
                .len = 0,
                .lines = undefined,
                .bounds = .{ .x = 10, .y = 10, .width = OPTIONS.WIDTH, .height = OPTIONS.TOP_SPACEING },
                .collapsed = OPTIONS.START_COLLAPSED,
            };
            out.setName("[SELECT WINDOW]");
            out.recalculateBounds();
            return out;
        }

        pub fn setName(self: *Self, name: []const u8) void {
            _ = std.fmt.bufPrintZ(&self.name, "{s}", .{name}) catch unreachable;
        }

        pub fn addLineFormat(self: *Self, comptime fmt: []const u8, fmt_args: anytype, category_header: bool) void {
            _ = std.fmt.bufPrintZ(&self.lines[self.len].value, fmt, fmt_args) catch
                std.debug.panic("LINE TOO LONG!", .{});
            self.lines[self.len].id = self.len;
            self.lines[self.len].category_header = category_header;
            self.len += 1;

            self.recalculateBounds();
        }

        pub fn addLine(self: *Self, line: []const u8) void {
            self.addLineFormat("{s}", .{line}, false);
        }

        pub fn addCategoryHeader(self: *Self, line: []const u8) void {
            self.addLineFormat("{s}", .{line}, true);
        }

        pub fn clear(self: *Self) void {
            self.lines = undefined;
            self.len = 0;
        }

        pub fn renderUpdate(self: *Self) void {
            self.handleDrag();

            if (raylib.GuiWindowBox(self.bounds, &self.name) != 0) {
                if (OPTIONS.X_TO_CLOSE) self.should_close = true;
                if (OPTIONS.X_TO_COLLAPSE) self.collapsed = !self.collapsed;
                self.recalculateBounds();
            }

            if (self.collapsed) {
                const box = rectanglePadded(splitRectangleHorizontal(self.bounds, 0.5).bottom, 2);

                if (self.collapsed)
                    if (raylib.GuiButton(box, "Click HERE to expand...") != 0) {
                        self.collapsed = false;
                        self.recalculateBounds();
                    };
                return;
            }

            for (self.lines[0..self.len], 0..) |line, i| {
                if (line.category_header)
                    _ = raylib.GuiLine(self.entryBounds(@intCast(i)), &line.value)
                else
                    _ = raylib.GuiLabel(self.entryBounds(@intCast(i)), &line.value);
            }
        }

        fn entryBounds(self: *const Self, i: u16) raylib.Rectangle {
            return .{
                .x = self.bounds.x + OPTIONS.SPACEING,
                .y = self.bounds.y + (OPTIONS.SPACEING + OPTIONS.LINE_HEIGHT * @as(f32, @floatFromInt(i))) + OPTIONS.TOP_SPACEING,
                .width = OPTIONS.WIDTH - 2 * OPTIONS.SPACEING,
                .height = OPTIONS.LINE_HEIGHT,
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
                self.bounds.width = OPTIONS.WIDTH;
                self.bounds.height = OPTIONS.COLLAPSED_HEIGHT;
            } else {
                self.bounds.width = OPTIONS.WIDTH;
                self.bounds.height = OPTIONS.TOP_SPACEING + OPTIONS.LINE_HEIGHT * @as(f32, @floatFromInt(self.len)) + OPTIONS.SPACEING;
            }
        }
    };
}

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
    KEEP_HIGHLIGHT: bool = true,
    NULL_OPTION: bool = false,
    TEXTURE_ENTRY_FRACTION: f32 = 0.75,
    START_COLLAPSED: bool = true,
    COLLAPSED_HEIGHT: f32 = 50, // should always be > 2x window top bar size
};

pub fn SelectWindow(comptime R: type, comptime options: SelectWindowOptions) type {
    return struct {
        const Self = @This();

        const OPTIONS = options;

        name: [255:0]u8 = undefined,

        should_close: bool = false,
        collapsed: bool,
        hidden: bool = false,
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
            var out: Self = .{
                .len = 0,
                .items = undefined,
                .bounds = .{ .x = 10, .y = 10, .width = OPTIONS.WIDTH, .height = OPTIONS.TOP_SPACEING },
                .collapsed = OPTIONS.START_COLLAPSED,
            };
            out.setName("[SELECT WINDOW]");
            return out;
        }

        pub fn new(values: []R) Self {
            var out = newEmpty();
            for (values) |value| {
                out.addItem(value);
            }
            return out;
        }

        pub fn setName(self: *Self, name: []const u8) void {
            _ = std.fmt.bufPrintZ(&self.name, "{s}", .{name}) catch unreachable;
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

        pub fn clearItems(self: *Self) void {
            self.len = 0;
        }

        pub fn addItemTexture(self: *Self, value: R, label: []const u8, texture: ?raylib.Texture2D) void {
            self.addItem(value, label);
            if (texture) |t| {
                self.items[self.len - 1].texture = t;
            }
        }

        pub fn renderUpdate(self: *Self) void {
            if (self.hidden) return;
            self.handleDrag();

            if (raylib.GuiWindowBox(self.bounds, &self.name) != 0) {
                if (OPTIONS.X_TO_CLOSE) self.should_close = true;
                if (OPTIONS.X_TO_COLLAPSE) self.collapsed = !self.collapsed;
                self.recalculateBounds();
            }

            if (self.collapsed) {
                const box = rectanglePadded(splitRectangleHorizontal(self.bounds, 0.5).bottom, 2);

                if (self.collapsed)
                    if (raylib.GuiButton(box, "Click HERE to expand...") != 0) {
                        self.collapsed = false;
                        self.recalculateBounds();
                    };
                return;
            }

            for (self.items[0..self.len], 0..) |item, i| {
                var box = self.entryBounds(@intCast(i));
                if (self.last_i) |last| if (last == i and OPTIONS.KEEP_HIGHLIGHT) raylib.DrawRectangleRec(box, raylib.BLUE);

                const split_box = splitRectangleHorizontal(box, OPTIONS.TEXTURE_ENTRY_FRACTION);
                if (item.texture) |texture| {
                    textureInRectangle(rectanglePadded(split_box.top, OPTIONS.SPACEING), texture);
                    box = split_box.bottom;
                }

                if (raylib.GuiButton(rectanglePadded(box, OPTIONS.SPACEING), &item.label) != 0) {
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
            const res = self.fetchSelectedNull(&selected);
            if (selected == null) return false;
            destination.* = selected.?;
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
            if (self.hidden) return false;
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
                self.bounds.height = OPTIONS.COLLAPSED_HEIGHT;
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
