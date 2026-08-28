const std = @import("std");
const zaudio = @import("zaudio");

const log = std.log.scoped(.eng);

pub const SoundMgr = struct {
    engine: *zaudio.Engine,
    soundsMap: std.StringHashMap(*zaudio.Sound),

    pub fn addSound(self: *SoundMgr, key: []const u8, filePath: [:0]const u8) !void {
        const sound = try self.engine.createSoundFromFile(filePath, .{});
        errdefer sound.destroy();
        try self.soundsMap.put(key, sound);
    }

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
