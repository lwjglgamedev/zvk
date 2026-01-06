const eng = @import("mod.zig");
const std = @import("std");
const zmesh = @import("zmesh");

const MeshIntData = struct {
    id: []const u8,
    materialId: []const u8,
    indices: std.ArrayListUnmanaged(u32),
    positions: std.ArrayListUnmanaged([3]f32),
    texcoords: std.ArrayListUnmanaged([2]f32),

    pub fn cleanup(self: *MeshIntData, allocator: std.mem.Allocator) void {
        self.indices.deinit(allocator);
        self.positions.deinit(allocator);
        self.texcoords.deinit(allocator);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3 or !std.mem.eql(u8, args[1], "-m")) {
        printHelp();
        return;
    }

    const modelPath = args[2];
    const baseDir = try normalizePath(allocator, std.fs.path.dirname(modelPath) orelse ".");
    const baseName = std.fs.path.basename(modelPath);
    const modelId = std.fs.path.stem(baseName);

    var dir = try std.fs.cwd().openDir(baseDir, .{});
    defer dir.close();

    zmesh.init(allocator);
    defer zmesh.deinit();

    const data = try zmesh.io.zcgltf.parseAndLoadFile(modelPath);
    defer zmesh.io.zcgltf.freeData(data);

    var materialList = std.ArrayListUnmanaged(eng.mdata.MaterialData){};
    defer materialList.deinit(allocator);

    if (data.materials_count > 0 and data.materials != null) {
        const materials = data.materials.?[0..data.materials_count];
        for (materials, 0..) |material, i| {
            const materialData = try processMaterial(allocator, &material, baseDir, modelId, i);
            try materialList.append(allocator, materialData);
        }
    }

    // Create indices file
    const idxFileName = try std.fmt.allocPrint(allocator, "{s}.idx", .{modelId});
    const idxFile = try dir.createFile(idxFileName, .{ .truncate = true });
    defer idxFile.close();

    // Create vertices file
    const vtxFileName = try std.fmt.allocPrint(allocator, "{s}.vtx", .{modelId});
    const vtxFile = try dir.createFile(vtxFileName, .{ .truncate = true });
    defer vtxFile.close();

    var meshDataList = std.ArrayListUnmanaged(eng.mdata.MeshData){};
    defer meshDataList.deinit(allocator);
    const defText = [_]f32{ 0.0, 0.0 };
    var idxOffset: usize = 0;
    var vtxOffset: usize = 0;
    if (data.meshes_count == 0 or data.meshes == null) {
        std.debug.print("No meshes found\n", .{});
        return;
    }
    const meshes = data.meshes.?[0..data.meshes_count];
    for (meshes, 0..) |mesh, meshIdx| {
        for (mesh.primitives, 0..mesh.primitives_count) |primitive, primIdx| {
            var meshIntData = try processMesh(
                allocator,
                data,
                &primitive,
                @as(u32, @intCast(meshIdx)),
                @as(u32, @intCast(primIdx)),
                materialList,
            );
            defer meshIntData.cleanup(allocator);

            // Dump to indices file
            try idxFile.writeAll(std.mem.sliceAsBytes(meshIntData.indices.items));

            // Dump to vertices file
            for (meshIntData.positions.items, 0..) |_, idx| {
                try vtxFile.writeAll(std.mem.sliceAsBytes(std.mem.asBytes(&meshIntData.positions.items[idx])));
                if (idx < meshIntData.texcoords.items.len) {
                    try vtxFile.writeAll(std.mem.sliceAsBytes(std.mem.asBytes(&meshIntData.texcoords.items[idx])));
                } else {
                    try vtxFile.writeAll(std.mem.sliceAsBytes(std.mem.asBytes(&defText)));
                }
            }

            const numIndices = meshIntData.indices.items.len;
            // There can be models with no texture coords, but we fill up with empty coords
            const numFloats = meshIntData.positions.items.len * 3 + meshIntData.positions.items.len * 2;
            const meshData = eng.mdata.MeshData{
                .id = meshIntData.id,
                .materialId = meshIntData.materialId,
                .idxOffset = idxOffset,
                .idxSize = numIndices * @sizeOf(u32),
                .vtxOffset = vtxOffset,
                .vtxSize = numFloats * @sizeOf(f32),
            };
            try meshDataList.append(allocator, meshData);

            idxOffset += meshData.idxSize;
            vtxOffset += meshData.vtxSize;
        }
    }

    // Dump materials file
    var writerMaterials = std.Io.Writer.Allocating.init(allocator);
    var jsonMat = std.json.Stringify{
        .writer = &writerMaterials.writer,
        .options = .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = true,
            .escape_unicode = false,
            .emit_nonportable_numbers_as_strings = false,
        },
    };
    const fileMaterialsName = try std.fmt.allocPrint(allocator, "{s}-mat.json", .{modelId});
    try jsonMat.write(materialList);
    const fileMaterials = try dir.createFile(fileMaterialsName, .{ .truncate = true });
    defer fileMaterials.close();
    try fileMaterials.writeAll(writerMaterials.written());
    std.debug.print("Dumped materials [{s}]\n", .{fileMaterialsName});

    // Build model data
    const idxRelPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, idxFileName });
    const vtxRelPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, vtxFileName });

    const modelData = eng.mdata.ModelData{
        .id = modelId,
        .meshes = meshDataList,
        .idxFilename = idxRelPath,
        .vtxFilename = vtxRelPath,
    };

    // Dump model file
    var writerModel = std.Io.Writer.Allocating.init(allocator);
    defer writerModel.deinit();
    var jsonModel = std.json.Stringify{
        .writer = &writerModel.writer,
        .options = .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = true,
            .escape_unicode = false,
            .emit_nonportable_numbers_as_strings = false,
        },
    };

    const fileModelName = try std.fmt.allocPrint(allocator, "{s}.json", .{modelId});
    try jsonModel.write(modelData);
    const fileModel = try dir.createFile(fileModelName, .{ .truncate = true });
    defer fileModel.close();
    try fileModel.writeAll(writerModel.written());
    std.debug.print("Dumped model [{s}]\n", .{fileModelName});
}

pub fn normalizePath(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, input_path.len);
    for (input_path, 0..) |c, i| {
        result[i] = if (c == '\\') '/' else c;
    }
    return result;
}

fn processMaterial(
    allocator: std.mem.Allocator,
    material: *const zmesh.io.zcgltf.Material,
    baseDir: []const u8,
    modelId: []const u8,
    pos: usize,
) !eng.mdata.MaterialData {
    var color = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    var texturePath: [*:0]const u8 = "";
    if (material.has_pbr_metallic_roughness > 0) {
        if (material.pbr_metallic_roughness.base_color_texture.texture) |texture| {
            texturePath = texture.image.?.uri.?;
        }
        color = material.pbr_metallic_roughness.base_color_factor;
    }
    const materialRelPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, std.mem.span(texturePath) });
    const materialId = try std.fmt.allocPrint(allocator, "{s}-mat-{d}", .{ modelId, pos });
    return eng.mdata.MaterialData{
        .id = materialId,
        .texturePath = materialRelPath,
        .color = color,
    };
}

fn processMesh(
    allocator: std.mem.Allocator,
    data: *zmesh.io.zcgltf.Data,
    primitive: *const zmesh.io.zcgltf.Primitive,
    meshIdx: u32,
    primIdx: u32,
    materialList: std.ArrayListUnmanaged(eng.mdata.MaterialData),
) !MeshIntData {
    const id = try std.fmt.allocPrint(allocator, "mesh-{d}-{d}", .{ meshIdx, primIdx });

    var indices = std.ArrayListUnmanaged(u32){};
    var positions = std.ArrayListUnmanaged([3]f32){};
    var texcoords = std.ArrayListUnmanaged([2]f32){};

    var materialId: []const u8 = "";
    if (primitive.material) |material| {
        const idx = materialIndexFromPtr(data, material);
        materialId = materialList.items[idx].id;
    }
    try zmesh.io.zcgltf.appendMeshPrimitive(
        allocator,
        data,
        meshIdx,
        @as(u32, @intCast(primIdx)),
        &indices,
        &positions,
        null,
        &texcoords,
        null,
    );

    return MeshIntData{
        .id = id,
        .materialId = materialId,
        .indices = indices,
        .positions = positions,
        .texcoords = texcoords,
    };
}

fn materialIndexFromPtr(
    data: *const zmesh.io.zcgltf.Data,
    mat: *const zmesh.io.zcgltf.Material,
) usize {
    const base = @intFromPtr(data.materials.?);
    const ptr = @intFromPtr(mat);
    return (ptr - base) / @sizeOf(zmesh.io.zcgltf.Material);
}

fn printHelp() void {
    std.debug.print(
        \\Usage: model-gen [OPTIONS]
        \\
        \\Options:
        \\  -m  FILE       Path to the model file
        \\
    , .{});
}
