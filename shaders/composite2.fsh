#version 430 compatibility
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex15;
uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
#define PT_HAS_TRANSLUCENT_UNIFORMS
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
uniform vec3 skyColor;
in vec2 texcoord;
#include "/lib/shadow_common.glsl"
#include "/lib/gi_common.glsl"
/*
const int colortex8Format = RGBA32F;
const float ambientOcclusionLevel = 0.0;
*/
/* RENDERTARGETS: 8 */
layout(location = 0) out vec4 currentGIOut;
#define GI_SAMPLES 1              // [0 1 2 4 6 8]
#define GI_BOUNCES 2              // [1 2 3 4 5]
#define TRIANGLE_GI_INTENSITY 1.0
#define TRIANGLE_GI_NORMAL_BIAS 0.02
#define TRIANGLE_LIGHT_EPS 0.003
#define TRIANGLE_LIGHT_GAIN 1.0
#define LABPBR_EMISSION_STRENGTH 1.0
#define SKY_PATH_INTENSITY 1.0
#include "/lib/PT.glsl"
#include "/lib/pbr_material.glsl"
#include "/lib/gi_geometry.glsl"
#include "/lib/di_sampling.glsl"
#define DI_FILTER_WRITE
#include "/lib/di_filter.glsl"
layout(rgba32f) uniform writeonly image2D ptSurface;
vec3 getTriangleHitRadiance(
    TriHit hit,
    vec3 rayDir,
    vec3 skyLightLevel
) {
    if (!hit.hit) {
        bool isSky = max(skyLightLevel.r,max(skyLightLevel.g,skyLightLevel.b)) > TRIANGLE_LIGHT_EPS;
        if (sceneHasSkyLight() && rayDir.y > 0.0 && isSky) {
            vec3 sky = getSkyPathRadiance();
            float Y = dot(
                sky,
                vec3(0.2126, 0.7152, 0.0722)
            );
            const float SKY_GI_CHROMA = 0.50;
            sky = mix(vec3(Y), sky, SKY_GI_CHROMA);
            return hit.transmittance * sky;
        }
        return vec3(0.0);
    }
    vec3 emissionRadiance = hit.color * hit.emission * LABPBR_EMISSION_STRENGTH;
    vec3 lightDirPlayer = normalize(
        mat3(gbufferModelViewInverse) * shadowLightPosition
    );
    float NdotL = max(dot(hit.normal, lightDirPlayer), 0.0);
#ifdef MC_SPECULAR_MAP
    vec3 V = -rayDir;
    float NdotV = max(dot(hit.normal, V), 0.0);
    vec2 sunWeights = pbrSunReflectionWeights(hit.normal, rayDir, lightDirPlayer,
                                      hit.roughness, hit.materialValue);
    vec3 diffuseWeight = hit.color * sunWeights.x;
    vec3 specularResponse = hit.color * NdotL * sunWeights.y;
    vec3 sunlight = vec3(0.0);
    if (sceneHasDirectLight() && NdotL > 0.0 && NdotV > 0.0) {
        sunlight = getSceneDirectLight() * getTraceHitSunVisibility(hit);
    }
    vec3 reflectedLight;
    if (hit.screenSpace) {
        // Screen light already contains shaded diffuse illumination. Do not
        // add another Lambert sun term. Scale the existing illumination by
        // the approximation's baseline and add only the directional sun term.
        vec3 screenDiffuseWeight = diffuseWeight;
        reflectedLight = screenDiffuseWeight * hit.screenLight + sunlight * specularResponse;
    } else {
        reflectedLight = sunlight * (diffuseWeight * NdotL + specularResponse);
        reflectedLight += hit.color * (1.0-decodeLabPBRSpecular(hit.materialValue,hit.color).metalness)
            * getPointLightIllumination(hit.position,hit.normal);
    }
    return hit.transmittance * (emissionRadiance + reflectedLight);
#else
    if (hit.screenSpace) {
        // SSPT replaces the voxel result only after the ray is outside the
        // voxelized region. This is one path contribution, not an extra layer.
        vec3 screenRadiance = hit.color * (
            hit.screenLight + vec3(hit.emission * LABPBR_EMISSION_STRENGTH)
        );
        screenRadiance *= hit.transmittance;
        return luminance3(screenRadiance) > TRIANGLE_LIGHT_EPS
            ? screenRadiance
            : vec3(0.0);
    }
    vec3 skyRadiance = hit.color * getSceneDirectLight()
        * getTraceHitSunVisibility(hit) * NdotL;
    vec3 triRadiance = hit.transmittance * (emissionRadiance + skyRadiance +
        hit.color * getPointLightIllumination(hit.position,hit.normal));

    return triRadiance;
#endif
}
void main() {
    ivec2 p = ivec2(gl_FragCoord.xy);
    diFilterStore(p,0,vec4(0.0));
    diWrite(p,0,vec4(0.0));
    diWrite(p,1,vec4(0.0));
    diWrite(p,2,vec4(0.0));
    bool storeGuide = ptSurfaceEnabled();
    ivec2 receiverPixel = giReceiverPixel(ivec2(gl_FragCoord.xy));
    vec2 receiverUv = (vec2(receiverPixel) + 0.5) / vec2(textureSize(depthtex0, 0));
    float rawDepth = texelFetch(depthtex0, receiverPixel, 0).r;
    if (rawDepth >= 1.0) {
        currentGIOut = vec4(0.0);
        if (storeGuide) {
            imageStore(ptSurface, ptSurfaceAddress(p, 0), vec4(0.0));
            imageStore(ptSurface, ptSurfaceAddress(p, 1), vec4(1.0));
        }
        return;
    }
    vec3 fragPos = getViewPos(receiverUv, rawDepth);
    vec4 normalData = texelFetch(colortex1, receiverPixel, 0);
    vec3 normalView = normalize(normalData.rgb * 2.0 - 1.0);
    vec3 playerPos = (gbufferModelViewInverse * vec4(fragPos, 1.0)).xyz;
    vec3 playerNormal = normalize(mat3(gbufferModelViewInverse) * normalView);
    vec3 originGrid = playerPos + fract(cameraPosition);
    float primarySkyVisibility = clamp(
        texture(colortex5, fsr2RenderStorageUv(receiverUv)).a,
        0.0,
        1.0
    );
    vec3 skyLightLevel = vec3(primarySkyVisibility);
    vec3 geoNormal = normalize(mat3(gbufferModelViewInverse) * giGeometricNormal(receiverPixel));
    vec4 guide = vec4(giPackNormal(geoNormal), giPackNormal(playerNormal),
        giPackRasterOffset(receiverPixel, p), fragPos.z);
    vec3 factor = texelFetch(colortex0, receiverPixel, 0).rgb;
    vec4 md = texelFetch(colortex3, receiverPixel, 0);
    LabPBRSpecularData surfaceMaterial = decodeLabPBRSpecular(md.b, factor);
    vec3 primaryRay = normalize(playerPos);
    vec3 rayDirection = primaryRay;
    vec3 mirrorWeight = vec3(1.0);
    mat3 unfold = mat3(1.0);
    float pathLength = length(playerPos);
    int mirrorCount = 0;
    bool terminalValid = true;
    bool translucent = texelFetch(colortex12, receiverPixel, 0).a > 0.5;
    bool replacing = storeGuide && !translucent && dot(geoNormal, playerNormal) > 0.9999
        && ptPureMirror(md.g, surfaceMaterial);
    // Replace only a deterministic mirror chain. The independent composite5
    // reflection pass owns direct lighting, emission and environment radiance.
    for (int mirror = 0; mirror < GI_BOUNCES; ++mirror) {
        if (!replacing) break;
        mirrorWeight *= fresnelLabPBR(max(dot(playerNormal, -rayDirection), 0.0),
            surfaceMaterial.F0, surfaceMaterial.eta, surfaceMaterial.k,
            surfaceMaterial.reflectionTint, surfaceMaterial.hardcodedMetal);
        unfold *= mat3(1.0) - 2.0 * outerProduct(playerNormal, playerNormal);
        rayDirection = normalize(reflect(rayDirection, playerNormal));
        TriHit hit = traceHybridWorld(originGrid + rayDirection * 0.002, rayDirection);
        mirrorWeight *= hit.transmittance;
        ++mirrorCount;
        if (!hit.hit) {
            terminalValid = false;
            guide.b = giPackRasterOffset(receiverPixel, p) + float(16 + mirrorCount) * 1024.0;
            break;
        }
        pathLength += max(dot(hit.position - originGrid, rayDirection), 0.0);
        originGrid = hit.position;
        playerNormal = hit.normal;
        skyLightLevel = vec3(clamp(hit.skyAccess, 0.0, 1.0));
        surfaceMaterial = decodeLabPBRSpecular(hit.materialValue, hit.color);
        vec3 virtualNormal = normalize(unfold * hit.normal);
        float virtualZ = (gbufferModelView * vec4(primaryRay * pathLength, 1.0)).z;
        guide = vec4(giPackNormal(virtualNormal), giPackNormal(virtualNormal),
            giPackRasterOffset(receiverPixel, p) + float(mirrorCount) * 1024.0, virtualZ);
        factor = mirrorWeight * hit.color * (1.0 - surfaceMaterial.metalness);
        replacing = ptPureMirror(hit.roughness, surfaceMaterial) && hit.emission <= 0.0;
        terminalValid = !replacing;
    }
    bool psrHasGI = mirrorCount > 0 && terminalValid && mirrorCount < GI_BOUNCES && GI_SAMPLES > 0;
    if (storeGuide) {
        imageStore(ptSurface, ptSurfaceAddress(p, 0), guide);
        imageStore(ptSurface, ptSurfaceAddress(p, 1), vec4(factor, psrHasGI ? 1.0 : 0.0));
    }
    vec3 giSum = vec3(0.0);
    vec3 primaryDI = vec3(0.0);
    vec3 directSum = vec3(0.0);
    int giSampleCount = offlineCameraIsStill() ? OFFLINE_MODE : GI_SAMPLES;
    for (int i = 0; i < GI_MAX_SAMPLES; i++) {
        if (i >= giSampleCount || !terminalValid) break;
        // Filter incident diffuse lighting; composeScene applies receiver albedo.
        vec3 throughput = vec3(1.0);
        vec3 bounceOriginGrid = originGrid;
        vec3 bounceNormalPlayer = playerNormal;
        vec3 bounceSkyLightLevel = skyLightLevel;
        vec3 bounceBaseColor = vec3(1.0);
        float bounceNdotV = 1.0;
        LabPBRSpecularData bounceMaterial = decodeLabPBRSpecular(0.0, vec3(1.0));
        for (int bounce = 0; bounce < GI_BOUNCES; bounce++) {
            if (bounce + mirrorCount >= GI_BOUNCES) break;
#if DI_QUALITY > 0
            vec3 nee;
            if (bounce == 0 && mirrorCount == 0) {
                if (i == 0 || offlineCameraIsStill()) primaryDI = diEstimate(bounceOriginGrid,bounceNormalPlayer,
                    bounceBaseColor,bounceMaterial,bounceNdotV,false,10000u+uint(i)*512u,!offlineCameraIsStill());
                if (i > 0 && !offlineCameraIsStill() && diActive(bounceOriginGrid + bounceNormalPlayer * TRIANGLE_GI_NORMAL_BIAS))
                    diPrepareProposal(bounceOriginGrid + bounceNormalPlayer * TRIANGLE_GI_NORMAL_BIAS,true,false);
                nee = primaryDI;
            } else {
                nee = diEstimate(bounceOriginGrid,bounceNormalPlayer,bounceBaseColor,
                    bounceMaterial,bounceNdotV,bounce>0,20000u+uint(i*GI_BOUNCES+bounce)*512u,false);
            }
            if (bounce==0 && mirrorCount==0) directSum+=throughput*nee*TRIANGLE_LIGHT_GAIN;
            else giSum += throughput * nee * TRIANGLE_LIGHT_GAIN;
#endif
            vec2 lightNoise = sampleNoisePair(i + bounce * giSampleCount * 2);
            vec3 lightDirPlayer = sampleCosineHemisphereDirection(lightNoise, bounceNormalPlayer);
            if (dot(lightDirPlayer, bounceNormalPlayer) <= 1e-4) break;
#ifdef MC_SPECULAR_MAP
            if (bounce > 0) {
                throughput *= pbrDiffuseWeight(bounceBaseColor, bounceMaterial,
                    bounceNdotV, dot(bounceNormalPlayer, lightDirPlayer));
                if (luminance3(throughput) < 0.01) break;
            }
#endif
            // One scene query supplies both this bounce's lighting and the
            // surface from which the next bounce starts.
            TriHit hit = traceHybridWorld(
                bounceOriginGrid + bounceNormalPlayer * TRIANGLE_GI_NORMAL_BIAS,
                lightDirPlayer
            );
            LabPBRSpecularData hitMaterial = decodeLabPBRSpecular(hit.materialValue, hit.color);
#if DI_QUALITY > 0
            float emissionWeight = diBSDFWeight(hit,
                bounceOriginGrid + bounceNormalPlayer * TRIANGLE_GI_NORMAL_BIAS,
                bounceNormalPlayer, lightDirPlayer);
            // Only emission competes with mesh NEE. Sun/point/sky retain their estimators.
            hit.emission *= emissionWeight;
#endif
            vec3 triRadiance = getTriangleHitRadiance(hit, lightDirPlayer, bounceSkyLightLevel);
#if DI_QUALITY > 0
            if (bounce==0 && mirrorCount==0 && hit.hit) {
                vec3 emitterHit=hit.transmittance*hit.color*hit.emission*LABPBR_EMISSION_STRENGTH;
                directSum+=throughput*emitterHit*TRIANGLE_LIGHT_GAIN;
                triRadiance=max(triRadiance-emitterHit,vec3(0.0));
            }
#endif
            if (luminance3(triRadiance) > 0.0) {
                giSum += throughput * triRadiance * TRIANGLE_LIGHT_GAIN;
            }
            if (!hit.hit || bounce + 1 >= GI_BOUNCES) break;
#ifdef MC_SPECULAR_MAP
            // Only the diffuse lobe continues in this stage. The GGX sun term
            // was evaluated above; do not trace a fictitious diffuse metal bounce.
            if (hitMaterial.metalness >= 1.0) break;
            throughput *= hit.transmittance;
            bounceMaterial = hitMaterial;
            bounceBaseColor = hit.color;
            bounceNdotV = max(dot(hit.normal, -lightDirPlayer), 0.0);
#else
            throughput *= hit.transmittance * clamp(hit.color, vec3(0.0), vec3(1.0));
#endif
            // Keep tracing through dark, reflective surfaces; only the
            // remaining path weight determines this low-energy termination.
            if (luminance3(throughput) < 0.01) break;
            bounceOriginGrid = hit.position;
            bounceNormalPlayer = hit.normal;
            bounceSkyLightLevel = vec3(clamp(hit.skyAccess, 0.0, 1.0));
        }
    }
    vec3 addLight = vec3(0.0);
    if (giSampleCount > 0) addLight = giSum / float(giSampleCount);
    addLight *= TRIANGLE_GI_INTENSITY * (mirrorCount > 0 ? 1.0 : normalData.a);
    addLight = max(addLight, vec3(0.0));
    vec3 directLight=giSampleCount>0 ? directSum/float(giSampleCount) : vec3(0.0);
    directLight*=TRIANGLE_GI_INTENSITY*normalData.a;
    diFilterStore(p,0,vec4(giFiniteLight(directLight),0.0));
    currentGIOut = vec4(addLight, 1.0);
}
