#ifndef LIGHT_AND_SHADOW_SHADOW_PCSS_GLSL
#define LIGHT_AND_SHADOW_SHADOW_PCSS_GLSL

#define PCSS_BLOCKER_SAMPLES 24
#define PCSS_FILTER_SAMPLES 24
#define PCSS_MIN_RADIUS 0.75
#define PCSS_MAX_RADIUS 18.0
#define PCSS_BLOCKER_RADIUS PCSS_MAX_RADIUS
#define PCSS_PENUMBRA_SCALE 80.0
#define PCSS_DEPTH_BIAS 0.0005
#define PCSS_MAX_PLANE_CORRECTION 0.003
const vec2 POISSON_24[24] = vec2[24](
    vec2(-0.326, -0.406), vec2(-0.840, -0.074), vec2(-0.696,  0.457), vec2(-0.203,  0.621),
    vec2( 0.962, -0.195), vec2( 0.473, -0.480), vec2( 0.519,  0.767), vec2( 0.185, -0.893),
    vec2( 0.507,  0.064), vec2( 0.896,  0.412), vec2(-0.322, -0.933), vec2(-0.792, -0.598),
    vec2(-0.094, -0.191), vec2(-0.359,  0.183), vec2( 0.164,  0.312), vec2(-0.579,  0.820),
    vec2( 0.742, -0.703), vec2(-0.045,  0.975), vec2( 0.301, -0.115), vec2(-0.982,  0.186),
    vec2( 0.020, -0.608), vec2( 0.689,  0.245), vec2(-0.522, -0.230), vec2( 0.327,  0.537)
);
mat2 pcssRotation(vec2 phase) {
    ivec2 screenCoord = ivec2(floor(phase));
    ivec2 noiseCoord = ((screenCoord % 64) + 64) % 64;
    float n = texelFetch(noisetex, noiseCoord, 0).r;
    float a = n * 6.2831853;
    float c = cos(a);
    float s = sin(a);
    return mat2(c, -s, s, c);
}
bool shadowUvValid(vec2 uv) {
    bool inside = uv.x > 0.001 && uv.x < 0.999 && uv.y > 0.001 && uv.y < 0.999;
    // Only the circular radial-map domain has a finite inverse.
    inside = inside && length(uv * 2.0 - 1.0) < 0.999;
    return inside;
}
vec2 pcssTexelCenter(vec2 uv) {
    vec2 size = vec2(textureSize(shadowtex0, 0));
    return (floor(uv * size) + 0.5) / size;
}
struct PCSSReceiverPlane {
    vec2 origin;
    vec2 depthSlope;
};
PCSSReceiverPlane pcssReceiverPlane(vec4 clipPos, vec3 normalPlayer) {
    PCSSReceiverPlane plane;
    plane.origin = clipPos.xy / clipPos.w;
    plane.depthSlope = vec2(0.0);
    float normalLength = length(normalPlayer);
    if (normalLength < 1e-5 || any(isnan(normalPlayer)) || any(isinf(normalPlayer))) return plane;
    vec3 normalLight = mat3(shadowModelView) * (normalPlayer / normalLength);
    // Inverse-transpose normal transform for orthographic shadow projection.
    vec3 normalClip = normalLight / vec3(shadowProjection[0][0],
                                        shadowProjection[1][1],
                                        shadowProjection[2][2]);
    if (abs(normalClip.z) < 1e-8) return plane;
    float reliability = smoothstep(0.03, 0.10, abs(normalLight.z));
    // clip Z is halved by distort(), then converted to [0,1]: dz factor = 1/4.
    plane.depthSlope = -0.25 * normalClip.xy / normalClip.z * reliability;
    return plane;
}
float pcssReceiverDepth(vec2 sampleUv, vec3 center, PCSSReceiverPlane plane) {
    // Exact radial inverse at the fetched texel: q = p / (length(p) + 0.1).
    vec2 q = sampleUv * 2.0 - 1.0;
    vec2 sampleClip = q * (0.1 / max(1.0 - length(q), 0.001));
    vec2 displacement = sampleClip - plane.origin;
    float correction = clamp(dot(plane.depthSlope, displacement),
                             -PCSS_MAX_PLANE_CORRECTION, PCSS_MAX_PLANE_CORRECTION);
    return center.z + correction;
}
vec3 shadowSampleAt(vec2 uv, float receiverDepth) {
    if (!shadowUvValid(uv)) return vec3(1.0);
    float z = receiverDepth - PCSS_DEPTH_BIAS;
    float allDepth = textureLod(shadowtex0, uv, 0.0).r;
    if (z <= allDepth) {
        return vec3(1.0);
    }
    float opaqueDepth = textureLod(shadowtex1, uv, 0.0).r;
    if (z > opaqueDepth) {
        return vec3(0.0);
    }
    vec4 shadowColor = textureLod(shadowcolor0, uv, 0.0);
    return clamp(shadowColor.rgb * (1.0 - shadowColor.a), vec3(0.0), vec3(1.0));
}
float findAverageBlockerDistance(vec3 shadowScreenPos, mat2 rot,
                                PCSSReceiverPlane plane, out float blockerCount) {
    // Blocker search must cover the maximum filter footprint.
    float sumDistance = 0.0;
    blockerCount = 0.0;
    vec2 texel = 1.0 / vec2(textureSize(shadowtex0, 0));
    for (int i = 0; i < PCSS_BLOCKER_SAMPLES; i++) {
        vec2 uv = pcssTexelCenter(shadowScreenPos.xy + (rot * POISSON_24[i]) * PCSS_BLOCKER_RADIUS * texel);
        if (!shadowUvValid(uv)) continue;
        float z = pcssReceiverDepth(uv, shadowScreenPos, plane) - PCSS_DEPTH_BIAS;
        float d = textureLod(shadowtex0, uv, 0.0).r;
        if (d < z) {
            // Average blocker separation relative to the local receiver plane.
            sumDistance += z - d;
            blockerCount += 1.0;
        }
    }
    if (blockerCount < 0.5) return 0.0;
    return sumDistance / blockerCount;
}
vec3 getPCSSShadow(vec4 shadowClipPos, vec3 normalPlayer, bool allowOutsideMap) {
    PCSSReceiverPlane plane = pcssReceiverPlane(shadowClipPos, normalPlayer);
    shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
    vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
    vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
    if (!shadowUvValid(shadowScreenPos.xy) || shadowScreenPos.z <= 0.0 || shadowScreenPos.z >= 1.0)
        return allowOutsideMap ? vec3(1.0) : vec3(0.0);
    // Share a shadow-space sampling phase across direct, GI and reflection hits.
    mat2 rot = pcssRotation(shadowScreenPos.xy * vec2(textureSize(shadowtex0, 0)));
    float blockerCount;
    float avgBlockerDistance = findAverageBlockerDistance(shadowScreenPos, rot, plane, blockerCount);
    if (blockerCount < 0.5) {
        return vec3(1.0);
    }
    float penumbra = clamp(avgBlockerDistance * PCSS_PENUMBRA_SCALE, 0.0, 1.0);
    float radiusPixels = mix(PCSS_MIN_RADIUS, PCSS_MAX_RADIUS, penumbra);
    vec2 texel = 1.0 / vec2(textureSize(shadowtex0, 0));
    vec3 accum = vec3(0.0);
    float weightSum = 0.0;
    for (int i = 0; i < PCSS_FILTER_SAMPLES; i++) {
        vec2 diskOffset = POISSON_24[i % 24];
        vec2 uv = pcssTexelCenter(shadowScreenPos.xy + (rot * diskOffset) * radiusPixels * texel);
        // Smoothly taper weights toward the filter rim.
        float weight = max(1.0 - dot(diskOffset, diskOffset), 0.0);
        weight *= weight;
        float receiverDepth = shadowScreenPos.z;
        if (shadowUvValid(uv)) receiverDepth = pcssReceiverDepth(uv, shadowScreenPos, plane);
        accum += shadowSampleAt(uv, receiverDepth) * weight;
        weightSum += weight;
    }
    return accum / max(weightSum, 1e-5);
}

#endif
