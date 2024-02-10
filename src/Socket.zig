const std = @import("std");
const builtin = @import("builtin");

const Self = @This();

pub const SendError = (std.os.SendError || std.os.SendToError);
pub const ReceiveError = std.os.RecvFromError;

pub const Reader = std.io.Reader(Self, ReceiveError, receive);
pub const Writer = std.io.Writer(Self, SendError, send);

socket: std.os.socket_t,

pub fn create(port: u16) !Self {
    const socket = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);
    errdefer std.os.close(socket);

    const address = std.net.Ip4Address.parse("127.0.0.1", port) catch unreachable;

    try std.os.bind(socket, @ptrCast(&address.sa), address.getOsSockLen());

    return .{ .socket = socket };
}

pub fn listenForConnection(self: Self) !Self {
    try std.os.listen(self.socket, 1);

    const new_socket = try std.os.accept(self.socket, null, null, 0);

    return .{
        .socket = new_socket,
    };
}

pub fn connect(address: std.net.Ip4Address) !Self {
    const socket = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);
    errdefer std.os.close(socket);
    try std.os.connect(socket, @ptrCast(&address.sa), address.getOsSockLen());
    return .{ .socket = socket };
}

pub fn close(self: Self) void {
    std.os.close(self.socket);
}

pub fn reader(self: Self) Reader {
    return .{ .context = self };
}

pub fn writer(self: Self) Writer {
    return .{ .context = self };
}

pub fn receive(self: Self, data: []u8) ReceiveError!usize {
    return switch (builtin.os.tag) {
        .linux => try std.os.recvfrom(
            self.socket,
            data,
            std.os.MSG.NOSIGNAL,
            null,
            null,
        ),
        .windows => try std.os.recvfrom(
            self.socket,
            data,
            0,
            null,
            null,
        ),
        else => unreachable,
    };
}

pub fn send(self: Self, data: []const u8) SendError!usize {
    return switch (builtin.os.tag) {
        .linux => try std.os.send(
            self.socket,
            data,
            std.os.MSG.NOSIGNAL,
        ),
        .windows => try std.os.send(
            self.socket,
            data,
            0,
        ),
        else => unreachable,
    };
}

pub fn hasData(self: Self) !bool {
    switch (builtin.os.tag) {
        .linux => {
            var buf: [1]u8 = undefined;
            const len = std.os.recvfrom(
                self.socket,
                &buf,
                std.os.MSG.PEEK,
                null,
                null,
            ) catch |err| switch (err) {
                error.WouldBlock => return false,
                else => return err,
            };
            if (len == 0) return false;
        },
        .windows => {
            var buf: [1]u8 = undefined;
            const len = std.os.recvfrom(
                self.socket,
                &buf,
                0x2,
                null,
                null,
            ) catch |err| switch (err) {
                error.WouldBlock => return false,
                else => return err,
            };
            if (len == 0) return false;
        },
        else => unreachable,
    }

    return true;
}

pub fn setBlocking(self: Self, blocking: bool) !void {
    switch (builtin.os.tag) {
        .linux => {
            var flags = try std.os.fcntl(self.socket, std.os.F.GETFL, 0);

            if (blocking) {
                flags &= ~@as(usize, std.os.SOCK.NONBLOCK);
            } else {
                flags |= std.os.SOCK.NONBLOCK;
            }
            _ = try std.os.fcntl(self.socket, std.os.F.SETFL, flags);
        },
        .windows => {
            var mode: u32 = if (blocking) 0 else 1;
            _ = std.os.windows.ws2_32.ioctlsocket(self.socket, std.os.windows.ws2_32.FIONBIO, &mode);
        },
        else => unreachable,
    }
}
