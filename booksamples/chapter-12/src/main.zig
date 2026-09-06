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
    defaultGui: bool = true,
    textureData: ?zgui.TextureData = null,
    textureImage: ?zstbi.Image = null,

    const ENTITY_ID: []const u8 = "SponzaEntity";

    pub fn cleanup(self: *Game) void {
        if (self.textureImage) |*img| {
            img.deinit();
        }
    }

    pub fn init(self: *Game, engCtx: *eng.engine.EngCtx, arenaAlloc: std.mem.Allocator) !eng.engine.InitData {
        const sponzaModel = try eng.mdata.loadModel(arenaAlloc, engCtx.io, "res/models/sponza/Sponza.json");
        const models = try arenaAlloc.alloc(eng.mdata.ModelData, 1);
        models[0] = sponzaModel;

        const sponzaEntity = try eng.ent.Entity.create(engCtx.allocator, ENTITY_ID, sponzaModel.id);
        errdefer sponzaEntity.cleanup(engCtx.allocator);
        sponzaEntity.setPos(0.0, 0.0, -4.0);
        sponzaEntity.scale = 0.01;
        sponzaEntity.update();
        try engCtx.scene.addEntity(sponzaEntity);

        var materials = try std.ArrayList(eng.mdata.MaterialData).initCapacity(arenaAlloc, 1);
        const sponzaMaterials = try eng.mdata.loadMaterials(arenaAlloc, engCtx.io, "res/models/sponza/Sponza-mat.json");
        try materials.appendSlice(arenaAlloc, sponzaMaterials.items);

        var viewData = &engCtx.scene.camera.viewData;
        viewData.pos = zm.Vec{ 0.0, 3.0, -4.0, 0.0 };
        viewData.addRotation(std.math.degreesToRadians(0), std.math.degreesToRadians(90));

        const textureImage = try zstbi.Image.loadFromFile("res/textures/vulkan.png", 4);
        self.textureImage = textureImage;

        self.textureData = eng.rgui.createTextureData(1, &textureImage);

        return .{ .models = models, .materials = materials };
    }

    fn handleGui(self: *Game, engCtx: *eng.engine.EngCtx) bool {
        const mouseState = engCtx.wnd.mouseState;
        zgui.io.addMousePositionEvent(mouseState.x, mouseState.y);
        zgui.io.addMouseButtonEvent(zgui.MouseButton.left, mouseState.flags.left);
        zgui.io.addMouseButtonEvent(zgui.MouseButton.middle, mouseState.flags.middle);
        zgui.io.addMouseButtonEvent(zgui.MouseButton.right, mouseState.flags.right);

        var open = true;
        if (self.defaultGui) {
            zgui.newFrame();
            zgui.showDemoWindow(&open);
            zgui.render();
        } else {
            const textRef = zgui.TextureRef{
                .tex_id = self.textureData.?.tex_id,
                .tex_data = &self.textureData.?,
            };
            zgui.newFrame();
            zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
            zgui.setNextWindowSize(.{ .w = 300, .h = 300 });
            _ = zgui.begin("Test Window", .{ .popen = &open });
            zgui.image(textRef, .{ .w = 300, .h = 300 });
            zgui.end();
            zgui.endFrame();
            zgui.render();
        }

        return zgui.io.getWantCaptureKeyboard() or zgui.io.getWantCaptureMouse();
    }

    pub fn input(self: *Game, engCtx: *eng.engine.EngCtx, deltaSec: f32) void {
        if (self.handleGui(engCtx)) {
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
        if (engCtx.wnd.isKeyPressed(sdl3.Scancode.one)) {
            self.defaultGui = true;
        } else if (engCtx.wnd.isKeyPressed(sdl3.Scancode.two)) {
            self.defaultGui = false;
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
