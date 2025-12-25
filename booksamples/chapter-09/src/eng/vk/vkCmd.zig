const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const VkCmdPool = struct {
    commandPool: vulkan.CommandPool,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, queueFamilyIndex: u32, resetSupport: bool) !VkCmdPool {
        const createInfo: vulkan.CommandPoolCreateInfo = .{ .queue_family_index = queueFamilyIndex, .flags = .{ .reset_command_buffer_bit = resetSupport } };
        const commandPool = try vkCtx.vkDevice.deviceProxy.createCommandPool(&createInfo, null);
        return .{ .commandPool = commandPool };
    }

    pub fn cleanup(self: *const VkCmdPool, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.destroyCommandPool(self.commandPool, null);
    }

    pub fn reset(self: *const VkCmdPool, vkCtx: *const vk.ctx.VkCtx) !void {
        try vkCtx.vkDevice.deviceProxy.resetCommandPool(self.commandPool, .{});
    }
};

pub const VkCmdBuff = struct {
    cmdBuffProxy: vulkan.CommandBufferProxy,
    oneTime: bool,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, vkCmdPool: *vk.cmd.VkCmdPool, oneTime: bool) !VkCmdBuff {
        const allocateInfo: vulkan.CommandBufferAllocateInfo = .{
            .command_buffer_count = 1,
            .command_pool = vkCmdPool.commandPool,
            .level = vulkan.CommandBufferLevel.primary,
        };
        var cmds: [1]vulkan.CommandBuffer = undefined;
        try vkCtx.vkDevice.deviceProxy.allocateCommandBuffers(&allocateInfo, &cmds);
        const cmdBuffProxy = vulkan.CommandBufferProxy.init(cmds[0], vkCtx.vkDevice.deviceProxy.wrapper);

        return .{ .cmdBuffProxy = cmdBuffProxy, .oneTime = oneTime };
    }

    pub fn cleanup(self: *const VkCmdBuff, vkCtx: *const vk.ctx.VkCtx, vkCmdPool: *vk.cmd.VkCmdPool) void {
        const cmds = [_]vulkan.CommandBuffer{self.cmdBuffProxy.handle};
        vkCtx.vkDevice.deviceProxy.freeCommandBuffers(vkCmdPool.commandPool, cmds.len, &cmds);
    }

    pub fn begin(self: *const VkCmdBuff, vkCtx: *const vk.ctx.VkCtx) !void {
        const beginInfo: vulkan.CommandBufferBeginInfo = .{ .flags = .{ .one_time_submit_bit = self.oneTime } };
        try vkCtx.vkDevice.deviceProxy.beginCommandBuffer(self.cmdBuffProxy.handle, &beginInfo);
    }

    pub fn end(self: *const VkCmdBuff, vkCtx: *const vk.ctx.VkCtx) !void {
        try vkCtx.vkDevice.deviceProxy.endCommandBuffer(self.cmdBuffProxy.handle);
    }

    pub fn submitAndWait(self: *const VkCmdBuff, vkCtx: *const vk.ctx.VkCtx, vkQueue: vk.queue.VkQueue) !void {
        const vkFence = try vk.sync.VkFence.create(vkCtx);
        defer vkFence.cleanup(vkCtx);

        const cmdBufferSubmitInfo = [_]vulkan.CommandBufferSubmitInfo{.{
            .device_mask = 0,
            .command_buffer = self.cmdBuffProxy.handle,
        }};

        const emptySemphs = [_]vulkan.SemaphoreSubmitInfo{};

        try vkQueue.submit(vkCtx, &cmdBufferSubmitInfo, &emptySemphs, &emptySemphs, vkFence);
        try vkFence.wait(vkCtx);
    }
};
