pub const MeshData = struct {
    id: []const u8,
    vertices: []const f32,
    indices: []const u32,
};

pub const ModelData = struct {
    id: []const u8,
    meshes: []const MeshData,
};
