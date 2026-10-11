#version 430 compatibility

in vec4 cloudColor;
in float cloudViewDepth;
layout(r32ui) uniform uimage2D cloudLayer;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 unusedColor;

void main() {
    if (cloudColor.a <= 0.001 || cloudViewDepth <= 0.0) discard;
    // Each channel carries the same nearest-depth key. Atomic selection of
    // depth AND color avoids the race of atomicMin(depth) + imageStore(color).
    // Dropping eight mantissa bits retains ~15 bits of relative depth precision.
    // Zero is the empty value, so Iris can clear these images normally.
    uint key = (0x00ffffffu - (floatBitsToUint(cloudViewDepth) >> 8u)) << 8u;
    uvec4 rgba = uvec4(clamp(cloudColor, 0.0, 1.0) * 255.0 + 0.5);
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    ivec2 size = imageSize(cloudLayer) / 2;
    imageAtomicMax(cloudLayer, pixel, key | rgba.r);
    imageAtomicMax(cloudLayer, pixel + ivec2(size.x, 0), key | rgba.g);
    imageAtomicMax(cloudLayer, pixel + ivec2(0, size.y), key | rgba.b);
    imageAtomicMax(cloudLayer, pixel + size, key | rgba.a);
    // Intentionally no early_fragment_tests: discard must suppress hardware
    // depth/color writes. Terrain, water, PT and FSR keep their original data.
    // Occlusion is resolved against the completed scene in composite12.
    discard;
}
