const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");

pub const AnimsCache = struct {
    entitiesAnimBuffers: std.StringArrayHashMapUnmanaged(std.StringArrayHashMapUnmanaged(vk.buf.VkBuffer)),

    pub fn cleanup(self: *AnimsCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        var outerIt = self.entitiesAnimBuffers.iterator();
        while (outerIt.next()) |entry| {
            var innerIt = entry.value_ptr.iterator();
            while (innerIt.next()) |innerEntry| {
                innerEntry.value_ptr.cleanup(vkCtx);
            }
            entry.value_ptr.deinit(allocator);
        }
        self.entitiesAnimBuffers.deinit(allocator);
    }

    pub fn create() AnimsCache {
        const entitiesAnimBuffers: std.StringArrayHashMapUnmanaged(std.StringArrayHashMapUnmanaged(vk.buf.VkBuffer)) = .empty;
        return .{
            .entitiesAnimBuffers = entitiesAnimBuffers,
        };
    }

    pub fn getBuffer(self: *const AnimsCache, entityId: []const u8, meshId: []const u8) ?*const vk.buf.VkBuffer {
        const meshMap = self.entitiesAnimBuffers.getPtr(entityId) orelse return null;
        return meshMap.getPtr(meshId);
    }

    pub fn init(
        self: *AnimsCache,
        allocator: std.mem.Allocator,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
    ) !void {
        var iter = engCtx.scene.entitiesMap.valueIterator();
        while (iter.next()) |entityRef| {
            const entity = entityRef.*;
            const vulkanModel = modelsCache.modelsMap.get(entity.modelId);
            if (!vulkanModel.?.hasAnimations()) {
                continue;
            }

            var bufferMap = std.StringHashMap(vk.buf.VkBuffer).init(allocator);

            for (vulkanModel.getVulkanMeshList()) |vulkanMesh| {
                const animation_buffer = try vk.buf.VkBuffer.init(
                    vkCtx,
                    vulkanMesh.verticesBuffer().getRequestedSize(),
                    vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                    vk.VMA_MEMORY_USAGE_AUTO,
                    vk.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
                    0,
                );
                try bufferMap.put(vulkanMesh.id(), animation_buffer);
            }

            try self.entitiesAnimBuffers.put(entity.getId(), bufferMap);
        }
    }
};
