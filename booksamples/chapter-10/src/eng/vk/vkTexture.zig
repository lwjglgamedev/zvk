const std = @import("std");
const vk = @import("mod.zig");
const vulkan = @import("vulkan");

pub const VkTextSamplerInfo = struct {
    addressMode: vulkan.SamplerAddressMode,
    anisotropy: bool,
    borderColor: vulkan.BorderColor,
};

pub const VkTextSampler = struct {
    sampler: vulkan.Sampler,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, samplerInfo: VkTextSamplerInfo) !VkTextSampler {
        const anisotropy = (vkCtx.vkPhysDevice.features.sampler_anisotropy == vulkan.Bool32.true) and samplerInfo.anisotropy;
        const createInfo = vulkan.SamplerCreateInfo{
            .mag_filter = vulkan.Filter.nearest,
            .min_filter = vulkan.Filter.nearest,
            .address_mode_u = samplerInfo.addressMode,
            .address_mode_v = samplerInfo.addressMode,
            .address_mode_w = samplerInfo.addressMode,
            .border_color = samplerInfo.borderColor,
            .mipmap_mode = vulkan.SamplerMipmapMode.nearest,
            .min_lod = 0.0,
            .max_lod = vulkan.LOD_CLAMP_NONE,
            .mip_lod_bias = 0.0,
            .compare_enable = vulkan.Bool32.false,
            .compare_op = vulkan.CompareOp.never,
            .unnormalized_coordinates = vulkan.Bool32.false,
            .anisotropy_enable = if (anisotropy) vulkan.Bool32.true else vulkan.Bool32.false,
            .max_anisotropy = if (anisotropy) vkCtx.vkPhysDevice.props.limits.max_sampler_anisotropy else 0.0,
        };
        const sampler = try vkCtx.vkDevice.deviceProxy.createSampler(&createInfo, null);
        return .{ .sampler = sampler };
    }

    pub fn cleanup(self: *const VkTextSampler, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.destroySampler(self.sampler, null);
    }
};

pub const VkTextureInfo = struct {
    data: []const u8,
    width: u32,
    height: u32,
    format: vulkan.Format,
};

pub const VkTexture = struct {
    vkImage: vk.img.VkImage,
    vkImageView: vk.imv.VkImageView,
    vkStageBuffer: ?vk.buf.VkBuffer,
    width: u32,
    height: u32,
    mipLevels: u32,
    transparent: bool,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, vkTextureInfo: *const VkTextureInfo) !VkTexture {
        const minDimension = @min(vkTextureInfo.width, vkTextureInfo.height);
        const mipLevels: u32 = @as(u32, @intFromFloat(std.math.floor(std.math.log2(@as(f64, @floatFromInt(minDimension)))))) + 1;

        const flags = vulkan.ImageUsageFlags{
            .transfer_dst_bit = true,
            .transfer_src_bit = true,
            .sampled_bit = true,
        };
        const vkImageData = vk.img.VkImageData{
            .width = vkTextureInfo.width,
            .height = vkTextureInfo.height,
            .usage = flags,
            .format = vkTextureInfo.format,
            .mipLevels = mipLevels,
        };
        const vkImage = try vk.img.VkImage.create(vkCtx, vkImageData);
        const imageViewData = vk.imv.VkImageViewData{ .format = vkTextureInfo.format, .levelCount = mipLevels };

        const image: vulkan.Image = @enumFromInt(@intFromPtr(vkImage.image));
        const vkImageView = try vk.imv.VkImageView.create(vkCtx.vkDevice, image, imageViewData);

        const dataSize = vkTextureInfo.data.len;
        const vkStageBuffer = try vk.buf.VkBuffer.create(
            vkCtx,
            dataSize,
            vulkan.BufferUsageFlags{ .transfer_src_bit = true },
            @intFromEnum(vk.vma.VmaFlags.VmaAllocationCreateHostAccessSSequentialWriteBit),
            vk.vma.VmaUsage.VmaUsageAuto,
            vk.vma.VmaMemoryFlags.MemoryPropertyHostVisibleBitAndCoherent,
        );
        try vk.buf.copyDataToBuffer(vkCtx, &vkStageBuffer, &vkTextureInfo.data);

        return .{
            .vkImage = vkImage,
            .vkImageView = vkImageView,
            .vkStageBuffer = vkStageBuffer,
            .width = vkTextureInfo.width,
            .height = vkTextureInfo.height,
            .mipLevels = mipLevels,
            .transparent = isTransparent(&vkTextureInfo.data),
        };
    }

    pub fn cleanup(self: *VkTexture, vkCtx: *const vk.ctx.VkCtx) void {
        if (self.vkStageBuffer) |sb| {
            sb.cleanup(vkCtx);
        }
        self.vkImageView.cleanup(vkCtx.vkDevice);
        self.vkImage.cleanup(vkCtx);
    }

    fn isTransparent(data: *const []const u8) bool {
        const numBlocks = data.len / 4;
        var transparent = false;
        for (0..numBlocks) |i| {
            if (data.*[i * 4 + 3] < 255) {
                transparent = true;
                break;
            }
        }
        return transparent;
    }

    fn recordMipMap(self: *const VkTexture, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        const device = vkCtx.vkDevice.deviceProxy;
        const image: vulkan.Image = @enumFromInt(@intFromPtr(self.vkImage.image));

        var barrier = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.transfer_dst_optimal,
            .new_layout = vulkan.ImageLayout.transfer_src_optimal,
            .src_stage_mask = .{ .all_transfer_bit = true },
            .dst_stage_mask = .{ .all_transfer_bit = true },
            .src_access_mask = .{ .transfer_write_bit = true },
            .dst_access_mask = .{ .transfer_read_bit = true },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_array_layer = 0,
                .base_mip_level = 0,
                .level_count = 1,
                .layer_count = 1,
            },
            .image = image,
        }};

        const depInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = barrier.len,
            .p_image_memory_barriers = &barrier,
        };

        var mipWidth: i32 = @as(i32, @intCast(self.width));
        var mipHeight: i32 = @as(i32, @intCast(self.height));

        for (1..self.mipLevels) |i| {
            barrier[0].old_layout = vulkan.ImageLayout.transfer_dst_optimal;
            barrier[0].new_layout = vulkan.ImageLayout.transfer_src_optimal;
            barrier[0].src_access_mask = .{ .transfer_write_bit = true };
            barrier[0].dst_access_mask = .{ .transfer_read_bit = true };
            barrier[0].src_stage_mask = .{ .all_transfer_bit = true };
            barrier[0].dst_stage_mask = .{ .all_transfer_bit = true };
            barrier[0].subresource_range.base_mip_level = @as(u32, @intCast(i)) - 1;

            device.cmdPipelineBarrier2(cmdHandle, &depInfo);

            const imageBlit = [_]vulkan.ImageBlit{.{
                .src_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .mip_level = @as(u32, @intCast(i)) - 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .src_offsets = [2]vulkan.Offset3D{
                    .{
                        .x = 0,
                        .y = 0,
                        .z = 0,
                    },
                    .{
                        .x = mipWidth,
                        .y = mipHeight,
                        .z = 1,
                    },
                },
                .dst_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .mip_level = @as(u32, @intCast(i)),
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .dst_offsets = [2]vulkan.Offset3D{
                    .{
                        .x = 0,
                        .y = 0,
                        .z = 0,
                    },
                    .{
                        .x = if (mipWidth > 1) @divTrunc(mipWidth, 2) else 1,
                        .y = if (mipHeight > 1) @divTrunc(mipHeight, 2) else 1,
                        .z = 1,
                    },
                },
            }};

            device.cmdBlitImage(
                cmdHandle,
                image,
                vulkan.ImageLayout.transfer_src_optimal,
                image,
                vulkan.ImageLayout.transfer_dst_optimal,
                imageBlit.len,
                &imageBlit,
                vulkan.Filter.linear,
            );

            barrier[0].old_layout = vulkan.ImageLayout.transfer_src_optimal;
            barrier[0].new_layout = vulkan.ImageLayout.shader_read_only_optimal;
            barrier[0].src_access_mask = .{ .transfer_read_bit = true };
            barrier[0].dst_access_mask = .{ .shader_read_bit = true };
            barrier[0].src_stage_mask = .{ .all_transfer_bit = true };
            barrier[0].dst_stage_mask = .{ .fragment_shader_bit = true };

            device.cmdPipelineBarrier2(cmdHandle, &depInfo);

            if (mipWidth > 1) {
                mipWidth = @divTrunc(mipWidth, 2);
            }
            if (mipHeight > 1) {
                mipHeight = @divTrunc(mipHeight, 2);
            }
        }

        const lastMip: u32 = self.mipLevels - 1;
        // Record transition to read only optimal
        const endBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.transfer_dst_optimal,
            .new_layout = vulkan.ImageLayout.shader_read_only_optimal,
            .src_stage_mask = .{ .all_transfer_bit = true },
            .dst_stage_mask = .{ .fragment_shader_bit = true },
            .src_access_mask = .{ .transfer_write_bit = true },
            .dst_access_mask = .{ .shader_read_bit = true },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = lastMip,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image = image,
        }};
        const endDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = endBarriers.len,
            .p_image_memory_barriers = &endBarriers,
        };
        device.cmdPipelineBarrier2(cmdHandle, &endDepInfo);
    }

    pub fn recordTransition(self: *const VkTexture, vkCtx: *const vk.ctx.VkCtx, cmdHandle: vulkan.CommandBuffer) void {
        // Record transition to dst optimal
        const device = vkCtx.vkDevice.deviceProxy;
        const image: vulkan.Image = @enumFromInt(@intFromPtr(self.vkImage.image));
        const initBarriers = [_]vulkan.ImageMemoryBarrier2{.{
            .old_layout = vulkan.ImageLayout.undefined,
            .new_layout = vulkan.ImageLayout.transfer_dst_optimal,
            .src_stage_mask = .{ .top_of_pipe_bit = true },
            .dst_stage_mask = .{ .all_transfer_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .transfer_write_bit = true },
            .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = vulkan.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vulkan.REMAINING_ARRAY_LAYERS,
            },
            .image = image,
        }};
        const initDepInfo = vulkan.DependencyInfo{
            .image_memory_barrier_count = initBarriers.len,
            .p_image_memory_barriers = &initBarriers,
        };
        device.cmdPipelineBarrier2(cmdHandle, &initDepInfo);

        // Record copy
        const region = [_]vulkan.BufferImageCopy{.{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = vulkan.ImageAspectFlags{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .image_extent = .{
                .width = self.vkImage.width,
                .height = self.vkImage.height,
                .depth = 1,
            },
        }};
        device.cmdCopyBufferToImage(
            cmdHandle,
            self.vkStageBuffer.?.buffer,
            image,
            vulkan.ImageLayout.transfer_dst_optimal,
            region.len,
            &region,
        );

        self.recordMipMap(vkCtx, cmdHandle);
    }
};
