const std = @import("std");
const toml = @import("toml");

pub const Constants = struct {
    ups: f32,

    pub fn load(allocator: std.mem.Allocator) !Constants {
        var parser = toml.Parser(Constants).init(allocator);
        defer parser.deinit();

        const result = try parser.parseFile("res/cfg/cfg.toml");
        defer result.deinit();

        const tmp = result.value;
        const constants = Constants{
            .ups = tmp.ups,
        };

        return constants;
    }

    pub fn cleanup(self: *Constants, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
