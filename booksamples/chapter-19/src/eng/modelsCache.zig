const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const log = std.log.scoped(.eng);
const zm = @import("zmath");

const MaterialBuffRecord = struct {
    diffuseColor: zm.Vec,
    hasTexture: u32,
    textureIdx: u32,
    hasNormalMap: u32,
    normalMapIdx: u32,
    hasRoughMap: u32,
    roughMapIdx: u32,
    metallicFactor: f32,
    roughFactor: f32,
};

pub const VulkanAnimation = struct {
    id: []const u8,
    buffers: std.ArrayList(vk.buf.VkBuffer),

    pub fn cleanup(self: *VulkanAnimation, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        allocator.free(self.id);
        for (self.buffers.items) |buffer| {
            buffer.cleanup(vkCtx);
        }
        self.buffers.deinit(allocator);
    }
};

pub const VulkanMesh = struct {
    buffIdx: vk.buf.VkBuffer,
    buffVtx: vk.buf.VkBuffer,
    buffWeights: ?vk.buf.VkBuffer,
    id: []const u8,
    materialId: []const u8,
    numIndices: usize,

    pub fn cleanup(self: *const VulkanMesh, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        self.buffVtx.cleanup(vkCtx);
        self.buffIdx.cleanup(vkCtx);
        if (self.buffWeights) |buffWeights| {
            buffWeights.cleanup(vkCtx);
        }
        allocator.free(self.id);
        allocator.free(self.materialId);
    }
};

pub const VulkanModel = struct {
    id: []const u8,
    meshes: std.ArrayList(VulkanMesh),
    animations: std.ArrayList(VulkanAnimation),

    pub fn cleanup(self: *VulkanModel, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        allocator.free(self.id);
        for (self.meshes.items) |mesh| {
            mesh.cleanup(allocator, vkCtx);
        }
        self.meshes.deinit(allocator);
        for (self.animations.items) |*anim| {
            anim.cleanup(allocator, vkCtx);
        }
        self.animations.deinit(allocator);
    }

    pub fn hasAnimations(self: *const VulkanModel) bool {
        return self.animations.items.len > 0;
    }
};

pub const VulkanMaterial = struct {
    id: []const u8,
    transparent: bool,

    pub fn cleanup(self: *VulkanMaterial, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
    }
};

pub const MaterialsCache = struct {
    materialsMap: std.StringArrayHashMapUnmanaged(VulkanMaterial),
    materialsBuffer: ?vk.buf.VkBuffer,

    pub fn cleanup(self: *MaterialsCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        var iter = self.materialsMap.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.cleanup(allocator);
        }
        self.materialsMap.deinit(allocator);
        if (self.materialsBuffer) |buff| {
            buff.cleanup(vkCtx);
        }
    }

    pub fn create() MaterialsCache {
        const materialsMap: std.StringArrayHashMapUnmanaged(VulkanMaterial) = .empty;
        return .{
            .materialsMap = materialsMap,
            .materialsBuffer = null,
        };
    }

    pub fn init(
        self: *MaterialsCache,
        allocator: std.mem.Allocator,
        io: std.Io,
        vkCtx: *const vk.ctx.VkCtx,
        textureCache: *eng.tcach.TextureCache,
        cmdPool: *vk.cmd.VkCmdPool,
        vkQueue: vk.queue.VkQueue,
        initData: *const eng.engine.InitData,
    ) !void {
        // Create a copy an add default material at first position
        var materialsList = try std.ArrayList(*eng.mdata.MaterialData).initCapacity(
            allocator,
            initData.materials.items.len + 1,
        );
        defer materialsList.deinit(allocator);
        var defaultMaterial = eng.mdata.MaterialData{
            .color = [_]f32{ 1, 1, 1, 1 },
            .id = "DEFAULT_MATERIAL_ID",
            .texturePath = "",
            .normalMapPath = "",
            .metalRoughMapPath = "",
            .metallicFactor = 0,
            .roughFactor = 0,
        };
        try materialsList.append(allocator, &defaultMaterial);
        for (initData.materials.items) |*materialData| {
            try materialsList.append(allocator, materialData);
        }

        const numMaterials = materialsList.items.len;
        log.debug("Loading {d} material(s)", .{numMaterials});
        const cmdBuff = try vk.cmd.VkCmdBuff.create(vkCtx, cmdPool, true);
        const cmdHandle = cmdBuff.cmdBuffProxy.handle;

        const buffSize = numMaterials * @sizeOf(MaterialBuffRecord);
        const srcBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            buffSize,
            vulkan.BufferUsageFlags{ .transfer_src_bit = true },
            @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
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
        const data = try srcBuffer.map(vkCtx);
        defer srcBuffer.unMap(vkCtx);
        const mappedData: [*]MaterialBuffRecord = @ptrCast(@alignCast(data));

        for (materialsList.items, 0..) |materialData, i| {
            const materialId = try allocator.dupe(u8, materialData.id);
            var vulkanMaterial = VulkanMaterial{
                .id = materialId,
                .transparent = false,
            };
            var hasTexture: u32 = 0;
            var textureIdx: u32 = 0;
            if (materialData.texturePath.len > 0) {
                const nullTermPath = try allocator.dupeZ(u8, materialData.texturePath);
                defer allocator.free(nullTermPath);
                if (try textureCache.addTextureFromPath(allocator, io, vkCtx, vulkan.Format.r8g8b8a8_srgb, nullTermPath)) {
                    if (textureCache.textureMap.getIndex(nullTermPath)) |idx| {
                        textureIdx = @as(u32, @intCast(idx));
                        hasTexture = 1;
                        vulkanMaterial.transparent = textureCache.textureMap.get(nullTermPath).?.transparent;
                    } else {
                        log.warn("Could not find texture added to the cache [{s}]", .{materialData.texturePath});
                    }
                }
            }
            var hasNormalMap: u32 = 0;
            var normalMapIdx: u32 = 0;
            if (materialData.normalMapPath.len > 0) {
                const nullTermPath = try allocator.dupeZ(u8, materialData.normalMapPath);
                defer allocator.free(nullTermPath);
                if (try textureCache.addTextureFromPath(allocator, io, vkCtx, vulkan.Format.r8g8b8a8_unorm, nullTermPath)) {
                    if (textureCache.textureMap.getIndex(nullTermPath)) |idx| {
                        normalMapIdx = @as(u32, @intCast(idx));
                        hasNormalMap = 1;
                    } else {
                        log.warn("Could not find normal map texture added to the cache [{s}]", .{materialData.normalMapPath});
                    }
                }
            }
            var hasRoughMap: u32 = 0;
            var roughMapIdx: u32 = 0;
            if (materialData.metalRoughMapPath.len > 0) {
                const nullTermPath = try allocator.dupeZ(u8, materialData.metalRoughMapPath);
                defer allocator.free(nullTermPath);
                if (try textureCache.addTextureFromPath(allocator, io, vkCtx, vulkan.Format.r8g8b8a8_unorm, nullTermPath)) {
                    if (textureCache.textureMap.getIndex(nullTermPath)) |idx| {
                        roughMapIdx = @as(u32, @intCast(idx));
                        hasRoughMap = 1;
                    } else {
                        log.warn("Could not find rough metal texture added to the cache [{s}]", .{materialData.metalRoughMapPath});
                    }
                }
            }
            const atBuffRecord = MaterialBuffRecord{
                .diffuseColor = materialData.color,
                .hasTexture = hasTexture,
                .textureIdx = textureIdx,
                .hasNormalMap = hasNormalMap,
                .normalMapIdx = normalMapIdx,
                .hasRoughMap = hasRoughMap,
                .roughMapIdx = roughMapIdx,
                .metallicFactor = materialData.metallicFactor,
                .roughFactor = materialData.roughFactor,
            };
            mappedData[i] = atBuffRecord;
            try self.materialsMap.put(allocator, materialId, vulkanMaterial);
        }

        try cmdBuff.begin(vkCtx);
        recordTransfer(vkCtx, cmdHandle, &srcBuffer, &dstBuffer);
        try cmdBuff.end(vkCtx);
        try cmdBuff.submitAndWait(vkCtx, vkQueue);

        self.materialsBuffer = dstBuffer;
        log.debug("Loaded {d} material(s)", .{numMaterials});
    }
};

pub const ModelsCache = struct {
    modelsMap: std.StringHashMap(VulkanModel),

    pub fn cleanup(self: *ModelsCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        var iter = self.modelsMap.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.cleanup(allocator, vkCtx);
        }
        self.modelsMap.deinit();
    }

    pub fn create(allocator: std.mem.Allocator) ModelsCache {
        const modelsMap = std.StringHashMap(VulkanModel).init(allocator);
        return .{
            .modelsMap = modelsMap,
        };
    }

    fn createJointMatricesBuffers(
        vkCtx: *const vk.ctx.VkCtx,
        allocator: std.mem.Allocator,
        cmdHandle: vulkan.CommandBuffer,
        srcBuffers: *std.ArrayList(vk.buf.VkBuffer),
        animatedFrame: eng.mdata.AnimatedFrame,
    ) !vk.buf.VkBuffer {
        const numMatrices = animatedFrame.jointMatrices.len;
        const bufferSize = numMatrices * @sizeOf([16]f32);

        const srcJointBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .transfer_src_bit = true },
            @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        try srcBuffers.append(allocator, srcJointBuffer);

        const dstJointBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
            @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );

        const dataJoints = try srcJointBuffer.map(vkCtx);
        const gpuJoints: [*]u8 = @ptrCast(@alignCast(dataJoints));

        const identity = [16]f32{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        };
        for (animatedFrame.jointMatrices, 0..) |maybeMatrix, i| {
            const matrix = maybeMatrix orelse identity;
            @memcpy(gpuJoints[i * 64 .. i * 64 + 64], std.mem.sliceAsBytes(&matrix));
        }
        srcJointBuffer.unMap(vkCtx);

        recordTransfer(vkCtx, cmdHandle, &srcJointBuffer, &dstJointBuffer);

        return dstJointBuffer;
    }

    fn createWeightsBuffers(
        vkCtx: *const vk.ctx.VkCtx,
        allocator: std.mem.Allocator,
        cmdHandle: vulkan.CommandBuffer,
        srcBuffers: *std.ArrayList(vk.buf.VkBuffer),
        animMeshData: eng.mdata.AnimMeshData,
    ) !vk.buf.VkBuffer {
        const weights = animMeshData.weights;
        const boneIds = animMeshData.boneIds;
        const bufferSize = weights.len * @sizeOf(f32) + boneIds.len * @sizeOf(i32);

        const srcWeightsBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .transfer_src_bit = true },
            @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        try srcBuffers.append(allocator, srcWeightsBuffer);

        const dstWeightsBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .vertex_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
            @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );

        const dataWeights = try srcWeightsBuffer.map(vkCtx);
        const gpuWeights: [*]u8 = @ptrCast(@alignCast(dataWeights));

        const rows = weights.len / 4;
        var data = try allocator.alloc(f32, weights.len + boneIds.len);
        defer allocator.free(data);
        var dstPos: usize = 0;
        for (0..rows) |row| {
            const srcPos = row * 4;
            data[dstPos] = weights[srcPos];
            data[dstPos + 1] = weights[srcPos + 1];
            data[dstPos + 2] = weights[srcPos + 2];
            data[dstPos + 3] = weights[srcPos + 3];
            data[dstPos + 4] = @floatFromInt(boneIds[srcPos]);
            data[dstPos + 5] = @floatFromInt(boneIds[srcPos + 1]);
            data[dstPos + 6] = @floatFromInt(boneIds[srcPos + 2]);
            data[dstPos + 7] = @floatFromInt(boneIds[srcPos + 3]);
            dstPos += 8;
        }
        @memcpy(gpuWeights[0..bufferSize], std.mem.sliceAsBytes(data));
        srcWeightsBuffer.unMap(vkCtx);

        recordTransfer(vkCtx, cmdHandle, &srcWeightsBuffer, &dstWeightsBuffer);

        return dstWeightsBuffer;
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
        log.debug("Loading {d} model(s)", .{initData.models.len});

        const cmdBuff = try vk.cmd.VkCmdBuff.create(vkCtx, cmdPool, true);
        const cmdHandle = cmdBuff.cmdBuffProxy.handle;

        var srcBuffers = try std.ArrayList(vk.buf.VkBuffer).initCapacity(allocator, 1);
        defer srcBuffers.deinit(allocator);
        try cmdBuff.begin(vkCtx);

        for (initData.models) |*modelData| {
            const vtxData = try com.utils.loadFile(allocator, io, modelData.vtxFilename);
            defer allocator.free(vtxData);
            const idxData = try com.utils.loadFile(allocator, io, modelData.idxFilename);
            defer allocator.free(idxData);

            var vulkanAnimations = try std.ArrayList(VulkanAnimation).initCapacity(allocator, modelData.animations.items.len);
            for (modelData.animations.items) |animData| {
                var buffers = try std.ArrayList(vk.buf.VkBuffer).initCapacity(allocator, animData.frames.len);
                for (animData.frames) |frame| {
                    try buffers.append(allocator, try createJointMatricesBuffers(vkCtx, allocator, cmdHandle, &srcBuffers, frame));
                }
                try vulkanAnimations.append(allocator, .{
                    .id = try allocator.dupe(u8, animData.name),
                    .buffers = buffers,
                });
            }

            var vulkanMeshes = try std.ArrayList(VulkanMesh).initCapacity(allocator, modelData.meshes.items.len);
            var meshCount: usize = 0;
            for (modelData.meshes.items) |meshData| {
                const verticesSize = meshData.vtxSize;
                const srcVtxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    verticesSize,
                    vulkan.BufferUsageFlags{ .transfer_src_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
                );
                try srcBuffers.append(allocator, srcVtxBuffer);
                const dstVtxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    verticesSize,
                    vulkan.BufferUsageFlags{ .vertex_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );

                const dataVertices = try srcVtxBuffer.map(vkCtx);
                const gpuVertices: [*]u8 = @ptrCast(@alignCast(dataVertices));
                const endVtx = meshData.vtxOffset + meshData.vtxSize;
                @memcpy(gpuVertices, vtxData[meshData.vtxOffset..endVtx]);
                srcVtxBuffer.unMap(vkCtx);

                const indicesSize = meshData.idxSize;
                const srcIdxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    indicesSize,
                    vulkan.BufferUsageFlags{ .transfer_src_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
                );
                try srcBuffers.append(allocator, srcIdxBuffer);
                const dstIdxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    indicesSize,
                    vulkan.BufferUsageFlags{ .index_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true },
                    @intFromEnum(vk.vma.VmaFlags.DedicatedMemory),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );

                const dataIndices = try srcIdxBuffer.map(vkCtx);
                const gpuIndices: [*]u8 = @ptrCast(@alignCast(dataIndices));
                const endIdx = meshData.idxOffset + meshData.idxSize;
                @memcpy(gpuIndices, idxData[meshData.idxOffset..endIdx]);
                srcIdxBuffer.unMap(vkCtx);

                var buffWeights: ?vk.buf.VkBuffer = null;
                if (modelData.animMeshes.items.len > 0) {
                    buffWeights = try createWeightsBuffers(vkCtx, allocator, cmdHandle, &srcBuffers, modelData.animMeshes.items[meshCount]);
                }

                const vulkanMesh = VulkanMesh{
                    .buffIdx = dstIdxBuffer,
                    .buffVtx = dstVtxBuffer,
                    .buffWeights = buffWeights,
                    .id = try allocator.dupe(u8, meshData.id),
                    .materialId = try allocator.dupe(u8, meshData.materialId),
                    .numIndices = indicesSize / @sizeOf(u32),
                };
                try vulkanMeshes.append(allocator, vulkanMesh);

                recordTransfer(vkCtx, cmdHandle, &srcVtxBuffer, &dstVtxBuffer);
                recordTransfer(vkCtx, cmdHandle, &srcIdxBuffer, &dstIdxBuffer);

                meshCount += 1;
            }

            const vulkanModel = VulkanModel{
                .id = try allocator.dupe(u8, modelData.id),
                .meshes = vulkanMeshes,
                .animations = vulkanAnimations,
            };
            try self.modelsMap.put(try allocator.dupe(u8, modelData.id), vulkanModel);
        }

        try cmdBuff.end(vkCtx);
        try cmdBuff.submitAndWait(vkCtx, vkQueue);

        for (srcBuffers.items) |vkBuff| {
            vkBuff.cleanup(vkCtx);
        }

        log.debug("Loaded {d} model(s)", .{initData.models.len});
    }
};

fn recordTransfer(
    vkCtx: *const vk.ctx.VkCtx,
    cmdHandle: vulkan.CommandBuffer,
    srcBuff: *const vk.buf.VkBuffer,
    dstBuff: *const vk.buf.VkBuffer,
) void {
    const copyRegion = [_]vulkan.BufferCopy{.{
        .src_offset = 0,
        .dst_offset = 0,
        .size = srcBuff.size,
    }};
    vkCtx.vkDevice.deviceProxy.cmdCopyBuffer(cmdHandle, srcBuff.buffer, dstBuff.buffer, &copyRegion);
}
