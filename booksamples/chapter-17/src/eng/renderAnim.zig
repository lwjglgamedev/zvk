const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");

const LOCAL_SIZE_X: u32 = 32;

pub const RenderAnim = struct {
    cmdPool: vk.cmd.VkCmdPool,
    cmdBuff: vk.cmd.VkCmdBuff,
    descLayout: vk.desc.VkDescSetLayout,
    grpSizeMap: std.StringHashMap(u32),
    vkPipeline: vk.cpipe.VkCompPipeline,

    pub fn cleanup(self: *RenderAnim, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        // TODO: Check if allocator is needed
        _ = allocator;
        self.descLayout.cleanup(vkCtx);
        self.vkPipeline.cleanup(vkCtx);
        self.cmdPool.cleanup(vkCtx);
        self.grpSizeMap.deinit();
    }

    pub fn create(allocator: std.mem.Allocator, io: std.Io, vkCtx: *const vk.ctx.VkCtx) !RenderAnim {
        var cmdPool = try vk.cmd.VkCmdPool.create(vkCtx, vkCtx.vkPhysDevice.queuesInfo.compute_family, false);
        const cmdBuff = try vk.cmd.VkCmdBuff.create(vkCtx, &cmdPool, true);

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

        const grpSizeMap = std.StringHashMap(u32).init(allocator);
        return .{
            .cmdPool = cmdPool,
            .cmdBuff = cmdBuff,
            .descLayout = descLayout,
            .grpSizeMap = grpSizeMap,
            .vkPipeline = vkPipeline,
        };
    }

    pub fn init(
        self: *RenderAnim,
        allocator: std.mem.Allocator,
        vkCtx: *vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
        animsCache: *const eng.acach.AnimsCache,
    ) !void {
        const layoutInfo = self.descLayout.layoutInfos[0];

        var modelsIt = modelsCache.modelsMap.valueIterator();
        while (modelsIt.next()) |vulkanModel| {
            if (!vulkanModel.hasAnimations()) {
                continue;
            }
            const modelId = vulkanModel.id;
            for (vulkanModel.animations.items, 0..) |animation, animationIdx| {
                for (animation.buffers.items, 0..) |jointsMatricesBuffer, buffPos| {
                    const id = try std.fmt.allocPrint(allocator, "{s}_{d}_{d}", .{ modelId, animationIdx, buffPos });
                    defer allocator.free(id);
                    const descSet = try vkCtx.vkDescAllocator.addDescSet(
                        allocator,
                        vkCtx.vkPhysDevice,
                        vkCtx.vkDevice,
                        id,
                        self.descLayout,
                    );
                    descSet.setBuffer(vkCtx.vkDevice, jointsMatricesBuffer, layoutInfo.binding, layoutInfo.descType);
                }
            }

            for (vulkanModel.meshes.items) |*mesh| {
                const vertexSize: f32 = 14.0 * 4.0;
                const groupSize: u32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(mesh.buffVtx.size)) / vertexSize / LOCAL_SIZE_X));
                const vtxId = try std.fmt.allocPrint(allocator, "{s}_VTX", .{mesh.id});
                defer allocator.free(vtxId);
                const vtxDescSet = try vkCtx.vkDescAllocator.addDescSet(allocator, vkCtx.vkPhysDevice, vkCtx.vkDevice, vtxId, self.descLayout);
                vtxDescSet.setBuffer(vkCtx.vkDevice, mesh.buffVtx, layoutInfo.binding, layoutInfo.descType);
                try self.grpSizeMap.put(mesh.id, groupSize);

                if (mesh.buffWeights) |weightsBuffer| {
                    const wId = try std.fmt.allocPrint(allocator, "{s}_W", .{mesh.id});
                    defer allocator.free(wId);
                    const weightsDescSet = try vkCtx.vkDescAllocator.addDescSet(allocator, vkCtx.vkPhysDevice, vkCtx.vkDevice, wId, self.descLayout);
                    weightsDescSet.setBuffer(vkCtx.vkDevice, weightsBuffer, layoutInfo.binding, layoutInfo.descType);
                }
            }
        }

        var entIt = engCtx.scene.entitiesMap.valueIterator();
        while (entIt.next()) |entityRef| {
            const entity = entityRef.*;
            const vulkanModel = modelsCache.modelsMap.get(entity.modelId);
            if (vulkanModel) |vm| {
                if (!vm.hasAnimations()) continue;
                for (vm.meshes.items) |mesh| {
                    const animBuffer = animsCache.getBuffer(entity.id, mesh.id) orelse continue;
                    const id = try std.fmt.allocPrint(allocator, "{s}_{s}_ENT", .{ entity.id, mesh.id });
                    defer allocator.free(id);
                    const descSet = try vkCtx.vkDescAllocator.addDescSet(allocator, vkCtx.vkPhysDevice, vkCtx.vkDevice, id, self.descLayout);
                    descSet.setBuffer(vkCtx.vkDevice, animBuffer.*, layoutInfo.binding, layoutInfo.descType);
                }
            }
        }
    }

    pub fn render(
        self: *RenderAnim,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
    ) !void {
        // TODO: Fences

        try self.cmdPool.reset(vkCtx);
        try self.cmdBuff.begin(vkCtx);

        const cmdHandle = self.cmdBuff.cmdBuffProxy.handle;
        const device = vkCtx.vkDevice.deviceProxy;
        const descAllocator = &vkCtx.vkDescAllocator;

        device.cmdBindPipeline(cmdHandle, vulkan.PipelineBindPoint.compute, self.vkPipeline.pipeline);

        var iter = engCtx.scene.entitiesMap.valueIterator();

        while (iter.next()) |entityRef| {
            const entity = entityRef.*;
            const vulkanModel = modelsCache.modelsMap.get(entity.modelId) orelse {
                std.log.warn("Could not find model {s}", .{entity.modelId});
                continue;
            };
            const entityAnim = entity.animation orelse continue;
            if (!vulkanModel.hasAnimations()) continue;

            const animIdx = entityAnim.animationIdx;
            for (vulkanModel.meshes.items) |mesh| {
                var groupCountX: u32 = 1;
                if (self.grpSizeMap.get(mesh.id)) |value| {
                    groupCountX = value;
                } else {
                    std.log.warn("Group not found for {s}", .{mesh.id});
                }

                const vtxId = try std.fmt.allocPrint(engCtx.allocator, "{s}_VTX", .{mesh.id});
                defer engCtx.allocator.free(vtxId);
                const vtxDesc = descAllocator.getDescSet(vtxId) orelse continue;

                const wId = try std.fmt.allocPrint(engCtx.allocator, "{s}_W", .{mesh.id});
                defer engCtx.allocator.free(wId);
                const wDesc = descAllocator.getDescSet(wId) orelse continue;

                const entId = try std.fmt.allocPrint(engCtx.allocator, "{s}_{s}_ENT", .{ entity.id, mesh.id });
                defer engCtx.allocator.free(entId);
                const entDesc = descAllocator.getDescSet(entId) orelse continue;

                const jointsId = try std.fmt.allocPrint(engCtx.allocator, "{s}_{d}_{d}", .{ entity.modelId, animIdx, entityAnim.currentFrame });
                defer engCtx.allocator.free(jointsId);
                const jointsDesc = descAllocator.getDescSet(jointsId) orelse continue;

                const descSets = [_]vulkan.DescriptorSet{
                    vtxDesc.descSet,
                    wDesc.descSet,
                    entDesc.descSet,
                    jointsDesc.descSet,
                };
                device.cmdBindDescriptorSets(
                    cmdHandle,
                    vulkan.PipelineBindPoint.compute,
                    self.vkPipeline.pipelineLayout,
                    0,
                    &descSets,
                    null,
                );

                device.cmdDispatch(cmdHandle, groupCountX, 1, 1);
            }
        }
        try self.cmdBuff.end(vkCtx);
    }
};
