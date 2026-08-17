#version 450
#extension GL_EXT_buffer_reference: require
#extension GL_EXT_buffer_reference2: enable
#extension GL_EXT_scalar_block_layout: require

layout(location = 0) out vec4 outPos;
layout(location = 1) out vec2 outTextCoords;
layout(location = 2) out vec3 outNormal;
layout(location = 3) out vec3 outTangent;
layout(location = 4) out vec3 outBitangent;

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

layout(push_constant) uniform pc {
    mat4 modelMatrix;
    VertexBuffer vertexBuffer;
    IndexBuffer indexBuffer;
} push_constants;

void main()
{
    uint index = push_constants.indexBuffer.indices[gl_VertexIndex];
    VertexBuffer vertexData = push_constants.vertexBuffer;

    Vertex vertex = vertexData.vertices[index];
    vec4 worldPos = push_constants.modelMatrix * vec4(vertex.inPos, 1);
    gl_Position   = camUniform.projMatrix * camUniform.viewMatrix * worldPos;
    mat3 mNormal  = transpose(inverse(mat3(push_constants.modelMatrix)));
    outPos        = worldPos;
    outTextCoords = vertex.inTextCoords;
    outNormal     = normalize(mNormal * vertex.inNormal);
    outTangent    = normalize(mNormal * vertex.inTangent);
    outBitangent  = normalize(mNormal * vertex.inBitangent);
}