Explain why
const flags = vulkan.ImageUsageFlags{
            .transfer_dst_bit = true,
            .transfer_src_bit = true,
            .sampled_bit = true,
};

transfer_src_bit is needed when mip mapping