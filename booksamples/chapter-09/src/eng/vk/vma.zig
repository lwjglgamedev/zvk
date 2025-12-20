const vulkan = @import("vulkan");
const vke = @import("mod.zig");
pub const vma = @cImport({
    @cInclude("vk_mem_alloc.h");
});

pub const VmaFlags = enum(u32) {
    None = 0,
    VmaAllocationCreateHostAccessSSequentialWriteBit = vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
    CreateMappedBit = vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
};

pub const VmaUsage = enum(u32) {
    VmaUsageAuto = vma.VMA_MEMORY_USAGE_AUTO,
};

pub const VmaMemoryFlags = enum(u32) {
    None = 0,
    MemoryPropertyHostVisibleBit = vma.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
};

pub const VkVmaAlloc = struct {
    vmaAlloc: vma.VmaAllocator,

    pub fn create(vkInstance: vke.inst.VkInstance, vkPhysDevice: vke.phys.VkPhysDevice, vkDevice: vke.dev.VkDevice) VkVmaAlloc {
        const vulkan_f = vma.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(vkInstance.vkb.dispatch.vkGetInstanceProcAddr),
            .vkGetDeviceProcAddr = @ptrCast(vkInstance.instanceProxy.wrapper.dispatch.vkGetDeviceProcAddr),
        };

        const createInfo = vma.VmaAllocatorCreateInfo{
            .physicalDevice = @ptrFromInt(@intFromEnum(vkPhysDevice.pdev)),
            .device = @ptrFromInt(@intFromEnum(vkDevice.deviceProxy.handle)),
            .instance = @ptrFromInt(@intFromEnum(vkInstance.instanceProxy.handle)),
            .pVulkanFunctions = @ptrCast(&vulkan_f),
            .vulkanApiVersion = @bitCast(vulkan.API_VERSION_1_3),
        };
        var vmaAlloc: vma.VmaAllocator = undefined;
        if (vma.vmaCreateAllocator(&createInfo, &vmaAlloc) != 0)
            @panic("Failed to initialize VMA");
        return .{ .vmaAlloc = vmaAlloc };
    }

    pub fn cleanup(self: *const VkVmaAlloc) void {
        vma.vmaDestroyAllocator(self.vmaAlloc);
    }
};
