const eng = @import("eng");
const sdl3 = @import("sdl3");
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
    const ENTITY_ID: []const u8 = "SponzaEntity";

    pub fn cleanup(self: *Game) void {
        _ = self;
    }

    pub fn init(self: *Game, engCtx: *eng.engine.EngCtx, arenaAlloc: std.mem.Allocator) !eng.engine.InitData {
        _ = self;

        const sponzaModel = try eng.mdata.loadModel(arenaAlloc, "res/models/sponza/Sponza.json");
        const models = try arenaAlloc.alloc(eng.mdata.ModelData, 1);
        models[0] = sponzaModel;

        const sponzaEntity = try eng.ent.Entity.create(engCtx.allocator, ENTITY_ID, sponzaModel.id);
        sponzaEntity.setPos(0.0, 0.0, -4.0);
        sponzaEntity.scale = 0.01;
        sponzaEntity.update();
        try engCtx.scene.addEntity(sponzaEntity);

        var materials = try std.ArrayList(eng.mdata.MaterialData).initCapacity(arenaAlloc, 1);
        const sponzaMaterials = try eng.mdata.loadMaterials(arenaAlloc, "res/models/sponza/Sponza-mat.json");
        try materials.appendSlice(arenaAlloc, sponzaMaterials.items);

        var viewData = &engCtx.scene.camera.viewData;
        viewData.pos = zm.Vec{ 0.0, 3.0, -4.0, 0.0 };
        viewData.addRotation(std.math.degreesToRadians(0), std.math.degreesToRadians(90));
        return .{ .models = models, .materials = materials };
    }

    pub fn input(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        _ = self;
        const inc: f32 = 10;
        var viewData = &engCtx.scene.camera.viewData;
        if (engCtx.wnd.isKeyPressed(sdl3.Scancode.w)) {
            viewData.moveForward(inc * deltaSec);
        } else if (engCtx.wnd.isKeyPressed(sdl3.Scancode.s)) {
            viewData.moveBack(inc * deltaSec);
        }
        if (engCtx.wnd.isKeyPressed(sdl3.Scancode.a)) {
            viewData.moveLeft(inc * deltaSec);
        } else if (engCtx.wnd.isKeyPressed(sdl3.Scancode.d)) {
            viewData.moveRight(inc * deltaSec);
        }
        if (engCtx.wnd.isKeyPressed(sdl3.Scancode.up)) {
            viewData.moveUp(inc * deltaSec);
        } else if (engCtx.wnd.isKeyPressed(sdl3.Scancode.down)) {
            viewData.moveDown(inc * deltaSec);
        }

        const mouseState = engCtx.wnd.mouseState;
        if (mouseState.flags.right) {
            const mouseInc: f32 = 0.1;
            viewData.addRotation(std.math.degreesToRadians(-mouseState.deltaY * mouseInc), std.math.degreesToRadians(-mouseState.deltaX * mouseInc));
        }
    }

    pub fn update(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        _ = self;
        _ = engCtx;
        _ = deltaSec;
    }
};
