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
};
