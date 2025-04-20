const std = @import("std");
const Socket = @import("Socket.zig");

pub const Serializable = struct {
    name: []const u8,
    ty: SerializableType = .default,

    pub const SerializableType = union(enum) {
        default: void,
        slice_with_len: []const u8,
        slice_with_len_extra: struct {
            len_name: []const u8,
            extra: u32,
        },
        hash_map_with_len: []const u8,
        hash_set_with_len: []const u8,
        hash_map: void,
        hash_set: void,
        hash_map_managed: void,
        hash_set_managed: void,
        dynamic_bit_set_unmanaged: void,
        array_of: []const SerializableType,
    };

    pub fn serialize(comptime self: Serializable, writer: anytype, parent: anytype, child: anytype) !void {
        switch (self.ty) {
            .default => try serializeValue(writer, child),
            .slice_with_len => |len_name| {
                const len = @field(parent, len_name);
                std.debug.assert(len == child.len);
                for (child) |e| try serializeValue(writer, e);
            },
            .slice_with_len_extra => |info| {
                const len = @field(parent, info.len_name) + 1;
                std.debug.assert(len == child.len);
                for (child) |e| try serializeValue(writer, e);
            },
            .hash_map_with_len => |len_name| {
                const len = @field(parent, len_name);
                std.debug.assert(len == child.count());
                var iter = child.iterator();
                while (iter.next()) |entry| {
                    try serializeValue(writer, entry.key_ptr.*);
                    try serializeValue(writer, entry.value_ptr.*);
                }
            },
            .hash_set_with_len => |len_name| {
                const len = @field(parent, len_name);
                std.debug.assert(len == child.count());
                var iter = child.iterator();
                while (iter.next()) |entry| {
                    try serializeValue(writer, entry.key_ptr.*);
                }
            },
            .hash_map, .hash_map_managed => {
                try writer.writeInt(u32, @intCast(child.count()), .little);
                var iter = child.iterator();
                while (iter.next()) |entry| {
                    try serializeValue(writer, entry.key_ptr.*);
                    try serializeValue(writer, entry.value_ptr.*);
                }
            },
            .hash_set, .hash_set_managed => {
                try writer.writeInt(u32, @intCast(child.count()), .little);
                var iter = child.iterator();
                while (iter.next()) |entry| {
                    try serializeValue(writer, entry.key_ptr.*);
                }
            },
            .dynamic_bit_set_unmanaged => {
                const bit_length = child.bit_length;
                try writer.writeInt(u32, @intCast(bit_length), .little);
                const num_masks = (bit_length + (@bitSizeOf(std.DynamicBitSet.MaskInt) - 1)) / @bitSizeOf(std.DynamicBitSet.MaskInt);
                try writer.writeAll(std.mem.sliceAsBytes(child.masks[0..num_masks]));
            },
            .array_of => |serializable| for (child) |e| try serializable[0].serialize(writer, parent, e),
        }
    }

    pub fn deserializeToAlloc(
        comptime self: Serializable,
        reader: anytype,
        comptime Parent: type,
        comptime Child: type,
        parent: Parent,
        child: *Child,
        allocator: std.mem.Allocator,
    ) !void {
        switch (self.ty) {
            .default => child.* = try deserializeValueAlloc(reader, Child, allocator),
            .slice_with_len => |len_name| {
                const len = @field(parent, len_name);
                const ChildType = @typeInfo(Child).pointer.child;
                const slice = try allocator.alloc(ChildType, len);
                for (slice) |*e| e.* = try deserializeValueAlloc(reader, ChildType, allocator);
                child.* = slice;
            },
            .slice_with_len_extra => |info| {
                const len = @field(parent, info.len_name) + info.extra;
                const ChildType = @typeInfo(Child).pointer.child;
                const slice = try allocator.alloc(ChildType, len);
                for (slice) |*e| e.* = try deserializeValueAlloc(reader, ChildType, allocator);
                child.* = slice;
            },
            .hash_map_with_len => |len_name| {
                const len = @field(parent, len_name);
                child.* = .{};
                try child.ensureUnusedCapacity(allocator, len);
                for (0..len) |_| {
                    const key_value = try deserializeValueAlloc(reader, Child.KV, allocator);
                    child.putAssumeCapacity(key_value.key, key_value.value);
                }
            },
            .hash_set_with_len => |len_name| {
                const len = @field(parent, len_name);
                child.* = .{};
                try child.ensureUnusedCapacity(allocator, len);
                for (0..len) |_| {
                    const key_value = try deserializeValueAlloc(reader, Child.KV, allocator);
                    child.putAssumeCapacity(key_value.key, {});
                }
            },
            .hash_map => {
                const len = try reader.readInt(u32, .little);
                child.* = .{};
                try child.ensureUnusedCapacity(allocator, len);
                for (0..len) |_| {
                    const key_value = try deserializeValueAlloc(reader, Child.KV, allocator);
                    child.putAssumeCapacity(key_value.key, key_value.value);
                }
            },
            .hash_set => {
                const len = try reader.readInt(u32, .little);
                child.* = .{};
                try child.ensureUnusedCapacity(allocator, len);
                for (0..len) |_| {
                    const key_value = try deserializeValueAlloc(reader, Child.KV, allocator);
                    child.putAssumeCapacity(key_value.key, {});
                }
            },
            .hash_map_managed => {
                const len = try reader.readInt(u32, .little);
                child.* = try Child.initWithCapacity(allocator, len);
                for (0..len) |_| {
                    const key_value = try deserializeValueAlloc(reader, Child.KV, allocator);
                    child.putAssumeCapacity(key_value.key, key_value.value);
                }
            },
            .hash_set_managed => {
                const len = try reader.readInt(u32, .little);
                child.* = try Child.initWithCapacity(allocator, len);
                for (0..len) |_| {
                    const key_value = try deserializeValueAlloc(reader, Child.KV, allocator);
                    child.putAssumeCapacity(key_value.key, {});
                }
            },
            .dynamic_bit_set_unmanaged => {
                const bit_length = try reader.readInt(u32, .little);
                const num_masks = (bit_length + (@bitSizeOf(std.DynamicBitSet.MaskInt) - 1)) / @bitSizeOf(std.DynamicBitSet.MaskInt);

                const masks = try allocator.alloc(std.DynamicBitSetUnmanaged.MaskInt, num_masks);

                _ = try reader.read(std.mem.sliceAsBytes(masks));

                child.* = .{
                    .bit_length = bit_length,
                    .masks = masks.ptr,
                };
            },
            .array_of => |serializable| for (child) |*e| try serializable[0].deserializeToAlloc(
                reader,
                Parent,
                @TypeOf(e.*),
                parent,
                e,
                allocator,
            ),
        }
    }
};

pub fn customSerialization(comptime serializables: []const Serializable, comptime Value: type) type {
    return struct {
        pub fn serialize(writer: anytype, value: Value) !void {
            inline for (serializables) |serializable| try serializable.serialize(writer, value, @field(value, serializable.name));
        }

        pub fn deserializeAlloc(reader: anytype, allocator: std.mem.Allocator) !Value {
            var self: Value = undefined;
            inline for (serializables) |serializable| try serializable.deserializeToAlloc(
                reader,
                Value,
                @TypeOf(@field(self, serializable.name)),
                self,
                &@field(self, serializable.name),
                allocator,
            );
            return self;
        }
    };
}

pub fn serializeValue(writer: anytype, value: anytype) !void {
    const Value = @TypeOf(value);
    switch (@typeInfo(Value)) {
        .void => {},
        .bool => try writer.writeByte(@intFromBool(value)),
        .int => try writer.writeInt(getAlignedInt(Value), value, .little),
        .@"enum" => |info| try writer.writeInt(getAlignedInt(info.tag_type), @intFromEnum(value), .little),
        .@"union" => |info| {
            const TagType = info.tag_type orelse unreachable;
            try writer.writeInt(
                getAlignedInt(std.meta.Tag(TagType)),
                @intFromEnum(std.meta.activeTag(value)),
                .little,
            );
            inline for (info.fields) |field| {
                if (value == @field(TagType, field.name)) try serializeValue(writer, @field(value, field.name));
            }
        },
        .@"struct" => |info| {
            if (info.backing_integer) |backing_integer| {
                const Int = getAlignedInt(backing_integer);
                const struct_int: backing_integer = @bitCast(value);
                try writer.writeInt(Int, struct_int, .little);
            } else {
                if (@hasDecl(Value, "serialize")) {
                    try value.serialize(writer);
                    return;
                }
                inline for (info.fields) |field| {
                    try serializeValue(writer, @field(value, field.name));
                }
            }
        },
        .array => {
            for (value) |e| try serializeValue(writer, e);
        },
        .pointer => |info| switch (info.size) {
            .slice => {
                try writer.writeInt(u32, @intCast(value.len), .little);
                for (value) |e| try serializeValue(writer, e);
            },
            else => @compileError("Can not serialize non slice pointer type"),
        },
        else => @compileError("Unimplemented serialization type: " ++ @typeName(Value)),
    }
}

pub fn deserializeValue(reader: anytype, comptime Value: type) !Value {
    return deserializeValueAlloc(reader, Value, null);
}

pub fn deserializeValueAlloc(reader: anytype, comptime Value: type, maybe_allocator: ?std.mem.Allocator) !Value {
    return switch (@typeInfo(Value)) {
        .void => {},
        .bool => blk: {
            const bool_int: u1 = @intCast(try reader.readByte());
            break :blk @bitCast(bool_int);
        },
        .int => @intCast(try reader.readInt(getAlignedInt(Value), .little)),
        .@"enum" => |info| @enumFromInt(try reader.readInt(getAlignedInt(info.tag_type), .little)),
        .@"union" => |info| blk: {
            const TagType = info.tag_type orelse unreachable;
            const tag: TagType = @enumFromInt(try reader.readInt(
                getAlignedInt(std.meta.Tag(TagType)),
                .little,
            ));
            inline for (info.fields) |field| {
                if (@field(TagType, field.name) == tag)
                    break :blk @unionInit(Value, field.name, try deserializeValueAlloc(reader, field.type, maybe_allocator));
            }
            unreachable;
        },
        .@"struct" => |info| blk: {
            if (info.backing_integer) |backing_integer| {
                const Int = getAlignedInt(backing_integer);
                const struct_int: backing_integer = @intCast(try reader.readInt(Int, .little));
                break :blk @bitCast(struct_int);
            } else {
                if (@hasDecl(Value, "deserializeAlloc")) return try Value.deserializeAlloc(reader, maybe_allocator orelse return error.NoAllocator);
                if (@hasDecl(Value, "deserialize")) return try Value.deserialize(reader);
                var value: Value = undefined;
                inline for (info.fields) |field| {
                    @field(value, field.name) = try deserializeValueAlloc(reader, field.type, maybe_allocator);
                }
                break :blk value;
            }
        },
        .array => |info| blk: {
            var value: Value = undefined;
            for (&value) |*e| e.* = try deserializeValueAlloc(reader, info.child, maybe_allocator);
            break :blk value;
        },
        .pointer => |info| switch (info.size) {
            .slice => if (maybe_allocator) |allocator| blk: {
                const len = try reader.readInt(u32, .little);
                const values = try allocator.alloc(info.child, len);
                errdefer allocator.free(values);
                for (values) |*e| e.* = try deserializeValueAlloc(reader, info.child, allocator);
                break :blk values;
            } else error.NoAllocator,
            else => @compileError("Cannot deserialize non slice pointer type"),
        },
        else => @compileError("Unimplemented deserialization type: " ++ @typeName(Value)),
    };
}

fn getAlignedInt(comptime Int: type) type {
    return switch (@typeInfo(Int)) {
        .int => |info| std.meta.Int(info.signedness, std.mem.alignForward(u16, info.bits, 8)),
        else => unreachable,
    };
}
