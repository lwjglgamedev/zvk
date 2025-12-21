const std = @import("std");
const sdl3 = @import("sdl3");

const log = std.log.scoped(.wnd);

pub const MouseState = struct {
    flags: sdl3.mouse.ButtonFlags,
    x: f32 = 0.0,
    y: f32 = 0.0,
    prevX: f32 = 0.0,
    prevY: f32 = 0.0,
    deltaX: f32 = 0.0,
    deltaY: f32 = 0.0,
    scroll: f32 = 0.0,
};

const Size = struct {
    width: usize,
    height: usize,
};

pub const Wnd = struct {
    initFlags: sdl3.InitFlags,
    window: sdl3.video.Window,
    closed: bool,
    mouseState: MouseState,
    keyState: ?[]const bool,

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
            .initFlags = initFlags,
            .window = window,
            .closed = false,
            .mouseState = .{ .flags = .{
                .left = false,
                .right = false,
                .middle = false,
                .side1 = false,
                .side2 = false,
            } },
            .keyState = null,
        };
    }

    pub fn cleanup(self: *Wnd) !void {
        log.debug("Destroying window", .{});
        self.window.deinit();
        sdl3.quit(self.initFlags);
    }

    pub fn getSize(self: *Wnd) !Size {
        const res = try sdl3.video.Window.getSize(self.window);
        return Size{ .width = res[0], .height = res[1] };
    }

    pub fn isKeyPressed(self: *Wnd, keyCode: sdl3.Scancode) bool {
        var result = false;
        if (self.keyState) |state| {
            result = state[@intFromEnum(keyCode)];
        }

        return result;
    }

    pub fn pollEvents(self: *Wnd) !void {
        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => self.closed = true,
                .mouse_wheel => {
                    if (event.mouse_wheel.scroll_y != 0.0) {
                        self.mouseState.scroll = event.mouse_wheel.scroll_y;
                    }
                },
                else => {},
            }
        }

        const keyState = sdl3.keyboard.getState();
        self.keyState = keyState;

        const mouseState = sdl3.mouse.getState();

        self.mouseState.deltaX = 0.0;
        self.mouseState.deltaY = 0.0;

        self.mouseState.prevX = self.mouseState.x;
        self.mouseState.prevY = self.mouseState.y;

        self.mouseState.flags = mouseState[0];
        self.mouseState.x = mouseState[1];
        self.mouseState.y = mouseState[2];

        self.mouseState.deltaX = self.mouseState.x - self.mouseState.prevX;
        self.mouseState.deltaY = self.mouseState.y - self.mouseState.prevY;
    }
};
