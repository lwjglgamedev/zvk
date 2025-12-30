# Chapter 01 - Setting Up The Basics

In this chapter, we will set up all the base code required to define a basic rendering loop. This game loop will have these
responsibilities: constantly render new frames; get user inputs; and update the game or application state. The code presented here is not
directly related to Vulkan, but rather the starting point before we dive right in. You will see something similar in any other application
independently of the specific API they use (this is the reason why we will mainly use large chunks of code here, without explaining step of
step every detail).

You can find the complete source code for this chapter [here](../../booksamples/chapter-01).

When posting source code, we wil use `...` to state that there is code above or below the fragment code in a struct or in a function.

## Build

The build file (`build.zig`) file is quite standard. It just builds an executable adding the required dependencies and modules.
We will use the following dependencies:

- [SDL3](https://github.com/Gota7/zig-sdl3) Zig bindings. We will use SDL3 to create windows and handel user input.
In order to add the dependency to the `build.zig.zon` file just execute:
`zig fetch --save git+https://github.com/Gota7/zig-sdl3#v0.1.5`
- [TOML](https://github.com/sam701/zig-toml) to be able to parse configuration files.
In order to add the dependency to the `build.zig.zon` file just execute:
`zig fetch --save git+https://github.com/sam701/zig-toml#zig-0.15`
- [Vulkan](https://github.com/Snektron/vulkan-zig) Zig bindings.
In order to add the dependency to the `build.zig.zon` file just execute:
`zig fetch --save git+https://github.com/Snektron/vulkan-zig#zig-0.15-compat`

> [!WARNING]  
> In order for Vulkan to work you will need the [Vulkan SDK](https://vulkan.lunarg.com/sdk/home). Just download the proper package for your
> operative system. Once installed, you will need to set up an environment variable named `VULKAN_SDK` which points to the root folder of
> the Vulkan SDK. The build file assumes that there is a `vk.xml` file in the Vulkan SDK. It will look for it in the following folders:
>
> - `$VULKAN_SDK/share/vulkan/registry`
> - `$VULKAN_SDK/x86_64/share/vulkan/registry`
>
> Make sure the `vk.xml` file is located there or change the path accordingly. It its required to generate the zig Vulkan bindings.

You will need also the Vulkan SDK when enabling validation.

The `build.zig` file is defined like this:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "chapter-01",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // SDL3
    const sdl3Dep = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .callbacks = false,
        .ext_image = true,
    });
    const sdl3 = sdl3Dep.module("sdl3");
    exe.root_module.addImport("sdl3", sdl3);

    // Vulkan
    const vk_sdk = std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK") catch {
        std.debug.panic("Environment variable VULKAN_SDK is not set", .{});
    };
    const primary = std.fs.path.join(b.allocator, &.{ vk_sdk, "share", "vulkan", "registry", "vk.xml" }) catch {
        std.debug.panic("Error constructing vk.xml path", .{});
    };
    const fallback = std.fs.path.join(b.allocator, &.{ vk_sdk, "x86_64", "share", "vulkan", "registry", "vk.xml" }) catch {
        std.debug.panic("Error constructing vk.xml path", .{});
    };
    const vk_xml_abs = blk: {
        if (std.fs.cwd().access(primary, .{})) |_| {
            break :blk primary;
        } else |_| {}

        if (std.fs.cwd().access(fallback, .{})) |_| {
            break :blk fallback;
        } else |_| {}

        std.debug.panic("vk.xml not found in Vulkan SDK", .{});
    };
    const vk_xml: std.Build.LazyPath = .{ .cwd_relative = vk_xml_abs };
    const vulkan_dep = b.dependency("vulkan", .{
        .registry = vk_xml,
    });
    const vulkan = vulkan_dep.module("vulkan-zig");
    exe.root_module.addImport("vulkan", vulkan);

    // TOML
    const tomlDep = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });
    const toml = tomlDep.module("toml");

    // Com
    const com = b.addModule("com", .{ .root_source_file = b.path("src/eng/com/mod.zig") });
    com.addImport("toml", toml);
    exe.root_module.addImport("com", com);

    // Engine
    const eng = b.addModule("eng", .{ .root_source_file = b.path("src/eng/mod.zig") });
    eng.addImport("com", com);
    eng.addImport("sdl3", sdl3);
    exe.root_module.addImport("eng", eng);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
```

## Main

So let's start from the beginning with, of all things, our `main.zig` file:

```zig
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
```

As you can see, in the `main` function, we just start our render/game engine, modeled by the `Engine` struct. This struct requires, in its
`create` function, the name of the window and a reference to the `Game` struct which will implement the application logic. This is
controlled by the following functions:

- `cleanup`: Which is invoked when the application finished to properly release the acquired resources.
- `init`: Invoked upon application startup to create the required resources (meshes, textures, etc.).
- `input`: Which is invoked periodically so that the application can update its stated reacting to user input.
- `update`: Which is invoked periodically so that the application can update its state.

## Engine

Engine code us located under `src/eng` and all the submodules are defined in the `mod.zig` file:

```zig
pub const engine = @import("eng.zig");
pub const rend = @import("render.zig");
pub const wnd = @import("wnd.zig");
```

This is the source code of the `Engine` type defined in the `eng.zig` file:

```zig
const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");

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

            const render = try eng.rend.Render.create();

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
```

The `EngCtx`servers as a context holder for the main elements of the engine, the allocator, the engine constants (we will come back to this
later on), and the main window. The `Engine` type needs to be instantiated through the `create` function which just loads the constants and
creates the window. It provides a `cleanup` function which just frees the allocated resources. The `run` function is where the game loop is
implemented. We basically control the elapsed time since the last loop block to check if enough seconds have passed to update the state. If
so, we've calculated the elapsed time since the last update and invoke the `update` function from the `GameLogic` reference. We invoke the
`input` from the `GameLogic` instance and the `render` function in each turn of the loop. Later on, we will be able to limit the frame rate
using vsync, or leave it uncapped. bu now it will just run at full speed.

You may have noticed that we use a struct named `Constants`, which in this case establishes the updates per second. This is a struct which
reads a property file that will allow us to configure several parameters of the engine at runtime. It is defined in the `com` module
(named for common), which requires a new `mod.zig` file:

```zig
pub const common = @import("common.zig");
```

The `Constants` struct is defined in the `common.zig` file:

```zig
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
```

The code is pretty straight forward. We just use TOML to parse `res/cfg/cfg.toml` file to load the value of the updates per second
configuration parameter.

Right now the `cfg.toml` is defined like this:

```toml
ups=40
```

At this point, the `Render` struct is just an empty shell:

```zig
const eng = @import("mod.zig");
const std = @import("std");

pub const Render = struct {
    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;
    }

    pub fn create() !Render {
        return .{};
    }

    pub fn render(self: *Render, engCtx: *eng.engine.EngCtx) !void {
        _ = self;
        _ = engCtx;
    }
};
```

## Window

Now it's the turn for our `Wnd` structure which mainly deals with window creation and input management. Alongside that, this struct is the
first one which shows the first tiny bits of Vulkan. Let's start by examining its main attributes and `create` function used to instantiate
it.


```zig
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
    ...
};
```

The code it's self-explanatory, we basically initialize SDL, and when in Linux set `SDL_VIDEO_PREFER_WAYLAND` to prioritize Wayland backend.
After that, we get the usable bounds for the new window on the primary monitor. We set the window to be resizable and a flag stating that it
will be used for Vulkan. The `MouseState` struct will be used later on to dump mouse state (state of the buttons, position of the mouse and
the displacement from previous position modelled by `deltaX` and `deltaY` attributes).

The rest of the functions are defined like this:

```zig
pub const Wnd = struct {
    ...
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
```
The `cleanup` function shall be called to free allocated resources. The `getSize` function will return current size in pixels and 
`isKeyPressed` returns `true` if the key code passed as a parameter is currently pressed. The `pollEvents` will be called before input
processing and basically checks if the window should be closed, if the mouse has moved (to compute relative displacement) and if the
window has been resized. It also retrieves mouse state.


If you run the sample, you will get a nice black window that you can resize, move and close. With that, this chapter comes to its end. In
the next chapter, we will start viewing the first basic Vulkan concepts.

[Next chapter](../chapter-02/chapter-02.md)