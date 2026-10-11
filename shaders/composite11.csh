#version 430 compatibility
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const vec2 workGroupsRender = vec2(1.0, 1.0);
// GI has finished reading the raster geometric normals in this attachment.
layout(rgba16f) uniform image2D colorimg15;

#define FSR2_PASS_RCAS
#include "fsr2/ffx_fsr2_iris_callbacks.glsl"

void StoreUpscaledOutput(FfxInt32x2 pixel, FfxFloat32x3 value) {
    if (all(greaterThanEqual(ivec2(pixel), ivec2(0))) &&
        all(lessThan(ivec2(pixel), fsr2DisplaySize()))) {
        imageStore(colorimg15, ivec2(pixel), vec4(value, 1.0));
    }
}

#include "fsr2/ffx_fsr2_common.h"
#include "fsr2/ffx_fsr2_rcas.h"

void main() {
    if (!fsr2Enabled()) return;
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(pixel, fsr2DisplaySize()))) return;
    CurrFilter(FFX_MIN16_U2(pixel));
}
