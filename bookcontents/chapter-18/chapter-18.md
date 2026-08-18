# Buffer Device Address (BDA)

In this chapter we will use Buffer device address, which will allow us to refer to buffer virtual addresses in shaders instead of using
descriptor sets. This is very convenient to use a bind-less approach where we will access data as pointers to the associated buffer, and,
as a bonuis, it will simplify the code. The drawback is that any miss-use in setting the addresses may cause the GPU to crash.

You can find the complete source code for this chapter [here](../../booksamples/chapter-18).


## Enable BDA

First we need to enable Buffer Device Address (BDA) feature in the `VkDevice` struct. Since we will be passing pointers to the shaders,
which are 8 bytes long, we need also to enable `int64` feature:

**File: src/eng/vk/vkDevice.zig**
```zig
pub const VkDevice = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !VkDevice {
        ...
        const features2 = vulkan.PhysicalDeviceVulkan12Features{
            ...
            .buffer_device_address = vulkan.Bool32.true,
            ...
        };
        const features = vulkan.PhysicalDeviceFeatures{
            ...
            .shader_int_64 = vulkan.Bool32.true,
        };
        ...
    }
    ...
};
```

In order to get a device address from a buffer we need to use the `VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT` flag, in the `bufferUsage`
constructor parameter (`shader_device_address_bit`). We will create a new field in the struct to store the address for buffers created
wuth that usage flag:

**File: src/eng/vk/vkBuffer.zig**
```zig
pub const VkBuffer = struct {
    ...
    address: ?u64,
    ...
    pub fn create(
        vkCtx: *const vk.ctx.VkCtx,
        size: u64,
        bufferUsage: vulkan.BufferUsageFlags,
        vmaFlags: u32,
        vmaUsage: vk.vma.VmaUsage,
        vmaReqFlags: vk.vma.VmaMemoryFlags,
    ) !VkBuffer {
        ...
        var address: ?u64 = null;
        if (bufferUsage.shader_device_address_bit) {
            address = getBufferAddress(vkCtx, buffer);
        }

        return .{
            ...
            .address = address,
        };
        ...
    }
    ...
    pub fn getBufferAddress(vkCtx: *const vk.ctx.VkCtx, buffer: vulkan.Buffer) u64 {
        const info = vulkan.BufferDeviceAddressInfo{
            .buffer = buffer,
        };
        return vkCtx.vkDevice.deviceProxy.getBufferDeviceAddress(&info);
    }
    ...    
};
```


We have defined a new function, named `getBufferAddress` which inviokes the `getBufferDeviceAddress` function to get its address.

Since we are allocating memory with [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator), we need to enable that
feature in VMA allocator using the `VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT` flag:

**File: src/eng/vk/vma.zig**
```zig
pub const VmaFlags = enum(u32) {
    ...
    DedicatedMemory = vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
};
...
pub const VkVmaAlloc = struct {
    ...
    pub fn create(vkInstance: vke.inst.VkInstance, vkPhysDevice: vke.phys.VkPhysDevice, vkDevice: vke.dev.VkDevice) VkVmaAlloc {
        ...
        const createInfo = vma.VmaAllocatorCreateInfo{
            .flags = vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
            ...
        };
        ...
    }
    ...
};
```

We have defined a new flag, named `DedicatedMemory` since buffer where we will get their address will need to have set up this flag
when created.

## Scene render changes

Now we are ready to start using BDAs in our render stages, let's start with the scene render one. In order to understand the changes that
need to be done, we will examine first the vertex shader. This will help us to understand how BDA works from the GPU side and the changes
that are required in the Zig code. The vertex shader starts like this:

**File: res/shaders/scn_vtx.glsl**
```glsl
#version 450
#extension GL_EXT_buffer_reference: require
#extension GL_EXT_buffer_reference2: enable
#extension GL_EXT_scalar_block_layout: require
...
```
We first use several extensions required to use buffer addresses and to use scalar layouts for them. The next part is quite similar to the
ones used before. We just define output values and the uniforms we will use to store projection and view matrices.

**File: res/shaders/scn_vtx.glsl**
```glsl
...
layout(location = 0) out vec4 outPos;
layout(location = 1) out vec2 outTextCoords;
layout(location = 2) out vec3 outNormal;
layout(location = 3) out vec3 outTangent;
layout(location = 4) out vec3 outBitangent;

layout(set = 0, binding = 0) uniform CamUniform {
    mat4 projMatrix;
    mat4 viewMatrix;
} camUniform;
...
```

You may have noticed that we do not define the structure of vertex input attributes. We will not need that. Vertices information will be
passed to the shader as a buffer reference (like a pointer). We can define the internal structure if that buffer as a GLS struct, like this:

**File: res/shaders/scn_vtx.glsl**
```glsl
...
struct Vertex {
    vec3 inPos;
    vec2 inTextCoords;
    vec3 inNormal;
    vec3 inTangent;
    vec3 inBitangent;
};

layout(scalar, buffer_reference) buffer VertexBuffer {
    Vertex[] vertices;
};

layout(std430, buffer_reference) buffer IndexBuffer {
    uint[] indices;
};
...
```

We define two buffer references:
- VertexBuffer, which will contain vertices data.
- IndexBuffer, which will contain the indices to be drawn.

For the `VertexBuffer` we define a `Vertex` structure which defines how the data is organized in the buffer reference. The code continues
like this:

**File: res/shaders/scn_vtx.glsl**
```glsl
...
layout(push_constant) uniform pc {
    mat4 modelMatrix;
    VertexBuffer vertexBuffer;
    IndexBuffer indexBuffer;
} push_constants;

void main()
{
    uint index = push_constants.indexBuffer.indices[gl_VertexIndex];
    VertexBuffer vertexData = push_constants.vertexBuffer;

    Vertex vertex = vertexData.vertices[index];
    vec4 worldPos = push_constants.modelMatrix * vec4(vertex.inPos, 1);
    gl_Position   = camUniform.projMatrix * camUniform.viewMatrix * worldPos;
    mat3 mNormal  = transpose(inverse(mat3(push_constants.modelMatrix)));
    outPos        = worldPos;
    outTextCoords = vertex.inTextCoords;
    outNormal     = normalize(mNormal * vertex.inNormal);
    outTangent    = normalize(mNormal * vertex.inTangent);
    outBitangent  = normalize(mNormal * vertex.inBitangent);
}
```

In the push constants, in addition to the model matrix, we are passing the addresses of the vertices and indices buffers. We can access
those buffers, and access the  specific index by using the `gl_VertexIndex` built-in variable. This variable will contain the index of the
current vertex being processed by the vertex shader. With that value, we can get the specific vertex associated to that index and process
vertices data as in previous examples.

Since we have modified vertex push constants, we need to update the offset associated to the push constants data used in the fragment
shader:

**File: res/shaders/scn_vtx.glsl**
```glsl
...
layout(push_constant) uniform pc {
    layout(offset = 80) uint materialIdx;
} push_constants;
...
```

We will update now the `RenderScn` struct to adapt it to the changes in the shader:

**File: src/eng/renderScn.zig**
```zig
...
pub const VtxBuffDesc = struct {
    pub const binding_description = vulkan.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(VtxBuffDesc),
        .input_rate = .vertex,
    };

    pub const attribute_description = [_]vulkan.VertexInputAttributeDescription{};
};

const PushConstantsVtx = struct {
    modelMatrix: zm.Mat,
    vtxAddress: u64,
    idxAddress: u64,
};
...
pub const RenderScn = struct {
    ...
    fn renderEntities(
        self: *RenderScn,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
        materialsCache: *const eng.mcach.MaterialsCache,
        animsCache: *const eng.acach.AnimsCache,
        cmdHandle: vulkan.CommandBuffer,
        transparent: bool,
    ) void {
        const device = vkCtx.vkDevice.deviceProxy;
        var iter = engCtx.scene.entitiesMap.valueIterator();

        while (iter.next()) |entityRef| {
            ...
                    const vtxAddress: u64 = if (vm.hasAnimations())
                        (animsCache.getBuffer(entity.id, mesh.id).?.address orelse mesh.buffVtx.address.?)
                    else
                        mesh.buffVtx.address.?;
                    self.setPushConstants(
                        vkCtx,
                        cmdHandle,
                        entity,
                        vtxAddress,
                        mesh.buffIdx.address.?,
                        materialIdx,
                    );
                    device.cmdDraw(cmdHandle, @as(u32, @intCast(mesh.numIndices)), 1, 0, 0);            
        }
        ...
    }
    ...
};
```

First of all, the `VtxBuffDesc` struct, the one that defines vertices structure is an empty place holder, we are not using input attributes
in the shader anymore. The `PushConstantsVtx` needs also to be updated to pass the vertices and indices buffer addresses. The biggest
change is in the `renderEntities` function. There are no calls to `vkCmdBindVertexBuffers` and `vkCmdBindIndexBuffer` functions. Drawing is
triggered by calling `vkCmdDraw` instead of calling `vkCmdDrawIndexed`.

The `setPushConstants` function needs also to be updated to pass the addresses of the buffers as push constants, instead of relying on
binding them:


**File: res/shaders/scn_vtx.glsl**
```glsl
...
layout(push_constant) uniform pc {
    mat4 modelMatrix;
    VertexBuffer vertexBuffer;
    IndexBuffer indexBuffer;
} push_constants;

void main()
{
    uint index = push_constants.indexBuffer.indices[gl_VertexIndex];
    VertexBuffer vertexData = push_constants.vertexBuffer;

    Vertex vertex = vertexData.vertices[index];
    vec4 worldPos = push_constants.modelMatrix * vec4(vertex.inPos, 1);
    gl_Position   = camUniform.projMatrix * camUniform.viewMatrix * worldPos;
    mat3 mNormal  = transpose(inverse(mat3(push_constants.modelMatrix)));
    outPos        = worldPos;
    outTextCoords = vertex.inTextCoords;
    outNormal     = normalize(mNormal * vertex.inNormal);
    outTangent    = normalize(mNormal * vertex.inTangent);
    outBitangent  = normalize(mNormal * vertex.inBitangent);
}
```

In the push constants, in addition to the model matrix, we are passing the addresses of the vertices and indices buffers. We can access
those buffers, and access the  specific index by using the `gl_VertexIndex` built-in variable. This variable will contain the index of the
current vertex being processed by the vertex shader. With that value, we can get the specific vertex associated to that index and process
vertices data as in previous examples.

Since we have modified vertex push constants, we need to update the offset associated to the push constants data used in the fragment
shader:

**File: res/shaders/scn_vtx.glsl**
```glsl
...
layout(push_constant) uniform pc {
    layout(offset = 80) uint materialIdx;
} push_constants;
...
```

We will update now the `RenderScn` struct to adapt it to the changes in the shader:

**File: src/eng/renderScn.zig**
```zig
pub const RenderScn = struct {
    ...
    fn setPushConstants(
        self: *RenderScn,
        vkCtx: *const vk.ctx.VkCtx,
        cmdHandle: vulkan.CommandBuffer,
        entity: *eng.ent.Entity,
        vtxAddress: u64,
        idxAddress: u64,
        materialIdx: u32,
    ) void {
        const pushConstantsVtx = PushConstantsVtx{
            .modelMatrix = entity.modelMatrix,
            .vtxAddress = vtxAddress,
            .idxAddress = idxAddress,
        };
        ...
    }
    ...
};
```

## Shadow render changes

Changes in the shadow render stage are quite similar. We need to update the vertex shader  to use buffer references:

**File: res/shaders/shadow_vtx.glsl**
```glsl
#version 450
#extension GL_EXT_buffer_reference: require
#extension GL_EXT_buffer_reference2: enable
#extension GL_EXT_scalar_block_layout: require
#extension GL_EXT_multiview : enable

#define SHADOW_MAP_CASCADE_COUNT 3

struct Vertex {
    vec3 inPos;
    vec2 inTextCoords;
    vec3 inNoral ;
    vec3 inTangent;
    vec3 inBitangent;
};

layout(scalar, buffer_reference) buffer VertexBuffer {
    Vertex[] vertices;
};

layout(std430, buffer_reference) buffer IndexBuffer {
    uint[] indices;
};

struct InstanceData {
    mat4 modelMatrix;
    uint materialIdx;
    uint padding[3];
};

layout(push_constant, scalar) uniform matrices {
    mat4 modelMatrix;
    uint materialIdx;
    VertexBuffer vertexBuffer;
    IndexBuffer indexBuffer;
} push_constants;

layout (location = 0) out vec2 outTextCoord;
layout (location = 1) out flat uint outMaterialIdx;

layout(set = 0, binding = 0) uniform ProjUniforms {
    mat4 projViewMatrices[SHADOW_MAP_CASCADE_COUNT];
} projUniforms;

void main()
{
    uint index = push_constants.indexBuffer.indices[gl_VertexIndex];
    VertexBuffer vertexData = push_constants.vertexBuffer;
    Vertex vertex = vertexData.vertices[index];

    outTextCoord   = vertex.inTextCoords;
    outMaterialIdx = push_constants.materialIdx;

    vec4 worldPos = push_constants.modelMatrix * vec4(vertex.inPos, 1.0f);
    gl_Position = projUniforms.projViewMatrices[gl_ViewIndex] * worldPos;
}
```

Changes are similar to the ones applied in scene vertex shader, we just remove input attributes and use buffer references passed in the
push constantes. We need also to modify the `RenderShadow` struct in the same way as the `ScnRenderScnRender` one:

**File: src/eng/renderShadow.zig**
```zig
const PushConstantsVtx = extern struct {
    ...
    vtxAddress: u64,
    idxAddress: u64,
};
...
pub const RenderShadow = struct {
    ...
    fn renderEntities(
        self: *RenderShadow,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
        materialsCache: *const eng.mcach.MaterialsCache,
        animsCache: *const eng.acach.AnimsCache,
        cmdHandle: vulkan.CommandBuffer,
    ) void {
        const device = vkCtx.vkDevice.deviceProxy;
        var iter = engCtx.scene.entitiesMap.valueIterator();

        while (iter.next()) |entityRef| {
            ...
                    const vtxAddress: u64 = if (vm.hasAnimations())
                        (animsCache.getBuffer(entity.id, mesh.id).?.address orelse mesh.buffVtx.address.?)
                    else
                        mesh.buffVtx.address.?;
                    self.setPushConstants(
                        vkCtx,
                        cmdHandle,
                        entity,
                        vtxAddress,
                        mesh.buffIdx.address.?,
                        materialIdx,
                    );
                    device.cmdDraw(cmdHandle, @as(u32, @intCast(mesh.numIndices)), 1, 0, 0);
            ...
        }
        ...
    }
    ...
    fn setPushConstants(
        self: *RenderShadow,
        vkCtx: *const vk.ctx.VkCtx,
        cmdHandle: vulkan.CommandBuffer,
        entity: *eng.ent.Entity,
        vtxAddress: u64,
        idxAddress: u64,
        materialIdx: u32,
    ) void {
        const pushConstantsVtx = PushConstantsVtx{
            .modelMatrix = entity.modelMatrix,
            .materialIdx = materialIdx,
            .vtxAddress = vtxAddress,
            .idxAddress = idxAddress,
        };
        ...
    }
    ...
};
```

## Animation render changes

We will also buffer references in the animation compute shader:

**File: res/shaders/anim_comp.glsl**
```glsl
#version 450
#extension GL_EXT_buffer_reference: require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : enable


layout(std430, buffer_reference) buffer FloatBuf {
    float data[];
};

layout(std430, buffer_reference) buffer MatricesBuf {
    mat4[] data;
};

layout (local_size_x=32, local_size_y=1, local_size_z=1) in;

layout(push_constant) uniform Pc {
    FloatBuf srcBuf;
    FloatBuf weightsBuf;
    MatricesBuf jointsBuf;
    FloatBuf dstBuf;
    uint64_t srcBuffFloatSize;
} pc;

void main()
{
    int baseIdxSrcBuf = int(gl_GlobalInvocationID.x) * 14;
    if ( baseIdxSrcBuf >= pc.srcBuffFloatSize) {
        return;
    }
    int baseIdxWeightsBuf  = int(gl_GlobalInvocationID.x) * 8;

    vec4 weights = vec4(pc.weightsBuf.data[baseIdxWeightsBuf], pc.weightsBuf.data[baseIdxWeightsBuf + 1], pc.weightsBuf.data[baseIdxWeightsBuf + 2], pc.weightsBuf.data[baseIdxWeightsBuf + 3]);
    ivec4 joints = ivec4(pc.weightsBuf.data[baseIdxWeightsBuf + 4], pc.weightsBuf.data[baseIdxWeightsBuf + 5], pc.weightsBuf.data[baseIdxWeightsBuf + 6], pc.weightsBuf.data[baseIdxWeightsBuf + 7]);

    vec4 position = vec4(pc.srcBuf.data[baseIdxSrcBuf], pc.srcBuf.data[baseIdxSrcBuf + 1], pc.srcBuf.data[baseIdxSrcBuf + 2], 1);
    position =
    weights.x * pc.jointsBuf.data[joints.x] * position +
    weights.y * pc.jointsBuf.data[joints.y] * position +
    weights.z * pc.jointsBuf.data[joints.z] * position +
    weights.w * pc.jointsBuf.data[joints.w] * position;
    pc.dstBuf.data[baseIdxSrcBuf] = position.x / position.w;
    pc.dstBuf.data[baseIdxSrcBuf + 1] = position.y / position.w;
    pc.dstBuf.data[baseIdxSrcBuf + 2] = position.z / position.w;

    baseIdxSrcBuf += 3;
    vec2 textCoords = vec2(pc.srcBuf.data[baseIdxSrcBuf], pc.srcBuf.data[baseIdxSrcBuf + 1]);
    pc.dstBuf.data[baseIdxSrcBuf] = textCoords.x;
    pc.dstBuf.data[baseIdxSrcBuf + 1] = textCoords.y;

    mat3 matJoint1 = mat3(transpose(inverse(pc.jointsBuf.data[joints.x])));
    mat3 matJoint2 = mat3(transpose(inverse(pc.jointsBuf.data[joints.y])));
    mat3 matJoint3 = mat3(transpose(inverse(pc.jointsBuf.data[joints.z])));
    mat3 matJoint4 = mat3(transpose(inverse(pc.jointsBuf.data[joints.w])));
    baseIdxSrcBuf += 2;
    vec3 normal = vec3(pc.srcBuf.data[baseIdxSrcBuf], pc.srcBuf.data[baseIdxSrcBuf + 1], pc.srcBuf.data[baseIdxSrcBuf + 2]);
    normal =
    weights.x * matJoint1 * normal +
    weights.y * matJoint2 * normal +
    weights.z * matJoint3 * normal +
    weights.w * matJoint4 * normal;
    normal = normalize(normal);
    pc.dstBuf.data[baseIdxSrcBuf] = normal.x;
    pc.dstBuf.data[baseIdxSrcBuf + 1] = normal.y;
    pc.dstBuf.data[baseIdxSrcBuf + 2] = normal.z;

    baseIdxSrcBuf += 3;
    vec3 tangent = vec3(pc.srcBuf.data[baseIdxSrcBuf], pc.srcBuf.data[baseIdxSrcBuf + 1], pc.srcBuf.data[baseIdxSrcBuf + 2]);
    tangent =
    weights.x * matJoint1 * tangent +
    weights.y * matJoint2 * tangent +
    weights.z * matJoint3 * tangent +
    weights.w * matJoint4 * tangent;
    tangent = normalize(tangent);
    pc.dstBuf.data[baseIdxSrcBuf] = tangent.x;
    pc.dstBuf.data[baseIdxSrcBuf + 1] = tangent.y;
    pc.dstBuf.data[baseIdxSrcBuf + 2] = tangent.z;

    baseIdxSrcBuf += 3;
    vec3 bitangent = vec3(pc.srcBuf.data[baseIdxSrcBuf], pc.srcBuf.data[baseIdxSrcBuf + 1], pc.srcBuf.data[baseIdxSrcBuf + 2]);
    bitangent =
    weights.x * matJoint1 * bitangent +
    weights.y * matJoint2 * bitangent +
    weights.z * matJoint3 * bitangent +
    weights.w * matJoint4 * bitangent;
    bitangent = normalize(bitangent);
    pc.dstBuf.data[baseIdxSrcBuf] = bitangent.x;
    pc.dstBuf.data[baseIdxSrcBuf + 1] = bitangent.y;
    pc.dstBuf.data[baseIdxSrcBuf + 2] = bitangent.z;
}
```

We will pass the addresses of the following buffers as push constants:
- The buffer that will contain binding pose vertices (`srcBuf`).
- The buffer that stores weights information (`weightsBuf`).
- The buffer that stores joint transformation matrices (`jointsBuf`).
- The buffer where we will dump the transformed vertices (`dstBuf`). This buffer is the one that will be used in the scene render stage.
- The size of the vertex buffer (`srcBuffFloatSize`).


You may have noticed that we first check if we are accessing indices above the size of the vertices buffer (`srcBuffFloatSize`). This is
very important when using BDA to prevent crashing the GPU by accessing illegal addresses. The rest of the code is quite similar,
instead of relying in storage buffers, we access them through their references. 

All these changes will simplify a lot the `RenderAnim` struct, since we do not need to create descriptor sets for all the potential buffer
combinations per animated model and animated frames. We will need to create a buffer for push constants and properly set the push constants
size when creating the pipeline:

**File: src/eng/renderAnim.zig**
```zig
const PushConstants = struct {
    srcBufAddr: u64,
    weightsBufAddr: u64,
    jointsBufAddr: u64,
    dstBufAddr: u64,
    srcBuffFloatSize: u64,
};

pub const RenderAnim = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, io: std.Io, vkCtx: *const vk.ctx.VkCtx) !RenderAnim {
        ...
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
        ...
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
        ...
        while (iter.next()) |entityRef| {
            ...
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
        ...
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
```

The `init` function has been simplified a lot since we do not need to create descriptor sets for all the buffers, we just need to keep the
code that associates group sizes to each mesh. In the `render` function, we just need to get access to the addresses of the buffers instead
of binding associated descriptor sets. Finally, we need to pass the buffer addresses as push constants using the `setPushConstants`
function.

## Final changes

We still have one important change to apply, all the buffers that are passed as references need to be created with the
`VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT` flag. This affects the `ModelsCache` struct:

**File: src/eng/modelsCache.zig**
```zig
pub const MaterialsCache = struct {
    ...
    fn createJointMatricesBuffers(
        vkCtx: *const vk.ctx.VkCtx,
        allocator: std.mem.Allocator,
        cmdHandle: vulkan.CommandBuffer,
        srcBuffers: *std.ArrayList(vk.buf.VkBuffer),
        animatedFrame: eng.mdata.AnimatedFrame,
    ) !vk.buf.VkBuffer {
        ...
        const dstJointBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
            @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );
        ...
    }

    fn createWeightsBuffers(
        vkCtx: *const vk.ctx.VkCtx,
        allocator: std.mem.Allocator,
        cmdHandle: vulkan.CommandBuffer,
        srcBuffers: *std.ArrayList(vk.buf.VkBuffer),
        animMeshData: eng.mdata.AnimMeshData,
    ) !vk.buf.VkBuffer {
        ...
        const dstWeightsBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .vertex_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
            @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );
        ...
    }

    pub fn init(
        self: *ModelsCache,
        allocator: std.mem.Allocator,
        io: std.Io,
        vkCtx: *const vk.ctx.VkCtx,
        cmdPool: *vk.cmd.VkCmdPool,
        vkQueue: vk.queue.VkQueue,
        initData: *const eng.engine.InitData,
    ) !void {
        ...
                const dstVtxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    verticesSize,
                    vulkan.BufferUsageFlags{ .vertex_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
                ...
                const dstIdxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    indicesSize,
                    vulkan.BufferUsageFlags{ .index_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
        ...
    }
    ...
};
```

These changes also affect the `AnimsCache` struct:

**File: src/eng/animsCache.zig**
```zig
pub const AnimsCache = struct {
    ...
    pub fn init(
        self: *AnimsCache,
        allocator: std.mem.Allocator,
        vkCtx: *const vk.ctx.VkCtx,
        engCtx: *const eng.engine.EngCtx,
        modelsCache: *const eng.mcach.ModelsCache,
    ) !void {
        ...
                const animBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    vulkanMesh.buffVtx.size,
                    .{ .vertex_buffer_bit = true, .storage_buffer_bit = true, .shader_device_address_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.None),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
                try bufferMap.put(allocator, vulkanMesh.id, animBuffer);
        ...
    }
};
```

Finally, we just need to update the `Render` struct to adapt to the signature changes of some of the `Render*` struct functions:

**File: src/eng/render.zig**
```zig
pub const Render = struct {
    ...
    pub fn init(self: *Render, engCtx: *eng.engine.EngCtx, initData: *const eng.engine.InitData) !void {
        ...
        try self.renderAnim.init(&self.modelsCache);
        ...
    }

    pub fn render(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        ...
        try self.renderAnim.render(
            &self.vkCtx,
            engCtx,
            &self.modelsCache,
            &self.animsCache,
        );
        ...
    }
    ...
};
```

And that's all! I hope you will appreciate how these changes simplify code. By getting rid of descriptor sets (or at least some of them) we
already have an almost bind-less render.

[Back to Table of Contents](../README.md)

[Previous chapter](../chapter-17/chapter-17.md)