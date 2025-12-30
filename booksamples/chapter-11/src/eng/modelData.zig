const std = @import("std");

const log = std.log.scoped(.eng);

pub const MaterialData = struct {
    id: []const u8,
    texturePath: []const u8,
    color: [4]f32,
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

pub fn loadMaterials(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList(MaterialData) {
    log.debug("Loading materials from [{s}]", .{path});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(std.ArrayListUnmanaged(MaterialData), allocator, bytes, .{});
    defer parsed.deinit();

    var materials = try std.ArrayList(MaterialData).initCapacity(allocator, parsed.value.items.len);
    for (parsed.value.items) |materialData| {
        const ownedMaterialData = MaterialData{
            .color = materialData.color,
            .id = try allocator.dupe(u8, materialData.id),
            .texturePath = try allocator.dupe(u8, materialData.texturePath),
        };
        try materials.append(allocator, ownedMaterialData);
    }

    return materials;
}

pub fn loadModel(allocator: std.mem.Allocator, path: []const u8) !ModelData {
    log.debug("Loading model from [{s}]", .{path});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(ModelData, allocator, bytes, .{});
    defer parsed.deinit();

    var modelData = parsed.value;
    modelData.id = try allocator.dupe(u8, modelData.id);
    modelData.idxFilename = try allocator.dupe(u8, modelData.idxFilename);
    modelData.vtxFilename = try allocator.dupe(u8, modelData.vtxFilename);

    for (modelData.meshes.items) |*meshData| {
        meshData.id = try allocator.dupe(u8, meshData.id);
        meshData.materialId = try allocator.dupe(u8, meshData.materialId);
    }

    return modelData;
}
