const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);

pub const VkDevice = struct {
    deviceProxy: vulkan.DeviceProxy,

    pub fn create(allocator: std.mem.Allocator, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !VkDevice {
        const priority = [_]f32{0};

        const maxFamilies = 3;
        var uniqueFamilies: [maxFamilies]u32 = undefined;
        var uniqueCount: u32 = 0;
        for ([_]u32{
            vkPhysDevice.queuesInfo.graphics_family,
            vkPhysDevice.queuesInfo.present_family,
            vkPhysDevice.queuesInfo.compute_family,
        }) |family| {
            var alreadyPresent = false;
            for (uniqueFamilies[0..uniqueCount]) |existing| {
                if (existing == family) {
                    alreadyPresent = true;
                    break;
                }
            }
            if (!alreadyPresent) {
                uniqueFamilies[uniqueCount] = family;
                uniqueCount += 1;
            }
        }

        var qciBuf: [maxFamilies]vulkan.DeviceQueueCreateInfo = undefined;
        for (uniqueFamilies[0..uniqueCount], 0..) |family, i| {
            qciBuf[i] = .{
                .queue_family_index = family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            };
        }
        const qci = qciBuf[0..uniqueCount];

        const featuresMultiview = vulkan.PhysicalDeviceMultiviewFeatures{
            .multiview = vulkan.Bool32.true,
        };
        const features13 = vulkan.PhysicalDeviceVulkan13Features{
            .p_next = @constCast(&featuresMultiview),
            .dynamic_rendering = vulkan.Bool32.true,
            .shader_demote_to_helper_invocation = vulkan.Bool32.true,
            .synchronization_2 = vulkan.Bool32.true,
        };
        const features12 = vulkan.PhysicalDeviceVulkan12Features{
            .p_next = @constCast(&features13),
            .buffer_device_address = vulkan.Bool32.true,
            .scalar_block_layout = vulkan.Bool32.true,
        };
        const features = vulkan.PhysicalDeviceFeatures{
            .draw_indirect_first_instance = vulkan.Bool32.true,
            .multi_draw_indirect = vulkan.Bool32.true,
            .sampler_anisotropy = vkPhysDevice.features.sampler_anisotropy,
            .shader_int_64 = vulkan.Bool32.true,
        };

        const devCreateInfo: vulkan.DeviceCreateInfo = .{
            .queue_create_info_count = @intCast(qci.len),
            .p_next = @ptrCast(&features12),
            .p_queue_create_infos = qci.ptr,
            .enabled_extension_count = vk.phys.reqExtensions.len,
            .pp_enabled_extension_names = vk.phys.reqExtensions[0..].ptr,
            .p_enabled_features = @ptrCast(&features),
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
