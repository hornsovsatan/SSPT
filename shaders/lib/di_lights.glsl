#ifndef DI_LIGHTS_GLSL
#define DI_LIGHTS_GLSL
#include "/lib/di_options.glsl"
const uint diLightCapacity = 16384u;
const uint DI_INVALID = 0xffffffffu;
// One record per submitted triangle/quad, never per voxel copy.
struct DILight {
    vec4 p0; // xyz grid position; w full geometric area
    vec4 e1;
    vec4 e2;
    uvec4 data; // three packed UVs and texture/tint/emission
    uvec4 meta; // stable identity hash, emission owner, quad flag, reserved
};
layout(std430, binding = 6) buffer DILightBuffer {
    uint diLightCount;
    uint diPadding0, diPadding1, diPadding2;
    DILight diLights[16384];
    uint diLightLookup[32768];
    vec4 diLightProxy[16384]; // center and approximate emitted power
    float diLightCDF[16384];
};
layout(std430, binding = 7) buffer DIPrimitiveBuffer {
    uint diPrimitiveLight[];
};
#endif
