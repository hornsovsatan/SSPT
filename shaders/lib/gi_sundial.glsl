#ifndef LIGHT_AND_SHADOW_GI_SUNDIAL_GLSL
#define LIGHT_AND_SHADOW_GI_SUNDIAL_GLSL
// Adapted from Sundial Alpha Build 2026-07-31 by GeForceLegend:
// libs/GlobalIllumination.glsl; programs/deferred/Deferred2..Deferred10.frag;
// libs/Common.glsl (blueNoiseTemporal). The eighth stage is inline in Deferred10.
// Changes at the interface: our stable GI grid, packed scratch atlas, explicit
// bounds checks, and finite arithmetic guards. Raw temporal radiance is untouched.
#include "/lib/gi_geometry.glsl"
#include "/lib/denoise_recovery.glsl"
#ifndef GI_SAMPLES
#define GI_SAMPLES 1 // [0 1 2 4 6 8]
#endif

ivec2 giScaleAddress(ivec2 p, int band) {
    ivec2 size = giRenderSizePixels();
    int index = (band * size.y + p.y) * size.x + p.x;
    int width = textureSize(giSpatialIntermediateSampler, 0).x;
    return ivec2(index % width, index / width);
}

// Two alternating RGB/variance planes and one immutable geometry plane.
// Use actual capacity: rounding up half-resolution GI can exceed a very small
// viewport. All passes must take the same raw-GI fallback in that case.
bool giSundialFilterEnabled() {
    if (offlineCameraIsStill()) return false;
    ivec2 size = giRenderSizePixels();
    ivec2 atlasSize = textureSize(giSpatialIntermediateSampler, 0);
    return any(greaterThan(size, ivec2(1))) &&
        size.x * size.y <= (atlasSize.x * atlasSize.y) / 3;
}

vec4 giSundialGeometryRecord(ivec2 p) {
    vec4 guide = ptReadSurface(p);
    if (guide.a == 0.0) return vec4(0.0);
    vec3 geo = normalize(mat3(gbufferModelView) * giUnpackNormal(guide.r));
    vec3 normal = normalize(mat3(gbufferModelView) * giUnpackNormal(guide.g));
    return vec4(giPackNormal(geo), giPackNormal(normal), guide.a,
        float(ptSurfaceClass(guide) + 1));
}

void giSundialDecodeNormals(vec4 geometry, out vec3 geo, out vec3 normal) {
    geo = giUnpackNormal(geometry.r);
    normal = giUnpackNormal(geometry.g);
}

vec3 giSundialViewPosition(ivec2 p, float viewZ) {
    ivec2 g = giReceiverPixel(p);
    vec2 uv = (vec2(g) + 0.5) / vec2(textureSize(depthtex0, 0));
    vec4 ray = gbufferProjectionInverse * vec4(fsr2UnjitterUv(uv) * 2.0 - 1.0, 1.0, 1.0);
    return ray.xyz * (viewZ / ray.z);
}


vec4 giSundialPrepare(ivec2 p) {
    ivec2 size = giRenderSizePixels();
    vec3 color = texelFetch(colortex4, p, 0).rgb;
    vec3 sum = color, sum2 = color * color;
    float neighborhoodWeight = 1.0;
    vec4 geometry = giSundialGeometryRecord(p);
    if (geometry.a < 0.5) return vec4(0.0);
    vec3 geo = giUnpackNormal(geometry.r);
    vec3 pos = giSundialViewPosition(p, geometry.b);
    const ivec2 neighbors[8] = ivec2[8](ivec2(0,-1), ivec2(1,-1), ivec2(1,0), ivec2(1,1),
        ivec2(0,1), ivec2(-1,1), ivec2(-1,0), ivec2(-1,-1));
    for (int i = 0; i < 8; ++i) {
        ivec2 q = clamp(p + neighbors[i], ivec2(0), size - 1);
        vec3 sampleColor = texelFetch(colortex4, q, 0).rgb;
        vec4 qGeometry = giSundialGeometryRecord(q);
        float w = 0.0;
        if (qGeometry.a == geometry.a) {
            vec3 qPos = giSundialViewPosition(q, qGeometry.b);
            w = giGeometryWeight(pos, geo, qPos, giUnpackNormal(qGeometry.r));
        }
        // Do not borrow a mature neighbor's age across newly exposed surfaces.
        w = clamp(w, 0.0, 1.0);
        sum += sampleColor * w;
        sum2 += sampleColor * sampleColor * w;
        neighborhoodWeight += w;
    }
    return denoisePrepareRecovery(color, sum / neighborhoodWeight, sum2 / neighborhoodWeight,
        max(texelFetch(colortex7, p, 0).a, 1.0), 16.0, float(max(GI_SAMPLES, 1)));
}

vec4 giSundialInput(ivec2 p, int stage) {
    int band = stage & 1;
    return texelFetch(giSpatialIntermediateSampler, giScaleAddress(p, band), 0);
}

float giSundialNoise(ivec2 p) {
    // Reuse Iris noisetex. Retain Sundial's 64-frame irrational phase sequence;
    // spatial noise now comes from the shared engine texture, not a bundled asset.
    ivec2 noiseSize = textureSize(noisetex, 0);
    float n = texelFetch(noisetex, p % noiseSize, 0).r;
    return fract(n + 0.447213595 * float(frameCounter & 63));
}

vec4 giSundialFilter(ivec2 p, int stage) {
    const vec2 offsets[8] = vec2[8](vec2(1,0), vec2(0,1), vec2(16,0), vec2(0,16),
        vec2(7,7), vec2(7,-7), vec2(2,2), vec2(2,-2));
    ivec2 size = giRenderSizePixels();
    vec4 center = giSundialInput(p, stage);
    vec4 geometry = texelFetch(giSpatialIntermediateSampler, giScaleAddress(p, 2), 0);
    if (geometry.w < 0.5) return vec4(0.0);
    vec3 geo, normal;
    giSundialDecodeNormals(geometry, geo, normal);
    vec3 pos = giSundialViewPosition(p, geometry.b);
    // Compare the current spatial result; raw temporal history stays untouched.
    vec3 guide = center.rgb;
    float confidence = denoiseHistoryConfidence(max(texelFetch(colortex7, p, 0).a, 1.0));
    float variance = max(center.a, 1e-20);
    float guideEnergy = dot(guide, guide) + 1e-6;
    float normalFactor = 64.0 * exp2(-0.15 * length(pos) / guideEnergy * variance);
    normalFactor *= confidence;
    // Preserve the source's conversion/rounding, including the negative diagonal.
    ivec2 delta = ivec2(offsets[stage] * (2.0 * giSundialNoise(p) + 1.0) *
        exp(-0.1 / (variance + 0.2)) + 0.5);
    vec3 sum = center.rgb;
    float varianceSum = variance, sumW = 1.0;
    for (int i = 0; i < 2; ++i) {
        ivec2 q = p + delta;
        delta = -delta;
        if (any(greaterThanEqual(uvec2(q), uvec2(size)))) continue;
        vec4 qGeometry = texelFetch(giSpatialIntermediateSampler, giScaleAddress(q, 2), 0);
        if (qGeometry.w < 0.5 || qGeometry.w != geometry.w) continue;
        vec3 qGeo, qNormal;
        giSundialDecodeNormals(qGeometry, qGeo, qNormal);
        vec3 qPos = giSundialViewPosition(q, qGeometry.b);
        vec4 qData = giSundialInput(q, stage);
        vec3 qGuide = qData.rgb;
        float colorWeight = denoiseRecoveryColorWeight(guide, qGuide, variance, confidence);
        float weight = colorWeight * exp2(
            -144.269502 * abs(dot(qPos - pos, geo)) +
            normalFactor * log2(clamp(dot(qNormal, normal), 1e-20, 1.0)) +
            64.0 * log2(clamp(dot(qGeo, geo), 1e-20, 1.0)));
        weight = clamp(weight, 0.0, 1.0);
        sum += qData.rgb * weight;
        varianceSum += max(qData.a, 0.0) * weight * weight;
        sumW += weight;
    }
    return vec4(sum / sumW, varianceSum / (sumW * sumW));
}

#ifndef GI_SPATIAL_COMPUTE
vec4 giFilterScales(ivec2 p) {
    if (!giSundialFilterEnabled()) return texelFetch(colortex4, p, 0);
    return giSundialFilter(p, 7);
}
#endif
#endif
