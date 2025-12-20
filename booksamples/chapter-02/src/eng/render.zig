const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");

pub const Render = struct {
    vkCtx: vk.ctx.VkCtx,

    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) !void {
        try self.vkCtx.cleanup(allocator);
    }

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants) !Render {
        const vkCtx = try vk.ctx.VkCtx.create(allocator, constants);
        return .{
            .vkCtx = vkCtx,
        };
    }

    pub fn render(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        _ = self;
        _ = engCtx;
    }
};
