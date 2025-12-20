const com = @import("com");
const eng = @import("mod.zig");
const std = @import("std");
const zm = @import("zmath");
const log = std.log.scoped(.eng);

pub const ProjData = struct {
    projMatrix: zm.Mat = zm.identity(),
    zoomFactor: f32 = 1.0,
    fov: f32 = 0.0,
    near: f32 = 0.0,
    far: f32 = 0.0,

    pub fn update(self: *ProjData, fov: f32, near: f32, far: f32, width: f32, height: f32) void {
        self.fov = fov;
        self.near = near;
        self.far = far;

        const aspect = width / height;

        const tan_half_fovy = @tan(fov * 0.5);

        const x_scale = 1.0 / (aspect * tan_half_fovy);
        const y_scale = 1.0 / tan_half_fovy;
        const z_scale = far / (near - far);
        const w_scale = (near * far) / (near - far);

        self.projMatrix = zm.Mat{
            zm.f32x4(x_scale, 0.0, 0.0, 0.0),
            zm.f32x4(0.0, y_scale, 0.0, 0.0),
            zm.f32x4(0.0, 0.0, z_scale, -1.0),
            zm.f32x4(0.0, 0.0, w_scale, 0.0),
        };
    }
};

pub const Camera = struct {
    projData: ProjData,

    pub fn create() Camera {
        const projData = ProjData{};
        return .{ .projData = projData };
    }
};

pub const Scene = struct {
    camera: Camera,
    entitiesMap: std.StringHashMap(*eng.ent.Entity),

    pub fn addEntity(self: *Scene, entity: *eng.ent.Entity) !void {
        try self.entitiesMap.put(entity.id, entity);
    }

    pub fn create(allocator: std.mem.Allocator) !Scene {
        const camera = Camera.create();
        const entitiesMap = std.StringHashMap(*eng.ent.Entity).init(allocator);

        return .{
            .camera = camera,
            .entitiesMap = entitiesMap,
        };
    }

    pub fn cleanup(self: *Scene, allocator: std.mem.Allocator) void {
        var iter = self.entitiesMap.valueIterator();
        while (iter.next()) |entityRef| {
            const entity = entityRef.*;
            entity.cleanup(allocator);
        }
        self.entitiesMap.deinit();
    }
};
