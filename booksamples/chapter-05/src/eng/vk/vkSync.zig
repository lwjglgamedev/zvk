const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const VkFence = struct {
    fence: vulkan.Fence,

    pub fn create(vkCtx: *const vk.ctx.VkCtx) !VkFence {
        const fence = try vkCtx.*.vkDevice.deviceProxy.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
        return .{ .fence = fence };
    }

    pub fn cleanup(self: *const VkFence, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.*.vkDevice.deviceProxy.destroyFence(self.fence, null);
    }

    pub fn reset(self: *const VkFence, vkCtx: *const vk.ctx.VkCtx) !void {
        try vkCtx.*.vkDevice.deviceProxy.resetFences(1, @ptrCast(&self.fence));
    }

    pub fn wait(self: *const VkFence, vkCtx: *const vk.ctx.VkCtx) !void {
        _ = try vkCtx.*.vkDevice.deviceProxy.waitForFences(1, @ptrCast(&self.fence), vulkan.Bool32.true, std.math.maxInt(u64));
    }
};

pub const VkSemaphore = struct {
    semaphore: vulkan.Semaphore,

    pub fn create(vkCtx: *const vk.ctx.VkCtx) !VkSemaphore {
        const semaphore = try vkCtx.*.vkDevice.deviceProxy.createSemaphore(&.{}, null);
        return .{ .semaphore = semaphore };
    }

    pub fn cleanup(self: *const VkSemaphore, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.*.vkDevice.deviceProxy.destroySemaphore(self.semaphore, null);
    }
};
