#ifndef LIGHT_AND_SHADOW_CLOUD_LAYER_GLSL
#define LIGHT_AND_SHADOW_CLOUD_LAYER_GLSL
#include "/lib/color_space.glsl"

uniform usampler2D cloudLayerSampler;
uniform sampler2D depthtex1;
uniform sampler2D colortex11;
uniform mat4 gbufferProjectionInverse;

float cloudSceneViewDepth(vec2 uv, float rawDepth) {
    vec4 view = gbufferProjectionInverse * vec4(
        fsr2UnjitterUv(uv) * 2.0 - 1.0, rawDepth * 2.0 - 1.0, 1.0);
    return -view.z / view.w;
}

vec4 readCloudLayer(ivec2 pixel) {
    ivec2 size = textureSize(cloudLayerSampler, 0) / 2;
    pixel = clamp(pixel, ivec2(0), size - 1);
    uint alphaRecord = texelFetch(cloudLayerSampler, pixel + size, 0).r;
    if (alphaRecord == 0u) return vec4(0.0);
    float cloudDepth = uintBitsToFloat(
        (0x00ffffffu - (alphaRecord >> 8u)) << 8u);
    vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
    float opaqueDepth = texelFetch(depthtex1, pixel, 0).r;
    if (opaqueDepth < 1.0 && cloudSceneViewDepth(uv, opaqueDepth) <= cloudDepth)
        return vec4(0.0);

    vec4 layer = vec4(
        float(texelFetch(cloudLayerSampler, pixel, 0).r & 255u),
        float(texelFetch(cloudLayerSampler, pixel + ivec2(size.x, 0), 0).r & 255u),
        float(texelFetch(cloudLayerSampler, pixel + ivec2(0, size.y), 0).r & 255u),
        float(alphaRecord & 255u)) / 255.0;
    vec4 translucent = texelFetch(colortex11, pixel, 0);
    bool hasTranslucent = texelFetch(colortex12, pixel, 0).a > 0.5 &&
        translucent.r > 0.0 && translucent.r < 1.0;
    if (hasTranslucent && cloudSceneViewDepth(uv, translucent.r) <= cloudDepth)
        layer.a *= 1.0 - clamp(translucent.g, 0.0, 1.0);
    return vec4(srgbToLinear(layer.rgb) * layer.a, layer.a);
}

vec4 sampleCloudLayer(vec2 uv) {
    // Reconstruct current-frame coverage, not moving-cloud history. Depth
    // rejection happens per tap, before interpolation at mountain silhouettes.
    vec2 pixel = uv * vec2(textureSize(cloudLayerSampler, 0) / 2) - 0.5;
    ivec2 base = ivec2(floor(pixel));
    vec2 f = fract(pixel);
    return mix(
        mix(readCloudLayer(base), readCloudLayer(base + ivec2(1, 0)), f.x),
        mix(readCloudLayer(base + ivec2(0, 1)), readCloudLayer(base + ivec2(1, 1)), f.x), f.y);
}

#endif
