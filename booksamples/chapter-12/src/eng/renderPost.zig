const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const zm = @import("zmath");

const PushConstants = struct {
    screenWidth: f32 = 0.0,
    screenHeight: f32 = 0.0,
};

const EmptyVtxBuffDesc = struct {
    const binding_description = vulkan.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(EmptyVtxBuffDesc),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vulkan.VertexInputAttributeDescription{};
};

const DESC_ID_POST_TEXT_SAMPLER = "RENDER_POST_DESC_ID_TEXT";

pub const RenderPost = struct {
    vkPipeline: vk.pipe.VkPipeline,
    descLayoutFrg: vk.desc.VkDescSetLayout,
    textSampler: vk.text.VkTextSampler,

    pub fn create(
        allocator: std.mem.Allocator,
        vkCtx: *vk.ctx.VkCtx,
        constants: com.common.Constants,
        attColor: *const eng.rend.Attachment,
    ) !RenderPost {
        // Textures
        const samplerInfo = vk.text.VkTextSamplerInfo{
            .addressMode = vulkan.SamplerAddressMode.repeat,
            .anisotropy = false,
            .borderColor = vulkan.BorderColor.float_opaque_black,
        };
        const textSampler = try vk.text.VkTextSampler.create(vkCtx, samplerInfo);

        // Descriptor sets
        const descLayoutFrg = try vk.desc.VkDescSetLayout.create(
            vkCtx,
            0,
            vulkan.DescriptorType.combined_image_sampler,
            vulkan.ShaderStageFlags{ .fragment_bit = true },
            1,
        );
        const descSetLayouts = [_]vulkan.DescriptorSetLayout{descLayoutFrg.descSetLayout};
        const vkDescSetTxt = try vkCtx.vkDescAllocator.addDescSet(
            allocator,
            vkCtx.vkPhysDevice,
            vkCtx.vkDevice,
            DESC_ID_POST_TEXT_SAMPLER,
            descLayoutFrg,
        );
        vkDescSetTxt.setImage(vkCtx.vkDevice, attColor.vkImageView, textSampler, 0);

        // Push constants
        const pushConstants = [_]vulkan.PushConstantRange{.{
            .stage_flags = vulkan.ShaderStageFlags{ .fragment_bit = true },
            .offset = 0,
            .size = @sizeOf(PushConstants),
        }};

        // Shader modules
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const fxaa: u32 = if (constants.fxaa) 1 else 0;
        const specConstants = try createSpecConsts(arena.allocator(), &fxaa);

        const vertCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/post_vtx.glsl.spv");
        const vert = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = vertCode.len,
            .p_code = @ptrCast(@alignCast(vertCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(vert, null);

        const fragCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/post_frg.glsl.spv");
        const frag = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = fragCode.len,
            .p_code = @ptrCast(@alignCast(fragCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(frag, null);

        const modulesInfo = try allocator.alloc(vk.pipe.ShaderModuleInfo, 2);
        modulesInfo[0] = .{ .module = vert, .stage = .{ .vertex_bit = true } };
        modulesInfo[1] = .{ .module = frag, .stage = .{ .fragment_bit = true }, .specInfo = &specConstants };
        defer allocator.free(modulesInfo);

        // Pipeline
        const vkPipelineCreateInfo = vk.pipe.VkPipelineCreateInfo{
            .colorFormat = vkCtx.vkSwapChain.surfaceFormat.format,
            .descSetLayouts = descSetLayouts[0..],
            .modulesInfo = modulesInfo,
            .pushConstants = pushConstants[0..],
            .vtxBuffDesc = .{
                .attribute_description = @constCast(&EmptyVtxBuffDesc.attribute_description)[0..],
                .binding_description = EmptyVtxBuffDesc.binding_description,
            },
            .useBlend = false,
        };
        const vkPipeline = try vk.pipe.VkPipeline.create(allocator, vkCtx, &vkPipelineCreateInfo);

        return .{
            .vkPipeline = vkPipeline,
            .descLayoutFrg = descLayoutFrg,
            .textSampler = textSampler,
        };
    }

    pub fn cleanup(self: *RenderPost, vkCtx: *const vk.ctx.VkCtx) void {
        self.textSampler.cleanup(vkCtx);
        self.descLayoutFrg.cleanup(vkCtx);
        self.vkPipeline.cleanup(vkCtx);
    }

    fn createSpecConsts(allocator: std.mem.Allocator, fxaa: *const u32) !vulkan.SpecializationInfo {
        const mapEntries = try allocator.alloc(vulkan.SpecializationMapEntry, 1);
        mapEntries[0] = vulkan.SpecializationMapEntry{
            .constant_id = 0,
            .offset = 0,
            .size = @sizeOf(u32),
        };
        return vulkan.SpecializationInfo{
            .p_map_entries = mapEntries.ptr,
            .map_entry_count = @as(u32, @intCast(mapEntries.len)),
            .p_data = fxaa,
            .data_size = @sizeOf(u32),
        };
    }

    pub fn render(
        self: *RenderPost,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        vkCmd: vk.cmd.VkCmdBuff,
        imageIndex: u32,
    ) !void {
        const allocator = engCtx.allocator;
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;

        const renderAttInfo = vulkan.RenderingAttachmentInfo{
            .image_view = vkCtx.vkSwapChain.imageViews[imageIndex].view,
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
            .p_color_attachments = @ptrCast(&renderAttInfo),
            .p_depth_attachment = null,
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
            .extent = extent,
        }};
        device.cmdSetScissor(cmdHandle, 0, scissor.len, &scissor);

        // Bind descriptor sets
        const vkDescAllocator = vkCtx.vkDescAllocator;
        var descSets = try std.ArrayList(vulkan.DescriptorSet).initCapacity(allocator, 1);
        defer descSets.deinit(allocator);
        try descSets.append(allocator, vkDescAllocator.getDescSet(DESC_ID_POST_TEXT_SAMPLER).?.descSet);
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

        self.setPushConstants(vkCtx, cmdHandle);

        device.cmdDraw(cmdHandle, 3, 1, 0, 0);

        device.cmdEndRendering(cmdHandle);
    }

    pub fn resize(self: *RenderPost, vkCtx: *const vk.ctx.VkCtx, attColor: *const eng.rend.Attachment) !void {
        const vkDescSetTxt = vkCtx.vkDescAllocator.getDescSet(DESC_ID_POST_TEXT_SAMPLER).?;
        vkDescSetTxt.setImage(vkCtx.vkDevice, attColor.vkImageView, self.textSampler, 0);
    }

    fn setPushConstants(self: *RenderPost, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        const extent = vkCtx.vkSwapChain.extent;
        const pushConstants = PushConstants{
            .screenWidth = @as(f32, @floatFromInt(extent.width)),
            .screenHeight = @as(f32, @floatFromInt(extent.height)),
        };

        vkCtx.vkDevice.deviceProxy.cmdPushConstants(
            cmdHandle,
            self.vkPipeline.pipelineLayout,
            vulkan.ShaderStageFlags{ .fragment_bit = true },
            0,
            @sizeOf(PushConstants),
            &pushConstants,
        );
    }
};
