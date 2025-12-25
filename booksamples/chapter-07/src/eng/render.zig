const com = @import("com");
const eng = @import("mod.zig");
const sdl3 = @import("sdl3");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");

pub const Attachment = struct {
    vkImage: vk.img.VkImage,
    vkImageView: vk.imv.VkImageView,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, width: u32, height: u32, format: vulkan.Format, usage: vulkan.ImageUsageFlags) !Attachment {
        var currUsage = usage;
        currUsage.sampled_bit = true;
        const vkImageData = vk.img.VkImageData{
            .format = format,
            .width = width,
            .height = height,
            .usage = currUsage,
        };

        const vkImage = try vk.img.VkImage.create(vkCtx, vkImageData);
        var aspectMask: vulkan.ImageAspectFlags = vulkan.ImageAspectFlags{ .color_bit = true };
        if (usage.depth_stencil_attachment_bit) {
            aspectMask.color_bit = false;
            aspectMask.depth_bit = true;
        }
        const imageViewData = vk.imv.VkImageViewData{
            .format = format,
            .aspectmask = aspectMask,
        };
        const vkImageView = try vk.imv.VkImageView.create(vkCtx.vkDevice, vkImage.image, imageViewData);

        return .{
            .vkImage = vkImage,
            .vkImageView = vkImageView,
        };
    }

    pub fn cleanup(self: *Attachment, vkCtx: *const vk.ctx.VkCtx) void {
        self.vkImageView.cleanup(vkCtx.vkDevice);
        self.vkImage.cleanup(vkCtx);
    }
};

pub const Render = struct {
    vkCtx: vk.ctx.VkCtx,
    cmdPools: []vk.cmd.VkCmdPool,
    cmdBuffs: []vk.cmd.VkCmdBuff,
    currentFrame: u8,
    fences: []vk.sync.VkFence,
    modelsCache: eng.mcach.ModelsCache,
    mustResize: bool,
    queueGraphics: vk.queue.VkQueue,
    queuePresent: vk.queue.VkQueue,
    renderScn: eng.rscn.RenderScn,
    semsPresComplete: []vk.sync.VkSemaphore,
    semsRenderComplete: []vk.sync.VkSemaphore,

    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) !void {
        try self.vkCtx.vkDevice.wait();

        self.renderScn.cleanup(allocator, &self.vkCtx);

        self.modelsCache.cleanup(allocator, &self.vkCtx);

        for (self.cmdPools) |cmdPool| {
            cmdPool.cleanup(&self.vkCtx);
        }
        allocator.free(self.cmdBuffs);

        defer allocator.free(self.cmdPools);
        for (self.fences) |fence| {
            fence.cleanup(&self.vkCtx);
        }
        defer allocator.free(self.fences);

        self.cleanupSemphs(allocator);

        try self.vkCtx.cleanup(allocator);
    }

    fn cleanupSemphs(self: *Render, allocator: std.mem.Allocator) void {
        for (self.semsRenderComplete) |sem| {
            sem.cleanup(&self.vkCtx);
        }
        defer allocator.free(self.semsRenderComplete);

        for (self.semsPresComplete) |sem| {
            sem.cleanup(&self.vkCtx);
        }
        defer allocator.free(self.semsPresComplete);
    }

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !Render {
        const vkCtx = try vk.ctx.VkCtx.create(allocator, constants, window);

        const fences = try allocator.alloc(vk.sync.VkFence, com.common.FRAMES_IN_FLIGHT);
        for (fences) |*fence| {
            fence.* = try vk.sync.VkFence.create(&vkCtx);
        }

        const semsRenderComplete = try allocator.alloc(vk.sync.VkSemaphore, vkCtx.vkSwapChain.imageViews.len);
        for (semsRenderComplete) |*sem| {
            sem.* = try vk.sync.VkSemaphore.create(&vkCtx);
        }

        const semsPresComplete = try allocator.alloc(vk.sync.VkSemaphore, com.common.FRAMES_IN_FLIGHT);
        for (semsPresComplete) |*sem| {
            sem.* = try vk.sync.VkSemaphore.create(&vkCtx);
        }

        const cmdPools = try allocator.alloc(vk.cmd.VkCmdPool, com.common.FRAMES_IN_FLIGHT);
        for (cmdPools) |*cmdPool| {
            cmdPool.* = try vk.cmd.VkCmdPool.create(&vkCtx, vkCtx.vkPhysDevice.queuesInfo.graphics_family, false);
        }

        const cmdBuffs = try allocator.alloc(vk.cmd.VkCmdBuff, com.common.FRAMES_IN_FLIGHT);
        for (cmdBuffs, 0..) |*cmdBuff, i| {
            cmdBuff.* = try vk.cmd.VkCmdBuff.create(&vkCtx, &cmdPools[i], true);
        }

        const queueGraphics = vk.queue.VkQueue.create(&vkCtx, vkCtx.vkPhysDevice.queuesInfo.graphics_family);
        const queuePresent = vk.queue.VkQueue.create(&vkCtx, vkCtx.vkPhysDevice.queuesInfo.present_family);

        const renderScn = try eng.rscn.RenderScn.create(allocator, &vkCtx);

        const modelsCache = eng.mcach.ModelsCache.create(allocator);

        return .{
            .vkCtx = vkCtx,
            .cmdPools = cmdPools,
            .cmdBuffs = cmdBuffs,
            .currentFrame = 0,
            .fences = fences,
            .modelsCache = modelsCache,
            .mustResize = false,
            .queueGraphics = queueGraphics,
            .queuePresent = queuePresent,
            .renderScn = renderScn,
            .semsPresComplete = semsPresComplete,
            .semsRenderComplete = semsRenderComplete,
        };
    }

    pub fn init(self: *Render, allocator: std.mem.Allocator, engCtx: *eng.engine.EngCtx, initData: *const eng.engine.InitData) !void {
        const constants = engCtx.constants;
        const extent = self.vkCtx.vkSwapChain.extent;
        engCtx.scene.camera.projData.update(
            constants.fov,
            constants.zNear,
            constants.zFar,
            @as(f32, @floatFromInt(extent.width)),
            @as(f32, @floatFromInt(extent.height)),
        );
        try self.modelsCache.init(allocator, &self.vkCtx, &self.cmdPools[0], self.queueGraphics, initData);
    }

    pub fn render(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        const fence = self.fences[self.currentFrame];
        try fence.wait(&self.vkCtx);

        const vkCmdPool = self.cmdPools[self.currentFrame];
        try vkCmdPool.reset(&self.vkCtx);

        const vkCmdBuff = self.cmdBuffs[self.currentFrame];
        try vkCmdBuff.begin(&self.vkCtx);

        const res = try self.vkCtx.vkSwapChain.acquire(self.vkCtx.vkDevice, self.semsPresComplete[self.currentFrame]);
        if (engCtx.wnd.resized or self.mustResize or res == .recreate) {
            try vkCmdBuff.end(&self.vkCtx);
            try self.resize(engCtx);
            return;
        }
        const imageIndex = res.ok;

        self.renderInit(vkCmdBuff, imageIndex);

        try self.renderScn.render(&self.vkCtx, engCtx, vkCmdBuff, &self.modelsCache, imageIndex);

        self.renderFinish(vkCmdBuff, imageIndex);

        try vkCmdBuff.end(&self.vkCtx);

        try self.submit(&vkCmdBuff, imageIndex);

        self.mustResize = !self.vkCtx.vkSwapChain.present(self.vkCtx.vkDevice, self.queuePresent, self.semsRenderComplete[imageIndex], imageIndex);

        self.currentFrame = (self.currentFrame + 1) % com.common.FRAMES_IN_FLIGHT;
    }

    fn renderFinish(self: *Render, vkCmd: vk.cmd.VkCmdBuff, imageIndex: u32) void {
        const endBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.color_attachment_optimal,
            .new_layout = vulkan.ImageLayout.present_src_khr,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_stage_mask = .{ .bottom_of_pipe_bit = true },
            .src_access_mask = .{ .color_attachment_write_bit = true },
            .dst_access_mask = .{},
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = vulkan.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
            },
            .image = self.vkCtx.vkSwapChain.imageViews[imageIndex].image,
        }};
        const endDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = endBarriers.len,
            .p_image_memory_barriers = &endBarriers,
        };
        self.vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(vkCmd.cmdBuffProxy.handle, &endDepInfo);
    }

    fn renderInit(self: *Render, vkCmd: vk.cmd.VkCmdBuff, imageIndex: u32) void {
        const initBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.undefined,
            .new_layout = vulkan.ImageLayout.color_attachment_optimal,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .color_attachment_write_bit = true },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = vulkan.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
            },
            .image = self.vkCtx.vkSwapChain.imageViews[imageIndex].image,
        }};
        const initDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = initBarriers.len,
            .p_image_memory_barriers = &initBarriers,
        };
        self.vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(vkCmd.cmdBuffProxy.handle, &initDepInfo);
    }

    fn resize(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        const allocator = engCtx.allocator;
        const size = try engCtx.wnd.getSize();
        if (size.width == 0 and size.height == 0) {
            return;
        }
        self.mustResize = false;
        try self.vkCtx.vkDevice.wait();
        try self.vkCtx.resize(allocator, engCtx.wnd.window);

        for (self.semsRenderComplete) |sem| {
            sem.cleanup(&self.vkCtx);
        }
        allocator.free(self.semsRenderComplete);

        for (self.semsPresComplete) |sem| {
            sem.cleanup(&self.vkCtx);
        }
        allocator.free(self.semsPresComplete);

        const semsRenderComplete = try allocator.alloc(vk.sync.VkSemaphore, self.vkCtx.vkSwapChain.imageViews.len);
        for (semsRenderComplete) |*sem| {
            sem.* = try vk.sync.VkSemaphore.create(&self.vkCtx);
        }

        const semsPresComplete = try allocator.alloc(vk.sync.VkSemaphore, com.common.FRAMES_IN_FLIGHT);
        for (semsPresComplete) |*sem| {
            sem.* = try vk.sync.VkSemaphore.create(&self.vkCtx);
        }

        self.semsPresComplete = semsPresComplete;
        self.semsRenderComplete = semsRenderComplete;

        const constants = engCtx.constants;
        const extent = self.vkCtx.vkSwapChain.extent;
        engCtx.scene.camera.projData.update(
            constants.fov,
            constants.zNear,
            constants.zFar,
            @as(f32, @floatFromInt(extent.width)),
            @as(f32, @floatFromInt(extent.height)),
        );

        try self.renderScn.resize(&self.vkCtx, engCtx);
    }

    fn submit(self: *Render, vkCmdBuff: *const vk.cmd.VkCmdBuff, imageIndex: u32) !void {
        const vkFence = self.fences[self.currentFrame];

        const cmdBufferInfo = vulkan.CommandBufferSubmitInfo{
            .device_mask = 0,
            .command_buffer = vkCmdBuff.cmdBuffProxy.handle,
        };

        const semWaitInfo = vulkan.SemaphoreSubmitInfo{
            .device_index = 0,
            .value = 0,
            .stage_mask = .{ .color_attachment_output_bit = true },
            .semaphore = self.semsPresComplete[self.currentFrame].semaphore,
        };

        const semSignalInfo = vulkan.SemaphoreSubmitInfo{
            .device_index = 0,
            .value = 0,
            .stage_mask = .{ .bottom_of_pipe_bit = true },
            .semaphore = self.semsRenderComplete[imageIndex].semaphore,
        };

        try self.queueGraphics.submit(&self.vkCtx, &.{cmdBufferInfo}, &.{semSignalInfo}, &.{semWaitInfo}, vkFence);
    }
};
