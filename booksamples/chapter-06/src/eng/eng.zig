const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");

pub const InitData = struct {
    models: []const eng.mdata.ModelData,
};

pub const EngCtx = struct {
    allocator: std.mem.Allocator,
    constants: com.common.Constants,
    wnd: eng.wnd.Wnd,

    pub fn cleanup(self: *EngCtx) !void {
        try self.wnd.cleanup();
        self.constants.cleanup(self.allocator);
    }
};

pub fn Engine(comptime GameLogic: type) type {
    return struct {
        engCtx: EngCtx,
        gameLogic: *GameLogic,
        render: eng.rend.Render,

        fn cleanup(self: *Engine(GameLogic)) !void {
            self.gameLogic.cleanup();
            try self.render.cleanup(self.engCtx.allocator);
            try self.engCtx.cleanup();
        }

        pub fn create(allocator: std.mem.Allocator, gameLogic: *GameLogic, wndTitle: [:0]const u8) !Engine(GameLogic) {
            const engCtx = EngCtx{
                .allocator = allocator,
                .constants = try com.common.Constants.load(allocator),
                .wnd = try eng.wnd.Wnd.create(wndTitle),
            };

            const render = try eng.rend.Render.create(allocator, engCtx.constants, engCtx.wnd.window);

            return .{
                .engCtx = engCtx,
                .gameLogic = gameLogic,
                .render = render,
            };
        }

        fn init(self: *Engine(GameLogic), allocator: std.mem.Allocator) !void {
            var arena = std.heap.ArenaAllocator.init(self.engCtx.allocator);
            const arenaAlloc = arena.allocator();
            defer arena.deinit();

            const initData = try self.gameLogic.init(&self.engCtx, arenaAlloc);
            try self.render.init(allocator, &initData);
        }

        pub fn run(self: *Engine(GameLogic), allocator: std.mem.Allocator) !void {
            try self.init(allocator);

            var timer = try std.time.Timer.start();
            var lastTime = timer.read();
            var updateTime = lastTime;
            var deltaUpdate: f32 = 0.0;
            const timeU: f32 = 1.0 / self.engCtx.constants.ups;

            while (!self.engCtx.wnd.closed) {
                const now = timer.read();
                const deltaNs = now - lastTime;
                const deltaSec = @as(f32, @floatFromInt(deltaNs)) / 1_000_000_000.0;
                deltaUpdate += deltaSec / timeU;

                try self.engCtx.wnd.pollEvents();

                self.gameLogic.input(&self.engCtx, deltaSec);

                if (deltaUpdate >= 1) {
                    const difUpdateSecs = @as(f32, @floatFromInt(now - updateTime)) / 1_000_000_000.0;
                    self.gameLogic.update(&self.engCtx, difUpdateSecs);
                    deltaUpdate -= 1;
                    updateTime = now;
                }

                try self.render.render(&self.engCtx);

                lastTime = now;
            }

            try self.cleanup();
        }
    };
}

pub const EngineAA = struct {
    engCtx: EngCtx,
    render: eng.rend.Render,

    fn cleanup(self: *EngineAA) !void {
        try self.render.cleanup(self.engCtx.allocator);
        try self.engCtx.cleanup();
    }

    pub fn create(allocator: std.mem.Allocator) !Engine {
        const engCtx = EngCtx{
            .allocator = allocator,
            .constants = try com.common.Constants.load(allocator),
            .wnd = try eng.wnd.Wnd.create(),
        };

        const render = try eng.rend.Render.create();

        return .{
            .engCtx = engCtx,
            .render = render,
        };
    }

    fn init(self: *EngineAA) !void {
        _ = self;
    }

    pub fn run(self: *EngineAA) !void {
        try self.init();

        var timer = try std.time.Timer.start();
        var lastTime = timer.read();
        var updateTime = lastTime;
        var deltaUpdate: f32 = 0.0;
        const timeU: f32 = 1.0 / self.engCtx.constants.ups;

        while (!self.engCtx.wnd.closed) {
            const now = timer.read();
            const deltaNs = now - lastTime;
            const deltaSec = @as(f32, @floatFromInt(deltaNs)) / 1_000_000_000.0;
            deltaUpdate += deltaSec / timeU;

            try self.engCtx.wnd.pollEvents();

            //try self.mainGame.input(&self.engCtx, deltaSec);

            if (deltaUpdate >= 1) {
                const diffTimeMillis = @as(f32, @floatFromInt(now - updateTime)) / 1_000_000.0;
                _ = diffTimeMillis;
                //self.engCtx.scene.updateAnimations();
                //try self.mainGame.update(&self.engCtx, diffTimeMillis);
                deltaUpdate -= 1;
                updateTime = now;
            }

            try self.render.render(&self.engCtx);

            lastTime = now;
        }

        try self.cleanup();
    }
};
