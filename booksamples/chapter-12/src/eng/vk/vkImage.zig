const vk = @import("mod.zig");
const vulkan = @import("vulkan");
const vma = vk.vma.vma;

pub const VkImageData = struct {
    arrayLayers: u32 = 1,
    format: vulkan.Format = vulkan.Format.r8g8b8a8_srgb,
    height: u32,
    memUsage: u32 = vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
    mipLevels: u32 = 1,
    sampleCount: vulkan.SampleCountFlags = vulkan.SampleCountFlags.fromInt(1),
    tiling: vulkan.ImageTiling = vulkan.ImageTiling.optimal,
    usage: vulkan.ImageUsageFlags,
    width: u32,
};

pub const VkImage = struct {
    image: vma.VkImage,
    allocation: vma.VmaAllocation,
    width: u32,
    height: u32,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, vkImageData: VkImageData) !VkImage {
        const createInfo = vma.VkImageCreateInfo{
            .sType = vma.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vma.VK_IMAGE_TYPE_2D,
            .format = @as(c_uint, @intCast(@intFromEnum(vkImageData.format))),
            .extent = .{
                .width = vkImageData.width,
                .height = vkImageData.height,
                .depth = 1,
            },
            .mipLevels = vkImageData.mipLevels,
            .arrayLayers = vkImageData.arrayLayers,
            .samples = @as(c_uint, @intCast(vkImageData.sampleCount.toInt())),
            .initialLayout = vma.VK_IMAGE_LAYOUT_UNDEFINED,
            .sharingMode = vma.VK_SHARING_MODE_EXCLUSIVE,
            .usage = @as(c_uint, @intCast(vkImageData.usage.toInt())),
        };

        const allocCreateInfo = vma.VmaAllocationCreateInfo{
            .usage = vma.VMA_MEMORY_USAGE_AUTO,
            .flags = vkImageData.memUsage,
            .priority = 1.0,
        };

        var image: vma.VkImage = undefined;
        var allocation: vma.VmaAllocation = undefined;
        if (vma.vmaCreateImage(
            vkCtx.vkVmaAlloc.vmaAlloc,
            @ptrCast(&createInfo),
            @ptrCast(&allocCreateInfo),
            @ptrCast(&image),
            &allocation,
            null,
        ) != 0) {
            @panic("Failed to create image");
        }
        return .{
            .image = image,
            .allocation = allocation,
            .width = vkImageData.width,
            .height = vkImageData.height,
        };
    }

    pub fn cleanup(self: *const VkImage, vkCtx: *const vk.ctx.VkCtx) void {
        vma.vmaDestroyImage(vkCtx.vkVmaAlloc.vmaAlloc, self.image, self.allocation);
    }
};
