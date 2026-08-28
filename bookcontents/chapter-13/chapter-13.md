# Chapter 13 - Sound with zaudio

Until this moment we have been dealing with graphics, but another key aspect of every game is audio. In this chapter we will add sound
support.

You can find the complete source code for this chapter [here](../../booksamples/chapter-13).

## zaudio

Audio capability is going to be addressed in this chapter with the help of [zaudio](https://github.com/zig-gamedev/zaudio/) which is a
wrapper for [miniaudio](https://github.com/mackron/miniaudio) library. It is a simple C library which provides high level and low level APIs
to manage sound.

In order to use it we first need to include the [zaudio](https://github.com/zig-gamedev/zaudio/) dependency in the `build.zig.zon` file by
executing the following command: `zig fetch --save=zaudio https://github.com/zig-gamedev/zaudio/archive/fed501100b029213898861b60c6b54f8121dff03.tar.gz`.

After that we shall modify the `build.zig` file:

**File: build.zig**

```zig
pub fn build(b: *std.Build) void {
    ...
    // zaudio
    const zaudioDep = b.dependency("zaudio", .{});
    const zaudio = zaudioDep.module("root");
    ...
    // Engine
    ...
    eng.addImport("zaudio", zaudio);
    ...
    exe.root_module.linkLibrary(zaudioDep.artifact("miniaudio"));
    ...
}
```

## Implementation

We will define in the `src/eng/sound.zig` file the code to manage sound. Therefore, the first step is to include that in the
`src/eng/mod.zig` file: `pub const snd = @import("sound.zig");`.

We will define a new struct named `SoundMgr` which starts like this:

**File: src/eng/sound.zig**

```zig
const std = @import("std");
const zaudio = @import("zaudio");

const log = std.log.scoped(.eng);

pub const SoundMgr = struct {
    engine: *zaudio.Engine,
    soundsMap: std.StringHashMap(*zaudio.Sound),
    ...
    pub fn cleanup(
        self: *SoundMgr,
    ) void {
        var iter = self.soundsMap.valueIterator();
        while (iter.next()) |soundRef| {
            soundRef.*.destroy();
        }
        self.soundsMap.deinit();
        self.engine.destroy();
        zaudio.deinit();
    }

    pub fn create(allocator: std.mem.Allocator) !SoundMgr {
        log.debug("Creating sound engine", .{});
        zaudio.init(allocator);
        errdefer zaudio.deinit();
        const engine = try zaudio.Engine.create(null);
        const soundsMap = std.StringHashMap(*zaudio.Sound).init(allocator);

        return .{
            .engine = engine,
            .soundsMap = soundsMap,
        };
    }
    ...
};
```

In the `create` function we first initialize the [zaudio](https://github.com/zig-gamedev/zaudio/) library by calling `zaudio.init` function.
After that we create a sound engine instance and we will also create a `StringHashMap` which will hold `zaudio.Sound` references indexed
by a key. We will use that map to store loaded sounds and be able to get access to their references to play / stop them. The `cleanup`
function is used to free the resources.

The struct is completed with functions to add new sounds and to play / stop them using their keys:

**File: src/eng/sound.zig**

```zig
pub const SoundMgr = struct {
    ...
    pub fn addSound(self: *SoundMgr, key: []const u8, filePath: [:0]const u8) !void {
        const sound = try self.engine.createSoundFromFile(filePath, .{});
        errdefer sound.destroy();
        try self.soundsMap.put(key, sound);
    }
    ...
    pub fn play(self: *SoundMgr, key: []const u8) !void {
        if (self.soundsMap.get(key)) |sound| {
            try sound.start();
        } else {
            log.warn("Could not find sound for key [{s}]", .{key});
        }
    }

    pub fn stop(self: *SoundMgr, key: []const u8) !void {
        if (self.soundsMap.get(key)) |sound| {
            try sound.stop();
        } else {
            log.warn("Could not find sound for key [{s}]", .{key});
        }
    }
};
```

We will store a reference to the `SoundMgr` struct in the `EngCtx` one:

**File: src/eng/eng.zig**

```zig
pub const EngCtx = struct {
    ...
    soundMgr: eng.snd.SoundMgr,
    ...
    pub fn cleanup(self: *EngCtx) !void {
        ...
        self.soundMgr.cleanup();
    }
};

pub fn Engine(comptime GameLogic: type) type {
    ...
        pub fn create(allocator: std.mem.Allocator, io: std.Io, gameLogic: *GameLogic, wndTitle: [:0]const u8) !Engine(GameLogic) {
            var constants = try com.common.Constants.load(allocator, io);
            errdefer constants.cleanup(allocator);

            var soundMgr = try eng.snd.SoundMgr.create(allocator);
            errdefer soundMgr.cleanup();

            var scene = try eng.scn.Scene.create(allocator);
            errdefer scene.cleanup(allocator);

            const engCtx = EngCtx{
                ...
                .soundMgr = soundMgr,
                .scene = scene,
                ...
            };
            ...
        }
    ...
};
```

And that’s all. We have all the infrastructure we need in order to play sounds. We just need to use it in the `Game` struct:

**File: src/main.zig**

```zig
const Game = struct {
    const ENTITY_ID: []const u8 = "SponzaEntity";

    pub fn cleanup(self: *Game) void {
        _ = self;
    }

    pub fn init(self: *Game, engCtx: *eng.engine.EngCtx, arenaAlloc: std.mem.Allocator) !eng.engine.InitData {
        _ = self;
        ...
        try engCtx.soundMgr.addSound("music", "res/sounds/music.mp3");
        try engCtx.soundMgr.play("music");
        ...
    }
    ...
};        
```

[Back to Table of Contents](../README.md)

[Previous chapter](../chapter-12/chapter-12.md) | [Next chapter](../chapter-14/chapter-14.md)