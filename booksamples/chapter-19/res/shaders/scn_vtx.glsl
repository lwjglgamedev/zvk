#version 450
#extension GL_EXT_buffer_reference: require
#extension GL_EXT_buffer_reference2: enable
#extension GL_EXT_scalar_block_layout: require

layout(location = 0) out vec4 outPos;
layout(location = 1) out vec2 outTextCoords;
layout(location = 2) out vec3 outNormal;
layout(location = 3) out vec3 outTangent;
layout(location = 4) out vec3 outBitangent;
layout(location = 5) flat out uint outMaterialIdx;

layout(set = 0, binding = 0) uniform CamUniform {
    mat4 projMatrix;
    mat4 viewMatrix;
} camUniform;

struct Vertex {
    vec3 inPos;
    vec2 inTextCoords;
    vec3 inNormal;
    vec3 inTangent;
    vec3 inBitangent;
};

layout(scalar, buffer_reference) buffer VertexBuffer {
    Vertex[] vertices;
};

layout(std430, buffer_reference) buffer IndexBuffer {
    uint[] indices;
};

struct InstanceData {
    uint modelMatrixIdx;
    uint materialIdx;
    VertexBuffer vertexBuffer;
    IndexBuffer indexBuffer;
};

layout(std430, buffer_reference, buffer_reference_align=16) buffer InstancesDataBuffer {
    InstanceData[] instancesData;
};

layout(std430, buffer_reference, buffer_reference_align=8) buffer ModelMatricesDataBuffer {
    mat4[] modelMatrices;
};

layout(push_constant) uniform pc {
    InstancesDataBuffer instancesDataBuffer;
    ModelMatricesDataBuffer modelsMatricesDataBuffer;
} push_constants;

void main()
{
    uint entityId = gl_InstanceIndex;

    InstancesDataBuffer instancesDataBuffer = push_constants.instancesDataBuffer;
    InstanceData instanceData = instancesDataBuffer.instancesData[entityId];

    ModelMatricesDataBuffer modelMatricesDataBuffer = push_constants.modelsMatricesDataBuffer;
    mat4 modelMatrix = modelMatricesDataBuffer.modelMatrices[instanceData.modelMatrixIdx];

    VertexBuffer vertexBuffer = instanceData.vertexBuffer;
    IndexBuffer indexBuffer = instanceData.indexBuffer;

    uint index = indexBuffer.indices[gl_VertexIndex];
    Vertex vertex = vertexBuffer.vertices[index];

    vec3 inPos    = vertex.inPos;
    vec4 worldPos = modelMatrix * vec4(inPos, 1);
    mat3 mNormal  = transpose(inverse(mat3(modelMatrix)));

    outPos         = worldPos;
    outTextCoords  = vertex.inTextCoords;
    outNormal      = normalize(mNormal * vertex.inNormal);
    outTangent     = normalize(mNormal * vertex.inTangent);
    outBitangent   = normalize(mNormal * vertex.inBitangent);
    outMaterialIdx = instanceData.materialIdx;

    gl_Position    = camUniform.projMatrix * camUniform.viewMatrix * worldPos;
}