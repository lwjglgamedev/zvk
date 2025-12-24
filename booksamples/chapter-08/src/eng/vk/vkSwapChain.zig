const std = @import("std");
const sdl3 = @import("sdl3");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);

pub const AcquireResult = union(enum) {
    ok: u32,
    recreate,
};

pub const VkSwapChain = struct {
    extent: vulkan.Extent2D,
    imageViews: []vk.imv.VkImageView,
    surfaceFormat: vulkan.SurfaceFormatKHR,
    handle: vulkan.SwapchainKHR,
    vsync: bool,

    pub fn cleanup(self: *const VkSwapChain, allocator: std.mem.Allocator, device: vk.dev.VkDevice) void {
        for (self.imageViews) |*iv| {
            iv.cleanup(device);
        }
        allocator.free(self.imageViews);
        device.deviceProxy.destroySwapchainKHR(self.handle, null);
    }

    pub fn create(
        allocator: std.mem.Allocator,
        window: sdl3.video.Window,
        instance: vk.inst.VkInstance,
        phys: vk.phys.VkPhysDevice,
        device: vk.dev.VkDevice,
        surface: vk.surf.VkSurface,
        requested_images: u32,
        vsync: bool,
    ) !VkSwapChain {
        const caps = try surface.getSurfaceCaps(instance, phys);
        const extent = try calcExtent(window, caps);
        const surfaceFormat = try surface.getSurfaceFormat(allocator, instance, phys);
        const presentMode = try choosePresentMode(allocator, instance, phys, surface.surface, vsync);
        const imageCount = chooseImageCount(caps, requested_images);

        const sameFamily =
            phys.queuesInfo.graphics_family ==
            phys.queuesInfo.present_family;

        const qfi = [_]u32{
            phys.queuesInfo.graphics_family,
            phys.queuesInfo.present_family,
        };

        const swapchain_info = vulkan.SwapchainCreateInfoKHR{
            .surface = surface.surface,
            .min_image_count = imageCount,
            .image_format = surfaceFormat.format,
            .image_color_space = surfaceFormat.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{
                .color_attachment_bit = true,
                .transfer_dst_bit = true,
            },
            .image_sharing_mode = if (sameFamily) .exclusive else .concurrent,
            .queue_family_index_count = if (sameFamily) 0 else qfi.len,
            .p_queue_family_indices = if (sameFamily) null else &qfi,
            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = presentMode,
            .clipped = vulkan.Bool32.true,
            .old_swapchain = .null_handle,
        };

        const handle = try device.deviceProxy.createSwapchainKHR(&swapchain_info, null);

        const imageViews = try createImageViews(
            allocator,
            device,
            handle,
            surfaceFormat.format,
        );

        log.debug(
            "VkSwapChain created: {d} images, extent {d}x{d}, present mode {any}",
            .{ imageViews.len, extent.width, extent.height, presentMode },
        );

        return .{
            .extent = extent,
            .imageViews = imageViews,
            .surfaceFormat = surfaceFormat,
            .handle = handle,
            .vsync = vsync,
        };
    }

    pub fn acquire(
        self: *const VkSwapChain,
        device: vk.dev.VkDevice,
        semaphore: vk.sync.VkSemaphore,
    ) !AcquireResult {
        const res = device.deviceProxy.acquireNextImageKHR(
            self.handle,
            std.math.maxInt(u64),
            semaphore.semaphore,
            .null_handle,
        );

        if (res) |ok| {
            return switch (ok.result) {
                .success, .suboptimal_khr => .{ .ok = ok.image_index },
                else => .recreate,
            };
        } else |err| {
            return switch (err) {
                error.OutOfDateKHR => .recreate,
                else => err,
            };
        }
    }

    pub fn present(
        self: *const VkSwapChain,
        device: vk.dev.VkDevice,
        queue: vk.queue.VkQueue,
        waitSem: vk.sync.VkSemaphore,
        imgIdx: u32,
    ) bool {
        const sems = [_]vulkan.Semaphore{waitSem.semaphore};
        const swaps = [_]vulkan.SwapchainKHR{self.handle};
        const indices = [_]u32{imgIdx};

        const info = vulkan.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &sems,
            .swapchain_count = 1,
            .p_swapchains = &swaps,
            .p_image_indices = &indices,
        };

        const result = device.deviceProxy.queuePresentKHR(queue.handle, &info) catch return false;

        return switch (result) {
            .success, .suboptimal_khr => true,
            else => false,
        };
    }

    fn chooseImageCount(caps: vulkan.SurfaceCapabilitiesKHR, requested: u32) u32 {
        var count = if (requested > 0) requested else caps.min_image_count + 1;

        if (count < caps.min_image_count) {
            count = caps.min_image_count;
        }

        if (caps.max_image_count > 0 and count > caps.max_image_count) {
            count = caps.max_image_count;
        }

        return count;
    }

    fn choosePresentMode(
        allocator: std.mem.Allocator,
        instance: vk.inst.VkInstance,
        phys: vk.phys.VkPhysDevice,
        surface: vulkan.SurfaceKHR,
        vsync: bool,
    ) !vulkan.PresentModeKHR {
        const modes = try instance.instanceProxy.getPhysicalDeviceSurfacePresentModesAllocKHR(
            phys.pdev,
            surface,
            allocator,
        );
        defer allocator.free(modes);

        if (!vsync) {
            for (modes) |m| {
                if (m == .mailbox_khr) return m;
            }
            for (modes) |m| {
                if (m == .immediate_khr) return m;
            }
        }

        return .fifo_khr;
    }

    fn calcExtent(window: sdl3.video.Window, caps: vulkan.SurfaceCapabilitiesKHR) !vulkan.Extent2D {
        if (caps.current_extent.width != std.math.maxInt(u32)) {
            return caps.current_extent;
        }

        const size = try sdl3.video.Window.getSizeInPixels(window);

        return .{
            .width = std.math.clamp(
                @as(u32, @intCast(size[0])),
                caps.min_image_extent.width,
                caps.max_image_extent.width,
            ),
            .height = std.math.clamp(
                @as(u32, @intCast(size[1])),
                caps.min_image_extent.height,
                caps.max_image_extent.height,
            ),
        };
    }

    fn createImageViews(
        allocator: std.mem.Allocator,
        device: vk.dev.VkDevice,
        swapChain: vulkan.SwapchainKHR,
        format: vulkan.Format,
    ) ![]vk.imv.VkImageView {
        const images = try device.deviceProxy.getSwapchainImagesAllocKHR(swapChain, allocator);
        defer allocator.free(images);

        const views = try allocator.alloc(vk.imv.VkImageView, images.len);

        const ivData = vk.imv.VkImageViewData{ .format = format };

        var i: usize = 0;
        for (images) |img| {
            views[i] = try vk.imv.VkImageView.create(device, img, ivData);
            i += 1;
        }

        return views;
    }
};
