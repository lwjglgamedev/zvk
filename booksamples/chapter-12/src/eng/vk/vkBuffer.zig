const vulkan = @import("vulkan");
const vk = @import("mod.zig");
const vma = vk.vma.vma;

pub const VkBuffer = struct {
    size: u64,
    buffer: vulkan.Buffer,
    allocation: vma.VmaAllocation,
    mappedData: ?*anyopaque,

    pub fn create(
        vkCtx: *const vk.ctx.VkCtx,
        size: u64,
        bufferUsage: vulkan.BufferUsageFlags,
        vmaFlags: u32,
        vmaUsage: vk.vma.VmaUsage,
        vmaReqFlags: vk.vma.VmaMemoryFlags,
    ) !VkBuffer {
        const createInfo = vulkan.BufferCreateInfo{
            .size = size,
            .usage = bufferUsage,
            .sharing_mode = vulkan.SharingMode.exclusive,
        };

        const allocInfo = vma.VmaAllocationCreateInfo{
            .flags = vmaFlags,
            .usage = @intFromEnum(vmaUsage),
            .requiredFlags = @intFromEnum(vmaReqFlags),
        };

        var buffer: vulkan.Buffer = undefined;
        var allocation: vma.VmaAllocation = undefined;
        var allocation_info: vma.VmaAllocationInfo = undefined;
        if (vma.vmaCreateBuffer(
            vkCtx.vkVmaAlloc.vmaAlloc,
            @ptrCast(&createInfo),
            &allocInfo,
            @ptrCast(&buffer),
            &allocation,
            &allocation_info,
        ) != 0) {
            @panic("Failed to create buffer");
        }
        return .{
            .size = size,
            .buffer = buffer,
            .allocation = allocation,
            .mappedData = allocation_info.pMappedData,
        };
    }

    pub fn cleanup(self: *const VkBuffer, vkCtx: *const vk.ctx.VkCtx) void {
        const c_buffer: vma.VkBuffer = @ptrFromInt(@intFromEnum(self.buffer));
        vma.vmaDestroyBuffer(vkCtx.vkVmaAlloc.vmaAlloc, c_buffer, self.allocation);
    }

    pub fn flush(self: *const VkBuffer, vkCtx: *const vk.ctx.VkCtx) void {
        _ = vma.vmaFlushAllocation(vkCtx.vkVmaAlloc.vmaAlloc, self.allocation, 0, self.size);
    }

    pub fn map(self: *const VkBuffer, vkCtx: *const vk.ctx.VkCtx) !?*anyopaque {
        var mappedPtr: ?*anyopaque = null;
        if (vma.vmaMapMemory(vkCtx.vkVmaAlloc.vmaAlloc, self.allocation, &mappedPtr) != 0) {
            @panic("Failed to map memory");
        }
        return mappedPtr orelse error.NullPointerReturned;
    }

    pub fn unMap(self: *const VkBuffer, vkCtx: *const vk.ctx.VkCtx) void {
        vma.vmaUnmapMemory(vkCtx.vkVmaAlloc.vmaAlloc, self.allocation);
    }
};

pub fn copyDataToBuffer(vkCtx: *const vk.ctx.VkCtx, vkBuffer: *const VkBuffer, data: *const []const u8) !void {
    const buffData = try vkBuffer.map(vkCtx);
    defer vkBuffer.unMap(vkCtx);

    const gpuBytes: [*]u8 = @ptrCast(buffData);

    @memcpy(gpuBytes[0..data.len], data.ptr);
}
