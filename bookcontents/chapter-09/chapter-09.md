TBD

Explain why
const flags = vulkan.ImageUsageFlags{
            .transfer_dst_bit = true,
            .transfer_src_bit = true,
            .sampled_bit = true,
};

transfer_src_bit is needed when mip mapping

Explain vulkan.LOD_CLAMP_NONE in texture sampler creation