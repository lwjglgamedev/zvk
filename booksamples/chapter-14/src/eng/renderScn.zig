const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const zm = @import("zmath");

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

const PushConstantsVtx = struct {
    modelMatrix: zm.Mat,
};

const PushConstantsFrg = struct {
    materialIdx: u32,
};

const DEPTH_FORMAT = vulkan.Format.d16_unorm;
const DESC_ID_MAT = "SCN_DESC_ID_MAT";
const DESC_ID_CAM = "SCN_DESC_ID_CAM";
const DESC_ID_TEXTS = "SCN_DESC_ID_TEXTS";

const COLOR_ATTACHMENT_FORMAT = vulkan.Format.r16g16b16a16_sfloat;

pub const RenderScn = struct {
    attachments: []eng.rend.Attachment,
    buffsCamera: []vk.buf.VkBuffer,
    depthAttachment: eng.rend.Attachment,
    descLayoutFrgSt: vk.desc.VkDescSetLayout,
    descLayoutVtx: vk.desc.VkDescSetLayout,
    descLayoutTexture: vk.desc.VkDescSetLayout,
    textSampler: vk.text.VkTextSampler,
    vkPipeline: vk.pipe.VkPipeline,

    pub fn cleanup(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        self.vkPipeline.cleanup(vkCtx);
        for (self.attachments) |*attachment| {
            attachment.cleanup(vkCtx);
        }
        allocator.free(self.attachments);

        self.depthAttachment.cleanup(vkCtx);

        self.textSampler.cleanup(vkCtx);
        self.descLayoutFrgSt.cleanup(vkCtx);
        self.descLayoutVtx.cleanup(vkCtx);
        self.descLayoutTexture.cleanup(vkCtx);
        for (self.buffsCamera) |*buffer| {
            buffer.cleanup(vkCtx);
        }
        allocator.free(self.buffsCamera);
    }

    pub fn create(allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx) !RenderScn {
        const attachments = try createColorAttachment(allocator, vkCtx);
        const depthAttachment = try createDepthAttachment(vkCtx);

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
            .anisotropy = true,
            .borderColor = vulkan.BorderColor.float_opaque_black,
        };
        const textSampler = try vk.text.VkTextSampler.create(vkCtx, samplerInfo);

        // Descriptor set layouts
        const descLayoutVtx = try vk.desc.VkDescSetLayout.create(
            allocator,
            vkCtx,
            &[_]vk.desc.LayoutInfo{.{
                .binding = 0,
                .descCount = 1,
                .descType = vulkan.DescriptorType.uniform_buffer,
                .stageFlags = vulkan.ShaderStageFlags{ .vertex_bit = true },
            }},
        );
        const descLayoutFrgSt = try vk.desc.VkDescSetLayout.create(
            allocator,
            vkCtx,
            &[_]vk.desc.LayoutInfo{.{
                .binding = 0,
                .descCount = 1,
                .descType = vulkan.DescriptorType.storage_buffer,
                .stageFlags = vulkan.ShaderStageFlags{ .fragment_bit = true },
            }},
        );
        const descLayoutTexture = try vk.desc.VkDescSetLayout.create(
            allocator,
            vkCtx,
            &[_]vk.desc.LayoutInfo{.{
                .binding = 0,
                .descCount = eng.tcach.MAX_TEXTURES,
                .descType = vulkan.DescriptorType.combined_image_sampler,
                .stageFlags = vulkan.ShaderStageFlags{ .fragment_bit = true },
            }},
        );
        const descSetLayouts = [_]vulkan.DescriptorSetLayout{ descLayoutVtx.descSetLayout, descLayoutFrgSt.descSetLayout, descLayoutTexture.descSetLayout };

        const buffsCamera = try createCamBuffers(allocator, vkCtx, descLayoutVtx);

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

        // Pipeline
        const colorFormats = try allocator.alloc(vulkan.Format, attachments.len);
        defer allocator.free(colorFormats);
        for (0..colorFormats.len) |i| {
            colorFormats[i] = attachments[i].vkImageView.format;
        }
        const vkPipelineCreateInfo = vk.pipe.VkPipelineCreateInfo{
            .colorFormats = colorFormats,
            .depthFormat = DEPTH_FORMAT,
            .descSetLayouts = descSetLayouts[0..],
            .modulesInfo = modulesInfo,
            .pushConstants = pushConstants[0..],
            .useBlend = true,
            .vtxBuffDesc = .{
                .attribute_description = @constCast(&VtxBuffDesc.attribute_description)[0..],
                .binding_description = VtxBuffDesc.binding_description,
            },
        };
        const vkPipeline = try vk.pipe.VkPipeline.create(allocator, vkCtx, &vkPipelineCreateInfo);

        return .{
            .attachments = attachments,
            .buffsCamera = buffsCamera,
            .depthAttachment = depthAttachment,
            .descLayoutFrgSt = descLayoutFrgSt,
            .descLayoutVtx = descLayoutVtx,
            .descLayoutTexture = descLayoutTexture,
            .textSampler = textSampler,
            .vkPipeline = vkPipeline,
        };
    }

    fn createColorAttachment(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) ![]eng.rend.Attachment {
        const extent = vkCtx.vkSwapChain.extent;
        const flags = vulkan.ImageUsageFlags{
            .color_attachment_bit = true,
            .sampled_bit = true,
        };

        const numAttachments = 1;
        const attachments = try allocator.alloc(eng.rend.Attachment, numAttachments);
        errdefer allocator.free(attachments);

        for (0..numAttachments) |i| {
            const attachment = try eng.rend.Attachment.create(
                vkCtx,
                extent.width,
                extent.height,
                COLOR_ATTACHMENT_FORMAT,
                flags,
            );
            attachments[i] = attachment;
        }
        return attachments;
    }

    fn createCamBuffers(allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx, descLayout: vk.desc.VkDescSetLayout) ![]vk.buf.VkBuffer {
        const buffers = try allocator.alloc(vk.buf.VkBuffer, com.common.FRAMES_IN_FLIGHT);
        for (buffers, 0..) |*buffer, i| {
            const id = try std.fmt.allocPrint(allocator, "{s}{d}", .{ DESC_ID_CAM, i });
            defer allocator.free(id);
            buffer.* = try vk.util.createHostVisibleBuff(
                allocator,
                vkCtx,
                id,
                vk.util.MATRIX_SIZE * 2,
                .{ .uniform_buffer_bit = true },
                descLayout,
            );
        }
        return buffers;
    }

    fn createDepthAttachment(vkCtx: *const vk.ctx.VkCtx) !eng.rend.Attachment {
        const extent = vkCtx.vkSwapChain.extent;
        const flags = vulkan.ImageUsageFlags{
            .depth_stencil_attachment_bit = true,
        };
        return try eng.rend.Attachment.create(
            vkCtx,
            extent.width,
            extent.height,
            DEPTH_FORMAT,
            flags,
        );
    }

    pub fn init(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx, textureCache: *eng.tcach.TextureCache, materialsCache: *eng.mcach.MaterialsCache) !void {
        const imageViews = try allocator.alloc(vk.imv.VkImageView, textureCache.textureMap.count());
        defer allocator.free(imageViews);

        const descSet = try vkCtx.vkDescAllocator.addDescSet(
            allocator,
            vkCtx.vkPhysDevice,
            vkCtx.vkDevice,
            DESC_ID_TEXTS,
            self.descLayoutTexture,
        );
        var iter = textureCache.textureMap.iterator();
        var i: u32 = 0;
        while (iter.next()) |entry| {
            imageViews[i] = entry.value_ptr.vkImageView;
            i += 1;
        }
        try descSet.setImageArr(allocator, vkCtx.vkDevice, imageViews, self.textSampler, 0);

        const matDescSet = try vkCtx.vkDescAllocator.addDescSet(
            allocator,
            vkCtx.vkPhysDevice,
            vkCtx.vkDevice,
            DESC_ID_MAT,
            self.descLayoutFrgSt,
        );
        const layoutInfo = self.descLayoutFrgSt.layoutInfos[0];
        matDescSet.setBuffer(vkCtx.vkDevice, materialsCache.materialsBuffer.?, layoutInfo.binding, layoutInfo.descType);
    }

    pub fn render(
        self: *RenderScn,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        vkCmd: vk.cmd.VkCmdBuff,
        modelsCache: *const eng.mcach.ModelsCache,
        materialsCache: *const eng.mcach.MaterialsCache,
        frameIdx: u8,
    ) !void {
        const allocator = engCtx.allocator;
        const scene = &engCtx.scene;
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;

        try self.renderInit(allocator, vkCtx, cmdHandle);

        const renderAttInfos = try allocator.alloc(vulkan.RenderingAttachmentInfo, self.attachments.len);
        defer allocator.free(renderAttInfos);
        for (0..self.attachments.len) |i| {
            const renderAttInfo = vulkan.RenderingAttachmentInfo{
                .image_view = self.attachments[i].vkImageView.view,
                .image_layout = vulkan.ImageLayout.color_attachment_optimal,
                .load_op = vulkan.AttachmentLoadOp.clear,
                .store_op = vulkan.AttachmentStoreOp.store,
                .clear_value = vulkan.ClearValue{ .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
                .resolve_mode = vulkan.ResolveModeFlags{},
                .resolve_image_layout = vulkan.ImageLayout.attachment_optimal,
            };
            renderAttInfos[i] = renderAttInfo;
        }

        const depthAttInfo = vulkan.RenderingAttachmentInfo{
            .image_view = self.depthAttachment.vkImageView.view,
            .image_layout = vulkan.ImageLayout.depth_stencil_attachment_optimal,
            .load_op = vulkan.AttachmentLoadOp.clear,
            .store_op = vulkan.AttachmentStoreOp.dont_care,
            .clear_value = vulkan.ClearValue{ .depth_stencil = .{ .depth = 1.0, .stencil = 0.0 } },
            .resolve_mode = vulkan.ResolveModeFlags{},
            .resolve_image_layout = vulkan.ImageLayout.undefined,
        };

        const extent = vkCtx.vkSwapChain.extent;
        const renderInfo = vulkan.RenderingInfo{
            .render_area = .{ .extent = extent, .offset = .{ .x = 0, .y = 0 } },
            .layer_count = 1,
            .color_attachment_count = @as(u32, @intCast(renderAttInfos.len)),
            .p_color_attachments = renderAttInfos.ptr,
            .p_depth_attachment = &depthAttInfo,
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
        device.cmdSetViewport(cmdHandle, 0, viewPort.len, &viewPort);
        const scissor = [_]vulkan.Rect2D{.{
            .offset = vulkan.Offset2D{ .x = 0, .y = 0 },
            .extent = vulkan.Extent2D{ .width = extent.width, .height = extent.height },
        }};
        device.cmdSetScissor(cmdHandle, 0, scissor.len, &scissor);

        try self.updateCamera(vkCtx, frameIdx, &scene.camera.projData.projMatrix, &scene.camera.viewData.viewMatrix);

        // Bind descriptor sets
        const vkDescAllocator = vkCtx.vkDescAllocator;
        var descSets = try std.ArrayList(vulkan.DescriptorSet).initCapacity(allocator, 3);
        defer descSets.deinit(allocator);
        const camDescIdc = try std.fmt.allocPrint(allocator, "{s}{d}", .{ DESC_ID_CAM, frameIdx });
        defer allocator.free(camDescIdc);
        try descSets.append(allocator, vkDescAllocator.getDescSet(camDescIdc).?.descSet);
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

        self.renderEntities(vkCtx, engCtx, modelsCache, materialsCache, cmdHandle, false);
        self.renderEntities(vkCtx, engCtx, modelsCache, materialsCache, cmdHandle, true);

        device.cmdEndRendering(cmdHandle);

        try self.renderFinish(allocator, vkCtx, cmdHandle);
    }

    fn renderEntities(
        self: *RenderScn,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
        materialsCache: *const eng.mcach.MaterialsCache,
        cmdHandle: vulkan.CommandBuffer,
        transparent: bool,
    ) void {
        const device = vkCtx.vkDevice.deviceProxy;
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
                        const material = materialsCache.materialsMap.get(mesh.materialId).?;
                        if (material.transparent != transparent) {
                            continue;
                        }
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
    }

    fn renderFinish(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) !void {
        const barriers = try allocator.alloc(vulkan.ImageMemoryBarrier2, self.attachments.len);
        defer allocator.free(barriers);
        for (0..self.attachments.len) |i| {
            const barrier =
                vulkan.ImageMemoryBarrier2{
                    .old_layout = vulkan.ImageLayout.color_attachment_optimal,
                    .new_layout = vulkan.ImageLayout.read_only_optimal,
                    .src_stage_mask = .{ .color_attachment_output_bit = true },
                    .dst_stage_mask = .{ .fragment_shader_bit = true },
                    .src_access_mask = .{ .color_attachment_write_bit = true },
                    .dst_access_mask = .{ .color_attachment_read_bit = true },
                    .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
                    .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
                    .subresource_range = .{
                        .aspect_mask = .{ .color_bit = true },
                        .base_mip_level = 0,
                        .level_count = vulkan.REMAINING_MIP_LEVELS,
                        .base_array_layer = 0,
                        .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
                    },
                    .image = @enumFromInt(@intFromPtr(self.attachments[i].vkImage.image)),
                };
            barriers[i] = barrier;
        }
        const depInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = @as(u32, @intCast(barriers.len)),
            .p_image_memory_barriers = barriers.ptr,
        };
        vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(cmdHandle, &depInfo);
    }

    fn renderInit(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) !void {
        const barriers = try allocator.alloc(vulkan.ImageMemoryBarrier2, self.attachments.len + 1);
        defer allocator.free(barriers);
        for (0..barriers.len - 1) |i| {
            const barrier = vulkan.ImageMemoryBarrier2{
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
                .image = @enumFromInt(@intFromPtr(self.attachments[i].vkImage.image)),
            };
            barriers[i] = barrier;
        }
        const depthImage: vulkan.Image = @enumFromInt(@intFromPtr(self.depthAttachment.vkImage.image));
        barriers[barriers.len - 1] = vulkan.ImageMemoryBarrier2{
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
            .image = depthImage,
        };
        const depInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = @as(u32, @intCast(barriers.len)),
            .p_image_memory_barriers = barriers.ptr,
        };
        vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(cmdHandle, &depInfo);
    }

    pub fn resize(self: *RenderScn, vkCtx: *const vk.ctx.VkCtx, engCtx: *const eng.engine.EngCtx) !void {
        const allocator = engCtx.allocator;

        for (self.attachments) |*attachment| {
            attachment.cleanup(vkCtx);
        }
        allocator.free(self.attachments);

        self.depthAttachment.cleanup(vkCtx);

        const attachments = try createColorAttachment(allocator, vkCtx);
        const depthAttachment = try createDepthAttachment(vkCtx);

        self.attachments = attachments;
        self.depthAttachment = depthAttachment;
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

    fn updateCamera(
        self: *RenderScn,
        vkCtx: *const vk.ctx.VkCtx,
        frameIdx: u8,
        projMatrix: *const zm.Mat,
        viewMatrix: *const zm.Mat,
    ) !void {
        const buffData = try self.buffsCamera[frameIdx].map(vkCtx);
        defer self.buffsCamera[frameIdx].unMap(vkCtx);
        const gpuBytes: [*]u8 = @ptrCast(buffData);

        const projMatrixBytes = std.mem.asBytes(projMatrix);
        const projMatrixPtr: [*]align(16) const u8 = projMatrixBytes.ptr;

        const viewMatrixBytes = std.mem.asBytes(viewMatrix);
        const viewMatrixPtr: [*]align(16) const u8 = viewMatrixBytes.ptr;

        @memcpy(gpuBytes[0..@sizeOf(zm.Mat)], projMatrixPtr[0..@sizeOf(zm.Mat)]);
        @memcpy(gpuBytes[@sizeOf(zm.Mat) .. @sizeOf(zm.Mat) * 2], viewMatrixPtr[0..@sizeOf(zm.Mat)]);
    }
};
