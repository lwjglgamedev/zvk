const std = @import("std");
const sdl3 = @import("sdl3");
const com = @import("com");
const vk = @import("mod.zig");
const vulkan = @import("vulkan");

pub const VkCtx = struct {
    constants: com.common.Constants,
    vkDescAllocator: vk.desc.VkDescAllocator,
    vkDevice: vk.dev.VkDevice,
    vkInstance: vk.inst.VkInstance,
    vkPhysDevice: vk.phys.VkPhysDevice,
    vkSurface: vk.surf.VkSurface,
    vkSwapChain: vk.swap.VkSwapChain,

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !VkCtx {
        const vkInstance = try vk.inst.VkInstance.create(allocator, constants.validation);
        const vkSurface = try vk.surf.VkSurface.create(window, vkInstance);
        const vkPhysDevice = try vk.phys.VkPhysDevice.create(allocator, constants, vkInstance.instanceProxy, vkSurface);
        const vkDevice = try vk.dev.VkDevice.create(allocator, vkInstance, vkPhysDevice);
        const vkSwapChain = try vk.swap.VkSwapChain.create(allocator, window, vkInstance, vkPhysDevice, vkDevice, vkSurface, constants.swapChainImages, constants.vsync);
        const vkDescAllocator = try vk.desc.VkDescAllocator.create(allocator, vkPhysDevice, vkDevice);

        return .{
            .constants = constants,
            .vkDescAllocator = vkDescAllocator,
            .vkDevice = vkDevice,
            .vkInstance = vkInstance,
            .vkPhysDevice = vkPhysDevice,
            .vkSurface = vkSurface,
            .vkSwapChain = vkSwapChain,
        };
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) !void {
        self.vkDescAllocator.cleanup(allocator, self.vkDevice);
        self.vkSwapChain.cleanup(allocator, self.vkDevice);
        self.vkDevice.cleanup(allocator);
        self.vkSurface.cleanup(self.vkInstance);
        try self.vkInstance.cleanup(allocator);
    }

    pub fn findMemoryTypeIndex(self: *const VkCtx, memTypeBits: u32, flags: vulkan.MemoryPropertyFlags) !u32 {
        const memProps = self.vkInstance.instanceProxy.getPhysicalDeviceMemoryProperties(self.vkPhysDevice.pdev);
        for (memProps.memory_types[0..memProps.memory_type_count], 0..) |mem_type, i| {
            if (memTypeBits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }
};
