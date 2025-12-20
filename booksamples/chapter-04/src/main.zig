const eng = @import("eng");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("memory leaked");

    const allocator = gpa.allocator();

    const wndTitle = "Vulkan Book";
    var game = Game{};
    var engine = try eng.engine.Engine(Game).create(allocator, &game, wndTitle);
    try engine.run();
}

const Game = struct {
    pub fn cleanup(self: *Game) void {
        _ = self;
    }

    pub fn init(self: *Game, engCtx: *eng.engine.EngCtx) void {
        _ = self;
        _ = engCtx;
    }

    pub fn input(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        _ = self;
        _ = engCtx;
        _ = deltaSec;
    }

    pub fn update(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        _ = self;
        _ = engCtx;
        _ = deltaSec;
    }
};
