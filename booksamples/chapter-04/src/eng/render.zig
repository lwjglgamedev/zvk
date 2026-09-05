const com = @import("com");
const eng = @import("mod.zig");
const sdl3 = @import("sdl3");
const std = @import("std");
const vk = @import("vk");
const log = std.log.scoped(.eng);

pub const Render = struct {
    vkCtx: vk.ctx.VkCtx,

    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) void {
        self.vkCtx.vkDevice.wait() catch |err| log.err("Device wait failed in cleanup: {}", .{err});

        self.vkCtx.cleanup(allocator);
    }

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !Render {
        var vkCtx = try vk.ctx.VkCtx.create(allocator, constants, window);
        errdefer vkCtx.cleanup(allocator);
        return .{
            .vkCtx = vkCtx,
        };
    }

    pub fn render(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        _ = self;
        _ = engCtx;
    }
};
