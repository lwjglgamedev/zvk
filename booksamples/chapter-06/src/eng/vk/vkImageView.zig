const vk = @import("mod.zig");
const vulkan = @import("vulkan");

pub const VkImageViewData = struct {
    aspectmask: vulkan.ImageAspectFlags = vulkan.ImageAspectFlags{ .color_bit = true },
    baseArrayLayer: u32 = 0,
    baseMipLevel: u32 = 0,
    format: vulkan.Format,
    layerCount: u32 = 1,
    levelCount: u32 = 1,
    viewType: vulkan.ImageViewType = .@"2d",
};

pub const VkImageView = struct {
    image: vulkan.Image,
    view: vulkan.ImageView,

    pub fn create(vkDevice: vk.dev.VkDevice, image: vulkan.Image, imageViewData: VkImageViewData) !VkImageView {
        const createInfo = vulkan.ImageViewCreateInfo{
            .image = image,
            .view_type = imageViewData.viewType,
            .format = imageViewData.format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = imageViewData.aspectmask,
                .base_mip_level = imageViewData.baseMipLevel,
                .level_count = imageViewData.levelCount,
                .base_array_layer = imageViewData.baseArrayLayer,
                .layer_count = imageViewData.layerCount,
            },
        };
        const imageView = try vkDevice.deviceProxy.createImageView(&createInfo, null);

        return .{
            .image = image,
            .view = imageView,
        };
    }

    pub fn cleanup(self: VkImageView, vkDevice: vk.dev.VkDevice) void {
        vkDevice.deviceProxy.destroyImageView(self.view, null);
    }
};
