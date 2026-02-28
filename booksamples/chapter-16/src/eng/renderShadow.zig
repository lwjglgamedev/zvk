const eng = @import("mod.zig");
const std = @import("std");
const vk = @import("vk");
const zm = @import("zmath");

const LAMBDA: f32 = 0.95;
const SHADOW_MAP_CASCADE_COUNT: u32 = 3;
const UP = zm.f32x4(0.0, 1.0, 0.0, 0.0);
const UP_ALT = zm.f32x4(0.0, 0.0, 1.0, 0.0);

pub const CascadeData = struct {
    floatDistance: f32 = 0,
    projViewMatrix: zm.Mat = zm.identity(),
};

// Function are derived from Vulkan examples from Sascha Willems, and licensed under the MIT License:
// https://github.com/SaschaWillems/Vulkan/tree/master/examples/shadowmappingcascade, which are based on
// https://johanmedestrom.wordpress.com/2016/03/18/opengl-cascaded-shadow-maps/
// combined with this source: https://github.com/TheRealMJP/Shadows
pub fn updateCascadeShadows(cascadeShadows: *[SHADOW_MAP_CASCADE_COUNT]CascadeData, scene: *eng.scn.Scene) void {
    const viewData = scene.camera.viewData;
    const viewMatrix = viewData.viewMatrix;
    const projData = scene.camera.projData;
    const projMatrix = projData.projMatrix;

    var dirLightOpt: ?eng.scn.Light = null;
    for (scene.lights.items) |l| {
        if (l.directional) {
            dirLightOpt = l;
            break;
        }
    }
    if (dirLightOpt == null) {
        std.log.err("Could not find directional light", .{});
        return;
    }
    const dirLight = dirLightOpt.?;

    const lightPos = dirLight.pos;

    var cascadeSplits = [SHADOW_MAP_CASCADE_COUNT]f32{ 0, 0, 0 };

    const nearClip = projData.near;
    const farClip = projData.far;
    const clipRange = farClip - nearClip;

    const minZ = nearClip;
    const maxZ = nearClip + clipRange;

    const range = maxZ - minZ;
    const ratio = maxZ / minZ;

    const numCascades = cascadeShadows.len;

    // Calculate split depths based on view camera frustum
    // Based on method presented in https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch10.html
    for (0..numCascades) |i| {
        const p: f32 = @as(f32, @floatFromInt(i + 1)) /
            @as(f32, @floatFromInt(SHADOW_MAP_CASCADE_COUNT));

        const log = minZ * std.math.pow(f32, ratio, p);
        const uniform = minZ + range * p;
        const d = LAMBDA * (log - uniform) + uniform;

        cascadeSplits[i] = (d - nearClip) / clipRange;
    }

    // Calculate orthographic projection matrix for each cascade
    var lastSplitDist: f32 = 0.0;
    for (0..numCascades) |i| {
        const splitDist = cascadeSplits[i];

        var frustumCorners = [_]zm.Vec{
            zm.Vec{ -1.0, 0.0, 0.0, 1.0 },
            zm.Vec{ 1.0, 1.0, 0.0, 1.0 },
            zm.Vec{ 1.0, -1.0, 0.0, 1.0 },
            zm.Vec{ -1.0, -1.0, 0.0, 1.0 },
            zm.Vec{ -1.0, 1.0, 1.0, 1.0 },
            zm.Vec{ 1.0, 1.0, 1.0, 1.0 },
            zm.Vec{ 1.0, -1.0, 1.0, 1.0 },
            zm.Vec{ -1.0, -1.0, 1.0, 1.0 },
        };

        // Project frustum corners into world space
        const invCam: zm.Mat = zm.inverse(zm.mul(projMatrix, viewMatrix));
        for (0..8) |j| {
            const invCorner = zm.mul(frustumCorners[j], invCam);
            frustumCorners[j][0] = invCorner[0] / invCorner[3];
            frustumCorners[j][1] = invCorner[1] / invCorner[3];
            frustumCorners[j][2] = invCorner[2] / invCorner[3];
        }

        for (0..4) |j| {
            const dist = frustumCorners[j + 4] - frustumCorners[j];
            const split1: @Vector(4, f32) = @splat(splitDist);
            frustumCorners[j + 4] = frustumCorners[j] + dist * split1;
            const split2: @Vector(4, f32) = @splat(lastSplitDist);
            frustumCorners[j] = frustumCorners[j] + dist * split2;
        }

        // Get frustum center
        var frustumCenter = zm.Vec{ 0, 0, 0, 0 };
        for (frustumCorners) |c| {
            frustumCenter = frustumCenter + c;
        }
        frustumCenter = frustumCenter / @as(@Vector(4, f32), @splat(8.0));

        var up = UP;

        var sphereRadius: f32 = 0.0;
        for (frustumCorners) |c| {
            const diff = c - frustumCenter;
            const dist = zm.length3(diff)[0];
            sphereRadius = @max(sphereRadius, dist);
        }

        sphereRadius = std.math.ceil(sphereRadius * 16.0) / 16.0;

        const maxExtents = zm.f32x4(sphereRadius, sphereRadius, sphereRadius, 0);
        const minExtents = maxExtents * @as(@Vector(4, f32), @splat(-1.0));

        const lightDir = lightPos;

        const shadow_camera_pos = frustumCenter + lightDir * @as(@Vector(4, f32), @splat((minExtents[3])));

        const dot = @abs(zm.dot3(lightPos, up))[0];
        if (dot == 1.0) {
            up = UP_ALT;
        }

        const lightView = zm.lookAtRh(shadow_camera_pos, frustumCenter, up);

        var lightOrtho = zm.orthographicRh(
            minExtents[0],
            maxExtents[0],
            minExtents[1],
            maxExtents[1],
        );

        // Stabilize shadow
        // TODO: Configure this
        const shadowMapSize: f32 = 2024;

        var shadowOrigin = zm.f32x4(0, 0, 0, 1);
        shadowOrigin = zm.mul(lightView, shadowOrigin);
        shadowOrigin = shadowOrigin * @as(@Vector(4, f32), @splat(shadowMapSize / 2.0));

        const roundedOrigin = zm.round(shadowOrigin);
        var roundOffset = roundedOrigin - shadowOrigin;
        roundOffset = roundOffset * @as(@Vector(4, f32), @splat(2.0 / shadowMapSize));

        roundOffset = zm.f32x4(
            roundOffset[0],
            roundOffset[1],
            0,
            0,
        );

        var lastCol = lightOrtho[3];
        lastCol += @Vector(4, f32){ roundOffset[0], roundOffset[1], roundOffset[2], 0 };
        lightOrtho[3] = lastCol;

        const cascadeData = &cascadeShadows[i];
        cascadeData.floatDistance = (nearClip + splitDist * clipRange) * -1.0;

        cascadeData.projViewMatrix = zm.mul(lightOrtho, lightView);

        lastSplitDist = cascadeSplits[i];
    }
}

pub const RenderShadow = struct {
    cascadeShadows: [SHADOW_MAP_CASCADE_COUNT]CascadeData,

    pub fn cleanup(self: *RenderShadow, allocator: std.mem.Allocator, vkCtx: *const vk.ctx.VkCtx) void {
        _ = self;
        _ = allocator;
        _ = vkCtx;
    }

    pub fn create() !RenderShadow {
        const cascadeShadows = [SHADOW_MAP_CASCADE_COUNT]CascadeData{ .{}, .{}, .{} };
        return .{
            .cascadeShadows = cascadeShadows,
        };
    }

    pub fn render(
        self: *RenderShadow,
        engCtx: *eng.engine.EngCtx,
    ) !void {
        updateCascadeShadows(&self.cascadeShadows, &engCtx.scene);
    }
};
