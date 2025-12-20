const vulkan = @import("vulkan");
const vk = @import("mod.zig");

const VtxBuffDesc = struct {
    const binding_description = vulkan.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(VtxBuffDesc),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vulkan.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(VtxBuffDesc, "pos"),
        },
    };

    pos: [3]f32,
};

pub const VkBuffer = struct {
    size: u64,
    buffer: vulkan.Buffer,
    memory: vulkan.DeviceMemory,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, size: u64, bufferUsage: vulkan.BufferUsageFlags, memFlags: vulkan.MemoryPropertyFlags) !VkBuffer {
        const createInfo = vulkan.BufferCreateInfo{
            .size = size,
            .usage = bufferUsage,
            .sharing_mode = vulkan.SharingMode.exclusive,
        };
        const buffer = try vkCtx.vkDevice.deviceProxy.createBuffer(&createInfo, null);

        const memReqs = vkCtx.vkDevice.deviceProxy.getBufferMemoryRequirements(buffer);

        const allocInfo = vulkan.MemoryAllocateInfo{
            .allocation_size = memReqs.size,
            .memory_type_index = try vkCtx.findMemoryTypeIndex(memReqs.memory_type_bits, memFlags),
        };
        const memory = try vkCtx.vkDevice.deviceProxy.allocateMemory(&allocInfo, null);

        try vkCtx.vkDevice.deviceProxy.bindBufferMemory(buffer, memory, 0);

        return .{
            .size = size,
            .buffer = buffer,
            .memory = memory,
        };
    }

    pub fn cleanup(self: *const VkBuffer, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.destroyBuffer(self.buffer, null);
        vkCtx.vkDevice.deviceProxy.freeMemory(self.memory, null);
    }

    pub fn map(self: *const VkBuffer, vkCtx: *const vk.ctx.VkCtx) !?*anyopaque {
        return try vkCtx.vkDevice.deviceProxy.mapMemory(self.memory, 0, vulkan.WHOLE_SIZE, .{});
    }

    pub fn unMap(self: *const VkBuffer, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.unmapMemory(self.memory);
    }
};
