const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const zm = @import("zmath");

const PushConstantsVtx = struct {
    modelMatrix: zm.Mat,
};

const PushConstantsFrg = struct {
    materialIdx: u32,
};

const VtxBuffDesc = struct {
    const binding_description = vulkan.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(VtxBuffDesc),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vulkan.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(VtxBuffDesc, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(VtxBuffDesc, "textCoords"),
        },
    };

    pos: [3]f32,
    textCoords: [2]f32,
};

const DEPTH_FORMAT = vulkan.Format.d16_unorm;
const DESC_ID_MAT = "SCN_DESC_ID_MAT";
const DESC_ID_PROJ = "SCN_DESC_ID_PROJ";
const DESC_ID_TEXTS = "SCN_DESC_ID_TEXTS";

pub const RenderScn = struct {
    buffProjMatrix: vk.buf.VkBuffer,
    depthAttachments: []eng.rend.Attachment,
    depthAttachmentInfos: []vulkan.RenderingAttachmentInfo,
    descLayoutFrgSt: vk.desc.VkDescSetLayout,
    descLayoutVtx: vk.desc.VkDescSetLayout,
    descLayoutTexture: vk.desc.VkDescSetLayout,
    renderAttachmentInfos: []vulkan.RenderingAttachmentInfo,
    renderInfos: []vulkan.RenderingInfo,
    textSampler: vk.text.VkTextSampler,
    vkPipeline: vk.pipe.VkPipeline,

    pub fn cleanup(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        self.vkPipeline.cleanup(vkCtx);
        allocator.free(self.renderInfos);
        allocator.free(self.renderAttachmentInfos);
        allocator.free(self.depthAttachmentInfos);
        for (self.depthAttachments) |depthAttachment| {
            depthAttachment.cleanup(vkCtx);
        }
        allocator.free(self.depthAttachments);

        self.textSampler.cleanup(vkCtx);
        self.descLayoutFrgSt.cleanup(vkCtx);
        self.descLayoutVtx.cleanup(vkCtx);
        self.descLayoutTexture.cleanup(vkCtx);
        self.buffProjMatrix.cleanup(vkCtx);
    }

    pub fn create(allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx) !RenderScn {
        const depthAttachments = try createDepthAttachments(allocator, vkCtx);
        const renderAttachmentInfos = try createRenderingAttachmentInfo(allocator, vkCtx);
        const depthAttachmentInfos = try createDepthAttachmentInfo(allocator, vkCtx, depthAttachments);
        const renderInfos = try createRenderInfos(allocator, vkCtx, renderAttachmentInfos, depthAttachmentInfos);

        // Shader modules
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const vertCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/scn_vtx.glsl.spv");
        const vert = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = vertCode.len,
            .p_code = @ptrCast(@alignCast(vertCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(vert, null);

        const fragCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/scn_frg.glsl.spv");
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
            .borderColor = vulkan.BorderColor.float_opaque_black,
        };
        const textSampler = try vk.text.VkTextSampler.create(vkCtx, samplerInfo);

        // Descriptor set layouts
        const descLayoutVtx = try vk.desc.VkDescSetLayout.create(
            vkCtx,
            0,
            vulkan.DescriptorType.uniform_buffer,
            vulkan.ShaderStageFlags{ .vertex_bit = true },
            1,
        );
        const descLayoutFrgSt = try vk.desc.VkDescSetLayout.create(
            vkCtx,
            0,
            vulkan.DescriptorType.storage_buffer,
            vulkan.ShaderStageFlags{ .fragment_bit = true },
            1,
        );
        const descLayoutTexture = try vk.desc.VkDescSetLayout.create(
            vkCtx,
            0,
            vulkan.DescriptorType.combined_image_sampler,
            vulkan.ShaderStageFlags{ .fragment_bit = true },
            eng.tcach.MAX_TEXTURES,
        );
        const descSetLayouts = [_]vulkan.DescriptorSetLayout{ descLayoutVtx.descSetLayout, descLayoutFrgSt.descSetLayout, descLayoutTexture.descSetLayout };

        const buffProjMatrix = try vk.util.createHostVisibleBuff(
            allocator,
            vkCtx,
            DESC_ID_PROJ,
            vk.util.MATRIX_SIZE,
            .{ .uniform_buffer_bit = true },
            descLayoutVtx,
        );

        // Push constants
        const pushConstants = [_]vulkan.PushConstantRange{
            .{
                .stage_flags = vulkan.ShaderStageFlags{ .vertex_bit = true },
                .offset = 0,
                .size = @sizeOf(PushConstantsVtx),
            },
            .{
                .stage_flags = vulkan.ShaderStageFlags{ .fragment_bit = true },
                .offset = @sizeOf(PushConstantsVtx),
                .size = @sizeOf(PushConstantsFrg),
            },
        };

        // Pipeline layout
        const pipelineLayout = try vkCtx.vkDevice.deviceProxy.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = descSetLayouts.len,
            .p_set_layouts = &descSetLayouts,
            .push_constant_range_count = pushConstants.len,
            .p_push_constant_ranges = &pushConstants,
        }, null);

        // Pipeline
        const vkPipelineCreateInfo = vk.pipe.VkPipelineCreateInfo{
            .colorFormat = vkCtx.vkSwapChain.surfaceFormat.format,
            .depthFormat = DEPTH_FORMAT,
            .modulesInfo = modulesInfo,
            .pipelineLayout = pipelineLayout,
            .useBlend = false,
            .vtxBuffDesc = .{
                .attribute_description = @constCast(&VtxBuffDesc.attribute_description)[0..],
                .binding_description = VtxBuffDesc.binding_description,
            },
        };
        const vkPipeline = try vk.pipe.VkPipeline.create(allocator, vkCtx, &vkPipelineCreateInfo);

        return .{
            .buffProjMatrix = buffProjMatrix,
            .depthAttachments = depthAttachments,
            .depthAttachmentInfos = depthAttachmentInfos,
            .descLayoutFrgSt = descLayoutFrgSt,
            .descLayoutVtx = descLayoutVtx,
            .descLayoutTexture = descLayoutTexture,
            .renderAttachmentInfos = renderAttachmentInfos,
            .renderInfos = renderInfos,
            .textSampler = textSampler,
            .vkPipeline = vkPipeline,
        };
    }

    fn createDepthAttachments(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) ![]eng.rend.Attachment {
        const numImages = vkCtx.vkSwapChain.imageViews.len;
        const extent = vkCtx.vkSwapChain.extent;
        const depthAttachments = try allocator.alloc(eng.rend.Attachment, numImages);
        const flags = vulkan.ImageUsageFlags{
            .depth_stencil_attachment_bit = true,
        };
        for (depthAttachments) |*attachment| {
            attachment.* = try eng.rend.Attachment.create(
                vkCtx,
                extent.width,
                extent.height,
                DEPTH_FORMAT,
                flags,
            );
        }
        return depthAttachments;
    }

    fn createDepthAttachmentInfo(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, attachments: []eng.rend.Attachment) ![]vulkan.RenderingAttachmentInfo {
        const numImages = vkCtx.vkSwapChain.imageViews.len;
        const renderAttachmentInfos = try allocator.alloc(vulkan.RenderingAttachmentInfo, numImages);
        for (renderAttachmentInfos, 0..) |*attachmentInfo, i| {
            attachmentInfo.* = vulkan.RenderingAttachmentInfo{
                .image_view = attachments[i].vkImageView.view,
                .image_layout = vulkan.ImageLayout.depth_stencil_attachment_optimal,
                .load_op = vulkan.AttachmentLoadOp.clear,
                .store_op = vulkan.AttachmentStoreOp.dont_care,
                .clear_value = vulkan.ClearValue{ .depth_stencil = .{ .depth = 1.0, .stencil = 0.0 } },
                .resolve_mode = vulkan.ResolveModeFlags{},
                .resolve_image_layout = vulkan.ImageLayout.undefined,
            };
        }
        return renderAttachmentInfos;
    }

    fn createRenderingAttachmentInfo(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) ![]vulkan.RenderingAttachmentInfo {
        const numImages = vkCtx.vkSwapChain.imageViews.len;
        const renderAttachmentInfos = try allocator.alloc(vulkan.RenderingAttachmentInfo, numImages);
        for (renderAttachmentInfos, 0..) |*attachmentInfo, i| {
            attachmentInfo.* = vulkan.RenderingAttachmentInfo{
                .image_view = vkCtx.vkSwapChain.imageViews[i].view,
                .image_layout = vulkan.ImageLayout.attachment_optimal_khr,
                .load_op = vulkan.AttachmentLoadOp.clear,
                .store_op = vulkan.AttachmentStoreOp.store,
                .clear_value = vulkan.ClearValue{ .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
                .resolve_mode = vulkan.ResolveModeFlags{},
                .resolve_image_layout = vulkan.ImageLayout.attachment_optimal_khr,
            };
        }
        return renderAttachmentInfos;
    }

    fn createRenderInfos(
        allocator: std.mem.Allocator,
        vkCtx: *const vk.ctx.VkCtx,
        renderAttachmentInfos: []vulkan.RenderingAttachmentInfo,
        depthAttachmentInfos: []vulkan.RenderingAttachmentInfo,
    ) ![]vulkan.RenderingInfo {
        const numImages = vkCtx.vkSwapChain.imageViews.len;
        const extent = vkCtx.vkSwapChain.extent;
        const renderInfos = try allocator.alloc(vulkan.RenderingInfo, numImages);
        for (renderInfos, 0..) |*renderInfo, i| {
            renderInfo.* = vulkan.RenderingInfo{
                .render_area = .{ .extent = extent, .offset = .{ .x = 0, .y = 0 } },
                .layer_count = 1,
                .color_attachment_count = 1,
                .p_color_attachments = @ptrCast(&renderAttachmentInfos[i]),
                .p_depth_attachment = &depthAttachmentInfos[i],
                .view_mask = 0,
            };
        }
        return renderInfos;
    }

    pub fn init(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx, textureCache: *eng.tcach.TextureCache, materialsCache: *eng.mcach.MaterialsCache) !void {
        const imageViews = try allocator.alloc(vk.imv.VkImageView, textureCache.textureMap.count());
        defer allocator.free(imageViews);

        const descSet = try vkCtx.vkDescAllocator.addDescSet(allocator, vkCtx.vkDevice, DESC_ID_TEXTS, self.descLayoutTexture);
        var iter = textureCache.textureMap.iterator();
        var i: u32 = 0;
        while (iter.next()) |entry| {
            imageViews[i] = entry.value_ptr.vkImageView;
            i += 1;
        }
        try descSet.setImageArr(allocator, vkCtx.vkDevice, imageViews, self.textSampler, 0);

        const matDescSet = try vkCtx.vkDescAllocator.addDescSet(allocator, vkCtx.vkDevice, DESC_ID_MAT, self.descLayoutFrgSt);
        matDescSet.setBuffer(vkCtx.vkDevice, materialsCache.materialsBuffer.?, self.descLayoutFrgSt.binding, self.descLayoutFrgSt.descType);
    }

    pub fn render(
        self: *RenderScn,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        vkCmd: vk.cmd.VkCmdBuff,
        modelsCache: *const eng.mcach.ModelsCache,
        materialsCache: *const eng.mcach.MaterialsCache,
        imageIndex: u32,
    ) !void {
        const allocator = engCtx.allocator;
        const scene = &engCtx.scene;
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;
        const renderInfo = self.renderInfos[imageIndex];

        const initBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.undefined,
            .new_layout = vulkan.ImageLayout.depth_attachment_optimal,
            .src_stage_mask = .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
            .dst_stage_mask = .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
            .src_access_mask = .{
                .depth_stencil_attachment_write_bit = true,
            },
            .dst_access_mask = .{
                .depth_stencil_attachment_read_bit = true,
                .depth_stencil_attachment_write_bit = true,
            },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .depth_bit = true },
                .base_mip_level = 0,
                .level_count = vulkan.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
            },
            .image = self.depthAttachments[imageIndex].vkImage.image,
        }};
        const initDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = initBarriers.len,
            .p_image_memory_barriers = &initBarriers,
        };
        vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(cmdHandle, &initDepInfo);

        device.cmdBeginRendering(cmdHandle, @ptrCast(&renderInfo));

        device.cmdBindPipeline(cmdHandle, vulkan.PipelineBindPoint.graphics, self.vkPipeline.pipeline);

        const extent = vkCtx.vkSwapChain.extent;
        const viewPort = [_]vulkan.Viewport{.{
            .x = 0,
            .y = @as(f32, @floatFromInt(extent.height)),
            .width = @as(f32, @floatFromInt(extent.width)),
            .height = -1.0 * @as(f32, @floatFromInt(extent.height)),
            .min_depth = 0,
            .max_depth = 1,
        }};
        device.cmdSetViewport(cmdHandle, 0, viewPort.len, &viewPort);
        const scissor = [_]vulkan.Rect2D{.{
            .offset = vulkan.Offset2D{ .x = 0, .y = 0 },
            .extent = vulkan.Extent2D{ .width = extent.width, .height = extent.height },
        }};
        device.cmdSetScissor(cmdHandle, 0, scissor.len, &scissor);

        // Copy matrices
        try self.updateProjView(vkCtx, &scene.camera.projData.projMatrix);

        // Bind descriptor sets
        const vkDescAllocator = vkCtx.vkDescAllocator;
        var descSets = try std.ArrayList(vulkan.DescriptorSet).initCapacity(allocator, 3);
        defer descSets.deinit(allocator);
        try descSets.append(allocator, vkDescAllocator.getDescSet(DESC_ID_PROJ).?.descSet);
        try descSets.append(allocator, vkDescAllocator.getDescSet(DESC_ID_MAT).?.descSet);
        try descSets.append(allocator, vkDescAllocator.getDescSet(DESC_ID_TEXTS).?.descSet);

        device.cmdBindDescriptorSets(
            cmdHandle,
            vulkan.PipelineBindPoint.graphics,
            self.vkPipeline.pipelineLayout,
            0,
            @as(u32, @intCast(descSets.items.len)),
            descSets.items.ptr,
            0,
            null,
        );

        const offset = [_]vulkan.DeviceSize{0};

        var iter = engCtx.scene.entitiesMap.valueIterator();

        while (iter.next()) |entityRef| {
            const entity = entityRef.*;
            const vulkanModel = modelsCache.modelsMap.get(entity.modelId);
            if (vulkanModel) |*vm| {
                for (vm.meshes.items) |mesh| {
                    var materialIdx: u32 = 0;
                    if (materialsCache.materialsMap.getIndex(mesh.materialId)) |idx| {
                        materialIdx = @as(u32, @intCast(idx));
                    }
                    self.setPushConstants(vkCtx, cmdHandle, entity, materialIdx);
                    device.cmdBindIndexBuffer(cmdHandle, mesh.buffIdx.buffer, 0, vulkan.IndexType.uint32);
                    device.cmdBindVertexBuffers(cmdHandle, 0, 1, @ptrCast(&mesh.buffVtx.buffer), &offset);
                    device.cmdDrawIndexed(cmdHandle, @as(u32, @intCast(mesh.numIndices)), 1, 0, 0, 0);
                }
            } else {
                std.log.warn("Could not find model {s}", .{entity.modelId});
            }
        }

        device.cmdEndRendering(cmdHandle);
    }

    fn setPushConstants(self: *RenderScn, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer, entity: *eng.ent.Entity, materialIdx: u32) void {
        const pushConstantsVtx = PushConstantsVtx{
            .modelMatrix = entity.modelMatrix,
        };
        vkCtx.vkDevice.deviceProxy.cmdPushConstants(
            cmdHandle,
            self.vkPipeline.pipelineLayout,
            vulkan.ShaderStageFlags{ .vertex_bit = true },
            0,
            @sizeOf(PushConstantsVtx),
            &pushConstantsVtx,
        );
        const pushConstantsFrg = PushConstantsFrg{
            .materialIdx = materialIdx,
        };
        vkCtx.vkDevice.deviceProxy.cmdPushConstants(
            cmdHandle,
            self.vkPipeline.pipelineLayout,
            vulkan.ShaderStageFlags{ .fragment_bit = true },
            @sizeOf(PushConstantsVtx),
            @sizeOf(PushConstantsFrg),
            &pushConstantsFrg,
        );
    }

    fn updateProjView(self: *RenderScn, vkCtx: *const vk.ctx.VkCtx, projMatrix: *const zm.Mat) !void {
        const buffData = try self.buffProjMatrix.map(vkCtx);
        defer self.buffProjMatrix.unMap(vkCtx);
        const gpuBytes: [*]u8 = @ptrCast(buffData);

        const projMatrixBytes = std.mem.asBytes(projMatrix);
        const projMatrixPtr: [*]align(16) const u8 = projMatrixBytes.ptr;

        @memcpy(gpuBytes[0..@sizeOf(zm.Mat)], projMatrixPtr[0..@sizeOf(zm.Mat)]);
    }
};
