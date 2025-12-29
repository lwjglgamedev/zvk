const eng = @import("eng");
const std = @import("std");
const zm = @import("zm");

const log = std.log.scoped(.main);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("memory leaked");

    const allocator = gpa.allocator();

    const wndTitle = "Vulkan Book";
    var game = Game{};
    var engine = try eng.engine.Engine(Game).create(allocator, &game, wndTitle);
    try engine.run(allocator);
}

const Game = struct {
    const ENTITY_ID: []const u8 = "CubeEntity";

    angle: f32 = 0,

    pub fn cleanup(self: *Game) void {
        _ = self;
    }

    pub fn init(self: *Game, engCtx: *eng.engine.EngCtx, arenaAlloc: std.mem.Allocator) !eng.engine.InitData {
        _ = self;

        const cubeModel = eng.mdata.ModelData{
            .id = "CubeModel",
            .meshes = &[_]eng.mdata.MeshData{
                .{
                    .id = "CubeMesh",
                    .vertices = &[_]f32{
                        -0.5, 0.5,  0.5,  0.0, 0.0,
                        -0.5, -0.5, 0.5,  0.5, 0.0,
                        0.5,  -0.5, 0.5,  1.0, 0.0,
                        0.5,  0.5,  0.5,  1.0, 0.5,
                        -0.5, 0.5,  -0.5, 1.0, 1.0,
                        0.5,  0.5,  -0.5, 0.5, 1.0,
                        -0.5, -0.5, -0.5, 0.0, 1.0,
                        0.5,  -0.5, -0.5, 0.0, 0.5,
                    },
                    .indices = &[_]u32{
                        // Front face
                        0, 1, 3, 3, 1, 2,
                        // Top Face
                        4, 0, 3, 5, 4, 3,
                        // Right face
                        3, 2, 7, 5, 3, 7,
                        // Left face
                        6, 1, 0, 6, 0, 4,
                        // Bottom face
                        2, 1, 6, 2, 6, 7,
                        // Back face
                        7, 6, 4, 7, 4, 5,
                    },
                },
            },
        };
        const models = try arenaAlloc.alloc(eng.mdata.ModelData, 1);
        models[0] = cubeModel;

        const cubeEntity = try eng.ent.Entity.create(engCtx.allocator, ENTITY_ID, "CubeModel");
        cubeEntity.setPos(0.0, 0.0, -2.0);
        cubeEntity.update();
        try engCtx.scene.addEntity(cubeEntity);

        return .{ .models = models };
    }

    pub fn input(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        _ = self;
        _ = engCtx;
        _ = deltaSec;
    }

    pub fn update(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        _ = deltaSec;
        self.angle += 1.0;
        if (self.angle >= 360) {
            self.angle = 0;
        }
        const cubeEntityRef = engCtx.scene.entitiesMap.get(ENTITY_ID);
        if (cubeEntityRef == null) {
            log.debug("Could not find entity [{s}]", .{ENTITY_ID});
            return;
        }
        const cubeEntity = cubeEntityRef.?;
        const angleRad: f32 = std.math.degreesToRadians(self.angle);
        cubeEntity.rotation = zm.quatFromAxisAngle(zm.f32x4(1.0, 1.0, 1.0, 0.0), angleRad);
        cubeEntity.update();
    }
};
