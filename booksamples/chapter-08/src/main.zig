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

        const cubeModel = try eng.mdata.loadModel(arenaAlloc, "res/models/cube/cube.json");
        const models = try arenaAlloc.alloc(eng.mdata.ModelData, 1);
        models[0] = cubeModel;

        const cubeEntity = try eng.ent.Entity.create(engCtx.allocator, ENTITY_ID, cubeModel.id);
        cubeEntity.setPos(0.0, 0.0, -4.0);
        cubeEntity.update();
        try engCtx.scene.addEntity(cubeEntity);

        var materials = try std.ArrayList(eng.mdata.MaterialData).initCapacity(arenaAlloc, 1);
        const cubeMaterials = try eng.mdata.loadMaterials(arenaAlloc, "res/models/cube/cube-mat.json");
        try materials.appendSlice(arenaAlloc, cubeMaterials.items);

        return .{ .models = models, .materials = materials };
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
