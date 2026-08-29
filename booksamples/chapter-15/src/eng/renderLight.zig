const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");

pub const COLOR_ATTACHMENT_FORMAT = vulkan.Format.r32g32b32a32_sfloat;
const DESC_ID_LIGHT_TEXT_SAMPLER = "RENDER_LIGHT_DESC_ID_TEXT";
const DESC_ID_LIGHTS = "RENDER_LIGHT_DESC_ID_LIGHTS";
const DESC_ID_SCENE_INFO = "RENDER_LIGHT_DESC_ID_SCENE_INFO";
const LIGHTS_BYTES_SIZE: u32 = 32;
const SCENE_INFO_BYTES_SIZE: u32 = 32;

const EmptyVtxBuffDesc = struct {
    const binding_description = vulkan.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(EmptyVtxBuffDesc),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vulkan.VertexInputAttributeDescription{};
};

pub const RenderLight = struct {
    buffsLights: []vk.buf.VkBuffer,
    buffsSceneInfo: []vk.buf.VkBuffer,
    descLayoutAtt: vk.desc.VkDescSetLayout,
    descLayoutArr: vk.desc.VkDescSetLayout,
    descLayoutScene: vk.desc.VkDescSetLayout,
    outputAtt: eng.rend.Attachment,
    textSampler: vk.text.VkTextSampler,
    vkPipeline: vk.pipe.VkPipeline,

    pub fn cleanup(self: *RenderLight, allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx) void {
        for (self.buffsLights) |*buffer| {
            buffer.cleanup(vkCtx);
        }
        allocator.free(self.buffsLights);
        for (self.buffsSceneInfo) |*buffer| {
            buffer.cleanup(vkCtx);
        }
        allocator.free(self.buffsSceneInfo);
        self.descLayoutAtt.cleanup(vkCtx);
        self.descLayoutArr.cleanup(vkCtx);
        self.descLayoutScene.cleanup(vkCtx);
        self.outputAtt.cleanup(vkCtx);
        self.vkPipeline.cleanup(vkCtx);
        self.textSampler.cleanup(vkCtx);
    }

    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        vkCtx: *vk.ctx.VkCtx,
        inputAttachments: *const []eng.rend.Attachment,
    ) !RenderLight {
        const outputAtt = try createColorAttachment(vkCtx);

        // Shader modules
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const vertCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), io, "res/shaders/light_vtx.glsl.spv");
        const vert = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = vertCode.len,
            .p_code = @ptrCast(@alignCast(vertCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(vert, null);

        const fragCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), io, "res/shaders/light_frg.glsl.spv");
        const frag = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = fragCode.len,
            .p_code = @ptrCast(@alignCast(fragCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(frag, null);

        const modulesInfo = try allocator.alloc(vk.pipe.ShaderModuleInfo, 2);
        modulesInfo[0] = .{ .module = vert, .stage = .{ .vertex_bit = true } };
        modulesInfo[1] = .{ .module = frag, .stage = .{ .fragment_bit = true } };
        defer allocator.free(modulesInfo);

        // Textures
        const samplerInfo = vk.text.VkTextSamplerInfo{
            .addressMode = vulkan.SamplerAddressMode.repeat,
            .anisotropy = true,
            .borderColor = vulkan.BorderColor.float_opaque_black,
        };
        const textSampler = try vk.text.VkTextSampler.create(vkCtx, samplerInfo);

        // Descriptor set: Attachments
        const layoutInfos = try allocator.alloc(vk.desc.LayoutInfo, inputAttachments.len);
        defer allocator.free(layoutInfos);
        const imageViews = try allocator.alloc(vk.imv.VkImageView, inputAttachments.len);
        defer allocator.free(imageViews);
        for (0..inputAttachments.len) |i| {
            layoutInfos[i] = vk.desc.LayoutInfo{
                .binding = @as(u32, @intCast(i)),
                .descCount = 1,
                .descType = vulkan.DescriptorType.combined_image_sampler,
                .stageFlags = vulkan.ShaderStageFlags{ .fragment_bit = true },
            };
            imageViews[i] = inputAttachments.ptr[i].vkImageView;
        }
        const descLayoutAtt = try vk.desc.VkDescSetLayout.create(
            allocator,
            vkCtx,
            layoutInfos,
        );
        const attDescSet = try vkCtx.vkDescAllocator.addDescSet(
            allocator,
            vkCtx.vkPhysDevice,
            vkCtx.vkDevice,
            DESC_ID_LIGHT_TEXT_SAMPLER,
            descLayoutAtt,
        );
        try attDescSet.setImages(allocator, vkCtx.vkDevice, imageViews, textSampler, 0);

        // Descriptor set: Lights
        const descLayoutArr = try vk.desc.VkDescSetLayout.create(allocator, vkCtx, &[_]vk.desc.LayoutInfo{.{
            .binding = 0,
            .descCount = 1,
            .descType = vulkan.DescriptorType.storage_buffer,
            .stageFlags = vulkan.ShaderStageFlags{ .fragment_bit = true },
        }});
        const buffsLights = try vk.util.createHostVisibleBuffs(
            allocator,
            vkCtx,
            DESC_ID_LIGHTS,
            com.common.FRAMES_IN_FLIGHT,
            @sizeOf(eng.scn.Light) * eng.scn.MAX_LIGHTS,
            .{ .storage_buffer_bit = true },
            descLayoutArr,
        );

        // Descriptor set: SceneInfo
        const descLayoutScene = try vk.desc.VkDescSetLayout.create(allocator, vkCtx, &[_]vk.desc.LayoutInfo{.{
            .binding = 0,
            .descCount = 1,
            .descType = vulkan.DescriptorType.uniform_buffer,
            .stageFlags = vulkan.ShaderStageFlags{ .fragment_bit = true },
        }});
        const buffsSceneInfo = try vk.util.createHostVisibleBuffs(
            allocator,
            vkCtx,
            DESC_ID_SCENE_INFO,
            com.common.FRAMES_IN_FLIGHT,
            SCENE_INFO_BYTES_SIZE,
            .{ .uniform_buffer_bit = true },
            descLayoutScene,
        );

        const descSetLayouts = [_]vulkan.DescriptorSetLayout{
            descLayoutAtt.descSetLayout,
            descLayoutArr.descSetLayout,
            descLayoutScene.descSetLayout,
        };

        // Pipeline
        const colorFormats = [_]vulkan.Format{COLOR_ATTACHMENT_FORMAT};
        const vkPipelineCreateInfo = vk.pipe.VkPipelineCreateInfo{
            .colorFormats = colorFormats[0..],
            .descSetLayouts = descSetLayouts[0..],
            .modulesInfo = modulesInfo,
            .useBlend = true,
            .pushConstants = null,
            .vtxBuffDesc = .{
                .attribute_description = @constCast(&EmptyVtxBuffDesc.attribute_description)[0..],
                .binding_description = EmptyVtxBuffDesc.binding_description,
            },
        };
        const vkPipeline = try vk.pipe.VkPipeline.create(allocator, vkCtx, &vkPipelineCreateInfo);

        return .{
            .buffsLights = buffsLights,
            .buffsSceneInfo = buffsSceneInfo,
            .descLayoutAtt = descLayoutAtt,
            .descLayoutArr = descLayoutArr,
            .descLayoutScene = descLayoutScene,
            .outputAtt = outputAtt,
            .textSampler = textSampler,
            .vkPipeline = vkPipeline,
        };
    }

    fn createColorAttachment(vkCtx: *const vk.ctx.VkCtx) !eng.rend.Attachment {
        const extent = vkCtx.vkSwapChain.extent;
        const flags = vulkan.ImageUsageFlags{
            .color_attachment_bit = true,
            .sampled_bit = true,
        };
        const attColor = try eng.rend.Attachment.create(
            vkCtx,
            extent.width,
            extent.height,
            COLOR_ATTACHMENT_FORMAT,
            flags,
        );
        return attColor;
    }

    pub fn render(
        self: *RenderLight,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        vkCmd: vk.cmd.VkCmdBuff,
        frameIdx: u8,
    ) !void {
        const allocator = engCtx.allocator;
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;

        self.renderInit(vkCtx, cmdHandle);

        const renderAttInfo = vulkan.RenderingAttachmentInfo{
            .image_view = self.outputAtt.vkImageView.view,
            .image_layout = vulkan.ImageLayout.attachment_optimal_khr,
            .load_op = vulkan.AttachmentLoadOp.clear,
            .store_op = vulkan.AttachmentStoreOp.store,
            .clear_value = vulkan.ClearValue{ .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
            .resolve_mode = vulkan.ResolveModeFlags{},
            .resolve_image_layout = vulkan.ImageLayout.attachment_optimal_khr,
        };
        const extent = vkCtx.vkSwapChain.extent;
        const renderInfo = vulkan.RenderingInfo{
            .render_area = .{ .extent = extent, .offset = .{ .x = 0, .y = 0 } },
            .layer_count = 1,
            .color_attachment_count = 1,
            .p_color_attachments = &[_]vulkan.RenderingAttachmentInfo{renderAttInfo},
            .view_mask = 0,
        };
        device.cmdBeginRendering(cmdHandle, @ptrCast(&renderInfo));

        device.cmdBindPipeline(cmdHandle, vulkan.PipelineBindPoint.graphics, self.vkPipeline.pipeline);

        const viewPort = [_]vulkan.Viewport{.{
            .x = 0,
            .y = @as(f32, @floatFromInt(extent.height)),
            .width = @as(f32, @floatFromInt(extent.width)),
            .height = -1.0 * @as(f32, @floatFromInt(extent.height)),
            .min_depth = 0,
            .max_depth = 1,
        }};
        device.cmdSetViewport(cmdHandle, 0, &viewPort);
        const scissor = [_]vulkan.Rect2D{.{
            .offset = vulkan.Offset2D{ .x = 0, .y = 0 },
            .extent = extent,
        }};
        device.cmdSetScissor(cmdHandle, 0, &scissor);

        try self.updateLights(vkCtx, &engCtx.scene, frameIdx);
        try self.updateSceneInfo(vkCtx, &engCtx.scene, frameIdx);

        // Bind descriptor sets
        const vkDescAllocator = vkCtx.vkDescAllocator;
        var descSets = try std.ArrayList(vulkan.DescriptorSet).initCapacity(allocator, 3);
        defer descSets.deinit(allocator);
        try descSets.append(allocator, vkDescAllocator.getDescSet(DESC_ID_LIGHT_TEXT_SAMPLER).?.descSet);
        const lightDescId = try std.fmt.allocPrint(allocator, "{s}{d}", .{ DESC_ID_LIGHTS, frameIdx });
        defer allocator.free(lightDescId);
        try descSets.append(allocator, vkDescAllocator.getDescSet(lightDescId).?.descSet);
        const sceneDescId = try std.fmt.allocPrint(allocator, "{s}{d}", .{ DESC_ID_SCENE_INFO, frameIdx });
        defer allocator.free(sceneDescId);
        try descSets.append(allocator, vkDescAllocator.getDescSet(sceneDescId).?.descSet);
        device.cmdBindDescriptorSets(
            cmdHandle,
            vulkan.PipelineBindPoint.graphics,
            self.vkPipeline.pipelineLayout,
            0,
            descSets.items,
            null,
        );

        device.cmdDraw(cmdHandle, 3, 1, 0, 0);

        device.cmdEndRendering(cmdHandle);

        self.renderFinish(vkCtx, cmdHandle);
    }

    fn renderFinish(
        self: *RenderLight,
        vkCtx: *const vk.ctx.VkCtx,
        cmdHandle: vulkan.CommandBuffer,
    ) void {
        const initBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.color_attachment_optimal,
            .new_layout = vulkan.ImageLayout.shader_read_only_optimal,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_stage_mask = .{ .fragment_shader_bit = true },
            .src_access_mask = .{ .color_attachment_write_bit = true },
            .dst_access_mask = .{ .shader_read_bit = true },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = vulkan.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
            },
            .image = @enumFromInt(@intFromPtr(self.outputAtt.vkImage.image)),
        }};
        const initDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = initBarriers.len,
            .p_image_memory_barriers = &initBarriers,
        };
        vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(cmdHandle, &initDepInfo);
    }

    fn renderInit(
        self: *RenderLight,
        vkCtx: *const vk.ctx.VkCtx,
        cmdHandle: vulkan.CommandBuffer,
    ) void {
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
            .image = @enumFromInt(@intFromPtr(self.outputAtt.vkImage.image)),
        }};
        const initDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = initBarriers.len,
            .p_image_memory_barriers = &initBarriers,
        };
        vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(cmdHandle, &initDepInfo);
    }

    pub fn resize(self: *RenderLight, vkCtx: *const vk.ctx.VkCtx, engCtx: *const eng.engine.EngCtx, inputAttachments: *const []eng.rend.Attachment) !void {
        const allocator = engCtx.allocator;
        self.outputAtt.cleanup(vkCtx);

        const outputAtt = try createColorAttachment(vkCtx);

        const imageViews = try allocator.alloc(vk.imv.VkImageView, inputAttachments.len);
        defer allocator.free(imageViews);
        for (0..inputAttachments.len) |i| {
            imageViews[i] = inputAttachments.ptr[i].vkImageView;
        }
        const vkDescSetTxt = vkCtx.vkDescAllocator.getDescSet(DESC_ID_LIGHT_TEXT_SAMPLER).?;
        try vkDescSetTxt.setImages(allocator, vkCtx.vkDevice, imageViews, self.textSampler, 0);

        self.outputAtt = outputAtt;
    }

    fn updateLights(
        self: *RenderLight,
        vkCtx: *const vk.ctx.VkCtx,
        scene: *const eng.scn.Scene,
        frameIdx: u8,
    ) !void {
        const buffData = try self.buffsLights[frameIdx].map(vkCtx);
        defer self.buffsLights[frameIdx].unMap(vkCtx);
        const gpuBytes: [*]u8 = @ptrCast(buffData);

        const numLights = scene.lights.items.len;
        var offset: usize = 0;
        for (0..numLights) |i| {
            const light = scene.lights.items[i];

            // Position
            const posBytes = std.mem.asBytes(&light.pos);
            @memcpy(gpuBytes[offset..][0..12], posBytes[0..12]);
            offset += 12;

            const directional: u32 = if (light.directional) 1 else 0;
            const dirBytes = std.mem.toBytes(directional);
            @memcpy(gpuBytes[offset..][0..4], &dirBytes);
            offset += 4;

            const intensityBytes = std.mem.toBytes(light.intensity);
            @memcpy(gpuBytes[offset..][0..4], &intensityBytes);
            offset += 4;

            const colorBytes = std.mem.asBytes(&light.color);
            @memcpy(gpuBytes[offset..][0..12], colorBytes[0..12]);
            offset += 12;
        }
    }

    fn updateSceneInfo(
        self: *RenderLight,
        vkCtx: *const vk.ctx.VkCtx,
        scene: *const eng.scn.Scene,
        frameIdx: u8,
    ) !void {
        const buffData = try self.buffsSceneInfo[frameIdx].map(vkCtx);
        defer self.buffsSceneInfo[frameIdx].unMap(vkCtx);
        const gpuBytes: [*]u8 = @ptrCast(buffData);

        var offset: usize = 0;
        const ambientLightBytes = std.mem.asBytes(&scene.ambientLight);
        @memcpy(gpuBytes[offset..], ambientLightBytes);
        offset += ambientLightBytes.len;

        const posBytes = std.mem.asBytes(&scene.camera.viewData.pos);
        @memcpy(gpuBytes[offset..][0..12], posBytes[0..12]);
        offset += 12;

        const numLights: u32 = @intCast(scene.lights.items.len);
        const numLightsBytes = std.mem.toBytes(numLights);
        @memcpy(gpuBytes[offset..], &numLightsBytes);
    }
};
