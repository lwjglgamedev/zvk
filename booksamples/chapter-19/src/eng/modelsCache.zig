const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const log = std.log.scoped(.eng);
const zm = @import("zmath");

pub const IND_COMMAND_STRIDE: u32 = @sizeOf(vulkan.DrawIndirectCommand);
const DEFAULT_NUM_COMMANDS: u32 = 100;
const instanceData_SIZE: u32 = @sizeOf(u32) * 2 + @sizeOf(u64) * 2;

pub const GlobalBuffers = struct {
    buffIndirectDrawCmds: [com.common.FRAMES_IN_FLIGHT]vk.buf.VkBuffer,
    buffInstanceData: [com.common.FRAMES_IN_FLIGHT]vk.buf.VkBuffer,
    buffModelMatrices: [com.common.FRAMES_IN_FLIGHT]vk.buf.VkBuffer,
    drawCounts: [com.common.FRAMES_IN_FLIGHT]u32,

    pub fn cleanup(self: *GlobalBuffers, vkCtx: *const vk.ctx.VkCtx) void {
        for (&self.buffIndirectDrawCmds) |buff| {
            buff.cleanup(vkCtx);
        }
        for (&self.buffInstanceData) |buff| {
            buff.cleanup(vkCtx);
        }
        for (&self.buffModelMatrices) |buff| {
            buff.cleanup(vkCtx);
        }
    }

    pub fn create(vkCtx: *vk.ctx.VkCtx) !GlobalBuffers {
        var buffIndirectDrawCmds: [com.common.FRAMES_IN_FLIGHT]vk.buf.VkBuffer = undefined;
        for (0..com.common.FRAMES_IN_FLIGHT) |i| {
            buffIndirectDrawCmds[i] = try vk.buf.VkBuffer.create(
                vkCtx,
                @as(u64, IND_COMMAND_STRIDE) * @as(u64, DEFAULT_NUM_COMMANDS),
                .{ .indirect_buffer = true, .storage_buffer = true },
                @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }

        var buffInstanceData: [com.common.FRAMES_IN_FLIGHT]vk.buf.VkBuffer = undefined;
        for (0..com.common.FRAMES_IN_FLIGHT) |i| {
            buffInstanceData[i] = try vk.buf.VkBuffer.create(
                vkCtx,
                @as(u64, DEFAULT_NUM_COMMANDS) * @as(u64, instanceData_SIZE),
                .{ .indirect_buffer = true, .storage_buffer = true },
                @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }

        var buffModelMatrices: [com.common.FRAMES_IN_FLIGHT]vk.buf.VkBuffer = undefined;
        for (0..com.common.FRAMES_IN_FLIGHT) |i| {
            buffModelMatrices[i] = try vk.buf.VkBuffer.create(
                vkCtx,
                @as(u64, DEFAULT_NUM_COMMANDS) * @as(u64, @sizeOf(zm.Mat)),
                .{ .indirect_buffer = true, .storage_buffer = true },
                @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }

        const drawCounts: [com.common.FRAMES_IN_FLIGHT]u32 = @splat(0);

        return .{
            .buffIndirectDrawCmds = buffIndirectDrawCmds,
            .buffInstanceData = buffInstanceData,
            .buffModelMatrices = buffModelMatrices,
            .drawCounts = drawCounts,
        };
    }

    fn createOrUpdateBuffers(
        self: *GlobalBuffers,
        vkCtx: *const vk.ctx.VkCtx,
        frame: usize,
        numIndCommands: u32,
        numInstanceData: u32,
        numEntities: u32,
    ) !void {
        const indCommandsSize: u64 =
            @as(u64, IND_COMMAND_STRIDE) * @as(u64, numIndCommands);

        if (self.buffIndirectDrawCmds[frame].size < indCommandsSize) {
            self.buffIndirectDrawCmds[frame].cleanup(vkCtx);
            self.buffIndirectDrawCmds[frame] = try vk.buf.VkBuffer.create(
                vkCtx,
                indCommandsSize,
                .{ .indirect_buffer = true, .storage_buffer = true },
                @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }
        self.drawCounts[frame] = numIndCommands;

        const instanceDataSize: u64 =
            @as(u64, numInstanceData) * @as(u64, instanceData_SIZE);

        if (self.buffInstanceData[frame].size < instanceDataSize) {
            self.buffInstanceData[frame].cleanup(vkCtx);
            self.buffInstanceData[frame] = try vk.buf.VkBuffer.create(
                vkCtx,
                instanceDataSize,
                .{ .storage_buffer = true, .shader_device_address = true },
                @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }

        const modelMatricesSize: u64 =
            @as(u64, numEntities) * @as(u64, @sizeOf(zm.Mat));

        if (self.buffModelMatrices[frame].size < modelMatricesSize) {
            self.buffModelMatrices[frame].cleanup(vkCtx);
            self.buffModelMatrices[frame] = try vk.buf.VkBuffer.create(
                vkCtx,
                modelMatricesSize,
                .{ .storage_buffer = true, .shader_device_address = true },
                @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                vk.vma.VmaUsage.VmaUsageAuto,
                vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
            );
        }
    }

    pub fn getAddrBufInstanceData(self: *const GlobalBuffers, frameIdx: usize) u64 {
        return self.buffInstanceData[frameIdx].address orelse 0;
    }

    pub fn getAddrBufModelMatrices(self: *const GlobalBuffers, frameIdx: usize) u64 {
        return self.buffModelMatrices[frameIdx].address orelse 0;
    }

    pub fn getDrawCount(self: *const GlobalBuffers, frameIdx: usize) u32 {
        return self.drawCounts[frameIdx];
    }

    pub fn getIndirectBuffer(self: *const GlobalBuffers, frameIdx: usize) *const vk.buf.VkBuffer {
        return &self.buffIndirectDrawCmds[frameIdx];
    }

    pub fn update(
        self: *GlobalBuffers,
        allocator: std.mem.Allocator,
        vkCtx: *const vk.ctx.VkCtx,
        scene: *eng.scn.Scene,
        modelsCache: *ModelsCache,
        animsCache: *eng.acach.AnimsCache,
        materialsCache: *MaterialsCache,
        frame: usize,
    ) !void {
        var arenaAlloc = std.heap.ArenaAllocator.init(allocator);
        defer arenaAlloc.deinit();
        const arena = arenaAlloc.allocator();

        var indCommandList: std.ArrayListUnmanaged(vulkan.DrawIndirectCommand) = .empty;

        var baseEntityIdx: u32 = 0;
        var numInstanceData: u32 = 0;
        var totalEntities: u32 = 0;

        var it = scene.entitiesMap.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const entities = entry.value_ptr.*;
            const numEntities: u32 = @intCast(entities.items.len);
            totalEntities += numEntities;

            const vulkanModel = modelsCache.modelsMap.get(key) orelse {
                log.warn("Model not found: {s}", .{key});
                continue;
            };
            const vulkanMeshList = vulkanModel.meshes.items;
            const numMeshes: u32 = @intCast(vulkanMeshList.len);

            if (vulkanModel.hasAnimations()) {
                var i: u32 = 0;
                while (i < numMeshes) : (i += 1) {
                    var j: u32 = 0;
                    while (j < numEntities) : (j += 1) {
                        const vulkanMesh = vulkanMeshList[i];
                        try indCommandList.append(arena, .{
                            .vertex_count = @intCast(vulkanMesh.numIndices),
                            .instance_count = 1,
                            .first_vertex = 0,
                            .first_instance = baseEntityIdx,
                        });
                        baseEntityIdx += 1;
                        numInstanceData += 1;
                    }
                }
            } else {
                var j: u32 = 0;
                while (j < numMeshes) : (j += 1) {
                    const vulkanMesh = vulkanMeshList[j];
                    try indCommandList.append(arena, .{
                        .vertex_count = @intCast(vulkanMesh.numIndices),
                        .instance_count = numEntities,
                        .first_vertex = 0,
                        .first_instance = baseEntityIdx,
                    });
                    baseEntityIdx += numEntities;
                    numInstanceData += numEntities;
                }
            }
        }

        try self.createOrUpdateBuffers(
            vkCtx,
            frame,
            @intCast(indCommandList.items.len),
            numInstanceData,
            totalEntities,
        );

        try self.updateCmdIndirectCommands(vkCtx, indCommandList.items, frame);
        try self.updateInstanceData(vkCtx, scene, modelsCache, materialsCache, animsCache, frame);
    }

    fn updateCmdIndirectCommands(
        self: *GlobalBuffers,
        vkCtx: *const vk.ctx.VkCtx,
        indCommandList: []const vulkan.DrawIndirectCommand,
        frame: usize,
    ) !void {
        const buffer = &self.buffIndirectDrawCmds[frame];
        const mapped = (try buffer.map(vkCtx)).?;
        const dst: [*]vulkan.DrawIndirectCommand = @ptrCast(@alignCast(mapped));

        for (indCommandList, 0..) |cmd, i| {
            dst[i] = cmd;
        }

        buffer.unMap(vkCtx);
    }

    fn updateInstanceData(
        self: *GlobalBuffers,
        vkCtx: *const vk.ctx.VkCtx,
        scene: *eng.scn.Scene,
        modelsCache: *ModelsCache,
        materialsCache: *MaterialsCache,
        animsCache: *eng.acach.AnimsCache,
        frame: usize,
    ) !void {
        var bufferInstances = &self.buffInstanceData[frame];
        const instanceData: [*]u8 = @ptrCast((try bufferInstances.map(vkCtx)).?);

        var bufferModels = &self.buffModelMatrices[frame];
        const matricesData: [*]u8 = @ptrCast((try bufferModels.map(vkCtx)).?);

        var baseEntities: u32 = 0;
        var offset: usize = 0;

        var it = scene.entitiesMap.iterator();
        while (it.next()) |entry| {
            const modelId = entry.key_ptr.*;
            const entities = entry.value_ptr.*;
            const numEntities: u32 = @intCast(entities.items.len);

            const vulkanModel = modelsCache.modelsMap.get(modelId) orelse {
                log.warn("Model not found: {s}", .{modelId});
                continue;
            };
            const animatedModel = vulkanModel.hasAnimations();
            const vulkanMeshList = vulkanModel.meshes.items;
            const numMeshes: u32 = @intCast(vulkanMeshList.len);

            var i: u32 = 0;
            while (i < numMeshes) : (i += 1) {
                const mesh = vulkanMeshList[i];
                var vtxBufferAddress: u64 = mesh.buffVtx.address.?;
                const idxBufferAddress: u64 = mesh.buffIdx.address.?;

                var j: u32 = 0;
                while (j < numEntities) : (j += 1) {
                    const entity = entities.items[j];
                    const entityIdx = baseEntities + j;

                    const modelMatrix = zm.matToArr(entity.modelMatrix);
                    const matrixBytes: []const u8 = std.mem.asBytes(&modelMatrix);
                    const matrixOffset = @as(usize, entityIdx) * @sizeOf(zm.Mat);
                    const matrixDst = matricesData + matrixOffset;
                    @memcpy(matrixDst[0..matrixBytes.len], matrixBytes);

                    std.mem.writeInt(u32, instanceData[offset..][0..4], entityIdx, .little);
                    offset += @sizeOf(u32);

                    const materialIdx: u32 = @intCast(
                        materialsCache.materialsMap.getIndex(mesh.materialId) orelse 0,
                    );
                    std.mem.writeInt(u32, instanceData[offset..][0..4], materialIdx, .little);
                    offset += @sizeOf(u32);

                    if (animatedModel) {
                        vtxBufferAddress = animsCache.getBuffer(entity.id, mesh.id).?.address.?;
                    }
                    std.mem.writeInt(u64, instanceData[offset..][0..8], vtxBufferAddress, .little);
                    offset += @sizeOf(u64);

                    std.mem.writeInt(u64, instanceData[offset..][0..8], idxBufferAddress, .little);
                    offset += @sizeOf(u64);
                }
            }
            baseEntities += numEntities;
        }

        bufferInstances.unMap(vkCtx);
        bufferModels.unMap(vkCtx);
    }
};

const MaterialBuffRecord = extern struct {
    diffuseColor: [4]f32,
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
        defer cmdBuff.cleanup(vkCtx, cmdPool);
        const cmdHandle = cmdBuff.cmdBuffProxy.handle;

        const buffSize = numMaterials * @sizeOf(MaterialBuffRecord);
        const srcBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            buffSize,
            vulkan.BufferUsageFlags{ .transfer_src = true },
            @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        defer srcBuffer.cleanup(vkCtx);
        const dstBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            buffSize,
            vulkan.BufferUsageFlags{ .storage_buffer = true, .transfer_dst = true },
            @backingInt(vk.vma.VmaFlags.None),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );
        errdefer dstBuffer.cleanup(vkCtx);
        const data = try srcBuffer.map(vkCtx);
        defer srcBuffer.unMap(vkCtx);
        const mappedData: [*]MaterialBuffRecord = @ptrCast(@alignCast(data));

        for (materialsList.items, 0..) |materialData, i| {
            const materialId = try allocator.dupe(u8, materialData.id);
            errdefer allocator.free(materialId);
            var vulkanMaterial = VulkanMaterial{
                .id = materialId,
                .transparent = false,
            };
            var hasTexture: u32 = 0;
            var textureIdx: u32 = 0;
            if (materialData.texturePath.len > 0) {
                const nullTermPath = try allocator.dupeSentinel(u8, materialData.texturePath, 0);
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
                const nullTermPath = try allocator.dupeSentinel(u8, materialData.normalMapPath, 0);
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
                const nullTermPath = try allocator.dupeSentinel(u8, materialData.metalRoughMapPath, 0);
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

    fn cleanupBufferList(allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, buffers: *std.ArrayList(vk.buf.VkBuffer)) void {
        for (buffers.items) |*buffer| {
            buffer.cleanup(vkCtx);
        }
        buffers.deinit(allocator);
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
            vulkan.BufferUsageFlags{ .transfer_src = true },
            @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        var appended = false;
        errdefer if (!appended) srcJointBuffer.cleanup(vkCtx);
        try srcBuffers.append(allocator, srcJointBuffer);
        appended = true;

        const dstJointBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .storage_buffer = true, .transfer_dst = true, .shader_device_address = true },
            @backingInt(vk.vma.VmaFlags.DedicatedMemory),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );
        errdefer dstJointBuffer.cleanup(vkCtx);

        const dataJoints = try srcJointBuffer.map(vkCtx);
        defer srcJointBuffer.unMap(vkCtx);
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
            vulkan.BufferUsageFlags{ .transfer_src = true },
            @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        var appended = false;
        errdefer if (!appended) srcWeightsBuffer.cleanup(vkCtx);
        try srcBuffers.append(allocator, srcWeightsBuffer);
        appended = true;

        const dstWeightsBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            bufferSize,
            vulkan.BufferUsageFlags{ .vertex_buffer = true, .storage_buffer = true, .transfer_dst = true, .shader_device_address = true },
            @backingInt(vk.vma.VmaFlags.DedicatedMemory),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.None,
        );
        errdefer dstWeightsBuffer.cleanup(vkCtx);

        const dataWeights = try srcWeightsBuffer.map(vkCtx);
        defer srcWeightsBuffer.unMap(vkCtx);
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
        defer cmdBuff.cleanup(vkCtx, cmdPool);
        const cmdHandle = cmdBuff.cmdBuffProxy.handle;

        var srcBuffers = try std.ArrayList(vk.buf.VkBuffer).initCapacity(allocator, 1);
        defer {
            for (srcBuffers.items) |*buffer| {
                buffer.cleanup(vkCtx);
            }
            srcBuffers.deinit(allocator);
        }
        try cmdBuff.begin(vkCtx);

        for (initData.models) |*modelData| {
            const vtxData = try com.utils.loadFile(allocator, io, modelData.vtxFilename);
            defer allocator.free(vtxData);
            const idxData = try com.utils.loadFile(allocator, io, modelData.idxFilename);
            defer allocator.free(idxData);

            var vulkanAnimations = try std.ArrayList(VulkanAnimation).initCapacity(allocator, modelData.animations.items.len);
            for (modelData.animations.items) |animData| {
                var buffers = try std.ArrayList(vk.buf.VkBuffer).initCapacity(allocator, animData.frames.len);
                errdefer cleanupBufferList(allocator, vkCtx, &buffers);
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
                    vulkan.BufferUsageFlags{ .transfer_src = true },
                    @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
                );
                var vtxAppended = false;
                errdefer if (!vtxAppended) srcVtxBuffer.cleanup(vkCtx);
                try srcBuffers.append(allocator, srcVtxBuffer);
                vtxAppended = true;
                const dstVtxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    verticesSize,
                    vulkan.BufferUsageFlags{ .vertex_buffer = true, .storage_buffer = true, .transfer_dst = true, .shader_device_address = true },
                    @backingInt(vk.vma.VmaFlags.DedicatedMemory),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
                errdefer dstVtxBuffer.cleanup(vkCtx);

                const dataVertices = try srcVtxBuffer.map(vkCtx);
                const gpuVertices: [*]u8 = @ptrCast(@alignCast(dataVertices));
                const endVtx = meshData.vtxOffset + meshData.vtxSize;
                @memcpy(gpuVertices, vtxData[meshData.vtxOffset..endVtx]);
                srcVtxBuffer.unMap(vkCtx);

                const indicesSize = meshData.idxSize;
                const srcIdxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    indicesSize,
                    vulkan.BufferUsageFlags{ .transfer_src = true },
                    @backingInt(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSequentialWriteBit),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
                );
                var idxAppended = false;
                errdefer if (!idxAppended) srcIdxBuffer.cleanup(vkCtx);
                try srcBuffers.append(allocator, srcIdxBuffer);
                idxAppended = true;
                const dstIdxBuffer = try vk.buf.VkBuffer.create(
                    vkCtx,
                    indicesSize,
                    vulkan.BufferUsageFlags{ .index_buffer = true, .transfer_dst = true, .shader_device_address = true },
                    @backingInt(vk.vma.VmaFlags.DedicatedMemory),
                    vk.vma.VmaUsage.VmaUsageAuto,
                    vk.vma.VmaMemoryFlags.None,
                );
                errdefer dstIdxBuffer.cleanup(vkCtx);

                const dataIndices = try srcIdxBuffer.map(vkCtx);
                const gpuIndices: [*]u8 = @ptrCast(@alignCast(dataIndices));
                const endIdx = meshData.idxOffset + meshData.idxSize;
                @memcpy(gpuIndices, idxData[meshData.idxOffset..endIdx]);
                srcIdxBuffer.unMap(vkCtx);

                var buffWeights: ?vk.buf.VkBuffer = null;
                if (modelData.animMeshes.items.len > 0) {
                    buffWeights = try createWeightsBuffers(vkCtx, allocator, cmdHandle, &srcBuffers, modelData.animMeshes.items[meshCount]);
                }

                const meshId = try allocator.dupe(u8, meshData.id);
                errdefer allocator.free(meshId);
                const meshMaterialId = try allocator.dupe(u8, meshData.materialId);
                errdefer allocator.free(meshMaterialId);
                const vulkanMesh = VulkanMesh{
                    .buffIdx = dstIdxBuffer,
                    .buffVtx = dstVtxBuffer,
                    .buffWeights = buffWeights,
                    .id = meshId,
                    .materialId = meshMaterialId,
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
