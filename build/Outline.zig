const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const Allocator = std.mem.Allocator;

const Self = @This();

const Reader = std.fs.File.Reader;
const Writer = std.fs.File.Writer;

src_path: []const u8,
target_path: []const u8,
src_file: std.fs.File,
target_file: std.fs.File,
reader: Reader,
writer: Writer,
imports: std.StringHashMapUnmanaged(void),
allocator: Allocator,
done: bool = false,

pub fn init(src_path: []const u8, target_path: []const u8, allocator: Allocator) !Self {
    var src_file = try std.fs.cwd().openFile(src_path, .{});
    var target_file = try std.fs.cwd().createFile(target_path, .{});
    const reader = src_file.reader();
    const writer = target_file.writer();

    var self: Self = .{
        .allocator = allocator,
        .imports = .{},
        .src_path = src_path,
        .target_path = target_path,
        .src_file = src_file,
        .target_file = target_file,
        .reader = reader,
        .writer = writer,
    };
    _ = try self.next_field();
    return self;
}

pub fn get_writer(self: Self) Writer {
    return self.writer;
}

pub fn deinit(self: Self) void {
    self.src_file.close();
    self.target_file.close();
    self.imports.deinit(self.allocator);
}

pub fn replace_src(self: Self, src_path: []const u8) !void {
    self.src_file.close();
    self.src_path = src_path;
    self.src_file = try std.fs.cwd().openFile(src_path, .{});
    self.next_field();
}

// pub fn makeModule(self: Self, step: Build.Step) *Build.Module {
//     _ = step; // autofix

//     return self.step.owner.createModule(.{ .source_file = self.Step });
// }

pub fn next_field(self: *Self) !void {
    while (true) {
        var buf: [1024]u8 = [_]u8{0} ** 1024;
        var line = try self.reader.readUntilDelimiterOrEof(&buf, '\n') orelse return {
            self.done = true;
            return;
        };

        var line_op: enum { print, remove, fill } = .print;

        for (0.., line) |i, ch| {
            if (ch == '$') {
                if (line[i -| 1] == 'R') line_op = .remove;
                if (line[i -| 1] == 'F') line_op = .fill;
                if (line[i -| 1] == 'B') {
                    line = line[0 .. i - 3];
                    break;
                }
            }
            // check for duplicate imports
            if (line.len > i + 7) {
                if (std.mem.eql(u8, line[i .. i + 7], "@import")) {
                    var trimed_line = std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t' });
                    trimed_line = std.mem.trimRight(u8, trimed_line, &[_]u8{ ' ', '\t' });
                    if (self.imports.contains(trimed_line)) {
                        line_op = .remove;
                    } else {
                        try self.imports.put(self.allocator, trimed_line, {});
                    }
                }
            }
        }
        if (line_op == .print) {
            try self.writer.print("{s}\n", .{line});
        }
        if (line_op == .remove) {
            // we do nothing :))
        }
        if (line_op == .fill) {
            break;
        }
    }
}
