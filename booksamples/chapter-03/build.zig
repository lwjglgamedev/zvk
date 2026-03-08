const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "chapter-03",
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
        .callbacks = false,
        .ext_image = true,
    });
    const sdl3 = sdl3Dep.module("sdl3");
    exe.root_module.addImport("sdl3", sdl3);

    // Vulkan
    const vkHeaders = b.dependency("vulkan_headers", .{});
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
    exe.linkLibCpp();

    // Engine
    const eng = b.addModule("eng", .{ .root_source_file = b.path("src/eng/mod.zig") });
    eng.addImport("com", com);
    eng.addImport("sdl3", sdl3);
    eng.addImport("vk", vk);
    exe.root_module.addImport("eng", eng);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
