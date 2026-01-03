const com = @import("com");
const std = @import("std");
const vk = @import("vk");
const vulkan = @import("vulkan");
const zstbi = @import("zstbi");
const log = std.log.scoped(.eng);

pub const MAX_TEXTURES: u32 = 100;

pub const TextureInfo = struct {
    id: []const u8,
    data: []const u8,
    width: u32,
    height: u32,
    format: vulkan.Format,
};

const EMPTY_PIXELS = [_]u8{ 0, 0, 0, 0 };

pub const TextureCache = struct {
    textureMap: std.ArrayHashMap([]const u8, vk.text.VkTexture, std.array_hash_map.StringContext, false),

    pub fn addTexture(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, textureInfo: *const TextureInfo) !void {
        if (self.textureMap.contains(textureInfo.id)) {
            return;
        }
        if (self.textureMap.count() >= MAX_TEXTURES) {
            @panic("Exceeded maximum number of textures");
        }
        const ownedId = try allocator.dupe(u8, textureInfo.id);
        const vkTextureInfo = vk.text.VkTextureInfo{
            .data = textureInfo.data,
            .width = textureInfo.width,
            .height = textureInfo.height,
            .format = textureInfo.format,
        };
        const vkTexture = try vk.text.VkTexture.create(vkCtx, &vkTextureInfo);
        try self.textureMap.put(ownedId, vkTexture);
    }

    pub fn addTextureFromPath(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, path: [:0]const u8) !bool {
        if (self.textureMap.count() >= MAX_TEXTURES) {
            @panic("Exceeded maximum number of textures");
        }
        std.fs.cwd().access(path, .{}) catch {
            log.err("Could not load texture file [{s}]", .{path});
            return false;
        };
        var image = try zstbi.Image.loadFromFile(path, 4);
        defer image.deinit();

        const textureInfo = TextureInfo{
            .id = path,
            .data = image.data,
            .width = image.width,
            .height = image.height,
            .format = vulkan.Format.r8g8b8a8_srgb,
        };

        try self.addTexture(allocator, vkCtx, &textureInfo);
        return true;
    }

    pub fn create(allocator: std.mem.Allocator) TextureCache {
        const textureMap = std.ArrayHashMap([]const u8, vk.text.VkTexture, std.array_hash_map.StringContext, false).init(allocator);
        return .{ .textureMap = textureMap };
    }

    pub fn cleanup(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        var iter = self.textureMap.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            const texture = entry.value_ptr;
            texture.cleanup(vkCtx);
        }
        self.textureMap.deinit();
    }

    pub fn getTexture(self: *const TextureCache, id: []const u8) vk.text.VkTexture {
        const texture = self.textureMap.get(id) orelse {
            @panic("Could not find texture");
        };

        return texture;
    }

    pub fn getTextureRef(self: *const TextureCache, id: []const u8) *vk.text.VkTexture {
        const texture = self.textureMap.getPtr(id) orelse {
            @panic("Could not find texture");
        };

        return texture;
    }

    pub fn recordTextures(self: *TextureCache, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx, vkCmdPool: *vk.cmd.VkCmdPool, vkQueue: vk.queue.VkQueue) !void {
        log.debug("Recording textures", .{});
        const numTextures = self.textureMap.count();
        if (numTextures < MAX_TEXTURES) {
            const numPadding = MAX_TEXTURES - numTextures;
            for (0..numPadding) |_| {
                const id = try com.utils.generateUuid(allocator);
                defer allocator.free(id);
                const textureInfo = TextureInfo{
                    .data = EMPTY_PIXELS[0..],
                    .width = 1,
                    .height = 1,
                    .format = vulkan.Format.r8g8b8a8_srgb,
                    .id = id,
                };
                try self.addTexture(allocator, vkCtx, &textureInfo);
            }
        }
        const cmd = try vk.cmd.VkCmdBuff.create(vkCtx, vkCmdPool, true);
        defer cmd.cleanup(vkCtx, vkCmdPool);

        try cmd.begin(vkCtx);
        const cmdHandle = cmd.cmdBuffProxy.handle;
        var it = self.textureMap.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.recordTransition(vkCtx, cmdHandle);
        }
        try cmd.end(vkCtx);
        try cmd.submitAndWait(vkCtx, vkQueue);

        while (it.next()) |entry| {
            entry.value_ptr.*.cleanupStgBuffer(vkCtx);
        }

        log.debug("Recorded textures", .{});
    }
};
