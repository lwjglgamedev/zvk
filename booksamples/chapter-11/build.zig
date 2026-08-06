const std = @import("std");

const Shader = struct {
    path: []const u8,
    stage: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "chapter-11",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // SDL3
    const sdl3Dep = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_image = true,
    });
    const sdl3 = sdl3Dep.module("sdl3");
    exe.root_module.addImport("sdl3", sdl3);

    // VMA
    const vmaDep = b.dependency("vma", .{});
    const vmaIncludePath = vmaDep.path("include");
    exe.root_module.link_libcpp = true;

    // Vulkan
    const vkHeaders = b.dependency("vulkan_headers", .{});
    const vkIncludePath = vkHeaders.path("include");
    const vulkanDep = b.dependency("vulkan", .{
        .registry = vkHeaders.path("registry/vk.xml"),
    });
    const vulkan = vulkanDep.module("vulkan-zig");
    exe.root_module.addImport("vulkan", vulkan);

    // TOML
    const tomlDep = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });
    const toml = tomlDep.module("toml");

    // Zmath
    const zmathDep = b.dependency("zmath", .{});
    const zmath = zmathDep.module("root");
    exe.root_module.addImport("zm", zmath);

    // zstbi
    const zstbiDep = b.dependency("zstbi", .{});
    const zstbi = zstbiDep.module("root");

    // Com
    const com = b.addModule("com", .{ .root_source_file = b.path("src/eng/com/mod.zig") });
    com.addImport("toml", toml);
    exe.root_module.addImport("com", com);

    // VKE
    const vk = b.addModule("vk", .{ .root_source_file = b.path("src/eng/vk/mod.zig") });
    vk.addImport("vulkan", vulkan);
    vk.addImport("sdl3", sdl3);
    vk.addImport("com", com);
    exe.root_module.addImport("vk", vk);
    vk.addIncludePath(vmaIncludePath);
    vk.addIncludePath(vkIncludePath);
    vk.addCSourceFile(.{ .file = b.path("src/eng/vk/vma.cpp"), .flags = &.{"-std=c++17"} });

    // Engine
    const eng = b.addModule("eng", .{ .root_source_file = b.path("src/eng/mod.zig") });
    eng.addImport("com", com);
    eng.addImport("sdl3", sdl3);
    eng.addImport("vk", vk);
    eng.addImport("vulkan", vulkan);
    eng.addImport("zmath", zmath);
    eng.addImport("zstbi", zstbi);

    exe.root_module.addImport("eng", eng);
    exe.root_module.addImport("zstbi", zstbi);

    // Shaders
    const shaders = [_]Shader{
        .{ .path = "res/shaders/scn_vtx.glsl", .stage = "vertex" },
        .{ .path = "res/shaders/scn_frg.glsl", .stage = "fragment" },
        .{ .path = "res/shaders/post_vtx.glsl", .stage = "vertex" },
        .{ .path = "res/shaders/post_frg.glsl", .stage = "fragment" },
    };
    for (shaders) |shader| {
        std.log.debug("Compiling [{s}]", .{shader.path});
        const outputPath = b.fmt("{s}.spv", .{shader.path});
        const stage = b.fmt("-fshader-stage={s}", .{shader.stage});
        const compFragment = b.addSystemCommand(&[_][]const u8{
            "glslc",
            "--target-env=vulkan1.3",
            stage,
            "-g", // Debug
            "-o",
            outputPath,
            shader.path,
        });
        b.getInstallStep().dependOn(&compFragment.step);
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const modelGen = b.addExecutable(.{
        .name = "model-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/eng/modelGen.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // zassimp
    const zassimpDep = b.dependency("zig_assimp", .{});
    modelGen.root_module.addImport("zassimp", zassimpDep.module("root"));
    modelGen.root_module.addImport("zmath", zmath);
    b.installArtifact(modelGen);
}
