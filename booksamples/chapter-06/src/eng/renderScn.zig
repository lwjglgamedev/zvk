const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");

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
    };

    pos: [3]f32,
};

pub const RenderScn = struct {
    renderAttachmentInfos: []vulkan.RenderingAttachmentInfo,
    renderInfos: []vulkan.RenderingInfo,
    vkPipeline: vk.pipe.VkPipeline,

    pub fn cleanup(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        self.vkPipeline.cleanup(vkCtx);
        allocator.free(self.renderInfos);
        allocator.free(self.renderAttachmentInfos);
    }

    pub fn create(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) !RenderScn {
        const renderAttachmentInfos = try createRenderingAttachmentInfo(allocator, vkCtx);
        const renderInfos = try createRenderInfos(allocator, vkCtx, renderAttachmentInfos);

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

        // Pipeline layout
        const pipelineLayout = try vkCtx.vkDevice.deviceProxy.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 0,
            .p_set_layouts = null,
            .push_constant_range_count = 0,
            .p_push_constant_ranges = null,
        }, null);

        // Pipeline
        const vkPipelineCreateInfo = vk.pipe.VkPipelineCreateInfo{
            .colorFormat = vkCtx.vkSwapChain.surfaceFormat.format,
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
            .renderAttachmentInfos = renderAttachmentInfos,
            .renderInfos = renderInfos,
            .vkPipeline = vkPipeline,
        };
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

    fn createRenderInfos(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, renderAttachmentInfos: []vulkan.RenderingAttachmentInfo) ![]vulkan.RenderingInfo {
        const numImages = vkCtx.vkSwapChain.imageViews.len;
        const extent = vkCtx.vkSwapChain.extent;
        const renderInfos = try allocator.alloc(vulkan.RenderingInfo, numImages);
        for (renderInfos, 0..) |*renderInfo, i| {
            renderInfo.* = vulkan.RenderingInfo{
                .render_area = .{ .extent = extent, .offset = .{ .x = 0, .y = 0 } },
                .layer_count = 1,
                .color_attachment_count = 1,
                .p_color_attachments = @ptrCast(&renderAttachmentInfos[i]),
                .view_mask = 0,
            };
        }
        return renderInfos;
    }

    pub fn render(self: *RenderScn, vkCtx: *const vk.ctx.VkCtx, vkCmd: vk.cmd.VkCmdBuff, modelsCache: *const eng.mcach.ModelsCache, imageIndex: u32) !void {
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;
        const renderInfo = self.renderInfos[imageIndex];

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

        const offset = [_]vulkan.DeviceSize{0};
        var iter = modelsCache.modelsMap.valueIterator();
        while (iter.next()) |vulkanRef| {
            for (vulkanRef.meshes.items) |mesh| {
                device.cmdBindIndexBuffer(cmdHandle, mesh.buffIdx.buffer, 0, vulkan.IndexType.uint32);
                device.cmdBindVertexBuffers(cmdHandle, 0, 1, @ptrCast(&mesh.buffVtx.buffer), &offset);
                device.cmdDrawIndexed(cmdHandle, @as(u32, @intCast(mesh.numIndices)), 1, 0, 0, 0);
            }
        }

        device.cmdEndRendering(cmdHandle);
    }
};
