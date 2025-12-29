const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");
const log = std.log.scoped(.vk);

const PoolInfo = struct {
    descCount: std.AutoArrayHashMap(vulkan.DescriptorType, u32),
    vkDescPool: VkDescPool,

    pub fn cleanup(self: *PoolInfo, vkDevice: vk.dev.VkDevice) void {
        self.descCount.deinit();
        self.vkDescPool.cleanup(vkDevice);
    }

    pub fn create(allocator: std.mem.Allocator, vkPhysDevice: vk.phys.VkPhysDevice, vkDevice: vk.dev.VkDevice) !PoolInfo {
        const descPoolSize = [_]vulkan.DescriptorPoolSize{ .{
            .type = vulkan.DescriptorType.uniform_buffer,
            .descriptor_count = try getLimits(vkPhysDevice, vulkan.DescriptorType.uniform_buffer),
        }, .{
            .type = vulkan.DescriptorType.combined_image_sampler,
            .descriptor_count = try getLimits(vkPhysDevice, vulkan.DescriptorType.combined_image_sampler),
        }, .{
            .type = vulkan.DescriptorType.storage_buffer,
            .descriptor_count = try getLimits(vkPhysDevice, vulkan.DescriptorType.storage_buffer),
        } };
        const vkDescPool = try VkDescPool.create(vkDevice, &descPoolSize);
        var descCount = std.AutoArrayHashMap(vulkan.DescriptorType, u32).init(allocator);
        for (descPoolSize) |item| {
            try descCount.put(item.type, item.descriptor_count);
        }

        return .{
            .descCount = descCount,
            .vkDescPool = vkDescPool,
        };
    }

    pub fn getLimits(vkPhysDevice: vk.phys.VkPhysDevice, descType: vulkan.DescriptorType) !u32 {
        const limits = vkPhysDevice.props.limits;
        return switch (descType) {
            vulkan.DescriptorType.uniform_buffer => limits.max_descriptor_set_uniform_buffers,
            vulkan.DescriptorType.combined_image_sampler => limits.max_descriptor_set_samplers,
            vulkan.DescriptorType.storage_buffer => limits.max_descriptor_set_storage_buffers,
            else => return error.NotSupportedDeviceType,
        };
    }
};

pub const VkDescAllocator = struct {
    poolInfoList: std.ArrayList(*PoolInfo),
    descSetMap: std.StringHashMap(VkDesSet),

    pub fn addDescSet(
        self: *VkDescAllocator,
        allocator: std.mem.Allocator,
        vkPhysDevice: vk.phys.VkPhysDevice,
        vkDevice: vk.dev.VkDevice,
        id: []const u8,
        vkDescSetLayout: VkDescSetLayout,
    ) !VkDesSet {
        const count = 1;
        var vkDescPoolOpt: ?VkDescPool = null;
        var poolInfoOpt: ?*PoolInfo = null;
        if (self.descSetMap.contains(id)) {
            log.err("Duplicate key for descriptor set [{s}]", .{id});
            return error.DuplicateDescKey;
        }
        for (self.poolInfoList.items) |poolInfo| {
            const available = poolInfo.descCount.get(vkDescSetLayout.descType) orelse return error.KeyNotFound;
            const limit = try PoolInfo.getLimits(vkPhysDevice, vkDescSetLayout.descType);
            if (count > limit) {
                log.err("Cannot create more than [{d}] for descriptor type [{any}]", .{
                    limit, vkDescSetLayout.descType,
                });
                return error.DescLimitExceeded;
            }
            if (available >= count) {
                vkDescPoolOpt = poolInfo.vkDescPool;
                poolInfoOpt = poolInfo;
                break;
            }
        }

        if (poolInfoOpt == null) {
            const poolInfo = try allocator.create(PoolInfo);
            poolInfo.* = try PoolInfo.create(allocator, vkPhysDevice, vkDevice);
            try self.poolInfoList.append(allocator, poolInfo);

            vkDescPoolOpt = poolInfo.vkDescPool;
            poolInfoOpt = poolInfo;
        }

        if (vkDescPoolOpt) |vkDescPool| {
            const vkDescSet = try VkDesSet.create(vkDevice, vkDescPool, vkDescSetLayout);
            const poolInfo = poolInfoOpt.?;
            const available = poolInfo.descCount.get(vkDescSetLayout.descType) orelse return error.KeyNotFound;
            if (available < count) {
                return error.NotAvailable;
            }

            try poolInfo.descCount.put(
                vkDescSetLayout.descType,
                available - count,
            );
            const ownedId = try allocator.dupe(u8, id);
            try self.descSetMap.put(ownedId, vkDescSet);
            return vkDescSet;
        } else {
            return error.NotAvailable;
        }
    }

    pub fn cleanup(self: *VkDescAllocator, allocator: std.mem.Allocator, vkDevice: vk.dev.VkDevice) void {
        for (self.poolInfoList.items) |poolInfo| {
            poolInfo.cleanup(vkDevice);
            allocator.destroy(poolInfo);
        }
        self.poolInfoList.deinit(allocator);

        var iter = self.descSetMap.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.descSetMap.deinit();
    }

    pub fn create(allocator: std.mem.Allocator, vkPhysDevice: vk.phys.VkPhysDevice, vkDevice: vk.dev.VkDevice) !VkDescAllocator {
        const descSetMap = std.StringHashMap(VkDesSet).init(
            allocator,
        );

        const poolInfo = try allocator.create(PoolInfo);
        poolInfo.* = try PoolInfo.create(allocator, vkPhysDevice, vkDevice);
        var poolInfoList = try std.ArrayList(*PoolInfo).initCapacity(allocator, 1);
        try poolInfoList.append(allocator, poolInfo);

        return .{
            .poolInfoList = poolInfoList,
            .descSetMap = descSetMap,
        };
    }

    pub fn getDescSet(self: *const VkDescAllocator, id: []const u8) ?VkDesSet {
        return self.descSetMap.get(id);
    }
};

pub const VkDescPool = struct {
    descPool: vulkan.DescriptorPool,

    pub fn create(vkDevice: vk.dev.VkDevice, descPoolSizes: []const vulkan.DescriptorPoolSize) !VkDescPool {
        var maxSets: u32 = 0;
        for (descPoolSizes) |*descPoolSize| {
            maxSets += descPoolSize.descriptor_count;
        }
        const createInfo = vulkan.DescriptorPoolCreateInfo{
            .flags = .{ .free_descriptor_set_bit = true },
            .p_pool_sizes = descPoolSizes.ptr,
            .pool_size_count = @as(u32, @intCast(descPoolSizes.len)),
            .max_sets = maxSets,
        };

        const descPool = try vkDevice.deviceProxy.createDescriptorPool(&createInfo, null);
        return .{ .descPool = descPool };
    }

    pub fn cleanup(self: *const VkDescPool, vkDevice: vk.dev.VkDevice) void {
        vkDevice.deviceProxy.destroyDescriptorPool(self.descPool, null);
    }
};

pub const VkDescSetLayout = struct {
    binding: u32,
    descSetLayout: vulkan.DescriptorSetLayout,
    descType: vulkan.DescriptorType,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, binding: u32, descType: vulkan.DescriptorType, stageFlags: vulkan.ShaderStageFlags, count: u32) !VkDescSetLayout {
        const bindingInfos = [_]vulkan.DescriptorSetLayoutBinding{.{
            .descriptor_count = count,
            .binding = binding,
            .descriptor_type = descType,
            .stage_flags = stageFlags,
        }};
        const createInfo = vulkan.DescriptorSetLayoutCreateInfo{
            .binding_count = bindingInfos.len,
            .p_bindings = &bindingInfos,
        };
        const descSetLayout = try vkCtx.vkDevice.deviceProxy.createDescriptorSetLayout(&createInfo, null);
        return .{ .binding = binding, .descSetLayout = descSetLayout, .descType = descType };
    }

    pub fn cleanup(self: *const VkDescSetLayout, vkCtx: *const vk.ctx.VkCtx) void {
        vkCtx.vkDevice.deviceProxy.destroyDescriptorSetLayout(self.descSetLayout, null);
    }
};

pub const VkDesSet = struct {
    descSet: vulkan.DescriptorSet,

    pub fn create(vkDevice: vk.dev.VkDevice, vkDescPool: vk.desc.VkDescPool, vkDescSetLayout: VkDescSetLayout) !VkDesSet {
        const descSetLayouts = [_]vulkan.DescriptorSetLayout{vkDescSetLayout.descSetLayout};
        const allocInfo = vulkan.DescriptorSetAllocateInfo{
            .descriptor_pool = vkDescPool.descPool,
            .p_set_layouts = &descSetLayouts,
            .descriptor_set_count = descSetLayouts.len,
        };

        var descSet: [1]vulkan.DescriptorSet = undefined;
        try vkDevice.deviceProxy.allocateDescriptorSets(&allocInfo, &descSet);
        return .{ .descSet = descSet[0] };
    }

    pub fn setBuffer(self: *const VkDesSet, vkDevice: vk.dev.VkDevice, vkBuffer: vk.buf.VkBuffer, binding: u32, descType: vulkan.DescriptorType) void {
        const bufferInfo = [_]vulkan.DescriptorBufferInfo{.{
            .buffer = vkBuffer.buffer,
            .offset = 0,
            .range = vkBuffer.size,
        }};

        const imageInfo = [_]vulkan.DescriptorImageInfo{};
        const texelBufferView = [_]vulkan.BufferView{};

        const descSets = [_]vulkan.WriteDescriptorSet{.{
            .dst_set = self.descSet,
            .descriptor_count = 1,
            .dst_binding = binding,
            .descriptor_type = descType,
            .p_buffer_info = &bufferInfo,
            .p_image_info = &imageInfo,
            .p_texel_buffer_view = &texelBufferView,
            .dst_array_element = 0,
        }};

        vkDevice.deviceProxy.updateDescriptorSets(descSets.len, &descSets, 0, null);
    }

    pub fn setImage(self: *const VkDesSet, vkDevice: vk.dev.VkDevice, vkImageView: vk.imv.VkImageView, vkTextSampler: vk.text.VkTextSampler, binding: u32) void {
        const imageInfo = [_]vulkan.DescriptorImageInfo{.{
            .image_layout = vulkan.ImageLayout.shader_read_only_optimal,
            .image_view = vkImageView.view,
            .sampler = vkTextSampler.sampler,
        }};

        const bufferInfo = [_]vulkan.DescriptorBufferInfo{};
        const texelBufferView = [_]vulkan.BufferView{};

        const descSets = [_]vulkan.WriteDescriptorSet{.{
            .dst_set = self.descSet,
            .descriptor_count = 1,
            .dst_binding = binding,
            .descriptor_type = vulkan.DescriptorType.combined_image_sampler,
            .p_buffer_info = &bufferInfo,
            .p_image_info = &imageInfo,
            .p_texel_buffer_view = &texelBufferView,
            .dst_array_element = 0,
        }};

        vkDevice.deviceProxy.updateDescriptorSets(descSets.len, &descSets, 0, null);
    }

    pub fn setImageArr(
        self: *const VkDesSet,
        allocator: std.mem.Allocator,
        vkDevice: vk.dev.VkDevice,
        vkImageViews: []const vk.imv.VkImageView,
        vkTextSampler: vk.text.VkTextSampler,
        binding: u32,
    ) !void {
        const imageInfos = try allocator.alloc(vulkan.DescriptorImageInfo, vkImageViews.len);
        defer allocator.free(imageInfos);

        for (vkImageViews, 0..) |vkImageView, i| {
            imageInfos[i] = .{
                .image_layout = vulkan.ImageLayout.shader_read_only_optimal,
                .image_view = vkImageView.view,
                .sampler = vkTextSampler.sampler,
            };
        }

        const bufferInfo = [_]vulkan.DescriptorBufferInfo{};
        const texelBufferView = [_]vulkan.BufferView{};

        const descSets = [_]vulkan.WriteDescriptorSet{.{
            .dst_set = self.descSet,
            .descriptor_count = @as(u23, @intCast(imageInfos.len)),
            .dst_binding = binding,
            .descriptor_type = vulkan.DescriptorType.combined_image_sampler,
            .p_buffer_info = &bufferInfo,
            .p_image_info = @ptrCast(imageInfos.ptr),
            .p_texel_buffer_view = &texelBufferView,
            .dst_array_element = 0,
        }};

        vkDevice.deviceProxy.updateDescriptorSets(descSets.len, &descSets, 0, null);
    }
};
