// Iris/OpenGL resource bridge for the official AMD FSR 2.3.3 GPU headers.
#include "/lib/scene_lighting.glsl"

#define FFX_GPU 1
#define FFX_GLSL 1
#define FFX_HALF 0
#define FFX_SKIP_EXT 1
#define FFX_FSR2_OPTION_HDR_COLOR_INPUT 1
#define FFX_FSR2_OPTION_LOW_RESOLUTION_MOTION_VECTORS 1
#define FFX_FSR2_OPTION_JITTERED_MOTION_VECTORS 0
#define FFX_FSR2_OPTION_INVERTED_DEPTH 1
#define FFX_FSR2_OPTION_APPLY_SHARPENING 1
#define FFX_FSR2_OPTION_UPSAMPLE_USE_LANCZOS_TYPE 2
#define FFX_FSR2_OPTION_REPROJECT_USE_LANCZOS_TYPE 0
#define FFX_FSR2_OPTION_REPROJECT_SAMPLERS_USE_DATA_HALF 0
#define FFX_FSR2_OPTION_POSTPROCESSLOCKSTATUS_SAMPLERS_USE_DATA_HALF 0

#include "ffx_core.h"

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D depthtex0;
uniform sampler2D fsrDilatedMotionSampler;
uniform sampler2D fsrDilatedDepthSampler;
uniform sampler2D fsrPreparedInputSampler;
uniform sampler2D fsrReactiveMasksSampler;
uniform sampler2D fsrNewLocksSampler;
uniform sampler2D fsrLockInputLumaSampler;
uniform sampler2D fsrColorHistorySampler;
uniform sampler2D fsrLockStatusSampler;
uniform sampler2D fsrLumaHistorySampler;
uniform usampler2D fsrReconstructedDepthSampler;

// Declare only this pass's images; some drivers count unused declarations
// before dead-code elimination against the eight-image stage limit.
#if defined(FSR2_PASS_RECONSTRUCT) || defined(FSR2_PASS_LOCK)
layout(r32ui) uniform coherent uimage2D fsrReconstructedDepth;
#endif
#if defined(FSR2_PASS_RECONSTRUCT)
layout(rg16f) uniform image2D fsrDilatedMotion;
#endif
#if defined(FSR2_PASS_RECONSTRUCT)
layout(r32f) uniform image2D fsrDilatedDepth;
#endif
#if defined(FSR2_PASS_DEPTH_CLIP)
layout(rgba16f) uniform image2D fsrPreparedInput;
#endif
#if defined(FSR2_PASS_DEPTH_CLIP)
layout(rg16f) uniform image2D fsrReactiveMasks;
#endif
#if defined(FSR2_PASS_LOCK) || defined(FSR2_PASS_ACCUMULATE)
layout(r16f) uniform image2D fsrNewLocks;
#endif
#if defined(FSR2_PASS_RECONSTRUCT)
layout(r16f) uniform image2D fsrLockInputLuma;
#endif
#if defined(FSR2_PASS_ACCUMULATE)
layout(rgba16f) uniform image2D fsrColorHistory;
#endif
#if defined(FSR2_PASS_ACCUMULATE)
layout(rg16f) uniform image2D fsrLockStatus;
#endif
#if defined(FSR2_PASS_ACCUMULATE)
layout(rgba16f) uniform image2D fsrLumaHistory;
#endif

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
uniform float frameTime;
uniform int frameCounter;

#include "ffx_fsr2_config.glsl"

// Bilinear taps must never cross the current/previous history boundary.
ivec2 fsrPairPixel(ivec2 p,int parity) {
    ivec2 size=fsr2DisplaySizePixels();
    return clamp(p,ivec2(0),size-1)+ivec2(0,parity*size.y);
}
vec2 fsrPairUv(vec2 uv,int parity) {
    vec2 halfTexel=0.5/vec2(fsr2DisplaySizePixels());
    uv=clamp(uv,halfTexel,vec2(1.0)-halfTexel);
    return vec2(uv.x,(uv.y+float(parity))*0.5);
}
ivec2 fsr2RenderSize() {
    return fsr2RenderSizePixels();
}

ivec2 fsr2DisplaySize() {
    return fsr2DisplaySizePixels();
}

ivec2 fsr2ClampRenderPixel(ivec2 p) {
    return clamp(p, ivec2(0), fsr2RenderSize() - ivec2(1));
}

ivec2 fsr2ClampDisplayPixel(ivec2 p) {
    return clamp(p, ivec2(0), fsr2DisplaySize() - ivec2(1));
}

vec2 fsr2RenderResourceUv(vec2 logicalUv) {
    return logicalUv * fsr2RenderFraction();
}

vec2 fsr2FullUvFromRenderPixel(ivec2 p) {
    return fsr2GbufferUvFromRenderPixel(fsr2ClampRenderPixel(p), textureSize(depthtex0, 0));
}

bool fsr2CurrentParity() {
    return (frameCounter & 1) != 0;
}

bool fsr2ResetHistory() {
    return frameCounter <= 1 || sceneLightHistoryChanged() ||
        any(greaterThan(abs(cameraPosition - previousCameraPosition), vec3(32.0)));
}

FfxInt32x2 RenderSize() { return FfxInt32x2(fsr2RenderSize()); }
FfxInt32x2 MaxRenderSize() { return FfxInt32x2(fsr2RenderSize()); }
FfxInt32x2 DisplaySize() { return FfxInt32x2(fsr2DisplaySize()); }
FfxInt32x2 InputColorResourceDimensions() { return FfxInt32x2(fsr2RenderSize()); }
FfxInt32x2 LumaMipDimensions() { return FfxInt32x2(fsr2RenderSize()); }
FfxInt32 LumaMipLevelToUse() { return 0; }
FfxInt32 FrameIndex() { return fsr2ResetHistory() ? 0 : frameCounter; }

FfxFloat32x4 DeviceToViewSpaceTransformFactors() {
    // depthtex0 is converted to inverted depth by LoadInputDepth().
    return FfxFloat32x4(
        0.5 + 0.5 * gbufferProjection[2][2],
        -0.5 * gbufferProjection[3][2],
        1.0 / gbufferProjection[0][0],
        1.0 / gbufferProjection[1][1]
    );
}

FfxFloat32x2 Jitter() { return FfxFloat32x2(fsr2CurrentJitterPixels()); }
FfxFloat32x2 MotionVectorScale() { return FfxFloat32x2(1.0); }
FfxFloat32x2 DownscaleFactor() {
    // FSR2 maps a high-resolution output pixel back into the low-resolution
    // render grid by multiplying by this factor.  The SDK constant therefore
    // is renderSize / displaySize (less than one while upscaling), not the
    // user-facing upscale ratio.
    return FfxFloat32x2(vec2(fsr2RenderSize()) / vec2(fsr2DisplaySize()));
}
FfxFloat32x2 MotionVectorJitterCancellation() { return FfxFloat32x2(0.0); }
FfxFloat32 PreExposure() { return 1.0; }
FfxFloat32 PreviousFramePreExposure() { return 1.0; }
FfxFloat32 TanHalfFoV() { return 1.0 / abs(gbufferProjection[1][1]); }
FfxFloat32 JitterSequenceLength() { return FfxFloat32(fsr2JitterPhaseCount()); }
FfxFloat32 DeltaTime() { return max(frameTime, 1.0 / 240.0); }
FfxFloat32 DynamicResChangeFactor() { return 1.0; }
FfxFloat32 ViewSpaceToMetersFactor() { return 1.0; }
FfxFloat32 Exposure() { return 1.0; }
FfxFloat32 AutoExposure() { return 1.0; }

FfxUInt32x4 RCASConfig() {
    return FfxUInt32x4(floatBitsToUint(exp2(-FSR2_SHARPNESS)), 0u, 0u, 0u);
}

float fsr2RawInputDepth(ivec2 p) {
    vec2 fullUv = fsr2FullUvFromRenderPixel(p);
    vec4 translucentNormal = textureLod(colortex12, fullUv, 0.0);
    vec4 translucentSurface = textureLod(colortex11, fullUv, 0.0);
    bool validTranslucent = translucentNormal.a >= 0.5
        && translucentSurface.r > 0.0
        && translucentSurface.r < 1.0;
    return validTranslucent
        ? translucentSurface.r
        : textureLod(depthtex0, fullUv, 0.0).r;
}

FfxFloat32 LoadInputDepth(FfxInt32x2 p) {
    return 1.0 - fsr2RawInputDepth(ivec2(p));
}

FfxFloat32 LoadSceneDepth(FfxInt32x2 p) { return LoadInputDepth(p); }

FfxFloat32x3 LoadInputColor(FfxInt32x2 p) {
    return texelFetch(colortex0, fsr2ClampRenderPixel(ivec2(p)), 0).rgb;
}

FfxFloat32x3 SampleInputColor(FfxFloat32x2 uv) {
    vec2 resourceUv = fsr2RenderResourceUv(
        clamp(vec2(uv), vec2(0.0), vec2(1.0))
    );
    return textureLod(colortex0, resourceUv, 0.0).rgb;
}

FfxFloat32x2 LoadInputMotionVector(FfxInt32x2 pixel) {
    ivec2 p = fsr2ClampRenderPixel(ivec2(pixel));
    float rawDepth = fsr2RawInputDepth(p);
    // Match the exact G-buffer sample used by composite5 and LoadInputDepth.
    vec2 currentUv = fsr2FullUvFromRenderPixel(p);
    vec2 currentUnjitteredUv = currentUv - fsr2CurrentJitterUv();
    if (rawDepth >= 1.0) {
        // Infinite sky ignores camera translation, but it still moves under
        // camera rotation.  A zero vector made the sky disagree with terrain
        // silhouettes whenever the view changed.
        vec4 currentClip = vec4(
            currentUnjitteredUv * 2.0 - 1.0, 1.0, 1.0
        );
        vec4 currentView = gbufferProjectionInverse * currentClip;
        vec3 currentViewDirection = normalize(
            currentView.xyz / max(abs(currentView.w), 1e-6)
        );
        vec3 worldDirection = normalize(
            mat3(gbufferModelViewInverse) * currentViewDirection
        );
        vec3 previousViewDirection = normalize(
            mat3(gbufferPreviousModelView) * worldDirection
        );
        vec4 previousClip = gbufferPreviousProjection
            * vec4(previousViewDirection, 0.0);
        if (previousClip.w <= 1e-6) return FfxFloat32x2(0.0);
        vec2 previousUnjitteredUv = previousClip.xy
            / previousClip.w * 0.5 + 0.5;
        return FfxFloat32x2(
            previousUnjitteredUv - currentUnjitteredUv
        );
    }

    vec4 clip = vec4(currentUnjitteredUv * 2.0 - 1.0,
                     rawDepth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    view /= view.w;
    vec3 player = (gbufferModelViewInverse * vec4(view.xyz, 1.0)).xyz;
    vec3 world = player + cameraPosition;
    vec3 previousPlayer = world - previousCameraPosition;
    vec4 previousView = gbufferPreviousModelView * vec4(previousPlayer, 1.0);
    vec4 previousClip = gbufferPreviousProjection * previousView;
    if (previousClip.w <= 1e-6) return FfxFloat32x2(0.0);
    vec2 previousUnjitteredUv = previousClip.xy / previousClip.w * 0.5 + 0.5;
    return FfxFloat32x2(previousUnjitteredUv - currentUnjitteredUv);
}

FfxFloat32 LoadReactiveMask(FfxInt32x2 pixel) {
    vec2 fullUv = fsr2FullUvFromRenderPixel(ivec2(pixel));
    vec4 translucentNormal = textureLod(colortex12, fullUv, 0.0);
    vec4 translucentSurface = textureLod(colortex11, fullUv, 0.0);
    bool validTranslucent = translucentNormal.a >= 0.5
        && translucentSurface.r > 0.0
        && translucentSurface.r < 1.0;
    float opacity = validTranslucent
        ? clamp(translucentSurface.g, 0.0, 1.0)
        : 0.0;
    float emission = clamp(textureLod(colortex3, fullUv, 0.0).r, 0.0, 1.0);
    // A value of one rejects nearly all temporal history.  The old blanket
    // value made every transparent block expose the projection jitter forever.
    // Static transparency only needs a small opacity-weighted response.
    return max(opacity * 0.15, emission * 0.5);
}

FfxFloat32 LoadTransparencyAndCompositionMask(FfxUInt32x2 pixel) {
    vec2 fullUv = fsr2FullUvFromRenderPixel(ivec2(pixel));
    vec4 translucentNormal = textureLod(colortex12, fullUv, 0.0);
    vec4 translucentSurface = textureLod(colortex11, fullUv, 0.0);
    bool validTranslucent = translucentNormal.a >= 0.5
        && translucentSurface.r > 0.0
        && translucentSurface.r < 1.0;
    float opacity = validTranslucent
        ? clamp(translucentSurface.g, 0.0, 1.0)
        : 0.0;
    return opacity * 0.25;
}

#if defined(FSR2_PASS_RECONSTRUCT)
void StoreReconstructedDepth(FfxInt32x2 p, FfxFloat32 depth) {
    imageAtomicMax(fsrReconstructedDepth, ivec2(p), floatBitsToUint(depth));
}
#endif

#if defined(FSR2_PASS_LOCK)
void SetReconstructedDepth(FfxInt32x2 p, FfxUInt32 value) {
    imageStore(fsrReconstructedDepth, ivec2(p), uvec4(value, 0u, 0u, 0u));
}
#endif

FfxFloat32 LoadReconstructedPrevDepth(FfxInt32x2 p) {
    return uintBitsToFloat(texelFetch(
        fsrReconstructedDepthSampler, fsr2ClampRenderPixel(ivec2(p)), 0
    ).r);
}

#if defined(FSR2_PASS_RECONSTRUCT)
void StoreDilatedMotionVector(FfxInt32x2 p, FfxFloat32x2 motion) {
    if (fsr2CurrentParity())
        imageStore(fsrDilatedMotion, fsrPairPixel(ivec2(p),1), vec4(motion, 0.0, 0.0));
    else
        imageStore(fsrDilatedMotion, fsrPairPixel(ivec2(p),0), vec4(motion, 0.0, 0.0));
}
#endif

FfxFloat32x2 LoadDilatedMotionVector(FfxInt32x2 p) {
    p = FfxInt32x2(fsr2ClampRenderPixel(ivec2(p)));
    return fsr2CurrentParity()
        ? texelFetch(fsrDilatedMotionSampler, fsrPairPixel(ivec2(p),1), 0).rg
        : texelFetch(fsrDilatedMotionSampler, fsrPairPixel(ivec2(p),0), 0).rg;
}

FfxFloat32x2 SampleDilatedMotionVector(FfxFloat32x2 uv) {
    vec2 resourceUv = fsr2RenderResourceUv(vec2(uv));
    return fsr2CurrentParity()
        ? textureLod(fsrDilatedMotionSampler, fsrPairUv(resourceUv,1), 0.0).rg
        : textureLod(fsrDilatedMotionSampler, fsrPairUv(resourceUv,0), 0.0).rg;
}

FfxFloat32x2 LoadPreviousDilatedMotionVector(FfxInt32x2 p) {
    p = FfxInt32x2(fsr2ClampRenderPixel(ivec2(p)));
    return fsr2CurrentParity()
        ? texelFetch(fsrDilatedMotionSampler, fsrPairPixel(ivec2(p),0), 0).rg
        : texelFetch(fsrDilatedMotionSampler, fsrPairPixel(ivec2(p),1), 0).rg;
}

FfxFloat32x2 SamplePreviousDilatedMotionVector(FfxFloat32x2 uv) {
    vec2 resourceUv = fsr2RenderResourceUv(vec2(uv));
    return fsr2CurrentParity()
        ? textureLod(fsrDilatedMotionSampler, fsrPairUv(resourceUv,0), 0.0).rg
        : textureLod(fsrDilatedMotionSampler, fsrPairUv(resourceUv,1), 0.0).rg;
}

#if defined(FSR2_PASS_RECONSTRUCT)
void StoreDilatedDepth(FfxInt32x2 p, FfxFloat32 depth) {
    imageStore(fsrDilatedDepth, ivec2(p), vec4(depth, 0.0, 0.0, 0.0));
}
#endif

FfxFloat32 LoadDilatedDepth(FfxInt32x2 p) {
    return texelFetch(fsrDilatedDepthSampler, fsr2ClampRenderPixel(ivec2(p)), 0).r;
}

#if defined(FSR2_PASS_RECONSTRUCT)
void StoreLockInputLuma(FfxInt32x2 p, FfxFloat32 luma) {
    imageStore(fsrLockInputLuma, ivec2(p), vec4(luma, 0.0, 0.0, 0.0));
}
#endif

FfxFloat32 LoadLockInputLuma(FfxInt32x2 p) {
    return texelFetch(fsrLockInputLumaSampler, fsr2ClampRenderPixel(ivec2(p)), 0).r;
}

float fsr2LogShadingLuma(vec3 rgb) {
    rgb = max(rgb, vec3(0.0));
    rgb /= max(max(rgb.r, rgb.g), rgb.b) + 1.0;
    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float perceived = luma <= 216.0 / 24389.0
        ? luma * (24389.0 / 27.0)
        : pow(luma, 1.0 / 3.0) * 116.0 - 16.0;
    return log(max(perceived * 0.01, 1e-6));
}

FfxFloat32 LoadMipLuma(FfxInt32x2 p, FfxInt32 mipLevel) {
    vec3 rgb = texelFetch(colortex0, fsr2ClampRenderPixel(ivec2(p)), 0).rgb;
    return fsr2LogShadingLuma(rgb);
}

FfxFloat32 SampleMipLuma(FfxFloat32x2 uv, FfxInt32 mipLevel) {
    return fsr2LogShadingLuma(textureLod(
        colortex0, fsr2RenderResourceUv(vec2(uv)), 0.0
    ).rgb);
}

#if defined(FSR2_PASS_DEPTH_CLIP)
void StorePreparedInputColor(FfxInt32x2 p, FfxFloat32x4 value) {
    imageStore(fsrPreparedInput, ivec2(p), vec4(value));
}
#endif

FfxFloat32x3 LoadPreparedInputColor(FfxInt32x2 p) {
    return texelFetch(fsrPreparedInputSampler, fsr2ClampRenderPixel(ivec2(p)), 0).rgb;
}

FfxFloat32 SampleDepthClip(FfxFloat32x2 uv) {
    return textureLod(
        fsrPreparedInputSampler, fsr2RenderResourceUv(vec2(uv)), 0.0
    ).a;
}

#if defined(FSR2_PASS_DEPTH_CLIP)
void StoreDilatedReactiveMasks(FfxInt32x2 p, FfxFloat32x2 value) {
    imageStore(fsrReactiveMasks, ivec2(p), vec4(value, 0.0, 0.0));
}
#endif

FfxFloat32x2 LoadDilatedReactiveMasks(FfxInt32x2 p) {
    return texelFetch(fsrReactiveMasksSampler, fsr2ClampRenderPixel(ivec2(p)), 0).rg;
}

FfxFloat32x2 SampleDilatedReactiveMasks(FfxFloat32x2 uv) {
    return textureLod(
        fsrReactiveMasksSampler, fsr2RenderResourceUv(vec2(uv)), 0.0
    ).rg;
}

#if defined(FSR2_PASS_LOCK) || defined(FSR2_PASS_ACCUMULATE)
void StoreNewLocks(FfxInt32x2 p, FfxFloat32 value) {
    imageStore(fsrNewLocks, ivec2(p), vec4(value, 0.0, 0.0, 0.0));
}
#endif

FfxFloat32 LoadNewLocks(FfxInt32x2 p) {
    return texelFetch(fsrNewLocksSampler, fsr2ClampDisplayPixel(ivec2(p)), 0).r;
}

#if defined(FSR2_PASS_ACCUMULATE)
FfxFloat32 LoadRwNewLocks(FfxInt32x2 p) {
    return imageLoad(fsrNewLocks, ivec2(p)).r;
}
#endif

FfxFloat32x4 LoadHistory(FfxInt32x2 p) {
    p = FfxInt32x2(fsr2ClampDisplayPixel(ivec2(p)));
    return fsr2CurrentParity()
        ? texelFetch(fsrColorHistorySampler, fsrPairPixel(ivec2(p),0), 0)
        : texelFetch(fsrColorHistorySampler, fsrPairPixel(ivec2(p),1), 0);
}

#if defined(FSR2_PASS_ACCUMULATE)
void StoreReprojectedHistory(FfxInt32x2 p, FfxFloat32x4 value) {
    if (fsr2CurrentParity()) imageStore(fsrColorHistory, fsrPairPixel(ivec2(p),1), vec4(value));
    else imageStore(fsrColorHistory, fsrPairPixel(ivec2(p),0), vec4(value));
}
#endif

#if defined(FSR2_PASS_ACCUMULATE)
void StoreInternalColorAndWeight(FfxInt32x2 p, FfxFloat32x4 value) {
    StoreReprojectedHistory(p, value);
}
#endif

FfxFloat32x2 LoadLockStatus(FfxInt32x2 p) {
    p = FfxInt32x2(fsr2ClampDisplayPixel(ivec2(p)));
    return fsr2CurrentParity()
        ? texelFetch(fsrLockStatusSampler, fsrPairPixel(ivec2(p),0), 0).rg
        : texelFetch(fsrLockStatusSampler, fsrPairPixel(ivec2(p),1), 0).rg;
}

FfxFloat32x2 SampleLockStatus(FfxFloat32x2 uv) {
    return fsr2CurrentParity()
        ? textureLod(fsrLockStatusSampler, fsrPairUv(vec2(uv),0), 0.0).rg
        : textureLod(fsrLockStatusSampler, fsrPairUv(vec2(uv),1), 0.0).rg;
}

#if defined(FSR2_PASS_ACCUMULATE)
void StoreLockStatus(FfxInt32x2 p, FfxFloat32x2 value) {
    if (fsr2CurrentParity()) imageStore(fsrLockStatus, fsrPairPixel(ivec2(p),1), vec4(value, 0.0, 0.0));
    else imageStore(fsrLockStatus, fsrPairPixel(ivec2(p),0), vec4(value, 0.0, 0.0));
}
#endif

FfxFloat32x4 SampleLumaHistory(FfxFloat32x2 uv) {
    return fsr2CurrentParity()
        ? textureLod(fsrLumaHistorySampler, fsrPairUv(vec2(uv),0), 0.0)
        : textureLod(fsrLumaHistorySampler, fsrPairUv(vec2(uv),1), 0.0);
}

#if defined(FSR2_PASS_ACCUMULATE)
void StoreLumaHistory(FfxInt32x2 p, FfxFloat32x4 value) {
    if (fsr2CurrentParity()) imageStore(fsrLumaHistory, fsrPairPixel(ivec2(p),1), vec4(value));
    else imageStore(fsrLumaHistory, fsrPairPixel(ivec2(p),0), vec4(value));
}
#endif

FfxFloat32 SampleLanczos2Weight(FfxFloat32 x) {
    float ax = abs(x);
    if (ax < 1e-5) return 1.0;
    if (ax >= 2.0) return 0.0;
    float pix = 3.141592653589793 * x;
    return sin(pix) * sin(0.5 * pix) / (0.5 * pix * pix);
}

FfxFloat32 SampleUpsampleMaximumBias(FfxFloat32x2 uv) {
    // Native-resolution AA only visits the center of the official bias LUT.
    // 1.319 is the SDK table's center/corner minimum and is conservative.
    return 1.319;
}

FfxFloat32x4 LoadRCAS_Input(FfxInt32x2 p) {
    p = FfxInt32x2(fsr2ClampDisplayPixel(ivec2(p)));
    return fsr2CurrentParity()
        ? texelFetch(fsrColorHistorySampler, fsrPairPixel(ivec2(p),1), 0)
        : texelFetch(fsrColorHistorySampler, fsrPairPixel(ivec2(p),0), 0);
}
