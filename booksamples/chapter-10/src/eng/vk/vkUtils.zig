const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const MATRIX_SIZE: u64 = 64;

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
        @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSSequentialWriteBit),
        vk.vma.VmaUsage.VmaUsageAuto,
        vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
    );

    const descSet = try vkCtx.vkDescAllocator.addDescSet(
        allocator,
        vkCtx.vkPhysDevice,
        vkCtx.vkDevice,
        id,
        vkDescSetLayout,
    );
    descSet.setBuffer(vkCtx.vkDevice, buffer, vkDescSetLayout.binding, vkDescSetLayout.descType);

    return buffer;
}
