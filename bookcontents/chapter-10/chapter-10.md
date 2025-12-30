# Chapter 10 - Vulkan Memory Allocator

This will be a short chapter where we will introduce the VMA library which will help us with Vulkan memory allocation.

You can find the complete source code for this chapter [here](../../booksamples/chapter-10).

## Vulkan Memory Allocator (VMA)

[Vulkan Memory Allocator (VMA)](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) is a library that will help us to
allocate memory in Vulkan in an easier en more efficient way. The advantages that this library provides, as stated in the Github page,
are:

- Reduction of boilerplate code.
- Separation of elements that should be managed together (memory and buffers).
- Memory type selection is complex and needs to be adapted to different GPUs.
- Allocation if large chunks of memory is much more efficient than allocating small chunks individually.

IMHO, the biggest advantages are the last ones. VMA helps you in selecting the most appropriate type of memory and hides the complexity of
managing large buffers to accommodate individual allocations while preventing fragmentation. In addition to that, VMA does not prevent you
to still managing allocation in the pure Vulkan way in case you need it.


## Setting dependencies

In order to use VMA library you will need to add the following entry to the `build.zig.zon` file:

```
.{
    ...
    .dependencies = .{
        ...
        .vma = .{
            .url = "https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/archive/refs/tags/v3.3.0.tar.gz",
            .hash = "N-V-__8AAIutPgABk6NlXZhlJ5P8qVECvakZIKoO94h7xUOw",
        },
        ...
    }
    ...
}
```

We will need to add the VMA dependency in the `build.zig` file:

```zig
pub fn build(b: *std.Build) void {
    ...
    // VMA
    const vmaDep = b.dependency("vma", .{});
    const vmaIncludePath = vmaDep.path("include");
    ...
    vk.addIncludePath(vmaIncludePath);
    vk.addCSourceFile(.{ .file = b.path("src/eng/vk/vma.cpp"), .flags = &.{"-std=c++17"} });
    ...
}
```

You will see we add the usual dependency but we need to:
- Specify that the `include` directory in the VMA dependency shall be added to the path where Zig looks for C headers.
- Add a source file to properly link the symbols defined by the VMA header. This file needs to be created manually and is defined like this:

```c
#define VMA_IMPLEMENTATION
#define VMA_STATIC_VULKAN_FUNCTIONS 0
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 1
#include <vk_mem_alloc.h>
```

In this file we state that Vulkan symbols shall bel linked dynamically and we include the `vk_mem_alloc.h` header file that includes VMA
code.

## Memory allocator

We will create a new struct named `VkVmaAlloc` to handle the initialization of the VMA library. This struct will be defined in a new file:
`src/eng/vk/vma.zig` (Remember to include it in the `mod.zig` file: `pub const vma = @import("vma.zig");). It is defined like this:

```zig
const vke = @import("mod.zig");
pub const vma = @cImport({
    @cInclude("vk_mem_alloc.h");
});

pub const VmaFlags = enum(u32) {
    None = 0,
    VmaAllocationCreateHostAccessSSequentialWriteBit = vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
    CreateMappedBit = vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
};

pub const VmaUsage = enum(u32) {
    VmaUsageAuto = vma.VMA_MEMORY_USAGE_AUTO,
};

pub const VmaMemoryFlags = enum(u32) {
    None = 0,
    MemoryPropertyHostVisibleBitAndCoherent = vma.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vma.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
};

pub const VkVmaAlloc = struct {
    vmaAlloc: vma.VmaAllocator,

    pub fn create(vkInstance: vke.inst.VkInstance, vkPhysDevice: vke.phys.VkPhysDevice, vkDevice: vke.dev.VkDevice) VkVmaAlloc {
        const vulkanFuncs = vma.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(vkInstance.vkb.dispatch.vkGetInstanceProcAddr),
            .vkGetDeviceProcAddr = @ptrCast(vkInstance.instanceProxy.wrapper.dispatch.vkGetDeviceProcAddr),
        };

        const createInfo = vma.VmaAllocatorCreateInfo{
            .physicalDevice = @ptrFromInt(@intFromEnum(vkPhysDevice.pdev)),
            .device = @ptrFromInt(@intFromEnum(vkDevice.deviceProxy.handle)),
            .instance = @ptrFromInt(@intFromEnum(vkInstance.instanceProxy.handle)),
            .pVulkanFunctions = @ptrCast(&vulkanFuncs),
            .vulkanApiVersion = @bitCast(vulkan.API_VERSION_1_3),
        };
        var vmaAlloc: vma.VmaAllocator = undefined;
        if (vma.vmaCreateAllocator(&createInfo, &vmaAlloc) != 0)
            @panic("Failed to initialize VMA");
        return .{ .vmaAlloc = vmaAlloc };
    }

    pub fn cleanup(self: *const VkVmaAlloc) void {
        vma.vmaDestroyAllocator(self.vmaAlloc);
    }
};
```

The `create` function instantiates a VMA allocator by setting up a `VmaAllocatorCreateInfo` structure. In this structure we setup the
device and physical device handles and a `VmaVulkanFunctions` structure which provides the Vulkan functions references that this library
will use. It is very important to properly set the `vulkanApiVersion` to `vulkan.API_VERSION_1_3` (`VK_API_VERSION_1_3`). If you forget to
use this, since we are using Vulkan 1.3, you will find strange issues when allocating buffers.

In the file we define som convenience `enum`s to prevent the rest of the code to have to get access to VMA.

We will create an instance of the `VkVmaAlloc` in the `VkCtx` struct:

```zig
pub const VkCtx = struct {
    ...
    vkVmaAlloc: vk.vma.VkVmaAlloc,
    ...
    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !VkCtx {
        ...
        const vkVmaAlloc = vk.vma.VkVmaAlloc.create(vkInstance, vkPhysDevice, vkDevice);
        ...
        return .{
            ...
            .vkVmaAlloc = vkVmaAlloc,
            ...
        }
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) !void {
        self.vkVmaAlloc.cleanup();
        ...
    }
    ...
};
```

The next step is to modify the `VkBuffer` struct to use the VMA library. We will start with the attributes:

```zig
const vma = vk.vma.vma;

pub const VkBuffer = struct {
    size: u64,
    buffer: vulkan.Buffer,
    allocation: vma.VmaAllocation,
    mappedData: ?*anyopaque,
    ...
};
```

The `allocation` attribute is a handle to the allocated memory, which will be used later on to refer to that block and to perform the map
and unmap operations. This removes the need to have the memory handle. Let's review the changes in the `create` function:

```zig
pub const VkBuffer = struct {
    ...
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
    ...
};
```

The `create` function has split the old parameter `usage` flag into two: `bufferUsage` to control the buffer usage characteristics and
`vmaUsage` to tune the memory usage. Buffer creation information is almost identical with the exception of the utilization of the
`bufferUsage` parameter. To allocate the buffer memory using the VMA library we need to create a  `VmaAllocationCreateInfo` structure which
is defined by the following attributes:

- `requiredFlags`: This will control the memory requirements (For example if we are using the `VK_MEMORY_PROPERTY_HOST_COHERENT_BIT` flag).
It can have a value equal to `0` if this is specified in other way.
- `usage`: This will instruct the intended usage for this buffer. For example if it should be accessed only by the GPU
(`VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE`) or the CPU (`VMA_MEMORY_USAGE_AUTO_PREFER_HOST`). Regarding this attribute, the recommended approach
is to set it always to `VMA_MEMORY_USAGE_AUTO` and let VMA manage it for us.

After that, we call the `vmaCreateBuffer` function which creates the Vulkan buffer, allocates the memory for it and binds the buffer to the
allocated memory. The rest of the functions of the `VkBuffer` struct that need also to be modified are shown below:

```zig
pub const VkBuffer = struct {
    ...
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
```

We need to modify the way the buffer resources are freed. Since the buffer and the associated memory are created in a single call, we can
now free them by just calling the `vmaDestroyBuffer` function. Map and unmap operations also need to call VMA functions, `vmaMapMemory` for
mapping the memory and `vmaUnmapMemory` for un-mapping. We have added a new method to flush the contents of CPU mapped buffers if we do not
swant to use the coherent flag to do it automatically for us.


The code inside the `src/eng/vj/vkImage.zig` file needs to be highly modified, since the allocation mechanisms for images and the associated 
buffers change a lot when using VMA. We first need to define memory usage flags in the `VkImageData` struct:

```zig
...
const vma = vk.vma.vma;

pub const VkImageData = struct {
    ...
    memUsage: u32 = vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
    ...
};
```

The `VkImage` attributes need also to be modified. We no longer will ned keep track of the allocated memory but we will need to keep an
allocation handle, as in the case of the `VkBuffer` struct.

```zig
pub const VkImage = struct {
    image: vma.VkImage,
    allocation: vma.VmaAllocation,
    ...
};
```

The `create` function now looks like this:

```zig
pub const VkImage = struct {
    ...
    pub fn create(vkCtx: *const vk.ctx.VkCtx, vkImageData: VkImageData) !VkImage {
        const createInfo = vma.VkImageCreateInfo{
            .sType = vma.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vma.VK_IMAGE_TYPE_2D,
            .format = @as(c_uint, @intCast(@intFromEnum(vkImageData.format))),
            .extent = .{
                .width = vkImageData.width,
                .height = vkImageData.height,
                .depth = 1,
            },
            .mipLevels = vkImageData.mipLevels,
            .arrayLayers = vkImageData.arrayLayers,
            .samples = @as(c_uint, @intCast(vkImageData.sampleCount.toInt())),
            .initialLayout = vma.VK_IMAGE_LAYOUT_UNDEFINED,
            .sharingMode = vma.VK_SHARING_MODE_EXCLUSIVE,
            .usage = @as(c_uint, @intCast(vkImageData.usage.toInt())),
        };

        const allocCreateInfo = vma.VmaAllocationCreateInfo{
            .usage = vma.VMA_MEMORY_USAGE_AUTO,
            .flags = vkImageData.memUsage,
            .priority = 1.0,
        };

        var image: vma.VkImage = undefined;
        var allocation: vma.VmaAllocation = undefined;
        if (vma.vmaCreateImage(
            vkCtx.vkVmaAlloc.vmaAlloc,
            @ptrCast(&createInfo),
            @ptrCast(&allocCreateInfo),
            @ptrCast(&image),
            &allocation,
            null,
        ) != 0) {
            @panic("Failed to create image");
        }
        return .{
            .image = image,
            .allocation = allocation,
            .width = vkImageData.width,
            .height = vkImageData.height,
        };
    }
    ...
};
```

We now use a `VmaAllocationCreateInfo` structure with `VMA_MEMORY_USAGE_AUTO` usage value and the memory usage flags. The `vmaCreateImage`
function will take care of allocating and binding the memory.

We need to update also the `cleanup` function to use `vmaDestroyImage`:

```zig
pub const VkImage = struct {
    ...
    pub fn cleanup(self: *const VkImage, vkCtx: *const vk.ctx.VkCtx) void {
        vma.vmaDestroyImage(vkCtx.vkVmaAlloc.vmaAlloc, self.image, self.allocation);
    }
    ...
};
```

The next struct to be modified is the `VkTexture` one. This struct a buffer to store the texture image contents. Since the `VkBuffer`
`create` function has been modified, we need to update the the code to correctly specify the usage flags.

```zig
pub const VkTexture = struct {
    ...
    pub fn create(vkCtx: *const vk.ctx.VkCtx, vkTextureInfo: *const VkTextureInfo) !VkTexture {
        ...
        const image: vulkan.Image = @enumFromInt(@intFromPtr(vkImage.image));
        const vkImageView = try vk.imv.VkImageView.create(vkCtx.vkDevice, image, imageViewData);
        ...
        const vkStageBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            dataSize,
            vulkan.BufferUsageFlags{ .transfer_src_bit = true },
            @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        ...
    }
    ...
};
```

In this case, since it is a buffer that needs to be accessed by both CPU and GPU, we use the
`VmaAllocationCreateHostAccessSSequentialWriteBit` (`VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT`) and the
`MemoryPropertyHostVisibleBitAndCoherent` flags s(`VK_MEMORY_PROPERTY_HOST_COHERENT_BIT`). In addition to that we need to cast the
`VkImage` `image` handle so it can be used by the image view.

This cast needs to be applied whenever we use the image:

```zig
pub const VkTexture = struct {
    ...
    fn recordMipMap(self: *const VkTexture, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        ...
        const image: vulkan.Image = @enumFromInt(@intFromPtr(self.vkImage.image));
        ...
        var barrier = [_]vulkan.ImageMemoryBarrier2{.{
            ...
            .image = image,
        }};
        ...
        for (1..self.mipLevels) |i| {
            ...
            device.cmdBlitImage(
                cmdHandle,
                image,
                vulkan.ImageLayout.transfer_src_optimal,
                image,
                vulkan.ImageLayout.transfer_dst_optimal,
                imageBlit.len,
                &imageBlit,
                vulkan.Filter.linear,
            ); 
            ...
        }
        ...
        const endBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            ...
            .image = image,
        }};
    }

    pub fn recordTransition(self: *const VkTexture, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        ...
        const image: vulkan.Image = @enumFromInt(@intFromPtr(self.vkImage.image));
        const initBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            ...
            .image = image,
        }};
        ...
        device.cmdCopyBufferToImage(
            cmdHandle,
            self.vkStageBuffer.?.buffer,
            image,
            vulkan.ImageLayout.transfer_dst_optimal,
            region.len,
            &region,
        );
        ...
    }
};
```

The `ModelsCache` struct needs also to be updated with small changes due to the changes in `VkBuffer`:

```zig
pub const ModelsCache = struct {
    ...
    pub fn init(
        self: *ModelsCache,
        allocator: std.mem.Allocator,
        vkCtx: *const vk.ctx.VkCtx,
        cmdPool: *vk.cmd.VkCmdPool,
        vkQueue: vk.queue.VkQueue,
        initData: *const eng.engine.InitData,
    ) !void {
        ...
        for (initData.models) |*modelData| {
            ...
            for (modelData.meshes.items) |meshData| {
                ...
                const srcVtxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    verticesSize,
                    vulkan.BufferUsageFlags{ .transfer_src_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSSequentialWriteBit),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
                );
                try srcBuffers.append(allocator, srcVtxBuffer);
                const dstVtxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    verticesSize,
                    vulkan.BufferUsageFlags{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.None),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
                ...
                const srcIdxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    indicesSize,
                    vulkan.BufferUsageFlags{ .transfer_src_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSSequentialWriteBit),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
                );
                try srcBuffers.append(allocator, srcIdxBuffer);
                const dstIdxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    indicesSize,
                    vulkan.BufferUsageFlags{ .index_buffer_bit = true, .transfer_dst_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.None),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
                ...
            }
            ...
        }
        ...
    }
    ...
};
```

We need to update also the `MaterialsCache` struct:

```zig
pub const MaterialsCache = struct {
    ...
    pub fn init(
        self: *MaterialsCache,
        allocator: std.mem.Allocator,
        vkCtx: *const vk.ctx.VkCtx,
        textureCache: *eng.tcach.TextureCache,
        cmdPool: *vk.cmd.VkCmdPool,
        vkQueue: vk.queue.VkQueue,
        initData: *const eng.engine.InitData,
    ) !void {
        ...
        const srcBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            buffSize,
            vulkan.BufferUsageFlags{ .transfer_src_bit = true },
            @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        defer srcBuffer.cleanup(vkCtx);
        const dstBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            buffSize,
            vulkan.BufferUsageFlags{ .storage_buffer_bit = true, .transfer_dst_bit = true },
            @intFromEnum(vk.vma.VmaFlags.None),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );
        ...
    }
    ...
};
```

We need to update also the `src/eng/vk/vkUtils.zig` file to update the `createHostVisibleBuff`:

```zig
...
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
```

We need to update also the `RenderScn` struct to accommodate the way wew handel image handles now:

```zig
pub const RenderScn = struct {
    ...
    pub fn render(
        self: *RenderScn,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        vkCmd: vk.cmd.VkCmdBuff,
        modelsCache: *const eng.mcach.ModelsCache,
        materialsCache: *const eng.mcach.MaterialsCache,
        imageIndex: u32,
        frameIdx: u8,
    ) !void {
        ...
        const image: vulkan.Image = @enumFromInt(@intFromPtr(self.depthAttachments[imageIndex].vkImage.image));
        const initBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            ...
            .image = image,
        }};
        ...
    }    
    ...
};
```

Finally, we update the `Attachment` struct to properly handle image handles.

```zig
pub const Attachment = struct {
    ...
    pub fn create(vkCtx: *const vk.ctx.VkCtx, width: u32, height: u32, format: vulkan.Format, usage: vulkan.ImageUsageFlags) !Attachment {
        ...
        const image: vulkan.Image = @enumFromInt(@intFromPtr(vkImage.image));
        const vkImageView = try vk.imv.VkImageView.create(vkCtx.vkDevice, image, imageViewData);
        ...
    }
    ...
};
```