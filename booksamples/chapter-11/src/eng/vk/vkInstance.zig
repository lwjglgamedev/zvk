const builtin = @import("builtin");
const std = @import("std");
const vulkan = @import("vulkan");
const sdl3 = @import("sdl3");
const log = std.log.scoped(.vk);

pub const VkInstance = struct {
    vkb: vulkan.BaseWrapper,
    instanceProxy: vulkan.InstanceProxy,

    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        const sdlExtensions = try sdl3.vulkan.getInstanceExtensions();

        const rawProc = sdl3.vulkan.getVkGetInstanceProcAddr() catch |err| {
            std.debug.print("SDL Vulkan not available: {}\n", .{err});
            return err;
        };

        const loader: vulkan.PfnGetInstanceProcAddr = @ptrCast(rawProc);
        const vkb = vulkan.BaseWrapper.load(loader);

        const appInfo = vulkan.ApplicationInfo{
            .p_application_name = "app_name",
            .application_version = @bitCast(vulkan.makeApiVersion(0, 1, 0, 0)),
            .p_engine_name = "app_name",
            .engine_version = @bitCast(vulkan.makeApiVersion(0, 1, 0, 0)),
            .api_version = @bitCast(vulkan.API_VERSION_1_3),
        };

        var layer_names = try std.ArrayList([*:0]const u8).initCapacity(allocator, 2);
        defer layer_names.deinit(allocator);
        if (validate) {
            log.debug("Enabling validation. Make sure Vulkan SDK is installed", .{});
            try layer_names.append(allocator, "VK_LAYER_KHRONOS_validation");
        }

        for (sdlExtensions) |value| {
            log.debug("SDL extension: {s}", .{value});
        }

        var extension_names = try std.ArrayList([*:0]const u8).initCapacity(allocator, 2);
        defer extension_names.deinit(allocator);
        try extension_names.appendSlice(allocator, sdlExtensions);
        const is_macos = builtin.target.os.tag == .macos;
        if (is_macos) {
            try extension_names.append("VK_KHR_portability_enumeration");
        }

        for (extension_names.items) |value| {
            log.debug("Instance create extension: {s}", .{value});
        }

        const createInfo = vulkan.InstanceCreateInfo{
            .p_application_info = &appInfo,
            .enabled_extension_count = @intCast(extension_names.items.len),
            .pp_enabled_extension_names = extension_names.items.ptr,
            .enabled_layer_count = @intCast(layer_names.items.len),
            .pp_enabled_layer_names = layer_names.items.ptr,
            .flags = .{ .enumerate_portability_bit_khr = is_macos },
        };
        const instance = try vkb.createInstance(&createInfo, null);

        const vki = try allocator.create(vulkan.InstanceWrapper);
        vki.* = vulkan.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
        const instanceProxy = vulkan.InstanceProxy.init(instance, vki);

        return .{ .vkb = vkb, .instanceProxy = instanceProxy };
    }

    pub fn cleanup(self: *VkInstance, allocator: std.mem.Allocator) !void {
        log.debug("Destroying Vulkan instance", .{});
        self.instanceProxy.destroyInstance(null);
        allocator.destroy(self.instanceProxy.wrapper);
        self.instanceProxy = undefined;
    }
};
