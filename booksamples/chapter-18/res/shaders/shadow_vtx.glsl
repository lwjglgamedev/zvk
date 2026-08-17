#version 450
#extension GL_EXT_buffer_reference: require
#extension GL_EXT_buffer_reference2: enable
#extension GL_EXT_scalar_block_layout: require
#extension GL_EXT_multiview : enable

#define SHADOW_MAP_CASCADE_COUNT 3


struct Vertex {
    vec3 inPos;
    vec2 inTextCoords;
    vec3 inNoral ;
    vec3 inTangent;
};

layout(scalar, buffer_reference) buffer VertexBuffer {
    Vertex[] vertices;
};

layout(std430, buffer_reference) buffer IndexBuffer {
    uint[] indices;
};

struct InstanceData {
    mat4 modelMatrix;
    uint materialIdx;
    uint padding[3];
};

layout(push_constant, scalar) uniform matrices {
    mat4 modelMatrix;
    uint materialIdx;
    VertexBuffer vertexBuffer;
    IndexBuffer indexBuffer;
} push_constants;

layout (location = 0) out vec2 outTextCoord;
layout (location = 1) out flat uint outMaterialIdx;

layout(set = 0, binding = 0) uniform ProjUniforms {
    mat4 projViewMatrices[SHADOW_MAP_CASCADE_COUNT];
} projUniforms;

void main()
{
    uint index = push_constants.indexBuffer.indices[gl_VertexIndex];
    VertexBuffer vertexData = push_constants.vertexBuffer;
    Vertex vertex = vertexData.vertices[index];

    outTextCoord   = vertex.inTextCoords;
    outMaterialIdx = push_constants.materialIdx;

    vec4 worldPos = push_constants.modelMatrix * vec4(vertex.inPos, 1.0f);
    gl_Position = projUniforms.projViewMatrices[gl_ViewIndex] * worldPos;
}
