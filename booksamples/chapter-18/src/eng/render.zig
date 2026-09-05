const com = @import("com");
const eng = @import("mod.zig");
const sdl3 = @import("sdl3");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const log = std.log.scoped(.eng);

pub const Attachment = struct {
    vkImage: vk.img.VkImage,
    vkImageView: vk.imv.VkImageView,

    pub fn create(
        vkCtx: *const vk.ctx.VkCtx,
        width: u32,
        height: u32,
        format: vulkan.Format,
        usage: vulkan.ImageUsageFlags,
        layers: u32,
    ) !Attachment {
        var currUsage = usage;
        currUsage.sampled_bit = true;
        const vkImageData = vk.img.VkImageData{
            .format = format,
            .width = width,
            .height = height,
            .arrayLayers = layers,
            .usage = currUsage,
        };

        const vkImage = try vk.img.VkImage.create(vkCtx, vkImageData);
        errdefer vkImage.cleanup(vkCtx);
        var aspectMask: vulkan.ImageAspectFlags = vulkan.ImageAspectFlags{ .color_bit = true };
        if (usage.depth_stencil_attachment_bit) {
            aspectMask.color_bit = false;
            aspectMask.depth_bit = true;
        }
        const imageViewData = vk.imv.VkImageViewData{
            .format = format,
            .aspectmask = aspectMask,
            .viewType = if (layers > 1) vulkan.ImageViewType.@"2d_array" else vulkan.ImageViewType.@"2d",
            .layerCount = layers,
        };
        const image: vulkan.Image = @enumFromInt(@intFromPtr(vkImage.image));
        var vkImageView = try vk.imv.VkImageView.create(vkCtx.vkDevice, image, imageViewData);
        errdefer vkImageView.cleanup(vkCtx.vkDevice);

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
    animsCache: eng.acach.AnimsCache,
    cmdPools: []vk.cmd.VkCmdPool,
    cmdBuffs: []vk.cmd.VkCmdBuff,
    currentFrame: u8,
    fences: []vk.sync.VkFence,
    materialsCache: eng.mcach.MaterialsCache,
    modelsCache: eng.mcach.ModelsCache,
    mustResize: bool,
    queueGraphics: vk.queue.VkQueue,
    queuePresent: vk.queue.VkQueue,
    renderAnim: eng.ranm.RenderAnim,
    renderGui: eng.rgui.RenderGui,
    renderLight: eng.rlgt.RenderLight,
    renderPost: eng.rpst.RenderPost,
    renderScn: eng.rscn.RenderScn,
    renderShadow: eng.rsha.RenderShadow,
    semsPresComplete: []vk.sync.VkSemaphore,
    semsRenderComplete: []vk.sync.VkSemaphore,
    textureCache: eng.tcach.TextureCache,

    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) void {
        self.vkCtx.vkDevice.wait() catch |err| log.err("Device wait failed in cleanup: {}", .{err});

        self.renderAnim.cleanup(&self.vkCtx);
        self.renderGui.cleanup(allocator, &self.vkCtx);
        self.renderPost.cleanup(&self.vkCtx);
        self.renderScn.cleanup(allocator, &self.vkCtx);
        self.renderShadow.cleanup(&self.vkCtx);
        self.renderLight.cleanup(allocator, &self.vkCtx);

        self.animsCache.cleanup(allocator, &self.vkCtx);
        self.textureCache.cleanup(allocator, &self.vkCtx);
        self.materialsCache.cleanup(allocator, &self.vkCtx);
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

        self.vkCtx.cleanup(allocator);
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

    pub fn create(allocator: std.mem.Allocator, io: std.Io, constants: com.common.Constants, window: sdl3.video.Window) !Render {
        var vkCtx = try vk.ctx.VkCtx.create(allocator, constants, window);
        errdefer vkCtx.cleanup(allocator);

        const fences = try allocator.alloc(vk.sync.VkFence, com.common.FRAMES_IN_FLIGHT);
        var initialized: usize = 0;
        errdefer {
            for (fences[0..initialized]) |*fence| {
                fence.cleanup(&vkCtx);
            }
            allocator.free(fences);
        }
        for (fences) |*fence| {
            fence.* = try vk.sync.VkFence.create(&vkCtx);
            initialized += 1;
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

        const renderAnim = try eng.ranm.RenderAnim.create(allocator, io, &vkCtx);
        const renderGui = try eng.rgui.RenderGui.create(allocator, io, &vkCtx);
        const renderScn = try eng.rscn.RenderScn.create(allocator, io, &vkCtx);
        const renderShadow = try eng.rsha.RenderShadow.create(allocator, io, &vkCtx, constants);
        const attachments = try allocator.alloc(eng.rend.Attachment, renderScn.attachments.len + 1);
        defer allocator.free(attachments);
        for (0..renderScn.attachments.len) |i| {
            attachments[i] = renderScn.attachments[i];
        }
        attachments[attachments.len - 1] = renderShadow.attColor;
        const renderLight = try eng.rlgt.RenderLight.create(allocator, io, &vkCtx, constants, &attachments);
        const renderPost = try eng.rpst.RenderPost.create(allocator, io, &vkCtx, constants, &renderLight.outputAtt);

        const materialsCache = eng.mcach.MaterialsCache.create();
        const modelsCache = eng.mcach.ModelsCache.create(allocator);
        const textureCache = eng.tcach.TextureCache.create();
        const animsCache = eng.acach.AnimsCache.create();

        return .{
            .vkCtx = vkCtx,
            .animsCache = animsCache,
            .cmdPools = cmdPools,
            .cmdBuffs = cmdBuffs,
            .currentFrame = 0,
            .fences = fences,
            .materialsCache = materialsCache,
            .modelsCache = modelsCache,
            .mustResize = false,
            .queueGraphics = queueGraphics,
            .queuePresent = queuePresent,
            .renderAnim = renderAnim,
            .renderGui = renderGui,
            .renderLight = renderLight,
            .renderPost = renderPost,
            .renderScn = renderScn,
            .renderShadow = renderShadow,
            .semsPresComplete = semsPresComplete,
            .semsRenderComplete = semsRenderComplete,
            .textureCache = textureCache,
        };
    }

    pub fn init(self: *Render, engCtx: *eng.engine.EngCtx, initData: *const eng.engine.InitData) !void {
        log.debug("Starting render init", .{});
        const constants = engCtx.constants;
        const extent = self.vkCtx.vkSwapChain.extent;
        engCtx.scene.camera.projData.update(
            constants.fov,
            constants.zNear,
            constants.zFar,
            @as(f32, @floatFromInt(extent.width)),
            @as(f32, @floatFromInt(extent.height)),
        );
        const allocator = engCtx.allocator;
        try self.materialsCache.init(
            allocator,
            engCtx.io,
            &self.vkCtx,
            &self.textureCache,
            &self.cmdPools[0],
            self.queueGraphics,
            initData,
        );
        const numTextures = self.textureCache.textureMap.count();
        if (numTextures < eng.tcach.MAX_TEXTURES) {
            const numPadding = eng.tcach.MAX_TEXTURES - numTextures;
            for (0..numPadding) |_| {
                const id = try com.utils.generateUuid(allocator, engCtx.io);
                defer allocator.free(id);
                const textureInfo = eng.tcach.TextureInfo{
                    .data = eng.tcach.EMPTY_PIXELS[0..],
                    .width = 1,
                    .height = 1,
                    .format = vulkan.Format.r8g8b8a8_srgb,
                    .id = id,
                };
                try self.textureCache.addTexture(allocator, &self.vkCtx, &textureInfo);
            }
        }
        try self.textureCache.recordTextures(&self.vkCtx, &self.cmdPools[0], self.queueGraphics);

        try self.modelsCache.init(allocator, engCtx.io, &self.vkCtx, &self.cmdPools[0], self.queueGraphics, initData);

        try self.animsCache.init(allocator, &self.vkCtx, engCtx, &self.modelsCache);

        try self.renderScn.init(allocator, &self.vkCtx, &self.textureCache, &self.materialsCache);
        try self.renderShadow.init(allocator, &self.vkCtx, &self.textureCache, &self.materialsCache);
        try self.renderAnim.init(&self.modelsCache);
        log.debug("Finished render init", .{});
    }

    pub fn render(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        const fence = self.fences[self.currentFrame];
        try fence.wait(&self.vkCtx);

        const vkCmdPool = self.cmdPools[self.currentFrame];
        try vkCmdPool.reset(&self.vkCtx);

        const vkCmdBuff = self.cmdBuffs[self.currentFrame];
        try vkCmdBuff.begin(&self.vkCtx);

        try self.renderAnim.render(
            &self.vkCtx,
            engCtx,
            &self.modelsCache,
            &self.animsCache,
        );

        const res = try self.vkCtx.vkSwapChain.acquire(self.vkCtx.vkDevice, self.semsPresComplete[self.currentFrame]);
        if (engCtx.wnd.resized or self.mustResize or res == .recreate) {
            try vkCmdBuff.end(&self.vkCtx);
            try self.resize(engCtx);
            return;
        }
        const imageIndex = res.ok;

        try self.renderScn.render(
            &self.vkCtx,
            engCtx,
            vkCmdBuff,
            &self.modelsCache,
            &self.materialsCache,
            &self.animsCache,
            self.currentFrame,
        );
        try self.renderShadow.render(
            &self.vkCtx,
            engCtx,
            vkCmdBuff,
            &self.modelsCache,
            &self.materialsCache,
            &self.animsCache,
        );
        try self.renderLight.render(
            &self.vkCtx,
            engCtx,
            vkCmdBuff,
            self.currentFrame,
            &self.renderShadow.cascadeShadows,
        );

        self.renderInitPost(vkCmdBuff, imageIndex);
        try self.renderPost.render(&self.vkCtx, engCtx, vkCmdBuff, imageIndex);
        try self.renderGui.render(
            &self.vkCtx,
            engCtx,
            vkCmdBuff,
            &self.cmdPools[0],
            self.queueGraphics,
            imageIndex,
            self.currentFrame,
        );
        self.renderFinishPost(vkCmdBuff, imageIndex);

        try vkCmdBuff.end(&self.vkCtx);

        try self.submit(&vkCmdBuff, imageIndex);

        self.mustResize = !self.vkCtx.vkSwapChain.present(self.vkCtx.vkDevice, self.queuePresent, self.semsRenderComplete[imageIndex], imageIndex);

        self.currentFrame = (self.currentFrame + 1) % com.common.FRAMES_IN_FLIGHT;
    }

    fn renderFinishPost(self: *Render, vkCmd: vk.cmd.VkCmdBuff, imageIndex: u32) void {
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

    fn renderInitPost(self: *Render, vkCmd: vk.cmd.VkCmdBuff, imageIndex: u32) void {
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
        self.vkCtx.vkDevice.wait() catch |err| log.err("Device wait failed in cleanup: {}", .{err});
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
        try self.renderLight.resize(&self.vkCtx, engCtx, &self.renderScn.attachments);
        try self.renderPost.resize(&self.vkCtx, &self.renderLight.outputAtt);
        try self.renderGui.resize(&self.vkCtx);
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
