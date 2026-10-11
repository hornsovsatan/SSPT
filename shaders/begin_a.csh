#version 430 compatibility
uniform int frameCounter;
layout(local_size_x = 256) in;
#define TRACE_END 0x00ffffffu
#define TRACE_SIZE_X 128
#define TRACE_SIZE_Y 128
#define TRACE_SIZE_Z 128
#define TRACE_VOXEL_COUNT (TRACE_SIZE_X * TRACE_SIZE_Y * TRACE_SIZE_Z)
#define TRACE_TEXTURE_KEY_COUNT 16u
const ivec3 workGroups = ivec3(8192, 1, 1);
struct TraceTextureKey {
    uint hash;
    uint bounds;
};
layout(std430, binding = 0) buffer TraceCounterBuffer {
    uint traceTriangleCount;
    uint traceReservedCounter;
};
layout(std430, binding = 2) buffer TraceHeadBuffer {
    uint traceHead[];
};
layout(std430, binding = 4) buffer TraceTextureBuffer {
    uint traceTextureLast;
    uint traceTextureReserved;
    TraceTextureKey traceTextureKeys[16];
    uint traceTextureData[];
};
#include "/lib/emission_area.glsl"
#include "/lib/point_lights.glsl"
#include "/lib/di_lights.glsl"
void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id == 0u) {
        traceTriangleCount = 0u;
        pointLightCount = 0u;
        diLightCount = 0u;
        traceReservedCounter = 0u;
        if (frameCounter <= 1) {
            traceTextureLast = 0u;
            traceTextureReserved = 0u;
        }
    }
    if (id < 32768u) diLightLookup[id] = DI_INVALID;
    if (id < TRACE_VOXEL_COUNT) {
        traceHead[id] = TRACE_END;
        emissionBlockArea[id] = 0u;
        emissionBlockShape[id] = 0u;
    }
    if (frameCounter <= 1 && id < TRACE_TEXTURE_KEY_COUNT) {
        traceTextureKeys[id].hash = 0u;
        traceTextureKeys[id].bounds = 0u;
    }
}
