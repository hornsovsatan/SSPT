#version 430 compatibility
#define PT_HAS_TRANSLUCENT_UNIFORMS
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex15;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D depthtex0;
uniform sampler2D noisetex;
uniform sampler2D traceBlockAtlas;
uniform sampler2D traceBlockSpecularAtlas;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 shadowLightPosition;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
#ifdef DISTANT_HORIZONS
uniform int dhRenderDistance;
#endif
#ifdef VOXY
uniform int vxRenderDistance;
#endif
uniform int frameCounter;
#define AUTO_EXPOSURE_KEY 0.25
#define AUTO_EXPOSURE_MIN 0.50
#define AUTO_EXPOSURE_MAX 4.00
#define AUTO_EXPOSURE_ADAPT 0.025
#define EXPOSURE_GRID_X 8
#define EXPOSURE_GRID_Y 8
#define AUTO_EXPOSURE_LUMA_MIN 0.035
#define AUTO_EXPOSURE_LUMA_MAX 8.0
#define AUTO_EXPOSURE_SKY_FALLBACK_LUMA AUTO_EXPOSURE_KEY
#define AUTO_EXPOSURE_HIGHLIGHT_KNEE 1.35
/*
const int colortex0Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA32F;
const int colortex5Format = RGBA16F;
const int colortex6Format = RGBA16F;
const int colortex10Format = RGBA32F;
const int colortex11Format = RGBA32F;
const int colortex12Format = RGBA16F;
const int colortex13Format = RGBA16F;
const bool colortex6Clear = false;
const bool colortex10Clear = false;
*/
in vec2 texcoord;
#include "/lib/shadow_common.glsl"
#include "/lib/gi_common.glsl"
/* RENDERTARGETS: 0,6,10 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 exposureData;
layout(location = 2) out vec4 finalHistoryOut;
float luminance(vec3 c) {
    return max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0);
}
// PBR reflections
#define GI_BOUNCES 2 // [1 2 3 4 5]
#define PBR_REFLECTION_NORMAL_BIAS 0.08
#define PBR_REFLECTION_MIN_SMOOTHNESS 0.45
#define PBR_REFLECTION_FULL_SMOOTHNESS 0.90
#define PBR_REFLECTION_ROUGHNESS_START 0.18
#define PBR_REFLECTION_ROUGHNESS_END 0.50
#define PBR_REFLECTION_STRENGTH 1.0
#define PBR_DIELECTRIC_REFLECTION_GAIN 1.0
#define PBR_METAL_REFLECTION_GAIN 1.0
// Visible emission
#define TRIANGLE_VISIBLE_RADIUS 64.0
#define TRIANGLE_VISIBLE_LIGHT_GAIN 1.0
#define TRIANGLE_LIGHT_EPS 0.003
#define TRIANGLE_PRIMARY_HIT_TOLERANCE 0.08
#define TRIANGLE_PRIMARY_RAY_BIAS 0.002
#define TRIANGLE_SURFACE_PROBE_BIAS 0.03
#define TRIANGLE_SURFACE_PROBE_DISTANCE 0.08
#define LABPBR_EMISSION_STRENGTH 1.0
#define SKY_PATH_INTENSITY 1.0
#define PT_SCREEN_COMPOSITE_LIGHTING
#include "/lib/PT.glsl"
#include "/lib/pbr_material.glsl"
float resolveVisibleTriangleEmission(
    vec3 surfacePosGrid,
    vec3 playerPos,
    vec3 surfaceNormal
) {
    float surfaceDistance = length(playerPos);
    if (surfaceDistance > 1e-4 && surfaceDistance < TRIANGLE_VISIBLE_RADIUS) {
        vec3 cameraGrid = fract(cameraPosition);
        vec3 primaryDir = playerPos / surfaceDistance;
        TriHit primaryHit = traceTriangleWorld(
            cameraGrid + primaryDir * TRIANGLE_PRIMARY_RAY_BIAS,
            primaryDir,
            min(
                surfaceDistance + TRIANGLE_PRIMARY_HIT_TOLERANCE,
                TRIANGLE_VISIBLE_RADIUS
            )
        );
        float expectedHitDistance =
            surfaceDistance - TRIANGLE_PRIMARY_RAY_BIAS;
        float hitTolerance = max(
            0.004,
            surfaceDistance * 0.0001
        );
        if (primaryHit.hit &&
            primaryHit.rawEmission > TRIANGLE_LIGHT_EPS &&
            abs(primaryHit.t - expectedHitDistance) <= hitTolerance) {
            return primaryHit.rawEmission;
        }
    }
    vec3 n = normalize(surfaceNormal);
    TriHit frontProbe = traceTriangleWorld(
        surfacePosGrid + n * TRIANGLE_SURFACE_PROBE_BIAS,
        -n,
        TRIANGLE_SURFACE_PROBE_DISTANCE
    );
    // A nearby emitter is not proof that the visible receiver emits light.
    // Accept only the reconstructed surface, not any hit along the probe segment.
    if (frontProbe.hit && frontProbe.rawEmission > TRIANGLE_LIGHT_EPS &&
        abs(frontProbe.t - TRIANGLE_SURFACE_PROBE_BIAS) <= 0.004 &&
        abs(dot(frontProbe.normal, n)) >= 0.9) {
        return frontProbe.rawEmission;
    }
    TriHit backProbe = traceTriangleWorld(
        surfacePosGrid - n * TRIANGLE_SURFACE_PROBE_BIAS,
        n,
        TRIANGLE_SURFACE_PROBE_DISTANCE
    );
    if (backProbe.hit && backProbe.rawEmission > TRIANGLE_LIGHT_EPS &&
        abs(backProbe.t - TRIANGLE_SURFACE_PROBE_BIAS) <= 0.004 &&
        abs(dot(backProbe.normal, n)) >= 0.9) {
        return backProbe.rawEmission;
    }
    return 0.0;
}
uint pbrHash32(uint x) {
    x ^= x >> 16u;
    x *= 0x7feb352du;
    x ^= x >> 15u;
    x *= 0x846ca68bu;
    x ^= x >> 16u;
    return x;
}
vec2 getGGXRandom(vec2 uv, int bounceIndex) {
    uvec2 pixel = uvec2(gl_FragCoord.xy);
    // FSR provides temporal reconstruction in real time; without it keep stable samples.
    uint temporalSeed = (offlineCameraIsStill() || fsr2Enabled())
        ? uint(frameCounter) * 26699u
        : 0u;
    uint seed = pixel.x * 1973u + pixel.y * 9277u + temporalSeed +
        uint(max(bounceIndex, 0)) * 0x9e3779b9u + 0x68bc21ebu;
    uint h0 = pbrHash32(seed);
    uint h1 = pbrHash32(h0 ^ 0x9e3779b9u);
    return clamp(
        vec2(float(h0), float(h1)) * (1.0 / 4294967296.0),
        vec2(1e-6),
        vec2(1.0 - 1e-6)
    );
}
bool sampleGGXReflection(
    vec3 N,
    vec3 V,
    float alpha,
    vec3 F0,
    vec3 eta,
    vec3 k,
    vec3 reflectionTint,
    float hardcodedMetal,
    vec2 xi,
    out vec3 L,
    out vec3 sampleWeight
) {
    float NoV = clamp(dot(N, V), 0.0, 1.0);
    if (NoV <= 1e-5) return false;
    if (alpha <= PBR_GGX_MIN_ALPHA) {
        L = normalize(reflect(-V, N));
        float NoL = clamp(dot(N, L), 0.0, 1.0);
        if (NoL <= 1e-5) return false;
        sampleWeight = fresnelLabPBR(
            NoV, F0, eta, k, reflectionTint, hardcodedMetal
        );
        return true;
    }
    vec3 H = sampleVisibleGGX(xi, N, V, alpha);
    float NoH = clamp(dot(N, H), 0.0, 1.0);
    float VoH = clamp(dot(V, H), 0.0, 1.0);
    if (NoH <= 1e-5 || VoH <= 1e-5) return false;
    L = normalize(reflect(-V, H));
    float NoL = clamp(dot(N, L), 0.0, 1.0);
    if (NoL <= 1e-5) return false;
    vec3 F = fresnelLabPBR(
        VoH, F0, eta, k, reflectionTint, hardcodedMetal
    );
    sampleWeight = F * visibleGGXWeight(NoV, NoL, alpha);
    return true;
}
float getPBRSmoothSurfaceMask(float roughness) {
    float smoothness = 1.0 - sqrt(max(roughness, 0.0));
    float smoothMask = smoothstep(
        PBR_REFLECTION_MIN_SMOOTHNESS,
        PBR_REFLECTION_FULL_SMOOTHNESS,
        smoothness
    );
    float roughMask = 1.0 - smoothstep(
        PBR_REFLECTION_ROUGHNESS_START,
        PBR_REFLECTION_ROUGHNESS_END,
        roughness
    );
    return smoothMask * roughMask;
}
float getPBRReflectionMask(float roughness, LabPBRSpecularData labSpecular) {
    float materialGain = mix(
        PBR_DIELECTRIC_REFLECTION_GAIN,
        PBR_METAL_REFLECTION_GAIN,
        labSpecular.metalness
    );
    return getPBRSmoothSurfaceMask(roughness) * materialGain;
}
float getPBRMetalMirrorMask(
    float roughness,
    LabPBRSpecularData labSpecular
) {
    return labSpecular.metalness * getPBRSmoothSurfaceMask(roughness);
}
vec3 getReflectionHitRadiance(TriHit hit, float localSurfaceWeight) {
    // A specular view of the source keeps its original surface brightness.
    // Area normalization is reserved for diffuse illumination transport.
    vec3 emissionRadiance = hit.color *
        hit.rawEmission * LABPBR_EMISSION_STRENGTH;
    if (hit.screenSpace) {
        vec3 screenLighting = max(
            hit.screenLight,
            vec3(getSceneBaseLight())
        );
        return hit.color * screenLighting * localSurfaceWeight +
            emissionRadiance;
    }
    vec3 lightDirPlayer = normalize(
        mat3(gbufferModelViewInverse) * normalize(shadowLightPosition)
    );
    float NdotL = clamp(dot(hit.normal, lightDirPlayer), 0.0, 1.0);
    vec3 shadowVisibility = getTraceHitSunVisibility(hit);
    vec3 reflectedLighting = vec3(getSceneBaseLight()) + getPointLightIllumination(hit.position,hit.normal);
    if (sceneHasDirectLight()) {
        // Indirect skylight comes from GI, not vanilla lightmap levels: doors
        // can block traced light without blocking vanilla skylight propagation.
        reflectedLighting += getSceneDirectLight() * shadowVisibility * NdotL;
    }
    return hit.color * reflectedLighting * localSurfaceWeight +
        emissionRadiance;
}
vec3 getReflectionMissRadiance(vec3 rayDirection) {
    if (!sceneHasSkyLight()) return vec3(0.0);
    vec3 horizonRadiance = srgbToLinear(fogColor);
    float skyBlend = smoothstep(-0.15, 0.35, rayDirection.y);
    return mix(horizonRadiance, getSkyPathRadiance(), skyBlend);
}
bool getTranslucentSurfaceData(
    vec2 uv,
    out vec4 surfaceData,
    out vec4 normalData,
    out vec4 colorData
) {
    surfaceData = texture(colortex11, uv);
    normalData = texture(colortex12, uv);
    colorData = texture(colortex13, uv);
    return normalData.a > 0.5 &&
        surfaceData.r > 0.0 && surfaceData.r < 1.0;
}
vec3 getPBRTriangleReflection(vec2 uv) {
#ifndef MC_SPECULAR_MAP
    return vec3(0.0);
#else
    vec4 translucentSurface;
    vec4 translucentNormal;
    vec4 translucentColor;
    bool hasTranslucentSurface = getTranslucentSurfaceData(
        uv,
        translucentSurface,
        translucentNormal,
        translucentColor
    );
    float rawDepth = hasTranslucentSurface
        ? translucentSurface.r
        : texture(depthtex0, uv).r;
    if (rawDepth >= 1.0) return vec3(0.0);
    vec4 material = hasTranslucentSurface
        ? vec4(
            translucentColor.a,
            translucentSurface.b,
            translucentSurface.a,
            0.0
        )
        : texture(colortex3, uv);
    vec4 normalData = hasTranslucentSurface
        ? translucentNormal
        : texture(colortex1, uv);
    vec3 baseColor = hasTranslucentSurface
        ? translucentColor.rgb
        : texture(colortex0, uv).rgb;
    float roughness = clamp(material.g, 0.0, 1.0);
    LabPBRSpecularData labSpecular = decodeLabPBRSpecular(material.b, baseColor);
    float reflectionMask = getPBRReflectionMask(roughness, labSpecular);
    if (reflectionMask <= 1e-4) return vec3(0.0);
    vec3 viewPos = getViewPos(uv, rawDepth);
    vec3 normalView = normalize(normalData.rgb * 2.0 - 1.0);
    vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 playerNormal = normalize(mat3(gbufferModelViewInverse) * normalView);
    vec3 viewRayPlayer = normalize(playerPos);
    vec3 V = normalize(-viewRayPlayer);
    vec3 F0 = labSpecular.F0;
    vec3 reflectDirPlayer;
    vec3 ggxWeight;
    if (!sampleGGXReflection(
        playerNormal,
        V,
        max(roughness, PBR_GGX_MIN_ALPHA),
        F0,
        labSpecular.eta,
        labSpecular.k,
        labSpecular.reflectionTint,
        labSpecular.hardcodedMetal,
        getGGXRandom(uv, 0),
        reflectDirPlayer,
        ggxWeight
    )) return vec3(0.0);
    vec3 originGrid = playerPos + fract(cameraPosition) +
        (ptPureMirror(roughness, labSpecular) ? reflectDirPlayer * 0.002 : playerNormal * PBR_REFLECTION_NORMAL_BIAS);
    vec3 rayDirection = reflectDirPlayer;
    vec3 throughput = ggxWeight * reflectionMask * PBR_REFLECTION_STRENGTH;
    vec3 reflectionResult = vec3(0.0);
    bool psrEligible = !hasTranslucentSurface && ptPureMirror(roughness, labSpecular);
    vec3 psrGI = vec3(0.0);
    if (psrEligible) psrGI = giReconstructFiltered(uv);
    bool psrCandidate = psrEligible && ptReconstructionValid;
    int psrClass = ptReconstructionClass;
    vec3 psrPosition = ptReconstructionPosition;
    vec3 psrNormal = ptReconstructionNormal;
    bool mirrorChain = ptPureMirror(roughness, labSpecular);
    mat3 unfold = mat3(1.0) - 2.0 * outerProduct(playerNormal, playerNormal);
    float pathLength = length(playerPos);
    vec3 previousSurface = playerPos + fract(cameraPosition);
    for (int bounce = 0; bounce < GI_BOUNCES; bounce++) {
        if (luminance(throughput) <= 1e-4) break;
        TriHit hit = traceHybridWorld(originGrid, rayDirection);
        throughput *= hit.transmittance;
        if (!hit.hit) {
            reflectionResult += throughput *
                getReflectionMissRadiance(rayDirection);
            break;
        }
        LabPBRSpecularData hitSpecular = decodeLabPBRSpecular(
            hit.materialValue,
            hit.color
        );
        float hitMetalMirrorMask = getPBRMetalMirrorMask(
            hit.roughness,
            hitSpecular
        );
        pathLength += max(dot(hit.position - previousSurface, rayDirection), 0.0);
        previousSurface = hit.position;
        float virtualZ = (gbufferModelView * vec4(viewRayPlayer * pathLength, 1.0)).z;
        vec3 virtualNormal = normalize(mat3(gbufferModelView) * unfold * hit.normal);
        bool usePsr = psrCandidate && mirrorChain && ptMatchesReplacement(
            psrClass, bounce + 1, psrPosition, psrNormal, virtualZ, virtualNormal);
        if (usePsr) {
            // Replace only the matched hit's indirect term. All other hits retain
            // their original lighting, including later rough/specular bounces.
            if (hit.screenSpace) hit.screenLight = max(hit.screenLight - hit.screenIndirect, vec3(0.0));
            reflectionResult += psrGI;
            psrCandidate = false;
        }
        reflectionResult += throughput * getReflectionHitRadiance(
            hit,
            1.0 - hitMetalMirrorMask
        );
        if (bounce + 1 >= GI_BOUNCES) break;
        float hitReflectionMask = getPBRReflectionMask(
            hit.roughness,
            hitSpecular
        );
        if (hitReflectionMask <= 1e-4) break;
        vec3 nextDirection;
        vec3 nextWeight;
        if (!sampleGGXReflection(
            hit.normal,
            normalize(-rayDirection),
            max(hit.roughness, PBR_GGX_MIN_ALPHA),
            hitSpecular.F0,
            hitSpecular.eta,
            hitSpecular.k,
            hitSpecular.reflectionTint,
            hitSpecular.hardcodedMetal,
            getGGXRandom(uv, bounce + 1),
            nextDirection,
            nextWeight
        )) break;
        mirrorChain = mirrorChain && ptPureMirror(hit.roughness, hitSpecular);
        if (mirrorChain) unfold *= mat3(1.0) - 2.0 * outerProduct(hit.normal, hit.normal);
        throughput *= nextWeight * hitReflectionMask;
        originGrid = hit.position + (ptPureMirror(hit.roughness, hitSpecular)
            ? nextDirection * 0.002 : hit.normal * PBR_REFLECTION_NORMAL_BIAS);
        rayDirection = nextDirection;
    }
    return reflectionResult;
#endif
}
vec3 composeScene(vec2 uv, vec2 surfaceUv) {
    vec3 albedo = texture(colortex0, surfaceUv).rgb;
    if (texture(depthtex0, surfaceUv).r == 1.0) {
        return albedo;
    }
    vec3 gi = giReconstructFiltered(surfaceUv);
    // PSR GI is added only by a matching full-resolution reflection hit.
    if (ptReconstructionClass > 0) gi = vec3(0.0);
    return gi +
        albedo * max(texture(colortex5, fsr2RenderStorageUv(uv)).rgb, vec3(0.0));
}
float getAverageLuma() {
    float logSum = 0.0;
    float count = 0.0;
    for (int x = 0; x < EXPOSURE_GRID_X; x++) {
        for (int y = 0; y < EXPOSURE_GRID_Y; y++) {
            vec2 uv = (vec2(float(x), float(y)) + vec2(0.5)) /
                      vec2(float(EXPOSURE_GRID_X), float(EXPOSURE_GRID_Y));
            float depth = texture(depthtex0, uv).r;
            if (depth < 1.0) {
                // Exposure is a coarse global statistic; do not repeat the
                // geometry-aware GI reconstruction for every exposure tap.
                vec3 sampleLight = textureLod(colortex8, giRenderStorageUv(uv), 0.0).rgb +
                    diFilteredLight(clamp(ivec2(giRenderStorageUv(uv)*vec2(textureSize(colortex8,0))),ivec2(0),giRenderSizePixels()-1)) +
                    texture(colortex5, fsr2RenderStorageUv(uv)).rgb;
                float l = clamp(luminance(texture(colortex0, uv).rgb * max(sampleLight, vec3(0.0))),
                    AUTO_EXPOSURE_LUMA_MIN, AUTO_EXPOSURE_LUMA_MAX);
                logSum += log(l);
                count += 1.0;
            }
        }
    }
    if (count < 1.0) {
        return AUTO_EXPOSURE_SKY_FALLBACK_LUMA;
    }
    return exp(logSum / count);
}
float getAutoExposure(float avgLuma) {
    float targetExposure = clamp(
        AUTO_EXPOSURE_KEY / max(avgLuma, AUTO_EXPOSURE_LUMA_MIN),
        AUTO_EXPOSURE_MIN,
        AUTO_EXPOSURE_MAX
    );
    float oldExposure = texture(
        colortex6,
        vec2(0.5) * fsr2RenderFraction()
    ).r;
    if (oldExposure < AUTO_EXPOSURE_MIN || oldExposure > AUTO_EXPOSURE_MAX || oldExposure != oldExposure) {
        oldExposure = targetExposure;
    }
    float adapt = targetExposure < oldExposure ? AUTO_EXPOSURE_ADAPT * 1.45 : AUTO_EXPOSURE_ADAPT * 0.75;
    return mix(oldExposure, targetExposure, adapt);
}
void main() {
    ivec2 surfacePixel = fsr2GbufferPixelFromRenderPixel(ivec2(gl_FragCoord.xy), textureSize(depthtex0, 0));
    vec2 surfaceUv = (vec2(surfacePixel) + 0.5) / vec2(textureSize(depthtex0, 0));
    float opaqueRawDepth = texture(depthtex0, surfaceUv).r;
    vec4 translucentSurface;
    vec4 translucentNormal;
    vec4 translucentColor;
    bool hasTranslucentSurface = getTranslucentSurfaceData(
        surfaceUv,
        translucentSurface,
        translucentNormal,
        translucentColor
    );
    float rawDepth = hasTranslucentSurface
        ? translucentSurface.r
        : opaqueRawDepth;
    bool isSky = opaqueRawDepth == 1.0 && !hasTranslucentSurface;
    vec3 sceneColor = composeScene(texcoord, surfaceUv);
    if (!isSky) {
        vec3 viewPos = getViewPos(surfaceUv, rawDepth);
        // Surface matching needs the raster geometric normal, not a normal-map perturbation.
        vec3 normalView = giGeometricNormal(surfacePixel);
        vec3 playerPos = (
            gbufferModelViewInverse * vec4(viewPos, 1.0)
        ).xyz;
        vec3 playerNormal = normalize(
            mat3(gbufferModelViewInverse) * normalView
        );
        vec3 surfacePosGrid = playerPos + fract(cameraPosition);
        float visibleEmission = resolveVisibleTriangleEmission(
            surfacePosGrid,
            playerPos,
            playerNormal
        );
        vec3 surfaceBaseColor = hasTranslucentSurface
            ? translucentColor.rgb
            : texture(colortex0, surfaceUv).rgb;
        ivec3 surfaceVoxel = traceVoxelHalf + ivec3(floor(surfacePosGrid));
        if (!traceVoxelInside(surfaceVoxel)) {
            float surfaceSeed = hasTranslucentSurface
                ? clamp(translucentNormal.a - 1.0, 0.0, 1.0)
                : clamp(texture(colortex3, surfaceUv).a, 0.0, 1.0);
            float surfacePbrEmission = hasTranslucentSurface
                ? translucentColor.a
                : texture(colortex3, surfaceUv).r;
            // Replace missing mesh emission outside the volume.
            visibleEmission = clamp(surfaceSeed + surfacePbrEmission, 0.0, 1.0);
        }
        vec3 visibleEmissionLight = vec3(visibleEmission * TRIANGLE_VISIBLE_LIGHT_GAIN);
        sceneColor += surfaceBaseColor * visibleEmissionLight;
        vec4 material = hasTranslucentSurface
            ? vec4(
                translucentColor.a,
                translucentSurface.b,
                translucentSurface.a,
                0.0
            )
            : texture(colortex3, surfaceUv);
        float roughness = clamp(material.g, 0.0, 1.0);
        LabPBRSpecularData labSpecular = decodeLabPBRSpecular(
            material.b,
            surfaceBaseColor
        );
        float metalMirrorMask = getPBRMetalMirrorMask(
            roughness,
            labSpecular
        );
        float surfaceOpacity = hasTranslucentSurface
            ? clamp(translucentSurface.g, 0.0, 1.0)
            : 1.0;
        sceneColor *= 1.0 - metalMirrorMask * surfaceOpacity;
        sceneColor += getPBRTriangleReflection(surfaceUv);
    }
    bool offlineStill = offlineCameraIsStill();
    if (offlineStill) {
        ivec2 historySize = textureSize(colortex10, 0);
        ivec2 historyTexel = clamp(
            ivec2(gl_FragCoord.xy),
            ivec2(0),
            historySize - ivec2(1)
        );
        vec4 previousFinal = texelFetch(colortex10, historyTexel, 0);
        float previousCount = -previousFinal.a;
        bool historyValid = !sceneLightHistoryChanged() && previousFinal.a <= -1.0 &&
            previousCount < 3.4e38 &&
            all(equal(previousFinal.rgb, previousFinal.rgb));
        float acceptedCount = historyValid ? previousCount + 1.0 : 1.0;
        if (historyValid) {
            sceneColor = (
                previousFinal.rgb * previousCount + sceneColor
            ) / acceptedCount;
        }
        // A negative count marks a history created while the camera was still.
        // A positive value written below forces a reset on the first still frame.
        finalHistoryOut = vec4(sceneColor, -acceptedCount);
    } else {
        finalHistoryOut = vec4(sceneColor, 1.0);
    }
    float avgLuma = getAverageLuma();
    float exposure = getAutoExposure(avgLuma);
    vec3 reconstructionColor = sceneColor;
    if (isSky) {
        // Pre-compensate sky for final exposure before temporal reconstruction.
        reconstructionColor /= max(exposure, 1e-4);
    }
    {
        // Both FSR and native output blend fog in linear HDR before tone mapping.
        ivec2 fogPixel = clamp(
            ivec2(gl_FragCoord.xy), ivec2(0), fsr2RenderSizePixels() - 1
        );
        float fogAmount = clamp(texelFetch(colortex2, fogPixel, 0).r, 0.0, 1.0);
        vec3 reconstructionFog = srgbToLinear(fogColor) / max(exposure, 1e-4);
        reconstructionColor = mix(reconstructionColor, reconstructionFog, fogAmount);
    }
    // Linear HDR, including fog, is shared by FSR and native output.
    // composite12 performs tone mapping and the only display encoding.
    color = vec4(max(reconstructionColor, vec3(0.0)), 1.0);
    exposureData = vec4(
        exposure,
        avgLuma,
        clamp(AUTO_EXPOSURE_KEY / max(avgLuma, AUTO_EXPOSURE_LUMA_MIN), AUTO_EXPOSURE_MIN, AUTO_EXPOSURE_MAX),
        1.0
    );
}
