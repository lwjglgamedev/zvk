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

pub const ViewData = struct {
    pos: zm.Vec,
    yaw: f32,
    pitch: f32,
    viewMatrix: zm.Mat,

    pub fn addRotation(self: *ViewData, pitch: f32, yaw: f32) void {
        self.pitch += pitch;
        self.yaw += yaw;
        self.recalculate();
    }

    pub fn create() ViewData {
        var viewData = ViewData{
            .pos = zm.Vec{ 0.0, 0.0, 0.0, 0.0 },
            .yaw = -std.math.pi / 2.0,
            .pitch = 0,
            .viewMatrix = zm.identity(),
        };
        viewData.recalculate();
        return viewData;
    }

    pub fn moveBack(self: *ViewData, inc: f32) void {
        const delta = self.forwardDir() * zm.splat(zm.Vec, inc);
        self.pos = self.pos - delta;
        self.recalculate();
    }

    pub fn moveForward(self: *ViewData, inc: f32) void {
        const delta = self.forwardDir() * zm.splat(zm.Vec, inc);
        self.pos = self.pos + delta;
        self.recalculate();
    }

    pub fn moveLeft(self: *ViewData, inc: f32) void {
        const delta = self.rightDir() * zm.splat(zm.Vec, inc);
        self.pos = self.pos - delta;
        self.recalculate();
    }

    pub fn moveRight(self: *ViewData, inc: f32) void {
        const delta = self.rightDir() * zm.splat(zm.Vec, inc);
        self.pos = self.pos + delta;
        self.recalculate();
    }

    pub fn moveUp(self: *ViewData, inc: f32) void {
        const delta = upDir() * zm.splat(zm.Vec, inc);
        self.pos = self.pos + delta;
        self.recalculate();
    }

    pub fn moveDown(self: *ViewData, inc: f32) void {
        const delta = upDir() * zm.splat(zm.Vec, inc);
        self.pos = self.pos - delta;
        self.recalculate();
    }

    fn forwardDir(self: *const ViewData) zm.Vec {
        return zm.normalize3(zm.f32x4(
            @cos(self.pitch) * @cos(self.yaw),
            @sin(self.pitch),
            @cos(self.pitch) * @sin(self.yaw),
            0.0,
        ));
    }

    fn rightDir(self: *const ViewData) zm.Vec {
        const up = zm.f32x4(0.0, 1.0, 0.0, 0.0);
        return zm.normalize3(zm.cross3(self.forwardDir(), up));
    }

    pub fn recalculate(self: *ViewData) void {
        // Avoid gimbal lock
        self.pitch = std.math.clamp(
            self.pitch,
            -std.math.pi / 2.0 + 0.001,
            std.math.pi / 2.0 - 0.001,
        );

        const forward = self.forwardDir();
        const target = self.pos + forward;
        const up = upDir();

        self.viewMatrix = zm.lookAtRh(
            self.pos,
            target,
            up,
        );
    }

    fn upDir() zm.Vec {
        return zm.f32x4(0.0, 1.0, 0.0, 0.0);
    }
};

pub const Camera = struct {
    projData: ProjData,
    viewData: ViewData,

    pub fn create() Camera {
        const projData = ProjData{};
        const viewData = ViewData.create();
        return .{ .projData = projData, .viewData = viewData };
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
