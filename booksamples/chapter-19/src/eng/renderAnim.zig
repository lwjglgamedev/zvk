const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");

const LOCAL_SIZE_X: u32 = 32;

const PushConstants = extern struct {
    srcBufAddr: u64,
    weightsBufAddr: u64,
    jointsBufAddr: u64,
    dstBufAddr: u64,
    srcBuffFloatSize: u64,
};
pub const RenderAnim = struct {
    cmdPool: vk.cmd.VkCmdPool,
    cmdBuff: vk.cmd.VkCmdBuff,
    descLayout: vk.desc.VkDescSetLayout,
    grpSizeMap: std.StringHashMap(u32),
    vkPipeline: vk.cpipe.VkCompPipeline,
    queue: vk.queue.VkQueue,
    fence: vk.sync.VkFence,

    pub fn cleanup(self: *RenderAnim, vkCtx: *const vk.ctx.VkCtx) void {
        self.fence.cleanup(vkCtx);
        self.descLayout.cleanup(vkCtx);
        self.vkPipeline.cleanup(vkCtx);
        self.cmdPool.cleanup(vkCtx);
        self.grpSizeMap.deinit();
    }

    pub fn create(allocator: std.mem.Allocator, io: std.Io, vkCtx: *const vk.ctx.VkCtx) !RenderAnim {
        var cmdPool = try vk.cmd.VkCmdPool.create(vkCtx, vkCtx.vkPhysDevice.queuesInfo.compute_family, false);
        errdefer cmdPool.cleanup(vkCtx);
        const cmdBuff = try vk.cmd.VkCmdBuff.create(vkCtx, &cmdPool, true);
        errdefer cmdBuff.cleanup(vkCtx, &cmdPool);
        const queue = vk.queue.VkQueue.create(vkCtx, vkCtx.vkPhysDevice.queuesInfo.compute_family);
        const fence = try vk.sync.VkFence.create(vkCtx);
        errdefer fence.cleanup(vkCtx);

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
        errdefer descLayout.cleanup(vkCtx);

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

        // Push constants
        const pushConstants = [_]vulkan.PushConstantRange{
            .{
                .stage_flags = vulkan.ShaderStageFlags{ .compute_bit = true },
                .offset = 0,
                .size = @sizeOf(PushConstants),
            },
        };

        const vkPipelineCreateInfo = vk.cpipe.VkCompPipelineCreateInfo{
            .descSetLayouts = descSetLayouts[0..],
            .moduleInfo = moduleInfo,
            .pushConstants = pushConstants[0..],
        };
        const vkPipeline = try vk.cpipe.VkCompPipeline.create(vkCtx, &vkPipelineCreateInfo);
        errdefer vkPipeline.cleanup(vkCtx);

        const grpSizeMap = std.StringHashMap(u32).init(allocator);
        return .{
            .cmdPool = cmdPool,
            .cmdBuff = cmdBuff,
            .descLayout = descLayout,
            .grpSizeMap = grpSizeMap,
            .vkPipeline = vkPipeline,
            .queue = queue,
            .fence = fence,
        };
    }

    pub fn init(
        self: *RenderAnim,
        modelsCache: *eng.mcach.ModelsCache,
    ) !void {
        var modelsIt = modelsCache.modelsMap.valueIterator();
        while (modelsIt.next()) |vulkanModel| {
            if (!vulkanModel.hasAnimations()) {
                continue;
            }
            for (vulkanModel.meshes.items) |*mesh| {
                const vertexSize: f32 = 14.0 * 4.0;
                const groupSize: u32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(mesh.buffVtx.size)) / vertexSize / LOCAL_SIZE_X));
                try self.grpSizeMap.put(mesh.id, groupSize);
            }
        }
    }

    pub fn render(
        self: *RenderAnim,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
        animsCache: *const eng.acach.AnimsCache,
    ) !void {
        try self.fence.wait(vkCtx);
        try self.fence.reset(vkCtx);

        try self.cmdPool.reset(vkCtx);
        try self.cmdBuff.begin(vkCtx);

        const cmdHandle = self.cmdBuff.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;

        const memBarrier = [_]vulkan.MemoryBarrier2{.{
            .src_stage_mask = .{ .vertex_input_bit = true },
            .dst_stage_mask = .{ .compute_shader_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .shader_write_bit = true },
        }};
        const depInfo = vulkan.DependencyInfo{
            .memory_barrier_count = memBarrier.len,
            .p_memory_barriers = &memBarrier,
        };
        device.cmdPipelineBarrier2(cmdHandle, &depInfo);

        device.cmdBindPipeline(cmdHandle, vulkan.PipelineBindPoint.compute, self.vkPipeline.pipeline);

        var iter = engCtx.scene.entitiesMap.valueIterator();

        while (iter.next()) |listRef| {
            for (listRef.items) |entity| {
                const vulkanModel = modelsCache.modelsMap.get(entity.modelId) orelse {
                    std.log.warn("Could not find model {s}", .{entity.modelId});
                    continue;
                };
                const entityAnim = entity.animation orelse continue;
                if (!vulkanModel.hasAnimations()) continue;

                const animIdx = entityAnim.animationIdx;
                const animation = vulkanModel.animations.items[animIdx];
                const jointsBuffAddr = animation.buffers.items[entityAnim.currentFrame].address.?;
                for (vulkanModel.meshes.items) |mesh| {
                    var groupCountX: u32 = 1;
                    if (self.grpSizeMap.get(mesh.id)) |value| {
                        groupCountX = value;
                    } else {
                        std.log.warn("Group not found for {s}", .{mesh.id});
                    }

                    self.setPushConstants(
                        vkCtx,
                        cmdHandle,
                        mesh.buffVtx.address.?,
                        mesh.buffWeights.?.address.?,
                        jointsBuffAddr,
                        animsCache.getBuffer(entity.id, mesh.id).?.address.?,
                        mesh.buffVtx.size / 4,
                    );

                    device.cmdDispatch(cmdHandle, groupCountX, 1, 1);
                }
            }
        }
        try self.cmdBuff.end(vkCtx);

        const cmdBufferSubmitInfo = [_]vulkan.CommandBufferSubmitInfo{.{
            .device_mask = 0,
            .command_buffer = self.cmdBuff.cmdBuffProxy.handle,
        }};
        const emptySemphs = [_]vulkan.SemaphoreSubmitInfo{};
        try self.queue.submit(vkCtx, &cmdBufferSubmitInfo, &emptySemphs, &emptySemphs, self.fence);
    }

    fn setPushConstants(
        self: *RenderAnim,
        vkCtx: *const vk.ctx.VkCtx,
        cmdHandle: vulkan.CommandBuffer,
        srcBufAddr: u64,
        weightsBufAddr: u64,
        jointsBufAddr: u64,
        dstBufAddr: u64,
        srcBuffFloatSize: u64,
    ) void {
        const pushConstants = PushConstants{
            .srcBufAddr = srcBufAddr,
            .weightsBufAddr = weightsBufAddr,
            .jointsBufAddr = jointsBufAddr,
            .dstBufAddr = dstBufAddr,
            .srcBuffFloatSize = srcBuffFloatSize,
        };
        vkCtx.vkDevice.deviceProxy.cmdPushConstants(
            cmdHandle,
            self.vkPipeline.pipelineLayout,
            vulkan.ShaderStageFlags{ .compute_bit = true },
            0,
            @sizeOf(PushConstants),
            &pushConstants,
        );
    }
};
