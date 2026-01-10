const builtin = @import("builtin");
const std = @import("std");
const vulkan = @import("vulkan");
const sdl3 = @import("sdl3");
const log = std.log.scoped(.vk);

const VALIDATION_LAYER = "VK_LAYER_KHRONOS_validation";

pub const VkInstance = struct {
    vkb: vulkan.BaseWrapper,
    instanceProxy: vulkan.InstanceProxy,

    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        const sdlExtensions = try sdl3.vulkan.getInstanceExtensions();

        const rawProc = sdl3.vulkan.getVkGetInstanceProcAddr() catch |err| {
            std.debug.print("Vulkan not available: {}\n", .{err});
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

        _ = try supportsValidation(allocator, &vkb);
        if (validate) {
            if (try supportsValidation(allocator, &vkb)) {
                log.debug("Enabling validation", .{});
                try layer_names.append(allocator, VALIDATION_LAYER);
            } else {
                log.debug("Validation layer not supported. Make sure Vulkan SDK is installed", .{});
            }
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

    fn supportsValidation(allocator: std.mem.Allocator, vkb: *const vulkan.BaseWrapper) !bool {
        var result = false;
        var numLayers: u32 = 0;
        _ = try vkb.enumerateInstanceLayerProperties(&numLayers, null);

        const layers = try allocator.alloc(vulkan.LayerProperties, numLayers);
        defer allocator.free(layers);
        _ = try vkb.enumerateInstanceLayerProperties(&numLayers, layers.ptr);

        for (layers) |layerProps| {
            const layerName = std.mem.sliceTo(&layerProps.layer_name, 0);
            log.debug("Supported layer [{s}]", .{layerName});
            if (std.mem.eql(u8, layerName, VALIDATION_LAYER)) {
                result = true;
            }
        }

        return result;
    }
};
