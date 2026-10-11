#version 430 compatibility
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const vec2 workGroupsRender = vec2(1.0, 1.0);

#define FSR2_PASS_RECONSTRUCT
#include "fsr2/ffx_fsr2_iris_callbacks.glsl"
#include "fsr2/ffx_fsr2_common.h"
#include "fsr2/ffx_fsr2_sample.h"
#include "fsr2/ffx_fsr2_reconstruct_dilated_velocity_and_previous_depth.h"

void main() {
    if (!fsr2Enabled()) return;
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(pixel, fsr2RenderSize()))) return;
    ReconstructAndDilate(FfxInt32x2(pixel));
}
