const com = @import("mod.zig");
const std = @import("std");

const log = std.log.scoped(.utils);

pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, filePath: []const u8) ![]u8 {
    const buf = try std.Io.Dir.cwd().readFileAlloc(io, filePath, allocator, .unlimited);
    return buf;
}
