const com = @import("mod.zig");
const std = @import("std");

const log = std.log.scoped(.utils);

pub fn loadFile(allocator: std.mem.Allocator, filePath: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(filePath, .{});
    defer file.close();

    const stat = try file.stat();
    const buf: []u8 = try file.readToEndAlloc(allocator, stat.size);
    return buf;
}
