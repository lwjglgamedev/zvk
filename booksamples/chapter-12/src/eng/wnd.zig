const std = @import("std");
const sdl3 = @import("sdl3");
const zgui = @import("zgui");

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

        const bounds = try sdl3.video.Display.getUsableBounds(try sdl3.video.Display.getPrimaryDisplay());

        const window = try sdl3.video.Window.init(
            wndTitle,
            @as(u32, @intCast(bounds.w)),
            @as(u32, @intCast(bounds.h)),
            .{
                .resizable = true,
                .vulkan = true,
            },
        );

        log.debug("Created window", .{});

        try sdl3.keyboard.startTextInput(window);

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
                .mouse_wheel => {
                    processMouseWheel(event.mouse_wheel.scroll_x, event.mouse_wheel.scroll_y);
                },
                .key_down => {
                    processKey(event.key_down.key.?, event.key_down.down);
                },
                .key_up => {
                    processKey(event.key_up.key.?, event.key_up.down);
                },
                .text_input => {
                    processTextInput(event.text_input.text);
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

    fn processMouseWheel(x: f32, y: f32) void {
        if (zgui.io.getWantCaptureMouse()) {
            zgui.io.addMouseWheelEvent(x, y);
        }
    }

    fn processTextInput(text: [:0]const u8) void {
        zgui.io.addInputCharactersUTF8(text);
    }

    fn processKey(keyCode: sdl3.keycode.Keycode, keyDown: bool) void {
        if (!zgui.io.getWantCaptureKeyboard()) {
            return;
        }

        const result = toZgui(keyCode);

        if (result) |key| {
            zgui.io.addKeyEvent(key, keyDown);
        }
    }

    fn toZgui(keyCode: sdl3.keycode.Keycode) ?zgui.Key {
        return switch (keyCode) {
            .escape => zgui.Key.escape,
            .backspace => zgui.Key.back_space,
            .tab => zgui.Key.tab,
            .return_key => zgui.Key.enter,

            .right => zgui.Key.right_arrow,
            .left => zgui.Key.left_arrow,
            .down => zgui.Key.down_arrow,
            .up => zgui.Key.up_arrow,

            .func1 => zgui.Key.f1,
            .func2 => zgui.Key.f2,
            .func3 => zgui.Key.f3,
            .func4 => zgui.Key.f4,
            .func5 => zgui.Key.f5,
            .func6 => zgui.Key.f6,
            .func7 => zgui.Key.f7,
            .func8 => zgui.Key.f8,
            .func9 => zgui.Key.f9,
            .func10 => zgui.Key.f10,
            .func11 => zgui.Key.f11,
            .func12 => zgui.Key.f12,

            .left_ctrl => zgui.Key.left_ctrl,
            .right_ctrl => zgui.Key.right_ctrl,
            .left_shift => zgui.Key.left_shift,
            .right_shift => zgui.Key.right_shift,
            .left_alt => zgui.Key.left_alt,
            .right_alt => zgui.Key.right_alt,

            .a => zgui.Key.a,
            .b => zgui.Key.b,
            .c => zgui.Key.c,
            .d => zgui.Key.d,
            .e => zgui.Key.e,
            .f => zgui.Key.f,
            .g => zgui.Key.g,
            .h => zgui.Key.h,
            .i => zgui.Key.i,
            .j => zgui.Key.j,
            .k => zgui.Key.k,
            .l => zgui.Key.l,
            .m => zgui.Key.m,
            .n => zgui.Key.n,
            .o => zgui.Key.o,
            .p => zgui.Key.p,
            .q => zgui.Key.q,
            .r => zgui.Key.r,
            .s => zgui.Key.s,
            .t => zgui.Key.t,
            .u => zgui.Key.u,
            .v => zgui.Key.v,
            .w => zgui.Key.w,
            .x => zgui.Key.x,
            .y => zgui.Key.y,
            .z => zgui.Key.z,

            .zero => zgui.Key.zero,
            .one => zgui.Key.one,
            .two => zgui.Key.two,
            .three => zgui.Key.three,
            .four => zgui.Key.four,
            .five => zgui.Key.five,
            .six => zgui.Key.six,
            .seven => zgui.Key.seven,
            .eight => zgui.Key.eight,
            .nine => zgui.Key.nine,

            .space => zgui.Key.space,
            .apostrophe => zgui.Key.apostrophe,
            .comma => zgui.Key.comma,
            .period => zgui.Key.period,
            .slash => zgui.Key.slash,
            .semicolon => zgui.Key.semicolon,
            .backslash => zgui.Key.back_slash,
            .equals => zgui.Key.equal,
            .minus => zgui.Key.minus,
            .grave => zgui.Key.grave_accent,
            .left_bracket => zgui.Key.left_bracket,
            .right_bracket => zgui.Key.right_bracket,

            .kp_0 => zgui.Key.keypad_0,
            .kp_1 => zgui.Key.keypad_1,
            .kp_2 => zgui.Key.keypad_2,
            .kp_3 => zgui.Key.keypad_3,
            .kp_4 => zgui.Key.keypad_4,
            .kp_5 => zgui.Key.keypad_5,
            .kp_6 => zgui.Key.keypad_6,
            .kp_7 => zgui.Key.keypad_7,
            .kp_8 => zgui.Key.keypad_8,
            .kp_9 => zgui.Key.keypad_9,
            .kp_plus => zgui.Key.keypad_add,
            .kp_minus => zgui.Key.keypad_subtract,
            .kp_multiply => zgui.Key.keypad_multiply,
            .kp_divide => zgui.Key.keypad_divide,
            .kp_decimal => zgui.Key.keypad_decimal,
            .kp_enter => zgui.Key.keypad_enter,

            .delete => zgui.Key.delete,
            .insert => zgui.Key.insert,
            .home => zgui.Key.home,
            .end => zgui.Key.end,
            .page_up => zgui.Key.page_up,
            .page_down => zgui.Key.page_down,

            else => zgui.Key.space,
        };
    }
};
