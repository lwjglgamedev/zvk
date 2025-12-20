const eng = @import("mod.zig");
const std = @import("std");
const zm = @import("zmath");

pub const Entity = struct {
    id: []const u8,
    modelId: []const u8,
    pos: zm.F32x4,
    modelMatrix: zm.Mat,
    rotation: zm.Quat,
    scale: f32,

    pub fn create(allocator: std.mem.Allocator, idOpt: ?[]const u8, modelId: []const u8) !*Entity {
        const ownedId = try if (idOpt) |id|
            allocator.dupe(u8, id)
        else
            eng.ent.Entity.generateUuid(allocator);

        var entity = try allocator.create(eng.ent.Entity);
        entity.id = ownedId;
        entity.modelId = try allocator.dupe(u8, modelId);
        entity.pos = zm.f32x4(0, 0, 0, 1);
        entity.modelMatrix = zm.identity();
        entity.rotation = zm.f32x4(0, 0, 0, 1);
        entity.scale = 1.0;

        entity.update();
        return entity;
    }

    pub fn cleanup(self: *Entity, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.modelId);
        allocator.destroy(self);
    }

    pub fn setPos(self: *Entity, x: f32, y: f32, z: f32) void {
        self.pos[0] = x;
        self.pos[1] = y;
        self.pos[2] = z;
    }

    pub fn generateUuid(allocator: std.mem.Allocator) ![]const u8 {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);

        // Set version (4) and variant bits (RFC 4122)
        bytes[6] = (bytes[6] & 0x0F) | 0x40;
        bytes[8] = (bytes[8] & 0x3F) | 0x80;

        // Format as UUID string
        const hex_chars = "0123456789abcdef";
        var uuid = try allocator.alloc(u8, 36);
        errdefer allocator.free(uuid);

        var i: usize = 0;
        for (bytes, 0..) |byte, j| {
            switch (j) {
                4, 6, 8, 10 => {
                    uuid[i] = '-';
                    i += 1;
                },
                else => {},
            }
            uuid[i] = hex_chars[byte >> 4];
            uuid[i + 1] = hex_chars[byte & 0x0F];
            i += 2;
        }

        return uuid;
    }

    pub fn update(self: *Entity) void {
        const translation = zm.translation(self.pos[0], self.pos[1], self.pos[2]);
        const scaling = zm.scaling(self.scale, self.scale, self.scale);
        const rotation = zm.quatToMat(self.rotation);
        self.modelMatrix = zm.mul(zm.mul(scaling, rotation), translation);
    }
};
