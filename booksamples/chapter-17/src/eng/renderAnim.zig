const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");

pub const RenderAnim = struct {
    descLayout: vk.desc.VkDescSetLayout,
    vkPipeline: vk.cpipe.VkCompPipeline,

    pub fn cleanup(self: *RenderAnim, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        // TODO: Check if allocator is needed
        _ = allocator;
        self.descLayout.cleanup(vkCtx);
        self.vkPipeline.cleanup(vkCtx);
    }

    pub fn create(allocator: std.mem.Allocator, io: std.Io, vkCtx: *const vk.ctx.VkCtx) !RenderAnim {
        const descLayout = try vk.desc.VkDescSetLayout.create(
            allocator,
            vkCtx,
            &[_]vk.desc.LayoutInfo{.{
                .binding = 0,
                .descCount = 1,
                .descType = vulkan.DescriptorType.storage_buffer,
                .stageFlags = vulkan.ShaderStageFlags{ .compute_bit = true },
            }},
        );
        const layout = descLayout.descSetLayout;
        const descSetLayouts = [_]vulkan.DescriptorSetLayout{ layout, layout, layout, layout };

        // Shader modules
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const compCode align(@alignOf(u32)) = try com.utils.loadFile(arena.allocator(), io, "res/shaders/anim_comp.glsl.spv");
        const comp = try vkCtx.vkDevice.deviceProxy.createShaderModule(&.{
            .code_size = compCode.len,
            .p_code = @ptrCast(@alignCast(compCode)),
        }, null);
        defer vkCtx.vkDevice.deviceProxy.destroyShaderModule(comp, null);

        const moduleInfo = vk.pipe.ShaderModuleInfo{ .module = comp, .stage = .{ .compute_bit = true } };

        const vkPipelineCreateInfo = vk.cpipe.VkCompPipelineCreateInfo{
            .descSetLayouts = descSetLayouts[0..],
            .moduleInfo = moduleInfo,
            .pushConstants = null,
        };
        const vkPipeline = try vk.cpipe.VkCompPipeline.create(vkCtx, &vkPipelineCreateInfo);

        return .{
            .descLayout = descLayout,
            .vkPipeline = vkPipeline,
        };
    }

    pub fn render(self: *RenderAnim) void {
        _ = self;
    }
};
