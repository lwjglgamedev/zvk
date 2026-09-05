const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");

pub const EngCtx = struct {
    allocator: std.mem.Allocator,
    constants: com.common.Constants,
    io: std.Io,
    wnd: eng.wnd.Wnd,

    pub fn cleanup(self: *EngCtx) void {
        self.wnd.cleanup();
        self.constants.cleanup(self.allocator);
    }
};

pub fn Engine(comptime GameLogic: type) type {
    return struct {
        engCtx: EngCtx,
        gameLogic: *GameLogic,
        render: eng.rend.Render,

        fn cleanup(self: *Engine(GameLogic)) void {
            self.gameLogic.cleanup();
            self.render.cleanup(self.engCtx.allocator);
            self.engCtx.cleanup();
        }

        pub fn create(allocator: std.mem.Allocator, io: std.Io, gameLogic: *GameLogic, wndTitle: [:0]const u8) !Engine(GameLogic) {
            var constants = try com.common.Constants.load(allocator, io);
            errdefer constants.cleanup(allocator);

            var wnd = try eng.wnd.Wnd.create(wndTitle);
            errdefer wnd.cleanup();

            const engCtx = EngCtx{
                .allocator = allocator,
                .constants = constants,
                .io = io,
                .wnd = wnd,
            };

            const render = try eng.rend.Render.create(allocator, engCtx.constants, engCtx.wnd.window);

            return .{
                .engCtx = engCtx,
                .gameLogic = gameLogic,
                .render = render,
            };
        }

        fn init(self: *Engine(GameLogic)) !void {
            self.gameLogic.init(&self.engCtx);
        }

        pub fn run(self: *Engine(GameLogic)) !void {
            defer self.cleanup();
            try self.init();

            const timeU: f32 = 1.0 / self.engCtx.constants.ups;
            var lastTime = std.Io.Clock.now(.awake, self.engCtx.io);
            var updateTime = lastTime;
            var deltaUpdate: f32 = 0.0;

            while (!self.engCtx.wnd.closed) {
                const now = std.Io.Clock.now(.awake, self.engCtx.io);
                const deltaNs = lastTime.durationTo(now).toNanoseconds();
                const deltaSec = @as(f32, @floatFromInt(deltaNs)) / 1_000_000_000.0;
                deltaUpdate += deltaSec / timeU;

                try self.engCtx.wnd.pollEvents();
                self.gameLogic.input(&self.engCtx, deltaSec);

                if (deltaUpdate >= 1) {
                    const difNs = updateTime.durationTo(now).toNanoseconds();
                    const difUpdateSecs = @as(f32, @floatFromInt(difNs)) / 1_000_000_000.0;
                    self.gameLogic.update(&self.engCtx, difUpdateSecs);
                    deltaUpdate -= 1;
                    updateTime = now;
                }

                try self.render.render(&self.engCtx);
                lastTime = now;
            }
        }
    };
}
