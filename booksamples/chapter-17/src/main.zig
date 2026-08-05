const eng = @import("eng");
const sdl3 = @import("sdl3");
const std = @import("std");
const zm = @import("zm");
const log = std.log.scoped(.main);
const zgui = @import("zgui");
const zstbi = @import("zstbi");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const wndTitle = "Vulkan Book";
    var game = Game{};
    var engine = try eng.engine.Engine(Game).create(allocator, io, &game, wndTitle);
    try engine.run();
}

const Game = struct {
    const ENTITY_ID: []const u8 = "SponzaEntity";
    const BOB_ENTITY_ID: []const u8 = "BobEntity";

    lightAngle: f32 = 90.0,
    bobEntity: ?*eng.ent.Entity = null,

    pub fn cleanup(self: *Game) void {
        _ = self;
    }

    pub fn init(self: *Game, engCtx: *eng.engine.EngCtx, arenaAlloc: std.mem.Allocator) !eng.engine.InitData {
        const sponzaModel = try eng.mdata.loadModel(arenaAlloc, engCtx.io, "res/models/sponza/Sponza.json");
        const models = try arenaAlloc.alloc(eng.mdata.ModelData, 2);
        models[0] = sponzaModel;

        const sponzaEntity = try eng.ent.Entity.create(engCtx.allocator, ENTITY_ID, sponzaModel.id);
        sponzaEntity.setPos(0.0, 0.0, -4.0);
        sponzaEntity.scale = 0.01;
        sponzaEntity.update();
        try engCtx.scene.addEntity(sponzaEntity);

        const bobModel = try eng.mdata.loadModel(arenaAlloc, engCtx.io, "res/models/bob/boblamp.json");
        models[1] = bobModel;

        const bobEntity = try eng.ent.Entity.create(engCtx.allocator, BOB_ENTITY_ID, bobModel.id);
        self.bobEntity = bobEntity;
        const maxFrames = bobModel.animations.items[0].frames.len;
        bobEntity.setPos(0.0, 0.0, 0.0);
        bobEntity.setAnimation(0, maxFrames, true);
        bobEntity.setPos(8.0, 0.0, -4.0);
        bobEntity.scale = 0.06;
        const rotationAngle = std.math.degreesToRadians(90.0);
        bobEntity.rotation = zm.quatFromAxisAngle(zm.Vec{ 1.0, 0.0, 0.0, 0.0 }, rotationAngle);
        bobEntity.update();
        try engCtx.scene.addEntity(bobEntity);

        var materials = try std.ArrayList(eng.mdata.MaterialData).initCapacity(arenaAlloc, 1);
        const sponzaMaterials = try eng.mdata.loadMaterials(arenaAlloc, engCtx.io, "res/models/sponza/Sponza-mat.json");
        try materials.appendSlice(arenaAlloc, sponzaMaterials.items);

        const bobMaterials = try eng.mdata.loadMaterials(arenaAlloc, engCtx.io, "res/models/bob/boblamp-mat.json");
        try materials.appendSlice(arenaAlloc, bobMaterials.items);

        var viewData = &engCtx.scene.camera.viewData;
        viewData.pos = zm.Vec{ 0.0, 3.0, -4.0, 0.0 };
        viewData.addRotation(std.math.degreesToRadians(0), std.math.degreesToRadians(90));

        engCtx.scene.ambientLight = zm.Vec{ 1.0, 1.0, 1.0, 0.9 };

        const dirLight = eng.scn.Light{
            .color = zm.Vec{ 1.0, 1.0, 1.0, 1.0 },
            .directional = true,
            .intensity = 10.0,
            .pos = zm.Vec{
                0.0,
                -std.math.sin(std.math.degreesToRadians(self.lightAngle)),
                -std.math.cos(std.math.degreesToRadians(self.lightAngle)),
                0.0,
            },
        };
        try engCtx.scene.addLight(engCtx.allocator, dirLight);

        const pointLight1 = eng.scn.Light{
            .color = zm.Vec{ 0.0, 1.0, 0.0, 1.0 },
            .directional = false,
            .intensity = 1.0,
            .pos = zm.Vec{ 5.0, 4.5, -2.5, 0.0 },
        };
        try engCtx.scene.addLight(engCtx.allocator, pointLight1);
        const pointLight2 = eng.scn.Light{
            .color = zm.Vec{ 1.0, 0.0, 0.0, 1.0 },
            .directional = false,
            .intensity = 1.0,
            .pos = zm.Vec{ 5.0, 4.5, -6.2, 0.0 },
        };
        try engCtx.scene.addLight(engCtx.allocator, pointLight2);

        return .{ .models = models, .materials = materials };
    }

    fn handleGui(self: *Game, engCtx: *eng.engine.EngCtx) !bool {
        const scene = &engCtx.scene;
        const mouseState = engCtx.wnd.mouseState;
        zgui.io.addMousePositionEvent(mouseState.x, mouseState.y);
        zgui.io.addMouseButtonEvent(zgui.MouseButton.left, mouseState.flags.left);
        zgui.io.addMouseButtonEvent(zgui.MouseButton.middle, mouseState.flags.middle);
        zgui.io.addMouseButtonEvent(zgui.MouseButton.right, mouseState.flags.right);

        var open = true;
        zgui.newFrame();
        zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
        zgui.setNextWindowSize(.{ .w = 300, .h = 400 });
        _ = zgui.begin("Lights", .{ .popen = &open });
        zgui.separatorText("Ambient Light");
        var ambientCol = [3]f32{ scene.ambientLight[0], scene.ambientLight[1], scene.ambientLight[2] };
        if (zgui.colorEdit3("Color", .{ .col = &ambientCol, .flags = zgui.ColorEditFlags{} })) {
            scene.ambientLight[0] = ambientCol[0];
            scene.ambientLight[1] = ambientCol[1];
            scene.ambientLight[2] = ambientCol[2];
        }
        var ambientLightIntensity = scene.ambientLight[3];
        if (zgui.inputFloat("Intensity", .{ .v = &ambientLightIntensity, .step = 0.1 })) {
            scene.ambientLight[3] = ambientLightIntensity;
        }

        const lights = &scene.lights;
        const numLights = lights.items.len;
        for (0..numLights) |i| {
            var light = &lights.items[i];

            var buf1: [32:0]u8 = undefined;
            const lightId = try std.fmt.bufPrintZ(&buf1, "Light-{d}", .{i});
            zgui.separatorText(lightId);

            var buf2: [32:0]u8 = undefined;
            const dirId = try std.fmt.bufPrintZ(&buf2, "Directional-{d}", .{i});
            var dirLight: bool = light.directional;
            _ = zgui.checkbox(dirId, .{ .v = &dirLight });
            if (light.directional) {
                var buf3: [32:0]u8 = undefined;
                const posId = try std.fmt.bufPrintZ(&buf3, "Angle-{d}", .{i});
                if (zgui.dragFloat(posId, .{ .v = &self.lightAngle, .speed = 0.50 })) {
                    if (self.lightAngle < 0) {
                        self.lightAngle = 0;
                    } else if (self.lightAngle > 180) {
                        self.lightAngle = 180;
                    }
                    light.pos[1] = -std.math.sin(std.math.degreesToRadians(self.lightAngle));
                    light.pos[2] = -std.math.cos(std.math.degreesToRadians(self.lightAngle));
                    light.pos = zm.normalize4(light.pos);
                }
            } else {
                var lightPos = [3]f32{ light.pos[0], light.pos[1], light.pos[2] };
                var buf3: [32:0]u8 = undefined;
                const posId = try std.fmt.bufPrintZ(&buf3, "Position-{d}", .{i});
                if (zgui.dragFloat3(posId, .{ .v = &lightPos, .speed = 0.05 })) {
                    light.pos[0] = lightPos[0];
                    light.pos[1] = lightPos[1];
                    light.pos[2] = lightPos[2];
                }
            }

            var lightCol = [3]f32{ light.color[0], light.color[1], light.color[2] };
            var buf4: [32:0]u8 = undefined;
            const lightColorId = try std.fmt.bufPrintZ(&buf4, "Color-{d}", .{i});

            if (zgui.colorEdit3(lightColorId, .{ .col = &lightCol, .flags = zgui.ColorEditFlags{} })) {
                light.color[0] = lightCol[0];
                light.color[1] = lightCol[1];
                light.color[2] = lightCol[2];
            }
        }
        zgui.end();
        zgui.endFrame();
        zgui.render();

        return zgui.io.getWantCaptureKeyboard() or zgui.io.getWantCaptureMouse();
    }

    pub fn input(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        const guiHandled: bool = self.handleGui(engCtx) catch |err| {
            std.log.err("Error in handleGui: {any}", .{err});
            return;
        };
        if (guiHandled) {
            return;
        }
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
        _ = engCtx;
        _ = deltaSec;
        if (self.bobEntity) |bobEntity| {
            bobEntity.nextFrame();
        }
    }
};
