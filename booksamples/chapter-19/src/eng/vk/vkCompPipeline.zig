const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const VkCompPipelineCreateInfo = struct {
    descSetLayouts: ?[]const vulkan.DescriptorSetLayout,
    moduleInfo: vk.pipe.ShaderModuleInfo,
    pushConstants: ?[]const vulkan.PushConstantRange,
};

pub const VkCompPipeline = struct {
    pipeline: vulkan.Pipeline,
    pipelineLayout: vulkan.PipelineLayout,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, createInfo: *const VkCompPipelineCreateInfo) !VkCompPipeline {
        const pssci = vulkan.PipelineShaderStageCreateInfo{
            .stage = createInfo.moduleInfo.stage,
            .module = createInfo.moduleInfo.module,
            .p_name = "main",
            .p_specialization_info = createInfo.moduleInfo.specInfo,
        };

        const pipelineLayout = try vkCtx.vkDevice.deviceProxy.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = if (createInfo.descSetLayouts) |ds| @as(u32, @intCast(ds.len)) else 0,
            .p_set_layouts = if (createInfo.descSetLayouts) |ds| ds.ptr else null,
            .push_constant_range_count = if (createInfo.pushConstants) |pc| @as(u32, @intCast(pc.len)) else 0,
            .p_push_constant_ranges = if (createInfo.pushConstants) |pcs| pcs.ptr else null,
        }, null);
        errdefer vkCtx.vkDevice.deviceProxy.destroyPipelineLayout(pipelineLayout, null);

        const pci = vulkan.ComputePipelineCreateInfo{
            .flags = .{},
            .stage = pssci,
            .layout = pipelineLayout,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        var pipeline: vulkan.Pipeline = undefined;
        _ = try vkCtx.vkDevice.deviceProxy.createComputePipelines(
            .null_handle,
            @ptrCast(&pci),
            null,
            @ptrCast(&pipeline),
        );

        return .{ .pipeline = pipeline, .pipelineLayout = pipelineLayout };
    }

    pub fn cleanup(self: *VkCompPipeline, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.destroyPipeline(self.pipeline, null);
        vkCtx.vkDevice.deviceProxy.destroyPipelineLayout(self.pipelineLayout, null);
    }
};
