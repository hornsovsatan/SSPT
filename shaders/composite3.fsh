#version 430 compatibility
uniform sampler2D colortex1;
uniform sampler2D colortex15;
uniform sampler2D colortex4;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
in vec2 texcoord;
#include "/lib/gi_common.glsl"
#include "/lib/gi_geometry.glsl"
/*
const int colortex7Format = RGBA32F;
const int colortex8Format = RGBA32F;
const int colortex9Format = RGBA32F;
*/
/* RENDERTARGETS: 4,7,9 */
layout(location = 0) out vec4 integratedGIOut;
// Raw luminance moments, sum of squared temporal weights, and valid history age.
layout(location = 1) out vec4 momentsOut;
layout(location = 2) out vec4 normalDepthOut;
const bool colortex4Clear = false;
const bool colortex7Clear = false;
const bool colortex9Clear = false;
#define HISTORY_NORMAL_MIN_DOT 0.75

void getPreviousProjection(vec3 currentViewPos, out vec2 prevUV, out float prevViewZ) {
    vec4 playerPos = gbufferModelViewInverse * vec4(currentViewPos, 1.0);
    vec3 prevPlayerPos = playerPos.xyz + cameraPosition - previousCameraPosition;
    vec4 prevViewPos = gbufferPreviousModelView * vec4(prevPlayerPos, 1.0);
    vec4 prevClipPos = gbufferPreviousProjection * prevViewPos;
    // History is stored on an unjittered GI grid.
    prevUV = prevClipPos.xy / prevClipPos.w * 0.5 + 0.5;
    prevViewZ = prevViewPos.z;
}

#define DI_FILTER_WRITE
#include "/lib/di_filter.glsl"
#include "/lib/di_temporal.glsl"

void main() {
    ivec2 centerPixel = ivec2(gl_FragCoord.xy);
    vec4 currentGuide = ptReadSurface(centerPixel);
    diAccumulate(centerPixel,currentGuide);
    if (currentGuide.a == 0.0) {
        integratedGIOut = vec4(0.0);
        momentsOut = vec4(0.0);
        normalDepthOut = vec4(0.0);
        return;
    }
    vec3 currentViewPos = ptSurfaceViewPosition(centerPixel, currentGuide);
    vec3 currentWorldNormal = giUnpackNormal(currentGuide.g);
    vec3 currentWorldGeoNormal = giUnpackNormal(currentGuide.r);
    normalDepthOut = currentGuide;
    vec3 currentInput = giFiniteLight(texelFetch(colortex8, centerPixel, 0).rgb);
    if (offlineCameraIsStill()) {
        // Offline accumulation keeps raw samples, including rare bright paths.
        integratedGIOut = vec4(currentInput, 0.0);
        momentsOut = vec4(0.0, 0.0, 0.0, -1.0);
        return;
    }

    bool cameraStill = length(cameraPosition - previousCameraPosition) <= 1e-5 &&
        offlineMatrixMaxDelta(gbufferModelView, gbufferPreviousModelView) <= 1e-6 &&
        offlineMatrixMaxDelta(gbufferProjection, gbufferPreviousProjection) <= 1e-6;

    vec2 prevUV;
    float predictedPrevViewZ;
    getPreviousProjection(currentViewPos, prevUV, predictedPrevViewZ);
    vec4 historyLight = vec4(0.0);
    vec4 history = vec4(0.0);
    float sumW = 0.0;
    mat4 previousInverseProjection = inverse(gbufferPreviousProjection);
    vec3 predictedPrevPos = (gbufferPreviousModelView * vec4(
        (gbufferModelViewInverse * vec4(currentViewPos, 1.0)).xyz +
        cameraPosition - previousCameraPosition, 1.0)).xyz;
    vec3 predictedGeoNormal = mat3(gbufferPreviousModelView) * currentWorldGeoNormal;
    if (all(greaterThanEqual(prevUV, vec2(0.0))) && all(lessThanEqual(prevUV, vec2(1.0)))) {
        ivec2 size = giRenderSizePixels();
        // Tight plane distance is invariant on a sloping face, unlike view-Z.
        // RGBA32F history avoids half-float depth quantization at long range.
        float planeTolerance = 0.002 + abs(predictedPrevViewZ) * 0.0001;
        // A stable camera must reuse its GI cell directly. Reprojecting the
        // snapped/jittered raster point back onto the nominal GI grid would
        // convolve history every frame, even while age keeps increasing.
        vec2 prevTexel = cameraStill ? vec2(centerPixel) : prevUV * vec2(size) - 0.5;
        // Avoid numerical reprojection drift across texels on a stationary surface.
        vec2 nearestTexel = round(prevTexel);
        prevTexel = mix(prevTexel, nearestTexel,
            lessThan(abs(prevTexel - nearestTexel), vec2(1e-4)));
        ivec2 base = ivec2(floor(prevTexel));
        vec2 f = fract(prevTexel);
        for (int y = 0; y <= 1; ++y) {
            for (int x = 0; x <= 1; ++x) {
                ivec2 p = base + ivec2(x, y);
                if (any(lessThan(p, ivec2(0))) || any(greaterThanEqual(p, size))) continue;
                vec4 aux = texelFetch(colortex9, p, 0);
                vec4 h = texelFetch(colortex7, p, 0);
                if (aux.a == 0.0 || ptSurfaceClass(aux) != ptSurfaceClass(currentGuide) || h.a < 1.0 ||
                    any(isnan(h)) || any(isinf(h))) continue;
                vec3 prevGeo = giUnpackNormal(aux.r);
                vec3 prevShading = giUnpackNormal(aux.g);
                float geoDot = dot(currentWorldGeoNormal, prevGeo);
                if (geoDot < 0.95) continue;
                vec2 historyUv = giHistoryRasterUv(p, size, aux.b) - fsr2PreviousJitterUv();
                vec4 ray = previousInverseProjection * vec4(historyUv * 2.0 - 1.0, 1.0, 1.0);
                vec3 prevPos = ray.xyz * (aux.a / ray.z);
                vec3 delta = prevPos - predictedPrevPos;
                vec3 prevGeoView = mat3(gbufferPreviousModelView) * prevGeo;
                float planeError = max(abs(dot(delta, predictedGeoNormal)), abs(dot(delta, prevGeoView)));
                float w = exp(-planeError / planeTolerance) * pow(max(geoDot, 0.0), 64.0);
                w *= smoothstep(HISTORY_NORMAL_MIN_DOT, 0.98, dot(currentWorldNormal, prevShading));
                vec2 bilinear = mix(1.0 - f, f, vec2(x, y));
                w *= bilinear.x * bilinear.y;
                if (w <= 0.0) continue;
                vec4 temporalSample = texelFetch(colortex4, p, 0);
                if (any(isnan(temporalSample)) || any(isinf(temporalSample))) continue;
                historyLight += vec4(giFiniteLight(temporalSample.rgb), max(temporalSample.a, 0.0)) * w;
                history += h * w;
                sumW += w;
            }
        }
    }
    bool historyValid = sumW > 0.05 && frameCounter > 1 && !sceneLightHistoryChanged();
    if (historyValid) {
        historyLight /= sumW;
        history /= sumW;
    } else {
        historyLight = vec4(0.0);
        history = vec4(0.0);
    }

    // A new surface uses its current sample immediately. Spatial reconstruction
    // handles short histories; filtered output never feeds this temporal mean.
    float historyLimit = cameraStill ? GI_MAX_HISTORY : GI_MOVING_HISTORY;
    // Poorly covered reprojections cannot inherit a fully mature history.
    float coverage = smoothstep(0.05, 0.8, sumW);
    float inheritedAge = min(history.a, historyLimit) * coverage;
    float age = historyValid ? min(inheritedAge + 1.0, historyLimit) : 1.0;
    float alpha = 1.0 / age;
    float lum = giLuminance(currentInput);
    vec2 moments = mix(history.rg, vec2(lum, lum * lum), alpha);
    float squaredWeights = historyValid
        ? (1.0 - alpha) * (1.0 - alpha) * max(history.b, 1.0 / max(inheritedAge, 1.0)) + alpha * alpha : 1.0;
    float rawVariance = max(moments.y - moments.x * moments.x, 0.0);
    float variance = rawVariance * squaredWeights / max(1.0 - squaredWeights, 1e-3);
    integratedGIOut = vec4(mix(historyLight.rgb, currentInput, alpha), variance);
    momentsOut = vec4(moments, squaredWeights, age);
}
