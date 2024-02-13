const std = @import("std");
const Socket = @import("Socket.zig");

pub fn serialize(writer: anytype, value: anytype) !void {
    const Value = @TypeOf(value);
    switch (@typeInfo(Value)) {
        .Void => {},
        .Bool => try writer.writeByte(@intFromBool(value)),
        .Int => try writer.writeInt(getAlignedInt(Value), value, .little),
        .Enum => |info| try writer.writeInt(getAlignedInt(info.tag_type), @intFromEnum(value), .little),
        .Union => |info| {
            const TagType = info.tag_type orelse unreachable;
            try writer.writeInt(
                getAlignedInt(std.meta.Tag(TagType)),
                @intFromEnum(std.meta.activeTag(value)),
                .little,
            );
            inline for (info.fields) |field| {
                if (value == @field(TagType, field.name)) try serialize(writer, @field(value, field.name));
            }
        },
        .Struct => |info| {
            if (info.backing_integer) |backing_integer| {
                const Int = getAlignedInt(backing_integer);
                const struct_int: backing_integer = @bitCast(value);
                try writer.writeInt(Int, struct_int, .little);
            } else {
                inline for (info.fields) |field| {
                    try serialize(writer, @field(value, field.name));
                }
            }
        },
        .Pointer => |info| switch (info.size) {
            .Slice => {
                try writer.writeInt(u32, @intCast(value.len), .little);
                for (value) |e| try serialize(writer, e);
            },
            else => @compileError("Can not serialize non slice pointer type"),
        },
        else => @compileError("Unimplemented serialization type: " ++ @typeName(Value)),
    }
}

pub fn deserialize(reader: anytype, comptime Value: type) !Value {
    return deserializeAlloc(reader, Value, null);
}

pub fn deserializeAlloc(reader: anytype, comptime Value: type, maybe_allocator: ?std.mem.Allocator) !Value {
    return switch (@typeInfo(Value)) {
        .Void => {},
        .Bool => blk: {
            const bool_int: u1 = @intCast(try reader.readByte());
            break :blk @bitCast(bool_int);
        },
        .Int => @intCast(try reader.readInt(getAlignedInt(Value), .little)),
        .Enum => |info| @enumFromInt(try reader.readInt(getAlignedInt(info.tag_type), .little)),
        .Union => |info| blk: {
            const TagType = info.tag_type orelse unreachable;
            const tag: TagType = @enumFromInt(try reader.readInt(
                getAlignedInt(std.meta.Tag(TagType)),
                .little,
            ));
            inline for (info.fields) |field| {
                if (@field(TagType, field.name) == tag)
                    break :blk @unionInit(Value, field.name, try deserializeAlloc(reader, field.type, maybe_allocator));
            }
            unreachable;
        },
        .Struct => |info| blk: {
            if (info.backing_integer) |backing_integer| {
                const Int = getAlignedInt(backing_integer);
                const struct_int: backing_integer = @intCast(try reader.readInt(Int, .little));
                break :blk @bitCast(struct_int);
            } else {
                var value: Value = undefined;
                inline for (info.fields) |field| {
                    @field(value, field.name) = try deserializeAlloc(reader, field.type, maybe_allocator);
                }
                break :blk value;
            }
        },
        .Pointer => |info| switch (info.size) {
            .Slice => if (maybe_allocator) |allocator| blk: {
                const len = try reader.readInt(u32, .little);
                const values = try allocator.alloc(info.child, len);
                errdefer allocator.free(values);
                for (values) |*e| e.* = deserializeAlloc(reader, info.child, allocator);
                break :blk values;
            } else error.NoAllocator,
            else => @compileError("Cannot deserialize non slice pointer type"),
        },
        else => @compileError("Unimplemented deserialization type: " ++ @typeName(Value)),
    };
}

fn getAlignedInt(comptime Int: type) type {
    return switch (@typeInfo(Int)) {
        .Int => |info| std.meta.Int(info.signedness, std.mem.alignForward(u16, info.bits, 8)),
        else => unreachable,
    };
}
