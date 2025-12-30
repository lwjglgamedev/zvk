const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const VkQueue = struct {
    handle: vulkan.Queue,
    family: u32,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, family: u32) VkQueue {
        return .{
            .handle = vkCtx.vkDevice.deviceProxy.getDeviceQueue(family, 0),
            .family = family,
        };
    }

    pub fn submit(self: *const VkQueue, vkCtx: *const vk.ctx.VkCtx, cmdBufferSubmitInfo: []const vulkan.CommandBufferSubmitInfo, semSignalInfo: []const vulkan.SemaphoreSubmitInfo, semWaitInfo: []const vulkan.SemaphoreSubmitInfo, vkFence: vk.sync.VkFence) !void {
        try vkFence.reset(vkCtx);
        const si = vulkan.SubmitInfo2{
            .command_buffer_info_count = @as(u32, @intCast(cmdBufferSubmitInfo.len)),
            .p_command_buffer_infos = cmdBufferSubmitInfo.ptr,
            .signal_semaphore_info_count = @as(u32, @intCast(semSignalInfo.len)),
            .p_signal_semaphore_infos = semSignalInfo.ptr,
            .wait_semaphore_info_count = @as(u32, @intCast(semWaitInfo.len)),
            .p_wait_semaphore_infos = semWaitInfo.ptr,
        };
        try vkCtx.vkDevice.deviceProxy.queueSubmit2(
            self.handle,
            1,
            @ptrCast(&si),
            vkFence.fence,
        );
    }
};
