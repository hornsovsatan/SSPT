#version 430 compatibility
uniform sampler2D shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D colortex5;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;
uniform sampler2D noisetex;
uniform sampler2D traceBlockAtlas;
uniform sampler2D traceBlockSpecularAtlas;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform vec3 skyColor;
uniform float far;
#ifdef DISTANT_HORIZONS
uniform int dhRenderDistance;
#endif
#ifdef VOXY
uniform int vxRenderDistance;
#endif
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
in vec2 texcoord;
#include "/lib/shadow_common.glsl"
#include "fsr2/ffx_fsr2_config.glsl"
/* RENDERTARGETS: 2,5 */
layout(location = 0) out vec4 o;
layout(location = 1) out vec4 ambient;
// Shared PT / PCSS lighting
#define SKY_PATH_INTENSITY 1.0
#define PT_SHADOW_ONLY
#include "/lib/PT.glsl"
// Fog
#define FOG_START_FRACTION 0.52
#define FOG_END_FRACTION 0.985
#define FOG_EXTENDED_START_FRACTION 0.90
#define FOG_EXTENDED_END_FRACTION 0.997
#define FOG_CURVE 1.35
#define FOG_HORIZON_BOOST 0.10
#define FOG_DITHER_STRENGTH 0.0015
float getScreenNoise(vec2 uv) {
    ivec2 screenCoord = ivec2(uv * vec2(viewWidth, viewHeight));
    ivec2 noiseCoord = screenCoord % 64;
    return texelFetch(noisetex, noiseCoord, 0).r;
}
float getFogAmount(vec3 viewPos) {
    float safeFar = max(far, 1.0);
#ifdef DISTANT_HORIZONS
    safeFar = max(safeFar, float(dhRenderDistance) * 16.0);
#endif
#ifdef VOXY
    // Voxy exposes vxRenderDistance directly in blocks.
    safeFar = max(safeFar, float(vxRenderDistance));
#endif
    float distanceToCamera = length(viewPos);
    float fogStartFraction = FOG_START_FRACTION;
    float fogEndFraction = FOG_END_FRACTION;
#if defined(DISTANT_HORIZONS) || defined(VOXY)
    fogStartFraction = FOG_EXTENDED_START_FRACTION;
    fogEndFraction = FOG_EXTENDED_END_FRACTION;
#endif
    float fogStart = safeFar * fogStartFraction;
    float fogEnd = max(safeFar * fogEndFraction, fogStart + 1.0);
    float fogAmount = smoothstep(fogStart, fogEnd, distanceToCamera);
    fogAmount = pow(fogAmount, FOG_CURVE);
    vec3 viewDir = viewPos / max(distanceToCamera, 1e-4);
    float horizon = pow(clamp(1.0 - abs(viewDir.y), 0.0, 1.0), 4.0);
    fogAmount = 1.0 - pow(max(1.0 - fogAmount, 0.0), 1.0 + horizon * FOG_HORIZON_BOOST);
    fogAmount += (
        getScreenNoise(fsr2UnjitterUv(texcoord)) - 0.5
    ) * FOG_DITHER_STRENGTH;
    return clamp(fogAmount, 0.0, 1.0);
}
void main() {
    ivec2 receiverPixel = fsr2GbufferPixelFromRenderPixel(
        ivec2(gl_FragCoord.xy), textureSize(depthtex0, 0));
    vec2 receiverUv = (vec2(receiverPixel) + 0.5) / vec2(textureSize(depthtex0, 0));
    float depth = texelFetch(depthtex0, receiverPixel, 0).r;
    vec3 viewPos = getViewPos(receiverUv, depth);
    // Evaluate geometric derivatives before any divergent return.
    vec3 positionDx = dFdx(viewPos);
    vec3 positionDy = dFdy(viewPos);
    vec3 planeNormal = cross(positionDx, positionDy);
    float planeLengthSquared = dot(planeNormal, planeNormal);
    bool validPlane = planeLengthSquared > 1e-16;
    vec3 viewNormal = validPlane
        ? planeNormal * inversesqrt(planeLengthSquared) : vec3(0.0, 0.0, 1.0);
    if (dot(viewNormal, -viewPos) < 0.0) viewNormal = -viewNormal;
    // Depth quantization makes derivative normals alternate across flat faces.
    // Use the raster geometric normal for point-light cosine and ray offset.
    vec4 geometricData = texelFetch(colortex15, receiverPixel, 0);
    vec3 pointNormalView = geometricData.a > 0.5
        ? normalize(geometricData.rgb * 2.0 - 1.0) : viewNormal;
    if (dot(pointNormalView, -viewPos) < 0.0) pointNormalView = -pointNormalView;
    // Reject receiver planes spanning cutout edges or silhouettes.
    float pixelFootprint = 2.0 * abs(viewPos.z) * max(
        abs(gbufferProjectionInverse[0][0]) / max(viewWidth, 1.0),
        abs(gbufferProjectionInverse[1][1]) / max(viewHeight, 1.0));
    bool reliableReceiverPlane = validPlane &&
        max(length(positionDx), length(positionDy)) < max(0.08, pixelFootprint * 8.0);
    o = vec4(0.0, 0.0, 0.0, 1.0);
    if (depth == 1.0) {
        ambient = texture(colortex5, texcoord);
        return;
    }
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    o.r = getFogAmount(viewPos);
    vec3 shadow = vec3(1.0);
    if (sceneHasDirectLight()) {
        vec3 normalGrid = normalize(mat3(gbufferModelViewInverse) * viewNormal);
        vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
        vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
        shadow = getPCSSShadow(shadowClipPos,
            reliableReceiverPlane ? normalGrid : vec3(0.0), true);
        if (max(shadow.r, max(shadow.g, shadow.b)) > 0.0)
            shadow *= getCloudSunVisibility(feetPlayerPos);
    }
    vec4 lightData = texelFetch(colortex5, receiverPixel, 0);
    vec3 directLight = lightData.rgb * shadow;
    vec3 pointNormalGrid = normalize(mat3(gbufferModelViewInverse) * pointNormalView);
    // Bound the receiver's depth rounding error along its normal. The fixed
    // trace offset alone is insufficient for distant rasterized surfaces.
    vec3 adjacentDepthPos = getViewPos(receiverUv, min(depth + exp2(-23.0), 1.0));
    float receiverError = abs(dot(adjacentDepthPos - viewPos, pointNormalView));
    vec3 pointLight = getPointLightIllumination(
        feetPlayerPos + fract(cameraPosition) + pointNormalGrid * receiverError,
        pointNormalGrid);
    ambient = vec4(max(directLight, getSceneBaseLight()) + pointLight, lightData.a);
}
