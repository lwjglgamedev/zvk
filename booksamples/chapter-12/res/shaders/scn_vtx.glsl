#version 450

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inTextCoords;

layout(location = 0) out vec2 outTextCoords;

layout(set = 0, binding = 0) uniform CamUniform {
    mat4 projMatrix;
    mat4 viewMatrix;
} camUniform;

layout(push_constant) uniform pc {
    mat4 modelMatrix;
} push_constants;

void main()
{
    gl_Position   = camUniform.projMatrix * camUniform.viewMatrix * push_constants.modelMatrix * vec4(inPos, 1);
    outTextCoords = inTextCoords;
}