const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");

pub const RenderScn = struct {
    renderAttachmentInfos: []vulkan.RenderingAttachmentInfo,
    renderInfos: []vulkan.RenderingInfo,

    pub fn cleanup(self: *RenderScn, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        _ = vkCtx;
        allocator.free(self.renderInfos);
        allocator.free(self.renderAttachmentInfos);
    }

    pub fn create(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) !RenderScn {
        const renderAttachmentInfos = try createRenderingAttachmentInfo(allocator, vkCtx);
        const renderInfos = try createRenderInfos(allocator, vkCtx, renderAttachmentInfos);

        return .{
            .renderAttachmentInfos = renderAttachmentInfos,
            .renderInfos = renderInfos,
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
                .clear_value = vulkan.ClearValue{ .color = .{ .float_32 = .{ 0.5, 0.7, 0.9, 1.0 } } },
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

    pub fn render(self: *RenderScn, vkCtx: *const vk.ctx.VkCtx, vkCmd: vk.cmd.VkCmdBuff, imageIndex: u32) !void {
        const cmdHandle = vkCmd.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;
        const renderInfo = self.renderInfos[imageIndex];

        device.cmdBeginRendering(cmdHandle, @ptrCast(&renderInfo));
        device.cmdEndRendering(cmdHandle);
    }
};
