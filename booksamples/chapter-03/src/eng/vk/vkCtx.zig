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

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !VkCtx {
        const vkInstance = try vk.inst.VkInstance.create(allocator, constants.validation);
        const vkSurface = try vk.surf.VkSurface.create(window, vkInstance);
        const vkPhysDevice = try vk.phys.VkPhysDevice.create(allocator, constants, vkInstance.instanceProxy, vkSurface);
        const vkDevice = try vk.dev.VkDevice.create(allocator, vkInstance, vkPhysDevice);

        return .{
            .constants = constants,
            .vkDevice = vkDevice,
            .vkInstance = vkInstance,
            .vkPhysDevice = vkPhysDevice,
            .vkSurface = vkSurface,
        };
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) !void {
        self.vkDevice.cleanup(allocator);
        self.vkSurface.cleanup(self.vkInstance);
        try self.vkInstance.cleanup(allocator);
    }
};
