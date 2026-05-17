const std = @import("std");
const toml = @import("toml");

pub const Constants = struct {
    ups: f32,
    validation: bool,

    pub fn load(allocator: std.mem.Allocator, io: std.Io) !Constants {
        var parser = toml.Parser(Constants).init(allocator);
        defer parser.deinit();

        const result = try parser.parseFile(io, "res/cfg/cfg.toml");
        defer result.deinit();

        const tmp = result.value;
        const constants = Constants{
            .ups = tmp.ups,
            .validation = tmp.validation,
        };

        return constants;
    }

    pub fn cleanup(self: *Constants, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
