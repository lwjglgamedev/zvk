const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const ShaderModuleInfo = struct {
    module: vulkan.ShaderModule,
    stage: vulkan.ShaderStageFlags,
};

pub const VkPipelineCreateInfo = struct {
    colorFormat: vulkan.Format,
    modulesInfo: []ShaderModuleInfo,
    useBlend: bool,
    vtxBuffDesc: VtxBuffDesc,
};

const VtxBuffDesc = struct {
    binding_description: vulkan.VertexInputBindingDescription,
    attribute_description: []vulkan.VertexInputAttributeDescription,
};

pub const VkPipeline = struct {
    pipeline: vulkan.Pipeline,
    pipelineLayout: vulkan.PipelineLayout,

    pub fn create(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, createInfo: *const VkPipelineCreateInfo) !VkPipeline {
        const pssci = try allocator.alloc(vulkan.PipelineShaderStageCreateInfo, createInfo.modulesInfo.len);
        defer allocator.free(pssci);

        for (pssci, 0..) |*info, i| {
            info.* = .{
                .stage = createInfo.modulesInfo[i].stage,
                .module = createInfo.modulesInfo[i].module,
                .p_name = "main",
            };
        }

        const piasci = vulkan.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = vulkan.Bool32.false,
        };

        const pvsci = vulkan.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = null,
            .scissor_count = 1,
            .p_scissors = null,
        };

        const prsci = vulkan.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = vulkan.Bool32.false,
            .rasterizer_discard_enable = vulkan.Bool32.false,
            .polygon_mode = .fill,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = vulkan.Bool32.false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        };

        const pmsci = vulkan.PipelineMultisampleStateCreateInfo{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = vulkan.Bool32.false,
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = vulkan.Bool32.false,
            .alpha_to_one_enable = vulkan.Bool32.false,
        };

        const dynstate = [_]vulkan.DynamicState{ .viewport, .scissor };
        const pdsci = vulkan.PipelineDynamicStateCreateInfo{
            .flags = .{},
            .dynamic_state_count = dynstate.len,
            .p_dynamic_states = &dynstate,
        };

        const pcbas = vulkan.PipelineColorBlendAttachmentState{
            .blend_enable = if (createInfo.useBlend) vulkan.Bool32.true else vulkan.Bool32.false,
            .color_blend_op = .add,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .alpha_blend_op = .add,
            .src_alpha_blend_factor = .src_alpha,
            .dst_alpha_blend_factor = .zero,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };

        const pcbsci = vulkan.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = vulkan.Bool32.false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&pcbas),
            .blend_constants = [_]f32{ 0, 0, 0, 0 },
        };

        const formats = [_]vulkan.Format{createInfo.colorFormat};
        const renderCreateInfo = vulkan.PipelineRenderingCreateInfo{
            .color_attachment_count = 1,
            .p_color_attachment_formats = &formats,
            .view_mask = 0,
            .depth_attachment_format = vulkan.Format.undefined,
            .stencil_attachment_format = vulkan.Format.undefined,
        };

        const pvisci = vulkan.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast(&createInfo.vtxBuffDesc.binding_description),
            .vertex_attribute_description_count = @intCast(createInfo.vtxBuffDesc.attribute_description.len),
            .p_vertex_attribute_descriptions = createInfo.vtxBuffDesc.attribute_description.ptr,
        };

        const pipelineLayout = try vkCtx.vkDevice.deviceProxy.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 0,
            .p_set_layouts = null,
            .push_constant_range_count = 0,
            .p_push_constant_ranges = null,
        }, null);

        const gpci = vulkan.GraphicsPipelineCreateInfo{
            .flags = .{},
            .stage_count = @intCast(createInfo.modulesInfo.len),
            .p_stages = pssci.ptr,
            .p_vertex_input_state = &pvisci,
            .p_input_assembly_state = &piasci,
            .p_tessellation_state = null,
            .p_viewport_state = &pvsci,
            .p_rasterization_state = &prsci,
            .p_multisample_state = &pmsci,
            .p_depth_stencil_state = null,
            .p_color_blend_state = &pcbsci,
            .p_dynamic_state = &pdsci,
            .layout = pipelineLayout,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
            .p_next = @constCast(&renderCreateInfo),
        };

        var pipeline: vulkan.Pipeline = undefined;
        _ = try vkCtx.vkDevice.deviceProxy.createGraphicsPipelines(
            .null_handle,
            1,
            @ptrCast(&gpci),
            null,
            @ptrCast(&pipeline),
        );

        return .{ .pipeline = pipeline, .pipelineLayout = pipelineLayout };
    }

    pub fn cleanup(self: *VkPipeline, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.destroyPipeline(self.pipeline, null);
        vkCtx.vkDevice.deviceProxy.destroyPipelineLayout(self.pipelineLayout, null);
    }
};
