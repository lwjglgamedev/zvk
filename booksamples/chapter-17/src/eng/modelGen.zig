const eng = @import("mod.zig");
const std = @import("std");
const zm = @import("zmath");
const zassimp = @import("zassimp");

const MeshIntData = struct {
    id: []const u8,
    materialId: []const u8,
    indices: std.ArrayListUnmanaged(u32),
    positions: std.ArrayListUnmanaged([3]f32),
    texcoords: std.ArrayListUnmanaged([2]f32),
    normals: std.ArrayListUnmanaged([3]f32),
    tangents: std.ArrayListUnmanaged([3]f32),

    pub fn cleanup(self: *MeshIntData, allocator: std.mem.Allocator) void {
        self.indices.deinit(allocator);
        self.positions.deinit(allocator);
        self.texcoords.deinit(allocator);
        self.normals.deinit(allocator);
        self.tangents.deinit(allocator);
    }
};

fn buildFrameMatrices(
    aiAnimation: *const zassimp.aiAnimation,
    boneList: *const std.ArrayListUnmanaged(eng.mdata.Bone),
    animatedFrame: *eng.mdata.AnimatedFrame,
    frameIdx: usize,
    node: *const eng.mdata.NodeData,
    nodeParentTransform: zm.Mat,
    globalInverseTransform: zm.Mat,
) void {
    var channel: ?*const zassimp.aiNodeAnim = null;
    const numChannels = aiAnimation.mNumChannels;
    if (aiAnimation.mChannels) |channelsPtr| {
        const channels = channelsPtr[0..numChannels];
        for (channels) |channelPtr| {
            if (channelPtr) |cp| {
                const ch: *const zassimp.aiNodeAnim = @ptrCast(cp);
                if (std.mem.eql(u8, ch.mNodeName.data[0..ch.mNodeName.length], node.name)) {
                    channel = ch;
                    break;
                }
            }
        }
    }

    var nodeTransform = zm.transpose(zm.matFromArr(node.transformation));
    if (channel) |ch| {
        const pos = calculatePosition(ch, frameIdx);
        const rot = calculateRotation(ch, frameIdx);
        const scl = calculateScaling(ch, frameIdx);

        const translation = zm.translation(pos[0], pos[1], pos[2]);
        const rotation = zm.quatToMat(.{ rot[0], rot[1], rot[2], rot[3] });
        const scaling = zm.scaling(scl[0], scl[1], scl[2]);
        nodeTransform = zm.mul(zm.mul(scaling, rotation), translation);
    }

    const nodeGlobalTransform = zm.mul(nodeTransform, nodeParentTransform);

    for (boneList.items, 0..) |bone, boneId| {
        if (std.mem.eql(u8, bone.name, node.name)) {
            if (boneId < animatedFrame.joint_matrices.len) {
                const offsetMat = zm.transpose(zm.matFromArr(bone.offset_matrix));
                const mat1 = zm.mul(nodeGlobalTransform, globalInverseTransform);
                const mat2 = zm.mul(offsetMat, mat1);
                animatedFrame.joint_matrices[boneId] = @bitCast(mat2);
            }
        }
    }

    for (node.children) |*child| {
        buildFrameMatrices(
            aiAnimation,
            boneList,
            animatedFrame,
            frameIdx,
            child,
            nodeGlobalTransform,
            globalInverseTransform,
        );
    }
}

fn buildNodesTree(
    allocator: std.mem.Allocator,
    aiNode: *const zassimp.aiNode,
    parent: ?*const eng.mdata.NodeData,
) !eng.mdata.NodeData {
    _ = parent;

    const name = try allocator.dupe(u8, aiNode.mName.data[0..aiNode.mName.length]);
    const transformation = toMatrix(aiNode.mTransformation);

    const numMeshes = aiNode.mNumMeshes;
    var meshes: []u32 = &.{};
    if (numMeshes > 0 and aiNode.mMeshes != null) {
        meshes = try allocator.alloc(u32, numMeshes);
        const srcMeshes = aiNode.mMeshes[0..numMeshes];
        for (srcMeshes, 0..) |meshIdx, i| {
            meshes[i] = meshIdx;
        }
    }

    const numChildren = aiNode.mNumChildren;
    var children: []eng.mdata.NodeData = &.{};
    if (numChildren > 0 and aiNode.mChildren != null) {
        children = try allocator.alloc(eng.mdata.NodeData, numChildren);
        const srcChildren = aiNode.mChildren[0..numChildren];
        for (srcChildren, 0..) |childPtr, i| {
            if (childPtr) |child| {
                children[i] = try buildNodesTree(allocator, child, null);
            }
        }
    }

    return eng.mdata.NodeData{
        .name = name,
        .transformation = @bitCast(transformation),
        .children = children,
        .meshes = meshes,
    };
}

fn calcAnimationMaxFrames(aiAnimation: *const zassimp.aiAnimation) usize {
    var maxFrames: usize = 0;
    const numChannels = aiAnimation.mNumChannels;
    if (aiAnimation.mChannels) |channelsPtr| {
        const channels = channelsPtr[0..numChannels];
        for (channels) |channelPtr| {
            if (channelPtr) |cp| {
                const channel: *const zassimp.aiNodeAnim = @ptrCast(cp);
                if (channel.mNumPositionKeys > maxFrames) maxFrames = channel.mNumPositionKeys;
                if (channel.mNumRotationKeys > maxFrames) maxFrames = channel.mNumRotationKeys;
                if (channel.mNumScalingKeys > maxFrames) maxFrames = channel.mNumScalingKeys;
            }
        }
    }
    return maxFrames;
}

fn calculatePosition(channel: *const zassimp.aiNodeAnim, frameIdx: usize) [3]f32 {
    if (channel.mNumPositionKeys == 0) return .{ 0.0, 0.0, 0.0 };
    const keys = channel.mPositionKeys[0..channel.mNumPositionKeys];
    const idx = if (frameIdx >= keys.len) keys.len - 1 else frameIdx;
    const val = keys[idx].mValue;
    return .{ val.x, val.y, val.z };
}

fn calculateRotation(channel: *const zassimp.aiNodeAnim, frameIdx: usize) [4]f32 {
    if (channel.mNumRotationKeys == 0) return .{ 0.0, 0.0, 0.0, 1.0 };
    const keys = channel.mRotationKeys[0..channel.mNumRotationKeys];
    const idx = if (frameIdx >= keys.len) keys.len - 1 else frameIdx;
    const val = keys[idx].mValue;
    return .{ val.x, val.y, val.z, val.w };
}

fn calculateScaling(channel: *const zassimp.aiNodeAnim, frameIdx: usize) [3]f32 {
    if (channel.mNumScalingKeys == 0) return .{ 1.0, 1.0, 1.0 };
    const keys = channel.mScalingKeys[0..channel.mNumScalingKeys];
    const idx = if (frameIdx >= keys.len) keys.len - 1 else frameIdx;
    const val = keys[idx].mValue;
    return .{ val.x, val.y, val.z };
}

fn embeddedTextureIndex(path: []const u8) ?usize {
    if (path.len < 2 or path[0] != '*') return null;
    return std.fmt.parseInt(usize, path[1..], 10) catch null;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 3 or !std.mem.eql(u8, args[1], "-m")) {
        printHelp();
        return;
    }

    const io = init.io;

    const modelPath = args[2];
    const baseDir = try normalizePath(allocator, std.fs.path.dirname(modelPath) orelse ".");
    const baseName = std.fs.path.basename(modelPath);
    const modelId = std.fs.path.stem(baseName);

    var dir = try std.Io.Dir.cwd().openDir(io, baseDir, .{});
    defer dir.close(io);

    const flags = zassimp.aiProcess_GenSmoothNormals | zassimp.aiProcess_JoinIdenticalVertices |
        zassimp.aiProcess_Triangulate | zassimp.aiProcess_FixInfacingNormals | zassimp.aiProcess_CalcTangentSpace | zassimp.aiProcess_LimitBoneWeights;
    const scene = zassimp.aiImportFile(modelPath, flags) orelse {
        const err = std.mem.sliceTo(zassimp.aiGetErrorString(), 0);
        std.debug.print("Failed to import mode: {s}\n", .{err});
        return error.ImportFailed;
    };
    defer zassimp.aiReleaseImport(scene);

    var materialList: std.ArrayListUnmanaged(eng.mdata.MaterialData) = .empty;
    defer materialList.deinit(allocator);

    const numMaterials = scene.mNumMaterials;
    std.debug.print("Number of materials: {}\n", .{numMaterials});
    if (numMaterials > 0) {
        for (0..numMaterials) |i| {
            const material = scene.mMaterials[i];
            const materialData = try processMaterial(
                allocator,
                io,
                scene,
                material,
                baseDir,
                modelId,
                i,
            );
            try materialList.append(allocator, materialData);
        }
    }

    // Create indices file
    const idxFileName = try std.fmt.allocPrint(allocator, "{s}.idx", .{modelId});
    const idxFile = try dir.createFile(io, idxFileName, .{ .truncate = true });
    defer idxFile.close(io);

    // Create vertices file
    const vtxFileName = try std.fmt.allocPrint(allocator, "{s}.vtx", .{modelId});
    const vtxFile = try dir.createFile(io, vtxFileName, .{ .truncate = true });
    defer vtxFile.close(io);

    var meshDataList: std.ArrayListUnmanaged(eng.mdata.MeshData) = .empty;
    defer meshDataList.deinit(allocator);
    const defText = [_]f32{ 0.0, 0.0 };
    var idxOffset: usize = 0;
    var vtxOffset: usize = 0;

    const numMeshes = scene.mNumMeshes;
    std.debug.print("Number of meshes: {}\n", .{numMeshes});
    if (numMeshes > 0) {
        for (0..numMeshes) |i| {
            const mesh = scene.mMeshes[i];
            var meshIntData = try processMesh(
                allocator,
                mesh,
                materialList,
            );
            defer meshIntData.cleanup(allocator);

            // Dump to indices file
            try idxFile.writeStreamingAll(io, std.mem.sliceAsBytes(meshIntData.indices.items));

            // Dump to vertices file (same layout as main2)
            for (meshIntData.positions.items, 0..) |_, idx| {
                try vtxFile.writeStreamingAll(io, std.mem.sliceAsBytes(std.mem.asBytes(&meshIntData.positions.items[idx])));
                if (idx < meshIntData.texcoords.items.len) {
                    try vtxFile.writeStreamingAll(io, std.mem.sliceAsBytes(std.mem.asBytes(&meshIntData.texcoords.items[idx])));
                } else {
                    try vtxFile.writeStreamingAll(io, std.mem.sliceAsBytes(std.mem.asBytes(&defText)));
                }
                try vtxFile.writeStreamingAll(io, std.mem.sliceAsBytes(std.mem.asBytes(&meshIntData.normals.items[idx])));
                try vtxFile.writeStreamingAll(io, std.mem.sliceAsBytes(std.mem.asBytes(&meshIntData.tangents.items[idx])));
            }

            const numIndices = meshIntData.indices.items.len;
            const numFloats = meshIntData.positions.items.len * 3 +
                meshIntData.texcoords.items.len * 2 +
                meshIntData.normals.items.len * 3 +
                meshIntData.tangents.items.len * 3;

            try meshDataList.append(allocator, .{
                .id = meshIntData.id,
                .materialId = meshIntData.materialId,
                .idxOffset = idxOffset,
                .idxSize = numIndices * @sizeOf(u32),
                .vtxOffset = vtxOffset,
                .vtxSize = numFloats * @sizeOf(f32),
            });

            idxOffset += numIndices * @sizeOf(u32);
            vtxOffset += numFloats * @sizeOf(f32);
        }
    }

    const numAnimations = scene.mNumAnimations;
    std.debug.print("Animations [{d}]\n", .{numAnimations});

    var boneList: std.ArrayListUnmanaged(eng.mdata.Bone) = .empty;
    defer boneList.deinit(allocator);

    var animMeshDataList: std.ArrayListUnmanaged(eng.mdata.AnimMeshData) = .empty;
    defer animMeshDataList.deinit(allocator);

    var animations: std.ArrayListUnmanaged(eng.mdata.AnimationData) = .empty;
    defer animations.deinit(allocator);

    if (numAnimations > 0) {
        std.debug.print("Processing animations\n", .{});

        for (0..numMeshes) |i| {
            const mesh = scene.mMeshes[i];
            const animMeshData = try processBones(allocator, mesh, &boneList);
            try animMeshDataList.append(allocator, animMeshData);
        }

        const rootNode = try buildNodesTree(allocator, scene.mRootNode.?, null);

        const rootTransform = toMatrix(scene.mRootNode.?.mTransformation);
        const globalInverseTransform = zm.inverse(rootTransform);

        try processAnimations(allocator, scene, &boneList, &rootNode, globalInverseTransform, &animations);
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
    const fileMaterials = try dir.createFile(io, fileMaterialsName, .{ .truncate = true });
    defer fileMaterials.close(io);
    try fileMaterials.writeStreamingAll(io, writerMaterials.written());
    std.debug.print("Dumped materials [{s}]\n", .{fileMaterialsName});

    // Build model data
    const idxRelPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, idxFileName });
    const vtxRelPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, vtxFileName });

    const modelData = eng.mdata.ModelData{
        .id = modelId,
        .meshes = meshDataList,
        .idxFilename = idxRelPath,
        .vtxFilename = vtxRelPath,
        .animations = animations,
        .animMeshes = animMeshDataList,
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
    const fileModel = try dir.createFile(io, fileModelName, .{ .truncate = true });
    defer fileModel.close(io);
    try fileModel.writeStreamingAll(io, writerModel.written());
    std.debug.print("Dumped model [{s}]\n", .{fileModelName});
}

pub fn normalizePath(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, input_path.len);
    for (input_path, 0..) |c, i| {
        result[i] = if (c == '\\') '/' else c;
    }
    return result;
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

fn processAnimations(
    allocator: std.mem.Allocator,
    scene: *const zassimp.aiScene,
    boneList: *const std.ArrayListUnmanaged(eng.mdata.Bone),
    rootNode: *const eng.mdata.NodeData,
    globalInverseTransform: zm.Mat,
    outAnimations: *std.ArrayListUnmanaged(eng.mdata.AnimationData),
) !void {
    const numAnimations = scene.mNumAnimations;
    if (scene.mAnimations) |animationsPtr| {
        const aiAnimations = animationsPtr[0..numAnimations];

        for (aiAnimations) |aiAnimPtr| {
            if (aiAnimPtr) |aiAnim| {
                const aiAnimation: *const zassimp.aiAnimation = @ptrCast(aiAnim);
                const maxFrames = calcAnimationMaxFrames(aiAnimation);
                if (maxFrames == 0) continue;
                const name = try allocator.dupe(u8, aiAnimation.mName.data[0..aiAnimation.mName.length]);

                const frameMillis: f32 = if (aiAnimation.mTicksPerSecond > 0.0)
                    @floatCast(aiAnimation.mDuration / aiAnimation.mTicksPerSecond)
                else
                    0.0;

                var frames = try allocator.alloc(eng.mdata.AnimatedFrame, maxFrames);

                for (0..maxFrames) |frameIdx| {
                    const jointMatrices = try allocator.alloc(?[16]f32, boneList.items.len);
                    // Fill with identity
                    const identity = zm.identity();
                    const identityArr = zm.matToArr(identity);
                    for (jointMatrices) |*jm| {
                        jm.* = identityArr;
                    }

                    var animatedFrame = eng.mdata.AnimatedFrame{
                        .joint_matrices = jointMatrices,
                    };

                    buildFrameMatrices(
                        aiAnimation,
                        boneList,
                        &animatedFrame,
                        frameIdx,
                        rootNode,
                        zm.identity(),
                        globalInverseTransform,
                    );

                    frames[frameIdx] = animatedFrame;
                }

                try outAnimations.append(allocator, .{
                    .name = name,
                    .frame_millis = frameMillis,
                    .frames = frames,
                });
            }
        }
    }
}

fn processBones(
    allocator: std.mem.Allocator,
    mesh: *const zassimp.aiMesh,
    boneList: *std.ArrayListUnmanaged(eng.mdata.Bone),
) !eng.mdata.AnimMeshData {
    const numVertices = mesh.mNumVertices;

    // Map: vertex_index -> list of VertexWeight
    var weightSet = std.AutoHashMap(u32, std.ArrayListUnmanaged(eng.mdata.VertexWeight)).init(allocator);
    defer {
        var it = weightSet.valueIterator();
        while (it.next()) |list| list.deinit(allocator);
        weightSet.deinit();
    }

    const numBones = mesh.mNumBones;
    if (mesh.mBones) |bonesPtr| {
        const aiBones = bonesPtr[0..numBones];
        for (aiBones) |aiBonePtr| {
            const aiBone = aiBonePtr.*;
            const boneId = boneList.items.len;
            const boneName = try allocator.dupe(u8, aiBone.mName.data[0..aiBone.mName.length]);
            const offsetMatrix = zm.matToArr(toMatrix(aiBone.mOffsetMatrix));

            try boneList.append(allocator, .{
                .id = boneId,
                .name = boneName,
                .offset_matrix = offsetMatrix,
            });

            const numWeights = aiBone.mNumWeights;
            const aiWeights = aiBone.mWeights[0..numWeights];
            for (aiWeights) |aiWeight| {
                const gop = try weightSet.getOrPut(aiWeight.mVertexId);
                if (!gop.found_existing) {
                    gop.value_ptr.* = .empty;
                }
                try gop.value_ptr.append(allocator, .{
                    .bone_id = boneId,
                    .vertex_id = aiWeight.mVertexId,
                    .weight = aiWeight.mWeight,
                });
            }
        }
    }

    const totalFloats = numVertices * eng.mdata.MAX_WEIGHTS;
    var weights = try allocator.alloc(f32, totalFloats);
    var boneIds = try allocator.alloc(i32, totalFloats);
    @memset(weights, 0.0);
    @memset(boneIds, 0);

    for (0..numVertices) |i| {
        const vertexWeightList = weightSet.get(@intCast(i));
        const size = if (vertexWeightList) |vl| vl.items.len else 0;

        for (0..eng.mdata.MAX_WEIGHTS) |j| {
            const offset = i * eng.mdata.MAX_WEIGHTS + j;
            if (j < size) {
                const vw = vertexWeightList.?.items[j];
                weights[offset] = vw.weight;
                boneIds[offset] = @intCast(vw.bone_id);
            } else {
                weights[offset] = 0.0;
                boneIds[offset] = 0;
            }
        }
    }

    return eng.mdata.AnimMeshData{
        .weights = weights,
        .bone_ids = boneIds,
    };
}

fn processMaterial(
    allocator: std.mem.Allocator,
    io: std.Io,
    scene: *const zassimp.aiScene,
    material: *const zassimp.aiMaterial,
    baseDir: []const u8,
    modelId: []const u8,
    pos: usize,
) !eng.mdata.MaterialData {
    var diffuse: zassimp.aiColor4D = undefined;
    const result = zassimp.aiGetMaterialColor(
        material,
        zassimp.AI_MATKEY_COLOR_DIFFUSE,
        0,
        0,
        &diffuse,
    );
    if (result != .SUCCESS) {
        diffuse = zassimp.aiColor4D{ .r = 0, .g = 0, .b = 0, .a = 0 };
    }
    const color = [_]f32{ diffuse.r, diffuse.g, diffuse.b, diffuse.a };

    const texturePath = try processTexture(allocator, io, scene, material, baseDir, .DIFFUSE);
    const normalMapPath = try processTexture(allocator, io, scene, material, baseDir, .NORMALS);
    const metalRoughMapPath = try processTexture(allocator, io, scene, material, baseDir, .GLTF_METALLIC_ROUGHNESS);
    const materialId = try std.fmt.allocPrint(allocator, "{s}-mat-{d}", .{ modelId, pos });

    var roughness: f32 = 0.0;
    var pMax: c_uint = 1;
    _ = zassimp.aiGetMaterialFloatArray(material, zassimp.AI_MATKEY_ROUGHNESS_FACTOR, 0, 0, &roughness, &pMax);
    if (roughness == 0.0) roughness = 1.0;

    var metallic: f32 = 0.0;
    pMax = 1;
    _ = zassimp.aiGetMaterialFloatArray(material, zassimp.AI_MATKEY_METALLIC_FACTOR, 0, 0, &metallic, &pMax);

    return eng.mdata.MaterialData{
        .id = materialId,
        .texturePath = texturePath,
        .color = color,
        .normalMapPath = normalMapPath,
        .metalRoughMapPath = metalRoughMapPath,
        .metallicFactor = metallic,
        .roughFactor = roughness,
    };
}

fn processMesh(
    allocator: std.mem.Allocator,
    mesh: *const zassimp.aiMesh,
    materialList: std.ArrayListUnmanaged(eng.mdata.MaterialData),
) !MeshIntData {
    const id = try std.fmt.allocPrint(allocator, "mesh-{}", .{@intFromPtr(mesh)});
    const numVertices = mesh.mNumVertices;

    var indices: std.ArrayListUnmanaged(u32) = .empty;
    var positions: std.ArrayListUnmanaged([3]f32) = .empty;
    var texcoords: std.ArrayListUnmanaged([2]f32) = .empty;
    var normals: std.ArrayListUnmanaged([3]f32) = .empty;
    var tangents: std.ArrayListUnmanaged([3]f32) = .empty;

    // Material
    var materialId: []const u8 = "";
    const matIdx = mesh.mMaterialIndex;
    if (matIdx < materialList.items.len) {
        materialId = materialList.items[matIdx].id;
    }

    // Positions
    const vtx = mesh.mVertices[0..numVertices];
    try positions.ensureTotalCapacity(allocator, numVertices);
    for (vtx) |v| try positions.append(allocator, .{ v.x, v.y, v.z });

    // Normals
    if (mesh.mNormals) |normsPtr| {
        const norms = normsPtr[0..numVertices];
        try normals.ensureTotalCapacity(allocator, numVertices);
        for (norms) |n| try normals.append(allocator, .{ n.x, n.y, n.z });
    }

    // Tangents
    if (mesh.mTangents) |tangsPtr| {
        const tangs = tangsPtr[0..numVertices];
        try tangents.ensureTotalCapacity(allocator, numVertices);
        for (tangs) |t| try tangents.append(allocator, .{ t.x, t.y, t.z });
    }

    // Texcoords
    if (mesh.mTextureCoords[0]) |uvPtr| {
        const uvArray: [*c]zassimp.aiVector3D = @ptrCast(uvPtr);
        const uvs = uvArray[0..numVertices];
        try texcoords.ensureTotalCapacity(allocator, numVertices);
        for (uvs) |uv| try texcoords.append(allocator, .{ uv.x, 1 - uv.y });
    }

    // Indices
    var totalIndices: usize = 0;
    const faces = mesh.mFaces[0..mesh.mNumFaces];
    for (faces) |face| totalIndices += face.mNumIndices;
    try indices.ensureTotalCapacity(allocator, totalIndices);
    for (faces) |face| {
        const faceIndices = face.mIndices[0..face.mNumIndices];
        for (faceIndices) |idx| try indices.append(allocator, idx);
    }

    return MeshIntData{
        .id = id,
        .materialId = materialId,
        .indices = indices,
        .positions = positions,
        .texcoords = texcoords,
        .normals = normals,
        .tangents = tangents,
    };
}
fn processTexture(
    allocator: std.mem.Allocator,
    io: std.Io,
    scene: *const zassimp.aiScene,
    material: *const zassimp.aiMaterial,
    baseDir: []const u8,
    textureType: zassimp.aiTextureType,
) ![]const u8 {
    const numEmbeddedTextures = scene.mNumTextures;
    var texPath: zassimp.aiString = undefined;

    const result = zassimp.aiGetMaterialTexture(material, textureType, 0, &texPath, null, null, null, null, null, null);
    if (result != .SUCCESS or texPath.length == 0) return "";

    const texturePathSlice = texPath.data[0..texPath.length];

    if (embeddedTextureIndex(texturePathSlice)) |embeddedIdx| {
        if (embeddedIdx < numEmbeddedTextures) {
            const aiTex = scene.mTextures[embeddedIdx];
            const tex = aiTex.*;
            const baseFileName = tex.mFilename.data[0..tex.mFilename.length];
            const outFileName = try std.fmt.allocPrint(allocator, "{s}.png", .{baseFileName});
            const outPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, outFileName });

            var dir = try std.Io.Dir.cwd().openDir(io, baseDir, .{});
            defer dir.close(io);
            const file = try dir.createFile(io, outFileName, .{ .truncate = true });
            defer file.close(io);
            try file.writeStreamingAll(io, tex.pcData[0..tex.mWidth]);

            return outPath;
        }
    }

    const fileName = std.fs.path.basename(texturePathSlice);
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, fileName });
}

fn toMatrix(m: zassimp.aiMatrix4x4) zm.Mat {
    return zm.matFromArr(.{
        m.a1, m.a2, m.a3, m.a4,
        m.b1, m.b2, m.b3, m.b4,
        m.c1, m.c2, m.c3, m.c4,
        m.d1, m.d2, m.d3, m.d4,
    });
}
