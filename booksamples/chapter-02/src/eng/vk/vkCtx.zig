const std = @import("std");
const sdl3 = @import("sdl3");
const com = @import("com");
const vk = @import("mod.zig");

pub const VkCtx = struct {
    constants: com.common.Constants,
    vkInstance: vk.inst.VkInstance,

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants) !VkCtx {
        var vkInstance = try vk.inst.VkInstance.create(allocator, constants.validation);
        errdefer vkInstance.cleanup(allocator);

        return .{
            .constants = constants,
            .vkInstance = vkInstance,
        };
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) void {
        self.vkInstance.cleanup(allocator);
    }
};
