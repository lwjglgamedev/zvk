const std = @import("std");

const log = std.log.scoped(.eng);

// Do not use ArrayList to prevent code changes when Zig API is modified
pub fn JsonList(comptime T: type) type {
    return struct {
        items: []T = &.{},
        capacity: usize = 0,

        pub fn fromList(list: std.ArrayListUnmanaged(T)) @This() {
            return .{ .items = list.items, .capacity = list.capacity };
        }
    };
}

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
    meshes: JsonList(MeshData),
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

    const parsed = try std.json.parseFromSlice(JsonList(MaterialData), allocator, bytes, .{});
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
    const src = parsed.value;

    const id = try allocator.dupe(u8, src.id);
    errdefer allocator.free(id);
    const idxFilename = try allocator.dupe(u8, src.idxFilename);
    errdefer allocator.free(idxFilename);
    const vtxFilename = try allocator.dupe(u8, src.vtxFilename);
    errdefer allocator.free(vtxFilename);

    const meshes = try allocator.alloc(MeshData, src.meshes.items.len);
    errdefer allocator.free(meshes);

    var numCopied: usize = 0;
    errdefer for (meshes[0..numCopied]) |m| {
        allocator.free(m.id);
        allocator.free(m.materialId);
    };
    for (src.meshes.items, 0..) |srcMesh, i| {
        const meshId = try allocator.dupe(u8, srcMesh.id);
        errdefer allocator.free(meshId);
        const materialId = try allocator.dupe(u8, srcMesh.materialId);
        meshes[i] = srcMesh; // copies the numeric fields (offsets and sizes)
        meshes[i].id = meshId;
        meshes[i].materialId = materialId;
        numCopied += 1;
    }

    return .{
        .id = id,
        .meshes = .{ .items = meshes, .capacity = meshes.len },
        .idxFilename = idxFilename,
        .vtxFilename = vtxFilename,
    };
}
