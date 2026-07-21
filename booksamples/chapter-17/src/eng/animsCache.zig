const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");

pub const AnimsCache = struct {
    modelsMap: std.StringHashMap(eng.mcach.VulkanModel),

    //pub fn init(
    //    self: *AnimsCache,
    //    allocator: std.mem.Allocator,
    //    io: std.Io,
    //    vkCtx: *const vk.ctx.VkCtx,
    //    textureCache: *eng.tcach.TextureCache,
    //    cmdPool: *vk.cmd.VkCmdPool,
    //    vkQueue: vk.queue.VkQueue,
    //    initData: *const eng.engine.InitData,
    //) !void {}
};
