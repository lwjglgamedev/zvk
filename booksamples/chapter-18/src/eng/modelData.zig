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

pub const AnimatedFrame = struct {
    jointMatrices: []?[16]f32,
};

pub const AnimationData = struct {
    name: []const u8,
    frameMillis: f32,
    frames: []AnimatedFrame,
};

pub const AnimMeshData = struct {
    weights: []f32,
    boneIds: []i32,
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
    meshes: JsonList(MeshData),
    idxFilename: []const u8,
    vtxFilename: []const u8,
    animations: JsonList(AnimationData),
    animMeshes: JsonList(AnimMeshData),

    pub fn cleanup(self: *const ModelData, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.idxFilename);
        allocator.free(self.vtxFilename);
        for (self.meshes.items) |*meshData| {
            allocator.free(meshData.id);
            allocator.free(meshData.materialId);
        }
        for (self.animations.items) |*animData| {
            allocator.free(animData.name);
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

fn dupeAnimation(allocator: std.mem.Allocator, src: AnimationData) !AnimationData {
    const name = try allocator.dupe(u8, src.name);
    errdefer allocator.free(name);

    const frames = try allocator.alloc(AnimatedFrame, src.frames.len);
    errdefer allocator.free(frames);
    var numFrames: usize = 0;
    errdefer for (frames[0..numFrames]) |f| allocator.free(f.jointMatrices);
    for (src.frames, 0..) |srcFrame, i| {
        frames[i] = .{ .jointMatrices = try allocator.dupe(?[16]f32, srcFrame.jointMatrices) };
        numFrames += 1;
    }

    return .{ .name = name, .frameMillis = src.frameMillis, .frames = frames };
}

fn freeAnimation(allocator: std.mem.Allocator, anim: AnimationData) void {
    allocator.free(anim.name);
    for (anim.frames) |f| allocator.free(f.jointMatrices);
    allocator.free(anim.frames);
}

fn dupeAnimMesh(allocator: std.mem.Allocator, src: AnimMeshData) !AnimMeshData {
    const weights = try allocator.dupe(f32, src.weights);
    errdefer allocator.free(weights);
    const boneIds = try allocator.dupe(i32, src.boneIds);
    return .{ .weights = weights, .boneIds = boneIds };
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

    // Meshes
    const meshes = try allocator.alloc(MeshData, src.meshes.items.len);
    errdefer allocator.free(meshes);
    var numMeshes: usize = 0;
    errdefer for (meshes[0..numMeshes]) |m| {
        allocator.free(m.id);
        allocator.free(m.materialId);
    };
    for (src.meshes.items, 0..) |srcMesh, i| {
        const meshId = try allocator.dupe(u8, srcMesh.id);
        errdefer allocator.free(meshId);
        const materialId = try allocator.dupe(u8, srcMesh.materialId);
        meshes[i] = srcMesh;
        meshes[i].id = meshId;
        meshes[i].materialId = materialId;
        numMeshes += 1;
    }

    // Animations
    const animations = try allocator.alloc(AnimationData, src.animations.items.len);
    errdefer allocator.free(animations);
    var numAnims: usize = 0;
    errdefer for (animations[0..numAnims]) |a| freeAnimation(allocator, a);
    for (src.animations.items, 0..) |srcAnim, i| {
        animations[i] = try dupeAnimation(allocator, srcAnim);
        numAnims += 1;
    }

    // Animated meshes
    const animMeshes = try allocator.alloc(AnimMeshData, src.animMeshes.items.len);
    errdefer allocator.free(animMeshes);
    var numAnimMeshes: usize = 0;
    errdefer for (animMeshes[0..numAnimMeshes]) |a| {
        allocator.free(a.weights);
        allocator.free(a.boneIds);
    };
    for (src.animMeshes.items, 0..) |srcAnimMesh, i| {
        animMeshes[i] = try dupeAnimMesh(allocator, srcAnimMesh);
        numAnimMeshes += 1;
    }

    return .{
        .id = id,
        .meshes = .{ .items = meshes, .capacity = meshes.len },
        .idxFilename = idxFilename,
        .vtxFilename = vtxFilename,
        .animations = .{ .items = animations, .capacity = animations.len },
        .animMeshes = .{ .items = animMeshes, .capacity = animMeshes.len },
    };
}
