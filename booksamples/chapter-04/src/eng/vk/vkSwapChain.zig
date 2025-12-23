const std = @import("std");
const sdl3 = @import("sdl3");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);

pub const ImageAcquisitionResult = union(enum) {
    imageIndex: u32,
    err: bool,
};

pub const VkSwapChain = struct {
    extent: vulkan.Extent2D,
    imageViews: []vk.imv.VkImageView,
    surfaceFormat: vulkan.SurfaceFormatKHR,
    swapChainKhr: vulkan.SwapchainKHR,

    pub fn cleanup(self: *const VkSwapChain, allocator: std.mem.Allocator, vkDevice: vk.dev.VkDevice) void {
        for (self.imageViews) |imageView| {
            imageView.cleanup(vkDevice);
        }
        allocator.free(self.imageViews);
        vkDevice.deviceProxy.destroySwapchainKHR(self.swapChainKhr, null);
    }

    pub fn create(
        allocator: std.mem.Allocator,
        window: sdl3.video.Window,
        vkInstance: vk.inst.VkInstance,
        vkPhysDevice: vk.phys.VkPhysDevice,
        vkDevice: vk.dev.VkDevice,
        vkSurface: vk.surf.VkSurface,
        requestedImages: u8,
        vsync: bool,
    ) !VkSwapChain {
        const presentMode = if (vsync) vulkan.PresentModeKHR.fifo_khr else vulkan.PresentModeKHR.immediate_khr;
        const surfaceKhr: vulkan.SurfaceKHR = vkSurface.surface;
        const surfaceFormat = try vkSurface.getSurfaceFormat(allocator, vkInstance, vkPhysDevice);
        const caps = try vkSurface.getSurfaceCaps(vkInstance, vkPhysDevice);
        const extent = try calcSurfaceExtent(window, caps);
        const qfi = [_]u32{ vkPhysDevice.queuesInfo.graphics_family, vkPhysDevice.queuesInfo.present_family };

        const numImages = getNumImages(caps, requestedImages);

        const swapChainCreateInfo: vulkan.SwapchainCreateInfoKHR = .{
            .surface = surfaceKhr,
            .min_image_count = numImages,
            .image_format = surfaceFormat.format,
            .image_color_space = surfaceFormat.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{
                .color_attachment_bit = true,
                .transfer_dst_bit = true,
            },
            .image_sharing_mode = vulkan.SharingMode.exclusive,
            .queue_family_index_count = qfi.len,
            .p_queue_family_indices = &qfi,
            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = presentMode,
            .clipped = vulkan.Bool32.true,
        };
        const swapChainKhr = try vkDevice.deviceProxy.createSwapchainKHR(&swapChainCreateInfo, null);

        const imageViews = try createSwapChainImages(
            allocator,
            vkDevice,
            swapChainKhr,
            surfaceFormat.format,
        );
        return .{
            .extent = extent,
            .imageViews = imageViews,
            .surfaceFormat = surfaceFormat,
            .swapChainKhr = swapChainKhr,
        };
    }

    fn getNumImages(caps: vulkan.SurfaceCapabilitiesKHR, requestedImages: u8) u32 {
        const maxImages = caps.max_image_count;
        const minImages = caps.min_image_count;
        var result = minImages;
        if (maxImages != 0) {
            result = @min(maxImages, requestedImages);
        }
        result = @max(result, minImages);
        log.debug("Requested [{d}] images, got [{d}] images. Surface capabilities, maxImages: [{d}], minImages [{d}]", .{ requestedImages, result, maxImages, minImages });

        return result;
    }

    pub fn acquire(self: *const VkSwapChain, vkDevice: vk.dev.VkDevice, sem: vk.sync.VkSemaphore) !ImageAcquisitionResult {
        const acquireRes = vkDevice.deviceProxy.acquireNextImageKHR(self.swapChainKhr, std.math.maxInt(u64), sem.semaphore, .null_handle);
        if (acquireRes) |success_value| {
            if (success_value.result == .not_ready or success_value.result == .timeout) {
                return .{ .err = true };
            } else {
                return .{ .imageIndex = success_value.image_index };
            }
        } else |err| {
            switch (err) {
                error.OutOfDateKHR => {
                    return .{ .err = true };
                },
                else => {
                    return error.ErrorAcquiring;
                },
            }
        }
    }

    fn calcSurfaceExtent(window: sdl3.video.Window, caps: vulkan.SurfaceCapabilitiesKHR) !vulkan.Extent2D {
        if (caps.current_extent.width != 0xFFFF_FFFF) {
            return caps.current_extent;
        } else {
            const windowSize = try sdl3.video.Window.getSizeInPixels(window);
            return .{
                .width = std.math.clamp(@as(u32, @intCast(windowSize[0])), caps.min_image_extent.width, caps.max_image_extent.width),
                .height = std.math.clamp(@as(u32, @intCast(windowSize[1])), caps.min_image_extent.height, caps.max_image_extent.height),
            };
        }
    }

    fn createSwapChainImages(allocator: std.mem.Allocator, vkDevice: vk.dev.VkDevice, swapChainKhr: vulkan.SwapchainKHR, format: vulkan.Format) ![]vk.imv.VkImageView {
        const images = try vkDevice.deviceProxy.getSwapchainImagesAllocKHR(swapChainKhr, allocator);
        defer allocator.free(images);

        const swapImages = try allocator.alloc(vk.imv.VkImageView, images.len);
        errdefer allocator.free(swapImages);

        const imageViewData = vk.imv.VkImageViewData{
            .format = format,
        };
        var i: usize = 0;
        for (images) |image| {
            swapImages[i] = try vk.imv.VkImageView.create(vkDevice, image, imageViewData);
            i += 1;
        }

        return swapImages;
    }

    pub fn present(self: *const VkSwapChain, vkDevice: vk.dev.VkDevice, queue: vk.queue.VkQueue, sem: vk.sync.VkSemaphore, imageIndex: u32) bool {
        const presentInfo = vulkan.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&sem.semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.swapChainKhr),
            .p_image_indices = @ptrCast(&imageIndex),
        };
        const result = vkDevice.deviceProxy.queuePresentKHR(queue.handle, &presentInfo) catch {
            // Any error means presentation failed
            return false;
        };

        return switch (result) {
            .success, .suboptimal_khr => true,
            else => false,
        };
    }
};
