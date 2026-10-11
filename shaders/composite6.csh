#version 430 compatibility
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const vec2 workGroupsRender = vec2(1.0, 1.0);
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
layout(r32ui) uniform writeonly uimage2D fsrReconstructedDepth;
layout(r16f) uniform writeonly image2D fsrNewLocks;
#include "fsr2/ffx_fsr2_config.glsl"

void main() {
    if (!fsr2Enabled()) return;
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(pixel, fsr2DisplaySizePixels()))) return;
    imageStore(fsrNewLocks, pixel, vec4(0.0));
    if (any(greaterThanEqual(pixel, fsr2RenderSizePixels()))) return;
    // FSR2's inverted-depth reconstruction uses atomicMax and therefore
    // requires a zeroed target before the scatter pass.
    imageStore(fsrReconstructedDepth, pixel, uvec4(0u));
}
