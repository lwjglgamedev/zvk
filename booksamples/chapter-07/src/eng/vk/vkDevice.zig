const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);
const required_device_extensions = [_][*:0]const u8{vulkan.extensions.khr_swapchain.name};

pub const VkDevice = struct {
    deviceProxy: vulkan.DeviceProxy,

    pub fn create(allocator: std.mem.Allocator, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !VkDevice {
        const priority = [_]f32{1};
        const qci = [_]vulkan.DeviceQueueCreateInfo{
            .{
                .queue_family_index = vkPhysDevice.queuesInfo.graphics_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
            .{
                .queue_family_index = vkPhysDevice.queuesInfo.present_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        };

        const queue_count: u32 = if (vkPhysDevice.queuesInfo.graphics_family == vkPhysDevice.queuesInfo.present_family)
            1
        else
            2;

        const features3 = vulkan.PhysicalDeviceVulkan13Features{
            .dynamic_rendering = vulkan.Bool32.true,
            .synchronization_2 = vulkan.Bool32.true,
        };
        const features2 = vulkan.PhysicalDeviceVulkan12Features{
            .p_next = @constCast(&features3),
        };

        const devCreateInfo: vulkan.DeviceCreateInfo = .{
            .queue_create_info_count = queue_count,
            .p_next = @ptrCast(&features2),
            .p_queue_create_infos = &qci,
            .enabled_extension_count = required_device_extensions.len,
            .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
        };
        const device = try vkInstance.instanceProxy.createDevice(vkPhysDevice.pdev, &devCreateInfo, null);

        const vkd = try allocator.create(vulkan.DeviceWrapper);
        vkd.* = vulkan.DeviceWrapper.load(device, vkInstance.instanceProxy.wrapper.dispatch.vkGetDeviceProcAddr.?);
        const deviceProxy = vulkan.DeviceProxy.init(device, vkd);

        return .{ .deviceProxy = deviceProxy };
    }

    pub fn cleanup(self: *VkDevice, allocator: std.mem.Allocator) void {
        log.debug("Destroying Vulkan Device", .{});
        self.deviceProxy.destroyDevice(null);
        allocator.destroy(self.deviceProxy.wrapper);
    }

    pub fn wait(self: *VkDevice) !void {
        try self.deviceProxy.deviceWaitIdle();
    }
};
