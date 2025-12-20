const vk = @import("mod.zig");
const vulkan = @import("vulkan");

pub const VkImageData = struct {
    arrayLayers: u32 = 1,
    format: vulkan.Format = vulkan.Format.r8g8b8a8_srgb,
    height: u32,
    mipLevels: u32 = 1,
    sampleCount: vulkan.SampleCountFlags = vulkan.SampleCountFlags.fromInt(1),
    tiling: vulkan.ImageTiling = vulkan.ImageTiling.optimal,
    usage: vulkan.ImageUsageFlags,
    width: u32,
};

pub const VkImage = struct {
    image: vulkan.Image,
    width: u32,
    height: u32,
    memory: vulkan.DeviceMemory,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, vkImageData: VkImageData) !VkImage {
        const createInfo = vulkan.ImageCreateInfo{
            .image_type = vulkan.ImageType.@"2d",
            .format = vkImageData.format,
            .extent = .{
                .width = vkImageData.width,
                .height = vkImageData.height,
                .depth = 1,
            },
            .mip_levels = vkImageData.mipLevels,
            .array_layers = vkImageData.arrayLayers,
            .samples = vkImageData.sampleCount,
            .usage = vkImageData.usage,
            .sharing_mode = vulkan.SharingMode.exclusive,
            .initial_layout = vulkan.ImageLayout.undefined,
            .tiling = vkImageData.tiling,
        };
        const image = try vkCtx.vkDevice.deviceProxy.createImage(&createInfo, null);

        const memReqs = vkCtx.vkDevice.deviceProxy.getImageMemoryRequirements(image);

        const allocInfo = vulkan.MemoryAllocateInfo{
            .allocation_size = memReqs.size,
            .memory_type_index = try vkCtx.findMemoryTypeIndex(memReqs.memory_type_bits, vulkan.MemoryPropertyFlags.fromInt(0)),
        };
        const memory = try vkCtx.vkDevice.deviceProxy.allocateMemory(&allocInfo, null);

        try vkCtx.vkDevice.deviceProxy.bindImageMemory(image, memory, 0);

        return .{
            .image = image,
            .width = vkImageData.width,
            .height = vkImageData.height,
            .memory = memory,
        };
    }

    pub fn cleanup(self: *const VkImage, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.destroyImage(self.image, null);
        vkCtx.vkDevice.deviceProxy.freeMemory(self.memory, null);
    }
};
