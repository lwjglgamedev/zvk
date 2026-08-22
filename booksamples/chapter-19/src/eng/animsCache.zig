const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");

pub const AnimsCache = struct {
    entitiesAnimBuffers: std.StringArrayHashMapUnmanaged(std.StringArrayHashMapUnmanaged(vk.buf.VkBuffer)),

    pub fn cleanup(self: *AnimsCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        var outerIt = self.entitiesAnimBuffers.iterator();
        while (outerIt.next()) |entry| {
            allocator.free(entry.key_ptr.*);
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

            var bufferMap: std.StringArrayHashMapUnmanaged(vk.buf.VkBuffer) = .empty;

            for (vulkanModel.?.meshes.items) |vulkanMesh| {
                const animBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    vulkanMesh.buffVtx.size,
                    .{ .vertex_buffer_bit = true, .storage_buffer_bit = true, .shader_device_address_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.None),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
                try bufferMap.put(allocator, vulkanMesh.id, animBuffer);
            }

            try self.entitiesAnimBuffers.put(allocator, try allocator.dupe(u8, entity.id), bufferMap);
        }
    }
};
