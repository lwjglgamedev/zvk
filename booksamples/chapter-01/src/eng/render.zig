const eng = @import("mod.zig");
const std = @import("std");

pub const Render = struct {
    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;
    }

    pub fn create() !Render {
        return .{};
    }

    pub fn render(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        _ = self;
        _ = engCtx;
    }
};
