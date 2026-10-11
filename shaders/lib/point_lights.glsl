#ifndef POINT_LIGHTS_GLSL
#define POINT_LIGHTS_GLSL
// Apparent source radius in blocks; never a light-distance cutoff.
#define LIGHT_BLOCK_RADIUS 0.0 // [0.0 0.05 0.1 0.2 0.35 0.5 0.75 1.0]
const uint pointLightCapacity = 256u;
layout(std430, binding = 5) buffer PointLightBuffer {
    uint pointLightCount;
    uint pointLightReserved0;
    uint pointLightReserved1;
    uint pointLightReserved2;
    vec4 pointLights[256]; // Grid-space center, normalized block emission level.
};
#endif
