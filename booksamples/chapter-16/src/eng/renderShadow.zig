const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const zm = @import("zmath");

const LAMBDA: f32 = 0.95;
const SHADOW_MAP_CASCADE_COUNT: u32 = 3;
const UP = zm.f32x4(0.0, 1.0, 0.0, 0.0);
const UP_ALT = zm.f32x4(0.0, 0.0, 1.0, 0.0);

pub const CascadeData = struct {
    floatDistance: f32 = 0,
    projViewMatrix: zm.Mat = zm.identity(),
};

// Function are derived from Vulkan examples from Sascha Willems, and licensed under the MIT License:
// https://github.com/SaschaWillems/Vulkan/tree/master/examples/shadowmappingcascade, which are based on
// https://johanmedestrom.wordpress.com/2016/03/18/opengl-cascaded-shadow-maps/
// combined with this source: https://github.com/TheRealMJP/Shadows
pub fn updateCascadeShadows(cascadeShadows: *[SHADOW_MAP_CASCADE_COUNT]CascadeData, scene: *eng.scn.Scene) void {
    const viewData = scene.camera.viewData;
    const viewMatrix = viewData.viewMatrix;
    const projData = scene.camera.projData;
    const projMatrix = projData.projMatrix;

    var dirLightOpt: ?eng.scn.Light = null;
    for (scene.lights.items) |l| {
        if (l.directional) {
            dirLightOpt = l;
            break;
        }
    }
    if (dirLightOpt == null) {
        std.log.err("Could not find directional light", .{});
        return;
    }
    const dirLight = dirLightOpt.?;

    const lightPos = dirLight.pos;

    var cascadeSplits = [SHADOW_MAP_CASCADE_COUNT]f32{ 0, 0, 0 };

    const nearClip = projData.near;
    const farClip = projData.far;
    const clipRange = farClip - nearClip;

    const minZ = nearClip;
    const maxZ = nearClip + clipRange;

    const range = maxZ - minZ;
    const ratio = maxZ / minZ;

    const numCascades = cascadeShadows.len;

    // Calculate split depths based on view camera frustum
    // Based on method presented in https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch10.html
    for (0..numCascades) |i| {
        const p: f32 = @as(f32, @floatFromInt(i + 1)) /
            @as(f32, @floatFromInt(SHADOW_MAP_CASCADE_COUNT));

        const log = minZ * std.math.pow(f32, ratio, p);
        const uniform = minZ + range * p;
        const d = LAMBDA * (log - uniform) + uniform;

        cascadeSplits[i] = (d - nearClip) / clipRange;
    }

    // Calculate orthographic projection matrix for each cascade
    var lastSplitDist: f32 = 0.0;
    for (0..numCascades) |i| {
        const splitDist = cascadeSplits[i];

        var frustumCorners = [_]zm.Vec{
            zm.Vec{ -1.0, 0.0, 0.0, 1.0 },
            zm.Vec{ 1.0, 1.0, 0.0, 1.0 },
            zm.Vec{ 1.0, -1.0, 0.0, 1.0 },
            zm.Vec{ -1.0, -1.0, 0.0, 1.0 },
            zm.Vec{ -1.0, 1.0, 1.0, 1.0 },
            zm.Vec{ 1.0, 1.0, 1.0, 1.0 },
            zm.Vec{ 1.0, -1.0, 1.0, 1.0 },
            zm.Vec{ -1.0, -1.0, 1.0, 1.0 },
        };

        // Project frustum corners into world space
        const invCam: zm.Mat = zm.inverse(zm.mul(projMatrix, viewMatrix));
        for (0..8) |j| {
            const invCorner = zm.mul(frustumCorners[j], invCam);
            frustumCorners[j][0] = invCorner[0] / invCorner[3];
            frustumCorners[j][1] = invCorner[1] / invCorner[3];
            frustumCorners[j][2] = invCorner[2] / invCorner[3];
        }

        for (0..4) |j| {
            const dist = frustumCorners[j + 4] - frustumCorners[j];
            const split1: @Vector(4, f32) = @splat(splitDist);
            frustumCorners[j + 4] = frustumCorners[j] + dist * split1;
            const split2: @Vector(4, f32) = @splat(lastSplitDist);
            frustumCorners[j] = frustumCorners[j] + dist * split2;
        }

        // Get frustum center
        var frustumCenter = zm.Vec{ 0, 0, 0, 0 };
        for (frustumCorners) |c| {
            frustumCenter = frustumCenter + c;
        }
        frustumCenter = frustumCenter / @as(@Vector(4, f32), @splat(8.0));

        var up = UP;

        var sphereRadius: f32 = 0.0;
        for (frustumCorners) |c| {
            const diff = c - frustumCenter;
            const dist = zm.length3(diff)[0];
            sphereRadius = @max(sphereRadius, dist);
        }

        sphereRadius = std.math.ceil(sphereRadius * 16.0) / 16.0;

        const maxExtents = zm.f32x4(sphereRadius, sphereRadius, sphereRadius, 0);
        const minExtents = maxExtents * @as(@Vector(4, f32), @splat(-1.0));

        const lightDir = lightPos;

        const shadow_camera_pos = frustumCenter + lightDir * @as(@Vector(4, f32), @splat((minExtents[3])));

        const dot = @abs(zm.dot3(lightPos, up))[0];
        if (dot == 1.0) {
            up = UP_ALT;
        }

        const lightView = zm.lookAtRh(shadow_camera_pos, frustumCenter, up);

        var lightOrtho = zm.orthographicRh(
            minExtents[0],
            maxExtents[0],
            minExtents[1],
            maxExtents[1],
        );

        // Stabilize shadow
        // TODO: Configure this
        const shadowMapSize: f32 = 2024;

        var shadowOrigin = zm.f32x4(0, 0, 0, 1);
        shadowOrigin = zm.mul(lightView, shadowOrigin);
        shadowOrigin = shadowOrigin * @as(@Vector(4, f32), @splat(shadowMapSize / 2.0));

        const roundedOrigin = zm.round(shadowOrigin);
        var roundOffset = roundedOrigin - shadowOrigin;
        roundOffset = roundOffset * @as(@Vector(4, f32), @splat(2.0 / shadowMapSize));

        roundOffset = zm.f32x4(
            roundOffset[0],
            roundOffset[1],
            0,
            0,
        );

        var lastCol = lightOrtho[3];
        lastCol += @Vector(4, f32){ roundOffset[0], roundOffset[1], roundOffset[2], 0 };
        lightOrtho[3] = lastCol;

        const cascadeData = &cascadeShadows[i];
        cascadeData.floatDistance = (nearClip + splitDist * clipRange) * -1.0;

        cascadeData.projViewMatrix = zm.mul(lightOrtho, lightView);

        lastSplitDist = cascadeSplits[i];
    }
}

const PushConstantsVtx = struct {
    modelMatrix: zm.Mat,
    materialIdx: u32,
};

const COLOR_ATTACHMENT_FORMAT = vulkan.Format.r32g32_sfloat;
const DEPTH_FORMAT = vulkan.Format.d16_unorm;
const DESC_ID_MAT = "SHADOW_DESC_ID_MAT";
const DESC_ID_PRJ = "SHADOW_DESC_ID_PRJ";
const DESC_ID_TEXTS = "SHADOW_DESC_ID_TEXTS";

pub const RenderShadow = struct {
    attColor: eng.rend.Attachment,
    attDepth: eng.rend.Attachment,
    buffShadowCascades: vk.buf.VkBuffer,
    cascadeShadows: [SHADOW_MAP_CASCADE_COUNT]CascadeData,
    descLayoutFrgSt: vk.desc.VkDescSetLayout,
    descLayoutGeom: vk.desc.VkDescSetLayout,
    descLayoutTexture: vk.desc.VkDescSetLayout,
    textSampler: vk.text.VkTextSampler,
    vkPipeline: vk.pipe.VkPipeline,

    pub fn cleanup(self: *RenderShadow, vkCtx: *const vk.ctx.VkCtx) void {
        self.vkPipeline.cleanup(vkCtx);
        self.attColor.cleanup(vkCtx);
        self.attDepth.cleanup(vkCtx);
        self.textSampler.cleanup(vkCtx);
        self.descLayoutFrgSt.cleanup(vkCtx);
        self.descLayoutGeom.cleanup(vkCtx);
        self.descLayoutTexture.cleanup(vkCtx);
        self.buffShadowCascades.cleanup(vkCtx);
    }

    pub fn create(allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx) !RenderShadow {
        const attColor = try createColorAttachment(vkCtx);
        const attDepth = try createDepthAttachment(vkCtx);
        const cascadeShadows = [SHADOW_MAP_CASCADE_COUNT]CascadeData{ .{}, .{}, .{} };

        // Shader modules
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const vertCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/shadow_vtx.glsl.spv");
        const vert = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = vertCode.len,
            .p_code = @ptrCast(@alignCast(vertCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(vert, null);

        const geomCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/shadow_geom.glsl.spv");
        const geom = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = geomCode.len,
            .p_code = @ptrCast(@alignCast(geomCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(geom, null);

        const fragCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/shadow_frg.glsl.spv");
        const frag = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = fragCode.len,
            .p_code = @ptrCast(@alignCast(fragCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(frag, null);

        const modulesInfo = try allocator.alloc(vk.pipe.ShaderModuleInfo, 3);
        modulesInfo[0] = .{ .module = vert, .stage = .{ .vertex_bit = true } };
        modulesInfo[1] = .{ .module = geom, .stage = .{ .geometry_bit = true } };
        modulesInfo[2] = .{ .module = frag, .stage = .{ .fragment_bit = true } };
        defer allocator.free(modulesInfo);

        // Textures
        const samplerInfo = vk.text.VkTextSamplerInfo{
            .addressMode = vulkan.SamplerAddressMode.repeat,
            .anisotropy = true,
            .borderColor = vulkan.BorderColor.float_opaque_black,
        };
        const textSampler = try vk.text.VkTextSampler.create(vkCtx, samplerInfo);

        // Descriptor set layouts
        const descLayoutGeom = try vk.desc.VkDescSetLayout.create(
            allocator,
            vkCtx,
            &[_]vk.desc.LayoutInfo{.{
                .binding = 0,
                .descCount = 1,
                .descType = vulkan.DescriptorType.uniform_buffer,
                .stageFlags = vulkan.ShaderStageFlags{ .geometry_bit = true },
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
        const descSetLayouts = [_]vulkan.DescriptorSetLayout{ descLayoutGeom.descSetLayout, descLayoutFrgSt.descSetLayout, descLayoutTexture.descSetLayout };

        const buffShadowCascades = try vk.util.createHostVisibleBuff(
            allocator,
            vkCtx,
            DESC_ID_PRJ,
            vk.util.MATRIX_SIZE * SHADOW_MAP_CASCADE_COUNT,
            .{ .uniform_buffer_bit = true },
            descLayoutGeom,
        );

        // Push constants
        const pushConstants = [_]vulkan.PushConstantRange{
            .{
                .stage_flags = vulkan.ShaderStageFlags{ .vertex_bit = true },
                .offset = 0,
                .size = @sizeOf(PushConstantsVtx),
            },
        };

        // Pipeline
        const vkPipelineCreateInfo = vk.pipe.VkPipelineCreateInfo{
            .colorFormats = &[_]vulkan.Format{COLOR_ATTACHMENT_FORMAT},
            .depthFormat = DEPTH_FORMAT,
            .descSetLayouts = descSetLayouts[0..],
            .modulesInfo = modulesInfo,
            .pushConstants = pushConstants[0..],
            .useBlend = true,
            .vtxBuffDesc = .{
                .attribute_description = @constCast(&eng.rscn.VtxBuffDesc.attribute_description)[0..],
                .binding_description = eng.rscn.VtxBuffDesc.binding_description,
            },
        };

        const vkPipeline = try vk.pipe.VkPipeline.create(allocator, vkCtx, &vkPipelineCreateInfo);
        return .{
            .attColor = attColor,
            .attDepth = attDepth,
            .buffShadowCascades = buffShadowCascades,
            .cascadeShadows = cascadeShadows,
            .descLayoutFrgSt = descLayoutFrgSt,
            .descLayoutGeom = descLayoutGeom,
            .descLayoutTexture = descLayoutTexture,
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

        return try eng.rend.Attachment.create(
            vkCtx,
            extent.width,
            extent.height,
            COLOR_ATTACHMENT_FORMAT,
            flags,
        );
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

    pub fn init(
        self: *RenderShadow,
        allocator: std.mem.Allocator,
        vkCtx: *vk.ctx.VkCtx,
        textureCache: *eng.tcach.TextureCache,
        materialsCache: *eng.mcach.MaterialsCache,
    ) !void {
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
        self: *RenderShadow,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *eng.engine.EngCtx,
        vkCmd: vk.cmd.VkCmdBuff,
        modelsCache: *const eng.mcach.ModelsCache,
        materialsCache: *const eng.mcach.MaterialsCache,
    ) !void {
        const allocator = engCtx.allocator;
        const scene = &engCtx.scene;
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;

        self.renderInit(vkCtx, cmdHandle);
        updateCascadeShadows(&self.cascadeShadows, scene);

        const renderAttInfos = [_]vulkan.RenderingAttachmentInfo{.{
            .image_view = self.attColor.vkImageView.view,
            .image_layout = vulkan.ImageLayout.color_attachment_optimal,
            .load_op = vulkan.AttachmentLoadOp.clear,
            .store_op = vulkan.AttachmentStoreOp.store,
            .clear_value = vulkan.ClearValue{ .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
            .resolve_mode = vulkan.ResolveModeFlags{},
            .resolve_image_layout = vulkan.ImageLayout.attachment_optimal,
        }};

        const depthAttInfo = vulkan.RenderingAttachmentInfo{
            .image_view = self.attDepth.vkImageView.view,
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
            .p_color_attachments = &renderAttInfos,
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

        // Bind descriptor sets
        const vkDescAllocator = vkCtx.vkDescAllocator;
        var descSets = try std.ArrayList(vulkan.DescriptorSet).initCapacity(allocator, 3);
        defer descSets.deinit(allocator);
        try descSets.append(allocator, vkDescAllocator.getDescSet(DESC_ID_PRJ).?.descSet);
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
    }

    fn renderEntities(
        self: *RenderShadow,
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

    fn renderInit(self: *RenderShadow, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        const barriers = [_]vulkan.ImageMemoryBarrier2{ .{
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
            .image = @enumFromInt(@intFromPtr(self.attColor.vkImage.image)),
        }, .{
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
            .image = @enumFromInt(@intFromPtr(self.attDepth.vkImage.image)),
        } };
        const depInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = @as(u32, @intCast(barriers.len)),
            .p_image_memory_barriers = &barriers,
        };
        vkCtx.vkDevice.deviceProxy.cmdPipelineBarrier2(cmdHandle, &depInfo);
    }

    fn setPushConstants(self: *RenderShadow, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer, entity: *eng.ent.Entity, materialIdx: u32) void {
        const pushConstantsVtx = PushConstantsVtx{
            .modelMatrix = entity.modelMatrix,
            .materialIdx = materialIdx,
        };
        vkCtx.vkDevice.deviceProxy.cmdPushConstants(
            cmdHandle,
            self.vkPipeline.pipelineLayout,
            vulkan.ShaderStageFlags{ .vertex_bit = true },
            0,
            @sizeOf(PushConstantsVtx),
            &pushConstantsVtx,
        );
    }
};
