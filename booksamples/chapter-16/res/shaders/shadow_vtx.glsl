#version 450
#extension GL_EXT_multiview : enable

#define SHADOW_MAP_CASCADE_COUNT 3

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inTextCoords;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec3 inBitangent;

layout(push_constant) uniform matrices {
    mat4 modelMatrix;
    uint materialIdx;
} push_constants;

layout (location = 0) out vec2 outTextCoord;
layout (location = 1) out flat uint outMaterialIdx;

layout(set = 0, binding = 0) uniform ProjUniforms {
    mat4 projViewMatrices[SHADOW_MAP_CASCADE_COUNT];
} projUniforms;

void main()
{
    outTextCoord   = inTextCoords;
    outMaterialIdx = push_constants.materialIdx;

    vec4 worldPos = push_constants.modelMatrix * vec4(inPos, 1.0f);
    gl_Position = projUniforms.projViewMatrices[gl_ViewIndex] * worldPos;
}
