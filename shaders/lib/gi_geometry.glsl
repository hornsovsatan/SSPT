#ifndef LIGHT_AND_SHADOW_GI_GEOMETRY_GLSL
#define LIGHT_AND_SHADOW_GI_GEOMETRY_GLSL

// colortex15 holds raster geometric normals until composite5 has consumed GI.
// The later FSR resolve reuses that attachment for its final color output.
ivec2 giGeometryPixel(vec2 uv) {
    ivec2 size = textureSize(depthtex0, 0);
    return clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
}

vec2 giRasterUv(vec2 uv) {
    return (vec2(giGeometryPixel(uv)) + 0.5) / vec2(textureSize(depthtex0, 0));
}

vec3 giGeometricNormal(ivec2 p) {
    vec4 data = texelFetch(colortex15, p, 0);
    return normalize((data.a > 0.5 ? data.rgb : texelFetch(colortex1, p, 0).rgb) * 2.0 - 1.0);
}

vec2 giOctEncode(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    vec2 signs = mix(vec2(-1.0), vec2(1.0), greaterThanEqual(n.xy, vec2(0.0)));
    return (n.z >= 0.0 ? n.xy : (1.0 - abs(n.yx)) * signs) * 0.5 + 0.5;
}

// Numeric 20-bit packing stays exact in RGBA32F, without NaN bit patterns.
float giPackNormal(vec3 n) {
    vec2 q = floor(giOctEncode(n) * 1023.0 + 0.5);
    return q.x + q.y * 1024.0;
}

vec3 giUnpackNormal(float encoded) {
    vec2 f = vec2(mod(encoded, 1024.0), floor(encoded / 1024.0)) / 1023.0 * 2.0 - 1.0;
    vec3 n = vec3(f, 1.0 - abs(f.x) - abs(f.y));
    float t = clamp(-n.z, 0.0, 1.0);
    n.xy += mix(vec2(t), vec2(-t), greaterThanEqual(n.xy, vec2(0.0)));
    return normalize(n);
}

// Retain the actual depth sample's pixel, not a continuous UV paired with a
// different pixel's depth. Offsets are relative to the stable GI grid and fit
// all supported FSR ratios, without depending on display pixel count.
ivec2 giRasterBase(ivec2 p, ivec2 size) {
    // Integer arithmetic is essential: interpolated UV and recomputed UV can
    // round to opposite sides of an exact raster-pixel boundary.
    return ((p * 2 + 1) * textureSize(depthtex0, 0)) / (size * 2);
}

ivec2 giReceiverPixel(ivec2 p) {
    ivec2 size = giRenderSizePixels();
    ivec2 fullSize = textureSize(depthtex0, 0);
    ivec2 numerator = (p * 2 + 1) * fullSize;
    vec2 remainder = vec2(numerator % (size * 2)) / vec2(size * 2);
    vec2 jitter = offlineCameraIsStill() ? vec2(0.0) : fsr2CurrentJitterUv() * vec2(fullSize);
    return clamp(giRasterBase(p, size) + ivec2(floor(remainder + jitter)), ivec2(0), fullSize - 1);
}

float giPackRasterOffset(ivec2 g, ivec2 giPixel) {
    ivec2 base = giRasterBase(giPixel, giRenderSizePixels());
    ivec2 d = clamp(g - base + 16, ivec2(0), ivec2(31));
    return float(d.x + d.y * 32);
}

vec2 giHistoryRasterUv(ivec2 p, ivec2 size, float encoded) {
    ivec2 fullSize = textureSize(depthtex0, 0);
    ivec2 base = giRasterBase(p, size);
    int offset = int(encoded) % 1024;
    ivec2 d = ivec2(offset % 32, offset / 32) - 16;
    return (vec2(base + d) + 0.5) / vec2(fullSize);
}
#include "/lib/pt_surface.glsl"
#endif
