const std = @import("std");

const log = std.log.scoped(.eng);

pub const MAX_WEIGHTS = 4;
pub const MAX_JOINTS = 64;

pub const Bone = struct {
    id: usize,
    name: []const u8,
    offset_matrix: [16]f32,
};

pub const VertexWeight = struct {
    bone_id: usize,
    vertex_id: u32,
    weight: f32,
};

pub const AnimMeshData = struct {
    weights: []f32,
    bone_ids: []i32,
};

pub const NodeData = struct {
    name: []const u8,
    transformation: [16]f32,
    children: []NodeData,
    meshes: []u32,
};

pub const AnimatedFrame = struct {
    joint_matrices: []?[16]f32,
};

pub const AnimationData = struct {
    name: []const u8,
    frame_millis: f32,
    frames: []AnimatedFrame,
};

pub const MaterialData = struct {
    id: []const u8,
    texturePath: []const u8,
    color: [4]f32,
    normalMapPath: []const u8,
    metalRoughMapPath: []const u8,
    roughFactor: f32,
    metallicFactor: f32,
};

pub const MeshData = struct {
    id: []const u8,
    materialId: []const u8,
    idxOffset: usize,
    idxSize: usize,
    vtxOffset: usize,
    vtxSize: usize,
};

pub const ModelData = struct {
    id: []const u8,
    meshes: std.ArrayListUnmanaged(MeshData),
    idxFilename: []const u8,
    vtxFilename: []const u8,
    animations: std.ArrayListUnmanaged(AnimationData),
    animMeshes: std.ArrayListUnmanaged(AnimMeshData),

    pub fn cleanup(self: *const ModelData, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.idxFilename);
        allocator.free(self.vtxFilename);
        for (self.meshes.items) |*meshData| {
            allocator.free(meshData.id);
            allocator.free(meshData.materialId);
        }
    }
};

pub fn loadMaterials(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !std.ArrayList(MaterialData) {
    log.debug("Loading materials from [{s}]", .{path});

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const metadata = try file.stat(io);
    const fileSize = metadata.size;

    var buffer: [8192]u8 = undefined;
    var fileReader = file.reader(io, &buffer);
    const bytes = try fileReader.interface.readAlloc(allocator, fileSize);
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(std.ArrayListUnmanaged(MaterialData), allocator, bytes, .{});
    defer parsed.deinit();

    var materials = try std.ArrayList(MaterialData).initCapacity(allocator, parsed.value.items.len);
    for (parsed.value.items) |materialData| {
        const ownedMaterialData = MaterialData{
            .color = materialData.color,
            .id = try allocator.dupe(u8, materialData.id),
            .texturePath = try allocator.dupe(u8, materialData.texturePath),
            .normalMapPath = try allocator.dupe(u8, materialData.normalMapPath),
            .metalRoughMapPath = try allocator.dupe(u8, materialData.metalRoughMapPath),
            .roughFactor = materialData.roughFactor,
            .metallicFactor = materialData.metallicFactor,
        };
        try materials.append(allocator, ownedMaterialData);
    }

    return materials;
}

pub fn loadModel(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !ModelData {
    log.debug("Loading model from [{s}]", .{path});

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const metadata = try file.stat(io);
    const fileSize = metadata.size;

    var buffer: [8192]u8 = undefined;
    var fileReader = file.reader(io, &buffer);
    const bytes = try fileReader.interface.readAlloc(allocator, fileSize);
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(ModelData, allocator, bytes, .{});
    defer parsed.deinit();

    var modelData = parsed.value;
    modelData.id = try allocator.dupe(u8, modelData.id);
    modelData.idxFilename = try allocator.dupe(u8, modelData.idxFilename);
    modelData.vtxFilename = try allocator.dupe(u8, modelData.vtxFilename);

    for (modelData.animations.items) |*animData| {
        animData.name = try allocator.dupe(u8, animData.name);
    }

    for (modelData.meshes.items) |*meshData| {
        meshData.id = try allocator.dupe(u8, meshData.id);
        meshData.materialId = try allocator.dupe(u8, meshData.materialId);
    }

    return modelData;
}
