#ifndef LIGHT_AND_SHADOW_GI_COMMON_GLSL
#define LIGHT_AND_SHADOW_GI_COMMON_GLSL

#include "/lib/scene_lighting.glsl"

// Zero disables offline accumulation; other values select GI samples per frame.
#define OFFLINE_MODE 0 // [0 4 8 12 16]
const int GI_MAX_SAMPLES = 16;

#define OFFLINE_CAMERA_POSITION_EPSILON 0.00001
#define OFFLINE_CAMERA_MATRIX_EPSILON 0.000001

float offlineMatrixMaxDelta(mat4 currentMatrix, mat4 previousMatrix) {
    float maxDelta = 0.0;
    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 4; ++row) {
            maxDelta = max(
                maxDelta,
                abs(currentMatrix[column][row] - previousMatrix[column][row])
            );
        }
    }
    return maxDelta;
}

bool offlineCameraIsStill() {
#if OFFLINE_MODE > 0
    vec3 positionDelta = cameraPosition - previousCameraPosition;
    float positionEpsilonSquared =
        OFFLINE_CAMERA_POSITION_EPSILON * OFFLINE_CAMERA_POSITION_EPSILON;
    bool positionStill = dot(positionDelta, positionDelta) <= positionEpsilonSquared;
    bool viewStill = offlineMatrixMaxDelta(
        gbufferModelView,
        gbufferPreviousModelView
    ) <= OFFLINE_CAMERA_MATRIX_EPSILON;
    bool projectionStill = offlineMatrixMaxDelta(
        gbufferProjection,
        gbufferPreviousProjection
    ) <= OFFLINE_CAMERA_MATRIX_EPSILON;
    return positionStill && viewStill && projectionStill;
#else
    return false;
#endif
}

// GI resolution and coordinate mapping.
#include "/fsr2/ffx_fsr2_config.glsl"

// GI: half FSR source resolution in real time, full source when offline/still.
ivec2 giRenderSizePixels() {
    if (offlineCameraIsStill()) {
        return fsr2RenderSizePixels();
    }
    return max(
        ivec2(ceil(vec2(fsr2RenderSizePixels()) * 0.5)),
        ivec2(1)
    );
}

vec2 giRenderFraction() {
    return vec2(giRenderSizePixels()) /
        vec2(fsr2DisplaySizePixels());
}

vec2 giClampLogicalUv(vec2 logicalUv) {
    vec2 halfTexel = 0.5 / vec2(giRenderSizePixels());
    return clamp(logicalUv, halfTexel, vec2(1.0) - halfTexel);
}

// Keep real-time GI on a stable grid. FSR jitter belongs to the G-buffer,
// not to persistent GI texels; resampling it every frame diffuses contact detail.
vec2 giGeometryUv(vec2 giUv) {
    return offlineCameraIsStill() ? giUv : giUv + fsr2CurrentJitterUv();
}

vec2 giRenderStorageUv(vec2 logicalUv) {
    if (!offlineCameraIsStill()) logicalUv -= fsr2CurrentJitterUv();
    return giClampLogicalUv(logicalUv) * giRenderFraction();
}

// Shared history limits and filtering math.
// Static rare-path estimates must be allowed to continue refining.
const float GI_MAX_HISTORY = 4096.0;
const float GI_MOVING_HISTORY = 64.0;
const float GI_SPATIAL_MAX_RADIUS = 30.0;

vec3 giFiniteLight(vec3 light) {
    if (any(isnan(light)) || any(isinf(light))) return vec3(0.0);
    return max(light, vec3(0.0));
}

float giLuminance(vec3 light) {
    return dot(giFiniteLight(light), vec3(0.2126, 0.7152, 0.0722));
}

float giGeometryWeight(vec3 p, vec3 n, vec3 q, vec3 m) {
    float normalDot = max(dot(n, m), 0.0);
    float normalWeight = pow(normalDot, 32.0) * smoothstep(0.90, 0.98, normalDot);
    // A sloping surface has changing view Z but zero tangent-plane distance.
    vec3 delta = q - p;
    float planeDistance = max(abs(dot(delta, n)), abs(dot(delta, m)));
    float tolerance = 0.003 + 0.0001 * max(abs(p.z), abs(q.z));
    float samePlane = 1.0 - smoothstep(tolerance, 3.0 * tolerance, planeDistance);
    return normalWeight * samePlane * exp(-planeDistance / tolerance);
}

#endif
