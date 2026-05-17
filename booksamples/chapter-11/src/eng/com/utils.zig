const com = @import("mod.zig");
const std = @import("std");

const log = std.log.scoped(.utils);

pub fn generateUuid(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    var bytes: [16]u8 = undefined;
    io.random(&bytes);

    // Set version (4) and variant bits (RFC 4122)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    // Format as UUID string
    const hex_chars = "0123456789abcdef";
    var uuid = try allocator.alloc(u8, 36);
    errdefer allocator.free(uuid);

    var i: usize = 0;
    for (bytes, 0..) |byte, j| {
        switch (j) {
            4, 6, 8, 10 => {
                uuid[i] = '-';
                i += 1;
            },
            else => {},
        }
        uuid[i] = hex_chars[byte >> 4];
        uuid[i + 1] = hex_chars[byte & 0x0F];
        i += 2;
    }

    return uuid;
}

pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, filePath: []const u8) ![]u8 {
    const buf = try std.Io.Dir.cwd().readFileAlloc(io, filePath, allocator, .unlimited);
    return buf;
}
