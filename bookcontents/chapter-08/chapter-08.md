# Chapter 08 - Complex models and textures

In this chapter we will add support for loading complex 3D models which may include textures.

You can find the complete source code for this chapter [here](../../booksamples/chapter-08).

## ZMesh and zstbi

In order to load complex mopdesl from disk we will use the [ZMesh](https://github.com/zig-gamedev/zmesh) library. Therefore, you will need to add the
dependency to the `build-.zig.zon` using `https://github.com/zig-gamedev/zmesh`.

We will create a new executable to process 3D models ([GLTF](https://github.com/KhronosGroup/glTF) models in our case). This executable will process
a 3D model and will generate the required file sto load de model data into Vulkan. Therefore, in the `build.zig` file we will ad the following code at the end:

```zig
pub fn build(b: *std.Build) void {
    ...
    const modelGen = b.addExecutable(.{
        .name = "model-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/eng/modelGen.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const zmesh = b.dependency("zmesh", .{});
    modelGen.root_module.addImport("zmesh", zmesh.module("root"));
    modelGen.linkLibrary(zmesh.artifact("zmesh"));
    b.installArtifact(modelGen);
}
```

The code for that executable will be located in the `src/eng/modelGen.zig` file.

Since we will also need to load textures, we will use the [Zstbi](https://github.com/zig-gamedev/zstbi) library. Therefore, you will need to add the
dependency to the `build-.zig.zon` using `zig fetch --save git+https://github.com/zig-gamedev/zstbi.

In order to load complex 3D models, we will develop a pre-processing stage to transform models using zmesh into an
intermediate format which will be ready to be loaded into the GPU. We will create a new struct that loads these models,
process them using zmesh and ump the results to a JSOn file. It is a little bit overkill for a tutorial like this,
but it will prevent you to process models again and again and will simplify the loading process at the end.
The `main` function defined in the `modelGen.zgi` file starts like this (you can skip this part if you are not interested in preprocessing
the models):

```zig
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
    ...
}
```

The function expects to receive as a command line argument the path to the model precede dby the "-m" flag. After that we will get the base directory
of the model (used to construct other paths later on) and assign the model identifier using the file name. Then we initialize the zmesh library and load 
the GLTF file by calling the function `parseAndLoadFile`.

```zig
pub fn main() !void {
    ...
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
    ...
}
```

Then we process the materials defined in the model:

```zig
pub fn main() !void {
    ...
    var materialList = std.ArrayListUnmanaged(eng.mdata.MaterialData){};
    defer materialList.deinit(allocator);

    if (data.materials_count > 0 and data.materials != null) {
        const materials = data.materials.?[0..data.materials_count];
        for (materials, 0..) |material, i| {
            const materialData = try processMaterial(allocator, &material, baseDir, modelId, i);
            try materialList.append(allocator, materialData);
        }
    }
    ...
}
```

We just iterate over the model materials and call the `processMaterial` which will return a `MaterialData` instance which stored in a list.
The `MaterialData` is defined in a struct like this (in the `src/eng/modelData.zig` file):

```zig
pub const MaterialData = struct {
    id: []const u8,
    texturePath: []const u8,
    color: [4]f32,
};
```

It just contains an identifier the path to a texture (for the albedo color by now if available) and a color (for the albedo also).
Let's continue with the `main` function code:

```zig
pub fn main() !void {
    ...
    // Create indices file
    const idxFileName = try std.fmt.allocPrint(allocator, "{s}.idx", .{modelId});
    const idxFile = try dir.createFile(idxFileName, .{ .truncate = true });
    defer idxFile.close();

    // Create vertices file
    const vtxFileName = try std.fmt.allocPrint(allocator, "{s}.vtx", .{modelId});
    const vtxFile = try dir.createFile(vtxFileName, .{ .truncate = true });
    defer vtxFile.close();
    ...
}
```
We will create two files, one that will store vertices data and the other that will store the indices. These files will store data
for all the meshes. Let's continue with the code.

```zig
pub fn main() !void {
    ...
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
    ...
}
```

After that, we get the meshes and their primitives. In GLTF a model is composed by meshes and a meshes is composed by
primitives. In our case we will assimilate primitive as meshes in our engines. GLTF primitives will define the vertices, texture coordinates,
indices and will be associated to materials, so, from our point of view are the meshes. Each primitive will be processed in the `processMesh`
function and added to a list as a `MeshIntData` struct. This struct is defined in the beginning of the file as:

```zig
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
```

It stores the mesh identifier (`id`), the identifier of the material associated to it (`materialId`), the indices, positions and texture
coordinates. We need this interim structs (that is what `Int` means) to store the data for the vertices and the indices. We will dump that
that to t he binary files associated to the model and will not need them in the `eng.mdata.MeshData` struct, which will be the one used in
the engine. In the `eng.mdata.MeshData` struct we will just store the offsets inside those binary files for the vertices and indices data
(Remember that this struct is stored in the `src/eng/modelData.zig` file):

```zig
pub const MeshData = struct {
    id: []const u8,
    materialId: []const u8,
    idxOffset: usize,
    idxSize: usize,
    vtxOffset: usize,
    vtxSize: usize,
};
```

Therefore, after we have dumped the data we just transform from `MeshIntData` to `MeshData`, store in the mesh lists and update the vertices
and indices offsets accordingly. You may have notices that we check if the number of texture coordinates match the number of positions.
If we have more positions that texture coordinates we just fill upo with zeroes.


Going back to the `main` function:

```zig
pub fn main() !void {
    ...
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
    ...
}
```

Now it is the turn to dump materials information to a JSON file. We will just dump the list of materials using Zig's builtin
JSON support. After that, we will build the model information:

```zig
pub fn main() !void {
    ...
    // Build model data
    const idxRelPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, idxFileName });
    const vtxRelPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ baseDir, vtxFileName });

    const modelData = eng.mdata.ModelData{
        .id = modelId,
        .meshes = meshDataList,
        .idxFilename = idxRelPath,
        .vtxFilename = vtxRelPath,
    };
    ...
}
```

The model data struct has been updated store the path to the vertices and indices files. You will need to modfiy the struct as
follows (Remember that this struct is stored in the `src/eng/modelData.zig` file):

```zig
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
```

After that, going back to the `main` function, we will just dump model information to a JSON file:

Let's review the `processMaterial` method:

```zig
pub fn main() !void {
    ...
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
```

That's all. Let's review now the missing functions used in `main`. The first one, `normalizePath`, just modifies path
strings to use `/` as path separator:

```zig
pub fn normalizePath(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, input_path.len);
    for (input_path, 0..) |c, i| {
        result[i] = if (c == '\\') '/' else c;
    }
    return result;
}
```

The next function is the `processMaterial` one:

```zig
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
```

This functions is executed for each of the materials found in the model file. First we retrieve the diffuse texture path (if present)
and then, the diffuse color accesing `zmesh.io.zcgltf.Material`'s `pbr_metallic_roughness` attribute. cWe just dump that
information into a `eng.mdata.MaterialData` instance and return it. We will not be supporting embedded textures (textures contained inside the
GLTF file) by now.

The next function is the `processMesh` one, which processes GLTF primitives and converts them to `MeshIntData` instances:

```zig
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
```

This method extracts indices, positions and texture coordinates from a GLTF primitive by calling the `appendMeshPrimitive`. It also
associates the mes with its material. Each primitive will have a pointer to the associated material the vertices, we need to
get the index of that material in the list that we constructed previously taking that pointer as a input. This what the 
`materialIndexFromPtr` function does:

```zig
fn materialIndexFromPtr(
    data: *const zmesh.io.zcgltf.Data,
    mat: *const zmesh.io.zcgltf.Material,
) usize {
    const base = @intFromPtr(data.materials.?);
    const ptr = @intFromPtr(mat);
    return (ptr - base) / @sizeOf(zmesh.io.zcgltf.Material);
}
```

All the materials pointers are basically an offset over the base pointer which address the materials list, so subtracting the 
material pointer form the base pointer we basically get an offset in bytes which we can divided by the `zmesh.io.zcgltf.Material`
size to get an index.

Finally the last function just prints some help text if the wrong number of arguments have been passed to the model generation executable:

```zig
fn printHelp() void {
    std.debug.print(
        \\Usage: model-gen [OPTIONS]
        \\
        \\Options:
        \\  -m  FILE       Path to the model file
        \\
    , .{});
}
```

## Textures

We have already created the classes that support images and image views, however, we need to be able to load texture context from image
files and to properly copy its contents to a buffer setting up the adequate layout. We will create a new struct named `VkTexture` to support
this. It will be included in a new file under `src/eng/vk/vkTexture` file. You will need to include in the `mod.zig` file: 
`pub const text = @import("vkTexture.zig");`. In order to create textures we will a helper struct that will hold relevant information
for texture creation. It will be named `VkTextureInfo` (defined in the same file):

```zig
pub const VkTextureInfo = struct {
    data: []const u8,
    width: u32,
    height: u32,
    format: vulkan.Format,
};
```

It will store the texture data, its dimensions and the format of the image data. We will review now the `VkTexture` struct which starts like this:

```zig
pub const VkTexture = struct {
    vkImage: vk.img.VkImage,
    vkImageView: vk.imv.VkImageView,
    vkStageBuffer: ?vk.buf.VkBuffer,
    width: u32,
    height: u32,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, vkTextureInfo: *const VkTextureInfo) !VkTexture {
        const flags = vulkan.ImageUsageFlags{
            .transfer_dst_bit = true,
            .sampled_bit = true,
        };
        const vkImageData = vk.img.VkImageData{
            .width = vkTextureInfo.width,
            .height = vkTextureInfo.height,
            .usage = flags,
            .format = vkTextureInfo.format,
        };
        const vkImage = try vk.img.VkImage.create(vkCtx, vkImageData);
        const imageViewData = vk.imv.VkImageViewData{ .format = vkTextureInfo.format };

        const vkImageView = try vk.imv.VkImageView.create(vkCtx.vkDevice, vkImage.image, imageViewData);

        const dataSize = vkTextureInfo.data.len;
        const vkStageBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            dataSize,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );
        try vk.buf.copyDataToBuffer(vkCtx, &vkStageBuffer, &vkTextureInfo.data);

        return .{
            .vkImage = vkImage,
            .vkImageView = vkImageView,
            .vkStageBuffer = vkStageBuffer,
            .width = vkTextureInfo.width,
            .height = vkTextureInfo.height,
        };
    }
    ...
};
```

The `create` function will create new instances of `VkTexture` structs and will receive, in addition of the Vulkan the context,
an instance of the `vkTextureInfo` struct that will hold all the required data. It creates first an image and image view and then
a  staging buffer which is CPU accessible to copy image contents. It is interesting to review the usage flags we are using in in this case:

- `transfer_dst_bit` (`VK_IMAGE_USAGE_TRANSFER_DST_BIT`): The image can be used as a destination of a transfer command.
We need this, because in our case, we will copy from a staging buffer to the image.
- `sampled_bit` (`VK_IMAGE_USAGE_SAMPLED_BIT`): The image can be used to occupy a descriptor set (more on this later).
In our case, the image needs to be used by a sampler in a fragment shader, so we need to set this flag.

At the end of the `create` function we just copy the image data to the staging buffer associated to the image by calling a function
that is located in the `vkBuffer.zig`:

```zig
pub fn copyDataToBuffer(vkCtx: *const vk.ctx.VkCtx, vkBuffer: *const VkBuffer, data: *const []const u8) !void {
    const buffData = try vkBuffer.map(vkCtx);
    defer vkBuffer.unMap(vkCtx);

    const gpuBytes: [*]u8 = @ptrCast(buffData);

    @memcpy(gpuBytes[0..data.len], data.ptr);
}
```

The `VkTexture` struct defines a `cleanup` function to free the resources:

```zig
pub const VkTexture = struct {
    ...
    pub fn cleanup(self: *VkTexture, vkCtx: *const vk.ctx.VkCtx) void {
        if (self.vkStageBuffer) |sb| {
            sb.cleanup(vkCtx);
        }
        self.vkImageView.cleanup(vkCtx.vkDevice);
        self.vkImage.cleanup(vkCtx);
    }
    ...
};
```

In order for Vulkan to correctly use the image, we need to perform the following steps:
- We need to set the image into `transfer_dst_optimal` (`VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL`) layout to be ready
to be in transfer state so we can copy the contents of the buffer.
- Record a copy operation from the buffer to the image.
- Set the image into `shader_read_only_optimal` (`VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL`) so it can be used in shaders.

We will do all of these operations by recording image memory barriers and copy operations inside a command buffer in a
function called `recordTransition`, which is defined like this:

```zig
pub const VkTexture = struct {
    ...
    pub fn recordTransition(self: *const VkTexture, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        // Record transition to dst optimal
        const device = vkCtx.vkDevice.deviceProxy;
        const initBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.undefined,
            .new_layout = vulkan.ImageLayout.transfer_dst_optimal,
            .src_stage_mask = .{ .top_of_pipe_bit = true },
            .dst_stage_mask = .{ .all_transfer_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .transfer_write_bit = true },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = vulkan.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
            },
            .image = self.vkImage.image,
        }};
        const initDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = initBarriers.len,
            .p_image_memory_barriers = &initBarriers,
        };
        device.cmdPipelineBarrier2(cmdHandle, &initDepInfo);

        // Record copy
        const region = [_]vulkan.BufferImageCopy{.{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = vulkan.ImageAspectFlags{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .image_extent = .{
                .width = self.vkImage.width,
                .height = self.vkImage.height,
                .depth = 1,
            },
        }};
        device.cmdCopyBufferToImage(
            cmdHandle,
            self.vkStageBuffer.?.buffer,
            self.vkImage.image,
            vulkan.ImageLayout.transfer_dst_optimal,
            region.len,
            &region,
        );

        // Record transition to src optimal
        const endBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.transfer_dst_optimal,
            .new_layout = vulkan.ImageLayout.shader_read_only_optimal,
            .src_stage_mask = .{ .all_transfer_bit = true },
            .dst_stage_mask = .{ .fragment_shader_bit = true },
            .src_access_mask = .{ .transfer_write_bit = true },
            .dst_access_mask = .{ .shader_read_bit = true },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = vulkan.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
            },
            .image = self.vkImage.image,
        }};
        const endDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = endBarriers.len,
            .p_image_memory_barriers = &endBarriers,
        };
        device.cmdPipelineBarrier2(cmdHandle, &endDepInfo);
    }
};
```

This function first records the transition of the image layout to one where we can copy the staging buffer contents. That is,
we transition from `vulkan.ImageLayout.undefined` (`VK_IMAGE_LAYOUT_UNDEFINED`) to `vulkan.ImageLayout.transfer_dst_optimal`
(`VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL`) layout by setting an image memory barrier. After that, it records the commands to copy
the staging buffer contents to the image. It first defines the region to copy (in this case the whole image size) and calls
the `cmdCopyBufferToImage` function. Finally, we record the commands to transition the layout from `vulkan.ImageLayout.transfer_dst_optimal`
(`VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL`) to `vulkan.ImageLayout.shader_read_only_optimal` (`VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL`)
by setting again an image memory barrier. The texture will be used in a shader, no one will be writing to it after we have finished
with the staging buffer, therefore, the `vulkan.ImageLayout.shader_read_only_optimal` is the appropriate state.

An important issue to highlight is that we are recording commands that can be submitted to a queue. In this way, we can group the commands associated to several textures and submit them using a single call, instead of going one by one. This should  reduce the loading time when dealing with several textures.

Now that the `VkTexture` struct is complete, we are ready to to use it. In 3D models, it is common that multiple meshes share the same texture file,
we want to control that to avoid loading the same resource multiple times. We will create a new struct named `TextureCache` to control this:

```zig
const com = @import("com");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const zstbi = @import("zstbi");
const log = std.log.scoped(.eng);

pub const MAX_TEXTURES: u32 = 100;

pub const TextureInfo = struct {
    id: []const u8,
    data: []const u8,
    width: u32,
    height: u32,
    format: vulkan.Format,
};

const EMPTY_PIXELS = [_]u8{ 0, 0, 0, 0 };

pub const TextureCache = struct {
    textureMap: std.ArrayHashMap([]const u8, vk.text.VkTexture, std.array_hash_map.StringContext, false),
    ...
    pub fn create(allocator: std.mem.Allocator) TextureCache {
        const textureMap = std.ArrayHashMap([]const u8, vk.text.VkTexture, std.array_hash_map.StringContext, false).init(allocator);
        return .{ .textureMap = textureMap };
    }
    ...    
};
```

This struct will store in a `ArrayHashMap` the textures indexed by the path to the file use to load them. The reason for this structure is to be able to recover the texture by its identifier (like in a `StringHashMap`) while maintaining the insertion order. Although by now, we will be accessing by identifier,
later on we will need to get the textures by the position they were loaded.

The `TextureCache` struct defines a function to add a `VkTexture` named `addTexture`. That function receives a `TextureInfo` struct
with all te information required to cerate a `VkTexture` and will check if the texture has been already added to the cache,
to avoid creating multiple textures for the same data. If it does not exists it will just instantiate a new `VkTexture`
and store it in the cache. We have another variant  thar receives a  a path to a texture and another one receiving a
`TextureInfo` will receive the path to the texture image:

```zig
pub const TextureCache = struct {
    ...
    pub fn addTexture(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, textureInfo: *const TextureInfo) !void {
        if (self.textureMap.contains(textureInfo.id)) {
            return;
        }
        if (self.textureMap.count() >= MAX_TEXTURES) {
            @panic("Exceeded maximum number of textures");
        }
        const ownedId = try allocator.dupe(u8, textureInfo.id);
        const vkTextureInfo = vk.text.VkTextureInfo{
            .data = textureInfo.data,
            .width = textureInfo.width,
            .height = textureInfo.height,
            .format = textureInfo.format,
        };
        const vkTexture = try vk.text.VkTexture.create(vkCtx, &vkTextureInfo);
        try self.textureMap.put(ownedId, vkTexture);
    }

    pub fn addTextureFromPath(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, path: [:0]const u8) !bool {
        if (self.textureMap.count() >= MAX_TEXTURES) {
            @panic("Exceeded maximum number of textures");
        }
        std.fs.cwd().access(path, .{}) catch {
            log.err("Could not load texture file [{s}]", .{path});
            return false;
        };
        var image = try zstbi.Image.loadFromFile(path, 4);
        defer image.deinit();

        const textureInfo = TextureInfo{
            .id = path,
            .data = image.data,
            .width = image.width,
            .height = image.height,
            .format = vulkan.Format.r8g8b8a8_srgb,
        };

        try self.addTexture(allocator, vkCtx, &textureInfo);
        return true;
    }
    ...
};
```

We will add also the classical `cleanup` function to free the images and a function to get a texture using its
identifier.

```zig
pub const TextureCache = struct {
    ...
    pub fn cleanup(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        var iter = self.textureMap.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            const texture = entry.value_ptr;
            texture.cleanup(vkCtx);
        }
        self.textureMap.deinit();
    }

    pub fn getTexture(self: *const TextureCache, id: []const u8) vk.text.VkTexture {
        const texture = self.textureMap.get(id) orelse {
            @panic("Could not find texture");
        };

        return texture;
    }
    ...
};
```

The only missing function is `recordTextures` which performs layout transitions over all the textures stored in the cache.
It is defined like this:

```zig
pub const TextureCache = struct {
    ...
    pub fn recordTextures(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, vkCmdPool: *vk.cmd.VkCmdPool, vkQueue: vk.queue.VkQueue) !void {
        log.debug("Recording textures", .{});
        const numTextures = self.textureMap.count();
        if (numTextures < MAX_TEXTURES) {
            const numPadding = MAX_TEXTURES - numTextures;
            for (0..numPadding) |_| {
                const id = try com.utils.generateUuid(allocator);
                defer allocator.free(id);
                const textureInfo = TextureInfo{
                    .data = EMPTY_PIXELS[0..],
                    .width = 1,
                    .height = 1,
                    .format = vulkan.Format.r8g8b8a8_srgb,
                    .id = id,
                };
                try self.addTexture(allocator, vkCtx, &textureInfo);
            }
        }
        const cmd = try vk.cmd.VkCmdBuff.create(vkCtx, vkCmdPool, true);
        defer cmd.cleanup(vkCtx, vkCmdPool);

        try cmd.begin(vkCtx);
        const cmdHandle = cmd.cmdBuffProxy.handle;
        var it = self.textureMap.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.recordTransition(vkCtx, cmdHandle);
        }
        try cmd.end(vkCtx);
        try cmd.submitAndWait(vkCtx, vkQueue);

        log.debug("Recorded textures", .{});
    }
    ...
};
```

We first check if we have reached the maximum number of textures. If we do not have reached that size, we will add empty slots
with a default texture (just one pixel). The reason behind this code is that we will be using arrays of textures in the shaders. When using
those arrays, the size needs to be set upfront and it expects to have valid images (empty slots will not work). We will see later
on how this works. After that we just create a command buffer, iterate over the textures calling `recordTextureTransition` and
submit the work and wait it to be completed. Using arrays of textures is also the reason  why we need to keeping track of the
position of each texture is important. This is why we use the `ArrayHashMap` struct which basically keeps insertion order.


## Models and Materials

The next step is to update the `VulkanMesh` struct to hold a reference to the material identifier it is associated:

```zig
pub const VulkanMesh = struct {
    buffIdx: vk.buf.VkBuffer,
    buffVtx: vk.buf.VkBuffer,
    id: []const u8,
    materialId: []const u8,
    numIndices: usize,

    pub fn cleanup(self: *const VulkanMesh, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        self.buffVtx.cleanup(vkCtx);
        self.buffIdx.cleanup(vkCtx);
        allocator.free(self.id);
        allocator.free(self.materialId);
    }
};
```

We will also add a new `VulkanMaterial` struct which will just store an identifier by now:

```zig
pub const VulkanMaterial = struct {
    id: []const u8,

    pub fn cleanup(self: *VulkanMaterial, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
    }
};
```