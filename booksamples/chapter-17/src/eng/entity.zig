const eng = @import("mod.zig");
const std = @import("std");
const zm = @import("zmath");

pub const EntityAnimation = struct {
    animationIdx: usize,
    currentFrame: usize,
    started: bool,
};

pub const Entity = struct {
    animation: ?EntityAnimation = null,
    id: []const u8,
    modelId: []const u8,
    pos: zm.F32x4,
    modelMatrix: zm.Mat,
    rotation: zm.Quat,
    scale: f32,

    pub fn create(allocator: std.mem.Allocator, id: []const u8, modelId: []const u8) !*Entity {
        const ownedId = try allocator.dupe(u8, id);
        var entity = try allocator.create(Entity);
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

    pub fn nextFrame(self: *Entity, maxFrames: usize) void {
        if (self.animation) |*anim| {
            if (anim.started) {
                anim.currentFrame = (anim.currentFrame + 1) % maxFrames;
            }
        }
    }

    pub fn setAnimation(self: *Entity, animationIdx: usize, started: bool) void {
        self.animation = .{
            .animationIdx = animationIdx,
            .currentFrame = 0,
            .started = started,
        };
    }

    pub fn setPos(self: *Entity, x: f32, y: f32, z: f32) void {
        self.pos[0] = x;
        self.pos[1] = y;
        self.pos[2] = z;
    }

    pub fn update(self: *Entity) void {
        const translation = zm.translation(self.pos[0], self.pos[1], self.pos[2]);
        const scaling = zm.scaling(self.scale, self.scale, self.scale);
        const rotation = zm.quatToMat(self.rotation);
        self.modelMatrix = zm.mul(zm.mul(scaling, rotation), translation);
    }
};
