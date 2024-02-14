const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("raygui.h");
});

pub const InfoWindowOptions = struct {
    line_height: f32 = 20,

    spacing: f32 = 5,
    top_spacing: f32 = 30,
    width: f32 = 200,

    max_lines: u16 = 255,

    collapsed_height: f32 = 50, // should always be > 2x window top bar size
};

pub fn InfoWindow(comptime name: [*:0]const u8, comptime options: InfoWindowOptions) type {
    return struct {
        const Self = @This();

        collapsed: bool,

        len: u16,
        lines: [options.max_lines]Line,

        bounds: raylib.Rectangle,

        const Line = struct {
            id: u16,
            value: [255:0]u8,
            category_header: bool = false,
        };

        pub fn newEmpty(collapsed: bool) Self {
            var out: Self = .{
                .len = 0,
                .lines = undefined,
                .bounds = .{
                    .x = 10,
                    .y = 10,
                    .width = options.width,
                    .height = options.top_spacing,
                },
                .collapsed = collapsed,
            };
            out.recalculateBounds();
            return out;
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
            self.recalculateBounds();
        }

        pub fn renderUpdate(self: *Self, accept_input: bool) void {
            self.handleDrag(accept_input);

            if (raylib.GuiWindowBox(self.bounds, name) != 0 and accept_input) {
                self.collapsed = !self.collapsed;
                self.recalculateBounds();
            }

            if (self.collapsed) {
                const box = rectanglePadded(splitRectangleHorizontal(self.bounds, 0.5).bottom, 2);

                if (self.collapsed)
                    if (raylib.GuiButton(box, "Click HERE to expand...") != 0 and accept_input) {
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
                .x = self.bounds.x + options.spacing,
                .y = self.bounds.y + (options.spacing + options.line_height * @as(f32, @floatFromInt(i))) + options.top_spacing,
                .width = options.width - 2 * options.spacing,
                .height = options.line_height,
            };
        }

        pub fn checkMouseCapture(self: *const Self) bool {
            const mouse_pos = raylib.GetMousePosition();
            const delta = raylib.GetMouseDelta();
            const mouse_last = raylib.Vector2Subtract(mouse_pos, delta);
            return (raylib.CheckCollisionPointRec(mouse_pos, self.bounds)) or
                (raylib.CheckCollisionPointRec(mouse_last, self.bounds));
        }

        fn handleDrag(self: *Self, accept_input: bool) void {
            if (!raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT) and raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT) and accept_input) {
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
                self.bounds.width = options.width;
                self.bounds.height = options.collapsed_height;
            } else {
                self.bounds.width = options.width;
                self.bounds.height = options.top_spacing + options.line_height * @as(f32, @floatFromInt(self.len)) + options.spacing;
            }
        }
    };
}

pub const SelectWindowOptions = struct {
    entry_height: f32 = 100,
    spacing: f32 = 5,
    top_spacing: f32 = 30,
    width: f32 = 200,
    columns: u16 = 1,
    max_label_len: u16 = 64,
    max_items: u16 = 255,
    keep_highlight: bool = true,
    nullable: enum {
        not_nullable,
        nullable,
        null_option,
    } = .nullable,
    texture_entry_fraction: f32 = 0.75,
    collapsed_height: f32 = 50, // should always be > 2x window top bar size
};

pub fn SelectWindow(comptime name: [*:0]const u8, comptime Type: type, comptime options: SelectWindowOptions) type {
    return struct {
        const Self = @This();

        const Selected = if (options.nullable == .not_nullable) Type else ?Type;

        collapsed: bool,
        new_selection: bool = false,
        selected: Selected,

        len: u16,
        items: [options.max_items]Item,
        bounds: raylib.Rectangle,

        const Item = struct {
            id: u16,
            value: Type,
            label: [options.max_label_len:0]u8,
            texture: ?raylib.Texture2D = null,
        };

        pub fn newEmpty(collapsed: bool, initial_selected: Selected) Self {
            return .{
                .len = 0,
                .items = undefined,
                .bounds = .{ .x = 10, .y = 10, .width = options.width, .height = options.top_spacing },
                .collapsed = collapsed,
                .selected = initial_selected,
            };
        }

        pub fn new(values: []const Type) Self {
            var out = newEmpty();
            for (values) |value| {
                out.addItem(value);
            }
            return out;
        }

        pub fn addItem(self: *Self, value: Type, label: []const u8) void {
            var buf: [options.max_label_len:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&buf, "{}. {s}", .{ self.len, label }) catch
                std.debug.panic("GUI LABEL TOO LONG!", .{});

            if (self.len < options.max_items - 1) {
                self.items[self.len] = .{ .id = self.len, .value = value, .label = buf };
                self.len += 1;
                self.recalculateBounds();
            } else std.debug.panic("GUI LIST IS FULL!", .{});
        }

        pub fn clearItems(self: *Self) void {
            self.len = 0;
        }

        pub fn addItemTexture(self: *Self, value: Type, label: []const u8, texture: raylib.Texture2D) void {
            self.addItem(value, label);
            self.items[self.len - 1].texture = texture;
        }

        pub fn renderUpdate(self: *Self, accept_input: bool) void {
            self.handleDrag(accept_input);

            if (raylib.GuiWindowBox(self.bounds, name) != 0 and accept_input) {
                self.collapsed = !self.collapsed;
                self.recalculateBounds();
            }

            if (self.collapsed) {
                const box = rectanglePadded(splitRectangleHorizontal(self.bounds, 0.5).bottom, 2);

                if (self.collapsed) if (raylib.GuiButton(box, "Click HERE to expand...") != 0 and accept_input) {
                    self.collapsed = false;
                    self.recalculateBounds();
                };
                return;
            }

            self.new_selection = false;
            for (self.items[0..self.len], 0..) |item, i| {
                var box = self.entryBounds(@intCast(i));
                if (options.keep_highlight) {
                    if (options.nullable == .not_nullable) {
                        if (std.mem.eql(
                            u8,
                            std.mem.asBytes(&self.selected),
                            std.mem.asBytes(&item.value),
                        )) {
                            raylib.DrawRectangleRec(box, raylib.BLUE);
                        }
                    } else {
                        if (self.selected) |selected| if (std.mem.eql(
                            u8,
                            std.mem.asBytes(&selected),
                            std.mem.asBytes(&item.value),
                        )) {
                            raylib.DrawRectangleRec(box, raylib.BLUE);
                        };
                    }
                }

                const split_box = splitRectangleHorizontal(box, options.texture_entry_fraction);
                if (item.texture) |texture| {
                    textureInRectangle(rectanglePadded(split_box.top, options.spacing), texture);
                    box = split_box.bottom;
                }

                if (raylib.GuiButton(rectanglePadded(box, options.spacing), &item.label) != 0 and accept_input) {
                    self.new_selection = true;
                    self.selected = item.value;
                }
            }

            if (options.nullable == .null_option) {
                if (raylib.GuiButton(rectanglePadded(self.entryBounds(self.len), options.spacing), "None") != 0 and accept_input) {
                    self.new_selection = true;
                    self.selected = null;
                }
            }

            if (options.nullable != .not_nullable and !options.keep_highlight and !self.new_selection) {
                self.selected = null;
            }
        }

        pub fn getSelected(self: *const Self) Selected {
            return self.selected;
        }

        pub fn checkMouseCapture(self: *const Self) bool {
            const mouse_pos = raylib.GetMousePosition();
            const delta = raylib.GetMouseDelta();
            const mouse_last = raylib.Vector2Subtract(mouse_pos, delta);
            return (raylib.CheckCollisionPointRec(mouse_pos, self.bounds)) or
                (raylib.CheckCollisionPointRec(mouse_last, self.bounds));
        }

        fn handleDrag(self: *Self, accept_input: bool) void {
            if (!raylib.IsMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT) and raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT) and accept_input) {
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

        fn entryBounds(self: *const Self, i: u16) raylib.Rectangle {
            const col: f32 = @floatFromInt(i % options.columns);
            const row: f32 = @floatFromInt(i / options.columns);
            const col_width = options.width / options.columns;
            return .{
                .x = self.bounds.x + col_width * col,
                .y = self.bounds.y + options.entry_height * row + options.top_spacing,
                .width = col_width,
                .height = options.entry_height,
            };
        }

        fn recalculateBounds(self: *Self) void {
            if (self.collapsed) {
                self.bounds.height = options.collapsed_height;
            } else {
                self.bounds.width = std.math.clamp(
                    @as(f32, @floatFromInt(self.cols())) * (options.width / options.columns),
                    50,
                    options.width,
                );
                self.bounds.height = options.top_spacing + @as(f32, @floatFromInt(self.rows())) * (options.entry_height + options.spacing);
            }
        }

        fn entryCount(self: *const Self) u16 {
            return self.len + @intFromBool(options.nullable == .null_option);
        }

        fn rows(self: *const Self) u16 {
            return @divFloor(self.entryCount(), options.columns) +
                @intFromBool(self.entryCount() % options.columns != 0);
        }

        fn cols(self: *const Self) u16 {
            return @min(self.entryCount(), options.columns);
        }
    };
}

fn rectanglePadded(rect: raylib.Rectangle, padding: f32) raylib.Rectangle {
    return .{
        .x = rect.x + padding,
        .y = rect.y + padding,
        .width = @max(0, rect.width - 2 * padding),
        .height = @max(0, rect.height - 2 * padding),
    };
}

fn textureInRectangle(rect: raylib.Rectangle, texture: raylib.Texture2D) void {
    const width: f32 = @as(f32, @floatFromInt(texture.width));
    const height: f32 = @as(f32, @floatFromInt(texture.height));

    const scale = @min(rect.width / width, rect.height / height);

    raylib.DrawTextureEx(
        texture,
        .{
            .y = rect.y,
            .x = rect.x + rect.width / 2 - width * scale / 2,
        },
        0,
        scale,
        raylib.WHITE,
    );
}

fn splitRectangleHorizontal(rect: raylib.Rectangle, t: f32) struct {
    top: raylib.Rectangle,
    bottom: raylib.Rectangle,
} {
    const top: raylib.Rectangle = .{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = rect.height * t,
    };
    const bottom: raylib.Rectangle = .{
        .x = rect.x,
        .y = rect.y + top.height,
        .width = rect.width,
        .height = rect.height * (1 - t),
    };
    return .{ .top = top, .bottom = bottom };
}
