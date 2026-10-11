#version 430 compatibility
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const vec2 workGroupsRender = vec2(1.0, 1.0);

#define FSR2_PASS_ACCUMULATE
#include "fsr2/ffx_fsr2_iris_callbacks.glsl"

void StoreUpscaledOutput(FfxInt32x2 pixel, FfxFloat32x3 value) {
    // FFX_FSR2_OPTION_APPLY_SHARPENING stores the reconstructed color in the
    // current internal history; composite11 reads that resource as RCAS input.
}

#include "fsr2/ffx_fsr2_common.h"
#include "fsr2/ffx_fsr2_sample.h"
#include "fsr2/ffx_fsr2_upsample.h"
#include "fsr2/ffx_fsr2_postprocess_lock_status.h"
#include "fsr2/ffx_fsr2_reproject.h"
#include "fsr2/ffx_fsr2_accumulate.h"

void main() {
    if (!fsr2Enabled()) return;
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(pixel, fsr2DisplaySize()))) return;
    Accumulate(FfxInt32x2(pixel));
}
