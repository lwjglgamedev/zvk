const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub fn createHostVisibleBuff(
    allocator: std.mem.Allocator,
    vkCtx: *vk.ctx.VkCtx,
    id: []const u8,
    size: u64,
    bufferUsage: vulkan.BufferUsageFlags,
    vkDescSetLayout: vk.desc.VkDescSetLayout,
) !vk.buf.VkBuffer {
    const buffer = try vk.buf.VkBuffer.create(
        vkCtx,
        size,
        bufferUsage,
        @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
        vk.vma.VmaUsage.VmaUsageAuto,
        vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
    );
    errdefer buffer.cleanup(vkCtx);

    const descSet = try vkCtx.vkDescAllocator.addDescSet(
        allocator,
        vkCtx.vkPhysDevice,
        vkCtx.vkDevice,
        id,
        vkDescSetLayout,
    );
    const layoutInfo = vkDescSetLayout.layoutInfos[0];
    descSet.setBuffer(vkCtx.vkDevice, buffer, layoutInfo.binding, layoutInfo.descType);

    return buffer;
}

pub fn createHostVisibleBuffs(
    allocator: std.mem.Allocator,
    vkCtx: *vk.ctx.VkCtx,
    baseId: []const u8,
    numBuffers: u32,
    size: u64,
    bufferUsage: vulkan.BufferUsageFlags,
    descLayout: vk.desc.VkDescSetLayout,
) ![]vk.buf.VkBuffer {
    const buffers = try allocator.alloc(vk.buf.VkBuffer, numBuffers);
    for (buffers, 0..) |*buffer, i| {
        const id = try std.fmt.allocPrint(allocator, "{s}{d}", .{ baseId, i });
        defer allocator.free(id);
        buffer.* = try vk.util.createHostVisibleBuff(
            allocator,
            vkCtx,
            id,
            size,
            bufferUsage,
            descLayout,
        );
    }
    return buffers;
}
