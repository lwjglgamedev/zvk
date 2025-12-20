const std = @import("std");
const sdl3 = @import("sdl3");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const VkSurface = struct {
    surface: sdl3.vulkan.Surface,

    pub fn cleanup(self: *VkSurface, vkInstance: vk.inst.VkInstance) void {
        const surfaceKhr: vulkan.SurfaceKHR = @enumFromInt(@intFromPtr(self.surface.surface));
        vkInstance.instanceProxy.destroySurfaceKHR(surfaceKhr, null);
    }

    pub fn create(window: sdl3.video.Window, vkInstance: vk.inst.VkInstance) !VkSurface {
        const vkHandle = vkInstance.instanceProxy.handle;
        const instancePtr: ?*sdl3.c.struct_VkInstance_T = @ptrFromInt(@intFromEnum(vkHandle));

        const surface = sdl3.vulkan.Surface.init(window, instancePtr, null) catch |err| {
            const sdlError = sdl3.c.SDL_GetError();
            std.debug.print("Failed to create Vulkan surface:\n", .{});
            std.debug.print("SDL Error: {s}\n", .{sdlError});
            std.debug.print("Zig Error: {}\n", .{err});
            return err;
        };

        return .{ .surface = surface };
    }

    pub fn getSurfaceCaps(self: *const VkSurface, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !vulkan.SurfaceCapabilitiesKHR {
        const surfaceKhr: vulkan.SurfaceKHR = @enumFromInt(@intFromPtr(self.surface.surface));
        return try vkInstance.instanceProxy.getPhysicalDeviceSurfaceCapabilitiesKHR(vkPhysDevice.pdev, surfaceKhr);
    }

    pub fn getSurfaceFormat(self: *const VkSurface, allocator: std.mem.Allocator, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !vulkan.SurfaceFormatKHR {
        const surfaceKhr: vulkan.SurfaceKHR = @enumFromInt(@intFromPtr(self.surface.surface));

        const preferred = vulkan.SurfaceFormatKHR{
            .format = .b8g8r8a8_srgb,
            .color_space = .srgb_nonlinear_khr,
        };

        const surfaceFormats = try vkInstance.instanceProxy.getPhysicalDeviceSurfaceFormatsAllocKHR(vkPhysDevice.pdev, surfaceKhr, allocator);
        defer allocator.free(surfaceFormats);

        for (surfaceFormats) |sfmt| {
            if (std.meta.eql(sfmt, preferred)) {
                return preferred;
            }
        }

        return surfaceFormats[0];
    }
};
