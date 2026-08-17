#version 450

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inTextCoords;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec3 inBitangent;

layout(location = 0) out vec4 outPos;
layout(location = 1) out vec2 outTextCoords;
layout(location = 2) out vec3 outNormal;
layout(location = 3) out vec3 outTangent;
layout(location = 4) out vec3 outBitangent;

layout(set = 0, binding = 0) uniform CamUniform {
    mat4 projMatrix;
    mat4 viewMatrix;
} camUniform;

layout(push_constant) uniform pc {
    mat4 modelMatrix;
} push_constants;

void main()
{
    vec4 worldPos = push_constants.modelMatrix * vec4(inPos, 1);
    gl_Position   = camUniform.projMatrix * camUniform.viewMatrix * worldPos;
    mat3 mNormal  = transpose(inverse(mat3(push_constants.modelMatrix)));
    outPos        = worldPos;
    outTextCoords = inTextCoords;
    outNormal     = normalize(mNormal * inNormal);
    outTangent    = normalize(mNormal * inTangent);
    outBitangent  = normalize(mNormal * inBitangent);    
}