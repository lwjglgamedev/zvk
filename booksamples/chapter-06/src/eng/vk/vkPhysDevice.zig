const std = @import("std");
const vulkan = @import("vulkan");
const com = @import("com");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);
const required_device_extensions = [_][*:0]const u8{vulkan.extensions.khr_swapchain.name};

const QueuesInfo = struct {
    graphics_family: u32,
    present_family: u32,
};

pub const VkPhysDevice = struct {
    pdev: vulkan.PhysicalDevice,
    props: vulkan.PhysicalDeviceProperties,
    queuesInfo: QueuesInfo,
    memProps: vulkan.PhysicalDeviceMemoryProperties,

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, instance: vulkan.InstanceProxy, vkSurface: vk.surf.VkSurface) !VkPhysDevice {
        const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
        defer allocator.free(pdevs);

        var list = try std.ArrayList(VkPhysDevice).initCapacity(allocator, 0);
        defer list.deinit(allocator);

        for (pdevs) |pdev| {
            const props = instance.getPhysicalDeviceProperties(pdev);
            const memProps = instance.getPhysicalDeviceMemoryProperties(pdev);
            log.debug("Checking [{s}] physical device", .{props.device_name});

            if (!try checkExtensionSupport(instance, pdev, allocator)) {
                continue;
            }
            if (try hasGraphicsQueue(instance, pdev, vkSurface, allocator)) |queuesInfo| {
                const vkPhysDevice = VkPhysDevice{
                    .pdev = pdev,
                    .props = props,
                    .queuesInfo = queuesInfo,
                    .memProps = memProps,
                };
                const name_slice = std.mem.span(@as([*:0]const u8, @ptrCast(&vkPhysDevice.props.device_name)));
                if (std.mem.eql(u8, constants.gpu, name_slice)) {
                    try list.insert(allocator, 0, vkPhysDevice);
                    break;
                }
                if (props.device_type == vulkan.PhysicalDeviceType.discrete_gpu) {
                    try list.insert(allocator, 0, vkPhysDevice);
                } else {
                    try list.append(allocator, vkPhysDevice);
                }
            }
        }
        const result = list.items[0];

        log.debug("Selected [{s}] physical device", .{result.props.device_name});
        return result;
    }

    fn hasGraphicsQueue(
        instance: vulkan.InstanceProxy,
        pdev: vulkan.PhysicalDevice,
        vkSurface: vk.surf.VkSurface,
        allocator: std.mem.Allocator,
    ) !?QueuesInfo {
        const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
        defer allocator.free(families);

        var graphics_family: ?u32 = null;
        var present_family: ?u32 = null;

        const surfaceKhr: vulkan.SurfaceKHR = @enumFromInt(@intFromPtr(vkSurface.surface.surface));

        for (families, 0..) |properties, i| {
            const family: u32 = @intCast(i);

            if (graphics_family == null and properties.queue_flags.graphics_bit) {
                graphics_family = family;
            }

            if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surfaceKhr)) == vulkan.Bool32.true) {
                present_family = family;
            }
        }

        if (graphics_family != null and present_family != null) {
            return QueuesInfo{
                .graphics_family = graphics_family.?,
                .present_family = present_family.?,
            };
        }

        return null;
    }

    fn checkExtensionSupport(
        instance: vulkan.InstanceProxy,
        pdev: vulkan.PhysicalDevice,
        allocator: std.mem.Allocator,
    ) !bool {
        const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
        defer allocator.free(propsv);

        for (required_device_extensions) |ext| {
            for (propsv) |props| {
                if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                    break;
                }
            } else {
                return false;
            }
        }

        return true;
    }
};
