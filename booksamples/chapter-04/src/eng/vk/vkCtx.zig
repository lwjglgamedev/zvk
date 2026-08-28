const std = @import("std");
const sdl3 = @import("sdl3");
const com = @import("com");
const vk = @import("mod.zig");

pub const VkCtx = struct {
    constants: com.common.Constants,
    vkDevice: vk.dev.VkDevice,
    vkInstance: vk.inst.VkInstance,
    vkPhysDevice: vk.phys.VkPhysDevice,
    vkSurface: vk.surf.VkSurface,
    vkSwapChain: vk.swap.VkSwapChain,

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !VkCtx {
        var vkInstance = try vk.inst.VkInstance.create(allocator, constants.validation);
        errdefer vkInstance.cleanup(allocator) catch {};

        var vkSurface = try vk.surf.VkSurface.create(window, vkInstance);
        errdefer vkSurface.cleanup(vkInstance);

        const vkPhysDevice = try vk.phys.VkPhysDevice.create(
            allocator,
            constants,
            vkInstance.instanceProxy,
            vkSurface,
        );

        var vkDevice = try vk.dev.VkDevice.create(allocator, vkInstance, vkPhysDevice);
        errdefer vkDevice.cleanup(allocator);

        var vkSwapChain = try vk.swap.VkSwapChain.create(
            allocator,
            window,
            vkInstance,
            vkPhysDevice,
            vkDevice,
            vkSurface,
            constants.swapChainImages,
            constants.vsync,
        );
        errdefer vkSwapChain.cleanup(allocator, vkDevice);

        return .{
            .constants = constants,
            .vkDevice = vkDevice,
            .vkInstance = vkInstance,
            .vkPhysDevice = vkPhysDevice,
            .vkSurface = vkSurface,
            .vkSwapChain = vkSwapChain,
        };
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) !void {
        self.vkSwapChain.cleanup(allocator, self.vkDevice);
        self.vkDevice.cleanup(allocator);
        self.vkSurface.cleanup(self.vkInstance);
        try self.vkInstance.cleanup(allocator);
    }
};
