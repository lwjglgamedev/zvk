const std = @import("std");
const toml = @import("toml");

pub const FRAMES_IN_FLIGHT = 2;

pub const Constants = struct {
    gpu: []const u8,
    swapChainImages: u8,
    ups: f32,
    validation: bool,
    vsync: bool,

    pub fn load(allocator: std.mem.Allocator) !Constants {
        var parser = toml.Parser(Constants).init(allocator);
        defer parser.deinit();

        const result = try parser.parseFile("res/cfg/cfg.toml");
        defer result.deinit();

        const tmp = result.value;

        const constants = Constants{
            .gpu = try allocator.dupe(u8, tmp.gpu),
            .swapChainImages = tmp.swapChainImages,
            .ups = tmp.ups,
            .validation = tmp.validation,
            .vsync = tmp.vsync,
        };

        return constants;
    }

    pub fn cleanup(self: *Constants, allocator: std.mem.Allocator) void {
        allocator.free(self.gpu);
    }
};
