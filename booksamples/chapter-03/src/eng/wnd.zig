const std = @import("std");
const sdl3 = @import("sdl3");

const log = std.log.scoped(.wnd);

pub const MouseState = struct {
    flags: sdl3.mouse.ButtonFlags,
    x: f32 = 0.0,
    y: f32 = 0.0,
    deltaX: f32 = 0.0,
    deltaY: f32 = 0.0,
};

const Size = struct {
    width: usize,
    height: usize,
};

pub const Wnd = struct {
    window: sdl3.video.Window,
    closed: bool,
    mouseState: MouseState,
    resized: bool,

    pub fn create(wndTitle: [:0]const u8) !Wnd {
        log.debug("Creating window", .{});

        const initFlags = sdl3.InitFlags{ .video = true };
        try sdl3.init(initFlags);
        if (!sdl3.c.SDL_SetHint("SDL_VIDEO_PREFER_WAYLAND", "1")) {
            // Handle error
        }

        sdl3.vulkan.loadLibrary(null) catch |err| {
            std.log.err("Failed to load Vulkan library: {s}", .{@errorName(err)});
            return error.VulkanNotSupported;
        };

        const window = try sdl3.video.Window.init(wndTitle, 300, 300, .{
            .resizable = true,
            .maximized = true,
            .vulkan = true,
        });

        log.debug("Created window", .{});

        log.debug("Waiting for window to be maximized", .{});
        var gotSize = false;
        while (!gotSize) {
            while (sdl3.events.poll()) |event| {
                switch (event) {
                    .window_resized => {
                        const windowSize = try window.getSize();
                        log.debug("Window resized to {d}x{d}", .{ windowSize[0], windowSize[1] });
                        gotSize = true;
                    },
                    else => {},
                }
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }

        return .{
            .window = window,
            .closed = false,
            .mouseState = .{ .flags = .{
                .left = false,
                .right = false,
                .middle = false,
                .side1 = false,
                .side2 = false,
            } },
            .resized = false,
        };
    }

    pub fn cleanup(self: *Wnd) !void {
        log.debug("Destroying window", .{});
        self.window.deinit();
        sdl3.shutdown();
    }

    pub fn getSize(self: *Wnd) !Size {
        const res = try sdl3.video.Window.getSizeInPixels(self.window);
        return Size{ .width = res[0], .height = res[1] };
    }

    pub fn isKeyPressed(self: *Wnd, keyCode: sdl3.Scancode) bool {
        _ = self;
        const keyState = sdl3.keyboard.getState();
        return keyState[@intFromEnum(keyCode)];
    }

    pub fn pollEvents(self: *Wnd) !void {
        self.resized = false;
        self.mouseState.deltaX = 0.0;
        self.mouseState.deltaY = 0.0;

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => self.closed = true,
                .mouse_motion => {
                    self.mouseState.deltaX += event.mouse_motion.x_rel;
                    self.mouseState.deltaY += event.mouse_motion.y_rel;
                },
                .window_resized => {
                    self.resized = true;
                },
                else => {},
            }
        }
        const mouseState = sdl3.mouse.getState();

        self.mouseState.flags = mouseState[0];
        self.mouseState.x = mouseState[1];
        self.mouseState.y = mouseState[2];
    }
};
