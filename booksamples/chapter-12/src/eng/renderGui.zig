const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const zgui = @import("zgui");

const PushConstants = struct {
    scaleX: f32 = 1.0,
    scaleY: f32 = 1.0,
};

const GuiVtxBuffDesc = struct {
    const binding_description = vulkan.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(GuiVtxBuffDesc),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vulkan.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(GuiVtxBuffDesc, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(GuiVtxBuffDesc, "textCoords"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32b32a32_sfloat,
            .offset = @offsetOf(GuiVtxBuffDesc, "color"),
        },
    };

    pos: [2]f32,
    textCoords: [2]f32,
    color: u32,
};

const TXT_ID_GUI_FONTS = "TXT_ID_GUI_IMGUI_FONTS";
const DESC_ID_TEXT_PFX = "GUI_DESC_ID_TEXT_PFX_";
const DESC_ID_TEXT_SAMPLER = "GUI_DESC_ID_TEXT_SAMPLER";
const DEFAULT_VTX_BUFF_SIZE: usize = 1024;
const DEFAULT_IDX_BUFF_SIZE: usize = 2024;

// TODO: Handle resizing
pub const RenderGui = struct {
    descLayoutFrg: vk.desc.VkDescSetLayout,
    guiTextureCache: eng.tcach.TextureCache,
    textSampler: vk.text.VkTextSampler,
    vtxBuffers: []vk.buf.VkBuffer,
    idxBuffers: []vk.buf.VkBuffer,
    vkPipeline: vk.pipe.VkPipeline,

    pub fn create(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, attColor: *const eng.rend.Attachment, textureCache: *eng.tcach.TextureCache) !RenderGui {
        // Init GUI
        try initGUI(allocator, vkCtx, attColor, textureCache);

        // Textures
        const samplerInfo = vk.text.VkTextSamplerInfo{
            .addressMode = vulkan.SamplerAddressMode.repeat,
            .anisotropy = true,
            .borderColor = vulkan.BorderColor.float_opaque_black,
        };
        const textSampler = try vk.text.VkTextSampler.create(vkCtx, samplerInfo);

        // Push constants
        const pushConstants = [_]vulkan.PushConstantRange{.{
            .stage_flags = vulkan.ShaderStageFlags{ .vertex_bit = true },
            .offset = 0,
            .size = @sizeOf(PushConstants),
        }};

        // Descriptor Set layouts
        const descLayoutFrg = try vk.desc.VkDescSetLayout.create(vkCtx, 0, vulkan.DescriptorType.combined_image_sampler, vulkan.ShaderStageFlags{ .fragment_bit = true }, 1);

        const descSetLayouts = [_]vulkan.DescriptorSetLayout{descLayoutFrg.descSetLayout};

        // Shader modules
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const vertCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/gui_vtx.glsl.spv");
        const vert = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = vertCode.len,
            .p_code = @ptrCast(@alignCast(vertCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(vert, null);

        const fragCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), "res/shaders/gui_frg.glsl.spv");
        const frag = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = fragCode.len,
            .p_code = @ptrCast(@alignCast(fragCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(frag, null);

        const modulesInfo = try allocator.alloc(vk.pipe.ShaderModuleInfo, 2);
        modulesInfo[0] = .{ .module = vert, .stage = .{ .vertex_bit = true } };
        modulesInfo[1] = .{ .module = frag, .stage = .{ .fragment_bit = true } };
        defer allocator.free(modulesInfo);

        // Pipeline
        const vkPipelineCreateInfo = vk.pipe.VkPipelineCreateInfo{
            .colorFormat = eng.rend.COLOR_ATTACHMENT_FORMAT,
            .descSetLayouts = descSetLayouts[0..],
            .pushConstants = pushConstants[0..],
            .modulesInfo = modulesInfo,
            .vtxBuffDesc = .{
                .attribute_description = @constCast(&GuiVtxBuffDesc.attribute_description)[0..],
                .binding_description = GuiVtxBuffDesc.binding_description,
            },
            .useBlend = true,
        };
        const vkPipeline = try vk.pipe.VkPipeline.create(allocator, vkCtx, &vkPipelineCreateInfo);

        // Buffers
        const vtxBuffers = try allocator.alloc(vk.buf.VkBuffer, com.common.FRAMES_IN_FLIGHT);
        const idxBuffers = try allocator.alloc(vk.buf.VkBuffer, com.common.FRAMES_IN_FLIGHT);
        for (0..com.common.FRAMES_IN_FLIGHT) |i| {
            vtxBuffers[i] = try vk.buf.VkBuffer.create(
                vkCtx,
                DEFAULT_VTX_BUFF_SIZE,
                .{ .vertex_buffer_bit = true },
                @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
            idxBuffers[i] = try vk.buf.VkBuffer.create(
                vkCtx,
                DEFAULT_VTX_BUFF_SIZE,
                .{ .index_buffer_bit = true },
                @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }

        const guiTextureCache = eng.tcach.TextureCache.create(allocator);
        return .{
            .descLayoutFrg = descLayoutFrg,
            .guiTextureCache = guiTextureCache,
            .textSampler = textSampler,
            .vtxBuffers = vtxBuffers,
            .idxBuffers = idxBuffers,
            .vkPipeline = vkPipeline,
        };
    }

    pub fn cleanup(self: *RenderGui, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        for (self.vtxBuffers) |vkVuffer| {
            vkVuffer.cleanup(vkCtx);
        }
        defer allocator.free(self.vtxBuffers);
        for (self.idxBuffers) |vkVuffer| {
            vkVuffer.cleanup(vkCtx);
        }
        defer allocator.free(self.idxBuffers);
        self.textSampler.cleanup(vkCtx);
        self.descLayoutFrg.cleanup(vkCtx);
        self.vkPipeline.cleanup(vkCtx);
        self.guiTextureCache.cleanup(allocator, vkCtx);
        zgui.deinit();
    }

    // TODO: Check if this is needed
    pub fn init(self: *RenderGui, allocator: std.mem.Allocator, vkCtx: *vk.ctx.VkCtx, textureCache: *const eng.tcach.TextureCache) !void {
        _ = textureCache;
        _ = self;
        _ = allocator;
        _ = vkCtx;
    }

    fn initGUI(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, attColor: *const eng.rend.Attachment, textureCache: *eng.tcach.TextureCache) !void {
        zgui.init(allocator);

        zgui.io.setIniFilename(null);

        zgui.io.setDisplaySize(@as(f32, @floatFromInt(attColor.vkImage.width)), @as(f32, @floatFromInt(attColor.vkImage.height)));
        zgui.io.setBackendFlags(.{ .renderer_has_textures = true });

        const fontCfg = zgui.FontConfig.init();
        _ = zgui.io.addFontDefault(fontCfg);

        _ = vkCtx;
        _ = textureCache;
    }

    pub fn render(
        self: *RenderGui,
        vkCtx: *vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        vkCmd: vk.cmd.VkCmdBuff,
        attColor: *const eng.rend.Attachment,
        vkCmdPool: *vk.cmd.VkCmdPool,
        vkQueue: vk.queue.VkQueue,
        currentFrame: u32,
    ) !void {
        if (!try self.updateBuffers(vkCtx, currentFrame)) {
            return;
        }

        const allocator = engCtx.allocator;
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;

        try self.updateGuiTextures(allocator, vkCtx, vkCmdPool, vkQueue);

        const renderAttInfo = vulkan.RenderingAttachmentInfo{
            .image_view = attColor.vkImageView.view,
            .image_layout = vulkan.ImageLayout.color_attachment_optimal,
            .load_op = vulkan.AttachmentLoadOp.load,
            .store_op = vulkan.AttachmentStoreOp.store,
            .clear_value = vulkan.ClearValue{ .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
            .resolve_mode = vulkan.ResolveModeFlags{},
            .resolve_image_layout = vulkan.ImageLayout.attachment_optimal,
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
            .y = @as(f32, @floatFromInt(attColor.vkImage.height)),
            .width = @as(f32, @floatFromInt(attColor.vkImage.width)),
            .height = -1.0 * @as(f32, @floatFromInt(attColor.vkImage.height)),
            .min_depth = 0,
            .max_depth = 1,
        }};
        device.cmdSetViewport(cmdHandle, 0, viewPort.len, &viewPort);

        self.setPushConstants(vkCtx, cmdHandle);

        const drawData = zgui.getDrawData();
        if (@intFromPtr(drawData) == 0) {
            return;
        }
        const offset = [_]vulkan.DeviceSize{0};
        device.cmdBindIndexBuffer(cmdHandle, self.idxBuffers[currentFrame].buffer, 0, vulkan.IndexType.uint16);
        device.cmdBindVertexBuffers(cmdHandle, 0, 1, @ptrCast(&self.vtxBuffers[currentFrame].buffer), &offset);

        const vkDescAllocator = vkCtx.vkDescAllocator;
        var descSets: [1]vulkan.DescriptorSet = undefined;

        var offsetIdx: u32 = 0;
        var offsetVtx: i32 = 0;
        const numCmds = @as(usize, @intCast(drawData.cmd_lists_count));
        for (0..numCmds) |i| {
            const cmd_list = drawData.cmd_lists.items[i];
            for (cmd_list.getCmdBuffer()) |cmd| {
                const x: i32 = @intFromFloat(cmd.clip_rect[0]);
                const y: i32 = @intFromFloat(cmd.clip_rect[1]);
                const z: i32 = @intFromFloat(cmd.clip_rect[2]);
                const w: i32 = @intFromFloat(cmd.clip_rect[3]);
                const scissor = [_]vulkan.Rect2D{.{
                    .offset = .{ .x = x, .y = y },
                    .extent = .{ .width = @intCast(z - x), .height = @intCast(w - y) },
                }};
                device.cmdSetScissor(cmdHandle, 0, scissor.len, &scissor);

                const idDesc = try std.fmt.allocPrint(allocator, "{s}{d}", .{ DESC_ID_TEXT_SAMPLER, cmd.texture_ref.tex_id });
                defer allocator.free(idDesc);
                descSets[0] = vkDescAllocator.getDescSet(idDesc).?.descSet;

                device.cmdBindDescriptorSets(
                    cmdHandle,
                    vulkan.PipelineBindPoint.graphics,
                    self.vkPipeline.pipelineLayout,
                    0,
                    @as(u32, @intCast(descSets.len)),
                    &descSets,
                    0,
                    null,
                );

                device.cmdDrawIndexed(
                    cmdHandle,
                    @intCast(cmd.elem_count),
                    1,
                    offsetIdx + @as(u32, @intCast(cmd.idx_offset)),
                    offsetVtx + @as(i32, @intCast(cmd.vtx_offset)),
                    0,
                );
            }
            offsetIdx += @as(u32, @intCast(cmd_list.getIndexBufferLength()));
            offsetVtx += @as(i32, @intCast(cmd_list.getVertexBufferLength()));
        }
        device.cmdEndRendering(cmdHandle);
    }

    fn setPushConstants(self: *RenderGui, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        const dispSize = zgui.io.getDisplaySize();
        const pushConstants = PushConstants{
            .scaleX = 2.0 / dispSize[0],
            .scaleY = -2.0 / dispSize[1],
        };

        vkCtx.vkDevice.deviceProxy.cmdPushConstants(
            cmdHandle,
            self.vkPipeline.pipelineLayout,
            vulkan.ShaderStageFlags{ .vertex_bit = true },
            0,
            @sizeOf(PushConstants),
            &pushConstants,
        );
    }

    pub fn resize(self: *RenderGui, attColor: *const eng.rend.Attachment) !void {
        _ = self;
        zgui.io.setDisplaySize(
            @as(f32, @floatFromInt(attColor.vkImage.width)),
            @as(f32, @floatFromInt(attColor.vkImage.height)),
        );
    }

    fn updateBuffers(self: *RenderGui, vkCtx: *const vk.ctx.VkCtx, currentFrame: u32) !bool {
        const drawData = zgui.getDrawData();
        if (@intFromPtr(drawData) == 0) {
            return false;
        }
        const vtxBuffSize: u64 = @as(u64, @intCast(drawData.total_vtx_count * @sizeOf(GuiVtxBuffDesc)));
        const idxBuffSize: u64 = @as(u64, @intCast(drawData.total_idx_count * @sizeOf(u16)));

        if (vtxBuffSize == 0 or idxBuffSize == 0) {
            return false;
        }

        const vtxBuffer = self.vtxBuffers[currentFrame];
        if (vtxBuffer.size < vtxBuffSize) {
            vtxBuffer.cleanup(vkCtx);
            self.vtxBuffers[currentFrame] = try vk.buf.VkBuffer.create(
                vkCtx,
                vtxBuffSize,
                .{ .vertex_buffer_bit = true },
                @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }

        const idxBuffer = self.idxBuffers[currentFrame];
        if (idxBuffer.size < idxBuffSize) {
            idxBuffer.cleanup(vkCtx);
            self.idxBuffers[currentFrame] = try vk.buf.VkBuffer.create(
                vkCtx,
                idxBuffSize,
                .{ .index_buffer_bit = true },
                @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }

        var vtxOffset: usize = 0;
        var idxOffset: usize = 0;
        const numCmds = @as(usize, @intCast(drawData.cmd_lists_count));

        const vtxBuffData = try vtxBuffer.map(vkCtx);
        defer vtxBuffer.unMap(vkCtx);
        const vtxGpuBuff: [*]GuiVtxBuffDesc = @ptrCast(@alignCast(vtxBuffData));

        const idxBuffData = try idxBuffer.map(vkCtx);
        defer idxBuffer.unMap(vkCtx);
        const idxGpuBuff: [*]u16 = @ptrCast(@alignCast(idxBuffData));

        for (0..numCmds) |i| {
            const cmd_list = drawData.cmd_lists.items[i];
            const vtxElemSize = @as(usize, @intCast(cmd_list.getVertexBufferLength()));
            const idxElemSize = @as(usize, @intCast(cmd_list.getIndexBufferLength()));

            const vtx_buffer_ptr: [*]GuiVtxBuffDesc = @ptrCast(@alignCast(cmd_list.getVertexBufferData()));
            const idx_buffer_ptr: [*]u16 = @ptrCast(@alignCast(cmd_list.getIndexBufferData()));

            const dstVtx = vtxOffset + vtxElemSize;
            const dstIdx = idxOffset + idxElemSize;

            @memcpy(vtxGpuBuff[vtxOffset..dstVtx], vtx_buffer_ptr[0..vtxElemSize]);
            @memcpy(idxGpuBuff[idxOffset..dstIdx], idx_buffer_ptr[0..idxElemSize]);

            vtxOffset += vtxElemSize;
            idxOffset += idxElemSize;
        }

        return true;
    }

    fn updateGuiTextures(
        self: *RenderGui,
        allocator: std.mem.Allocator,
        vkCtx: *vk.ctx.VkCtx,
        vkCmdPool: *vk.cmd.VkCmdPool,
        vkQueue: vk.queue.VkQueue,
    ) !void {
        const drawData = zgui.getDrawData();
        if (@intFromPtr(drawData) == 0) {
            return;
        }
        var textList = try std.ArrayList(*zgui.TextureData).initCapacity(allocator, 1);
        defer textList.deinit(allocator);

        const numCmds = @as(usize, @intCast(drawData.cmd_lists_count));
        for (0..numCmds) |i| {
            const cmd_list = drawData.cmd_lists.items[i];
            for (cmd_list.getCmdBuffer()) |cmd| {
                if (cmd.texture_ref.tex_data.?.status != zgui.TextureStatus.ok) {
                    try textList.append(allocator, cmd.texture_ref.tex_data.?);
                    cmd.texture_ref.tex_data.?.status = zgui.TextureStatus.ok;
                }
            }
        }

        for (textList.items) |textData| {
            const numPixels = textData.width * textData.height * textData.bytes_per_pixel;
            const id = try std.fmt.allocPrint(allocator, "{s}{d}", .{ "GUI_TEXTURE_", textData.tex_id });
            defer allocator.free(id);
            const textureInfo = eng.tcach.TextureInfo{
                .id = id,
                .data = textData.pixels[0..@as(usize, @intCast(numPixels))],
                .height = @as(u32, @intCast(textData.height)),
                .width = @as(u32, @intCast(textData.width)),
                .format = vulkan.Format.r8g8b8a8_srgb,
            };
            try self.guiTextureCache.addTexture(allocator, vkCtx, &textureInfo);
            const idDesc = try std.fmt.allocPrint(allocator, "{s}{d}", .{ DESC_ID_TEXT_SAMPLER, textData.tex_id });
            defer allocator.free(idDesc);
            const descSet = try vkCtx.vkDescAllocator.addDescSet(
                allocator,
                vkCtx.vkPhysDevice,
                vkCtx.vkDevice,
                idDesc,
                self.descLayoutFrg,
            );
            const texture = self.guiTextureCache.getTexture(textureInfo.id);
            descSet.setImage(vkCtx.vkDevice, texture.vkImageView, self.textSampler, 0);
        }
        if (textList.items.len > 0) {
            try self.guiTextureCache.recordTextures(allocator, vkCtx, vkCmdPool, vkQueue);
        }
    }
};
