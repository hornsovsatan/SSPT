#ifndef LIGHT_AND_SHADOW_FSR2_CONFIG_GLSL
#define LIGHT_AND_SHADOW_FSR2_CONFIG_GLSL

// FSR2 upscale factor. The source composition is rendered into the lower-left
// region of the full-size buffers, while the Minecraft G-buffer stays at full
// resolution so Distant Horizons and Voxy keep their normal viewport.
#define FSR2_SCALE 1.0 // [0.0 1.0 1.5 1.75 2.0 3.0]
#define FSR2_SHARPNESS 0.35

bool fsr2Enabled() {
    return FSR2_SCALE > 0.0;
}

float fsr2UpscaleFactor() {
    return fsr2Enabled() ? float(FSR2_SCALE) : 1.0;
}

ivec2 fsr2DisplaySizePixels() {
    return max(ivec2(int(viewWidth + 0.5), int(viewHeight + 0.5)), ivec2(1));
}

ivec2 fsr2RenderSizePixels() {
    vec2 scaled = ceil(vec2(fsr2DisplaySizePixels()) / fsr2UpscaleFactor());
    return max(ivec2(scaled), ivec2(1));
}

// A low-resolution composition texel selects one actual full-resolution
// G-buffer sample. Its depth, normal, material and reconstruction ray must
// all use that sample's center (not the continuous low-resolution UV).
ivec2 fsr2GbufferPixelFromRenderPixel(ivec2 pixel, ivec2 fullSize) {
    ivec2 renderSize = fsr2RenderSizePixels();
    pixel = clamp(pixel, ivec2(0), renderSize - 1);
    return min(((pixel * 2 + 1) * fullSize) / (renderSize * 2), fullSize - 1);
}

vec2 fsr2GbufferUvFromRenderPixel(ivec2 pixel, ivec2 fullSize) {
    return (vec2(fsr2GbufferPixelFromRenderPixel(pixel, fullSize)) + 0.5) / vec2(fullSize);
}

vec2 fsr2RenderFraction() {
    return vec2(fsr2RenderSizePixels()) / vec2(fsr2DisplaySizePixels());
}

// Composite source passes keep full-size Iris targets so every selectable
// upscale factor can share the same attachments. Their active pixels occupy
// the lower-left render-size region. G-buffer UVs remain logical 0..1 UVs;
// only intermediate composite textures use this storage mapping.
vec2 fsr2ClampRenderLogicalUv(vec2 logicalUv) {
    vec2 halfTexel = 0.5 / vec2(fsr2RenderSizePixels());
    return clamp(logicalUv, halfTexel, vec2(1.0) - halfTexel);
}

vec2 fsr2RenderStorageUv(vec2 logicalUv) {
    return fsr2ClampRenderLogicalUv(logicalUv) * fsr2RenderFraction();
}

int fsr2JitterPhaseCount() {
    float ratio = float(fsr2DisplaySizePixels().x) /
        float(fsr2RenderSizePixels().x);
    return clamp(int(ceil(8.0 * ratio * ratio)), 8, 72);
}

float fsr2RadicalInverse(int index, int base) {
    float result = 0.0;
    float invBase = 1.0 / float(base);
    float fraction = invBase;
    int value = index;
    for (int i = 0; i < 8; ++i) {
        if (value <= 0) break;
        result += float(value % base) * fraction;
        value /= base;
        fraction *= invBase;
    }
    return result;
}

vec2 fsr2JitterPixelsForFrame(int frame) {
    if (!fsr2Enabled()) return vec2(0.0);
    int index = (frame % fsr2JitterPhaseCount()) + 1;
    return vec2(fsr2RadicalInverse(index, 2),
                fsr2RadicalInverse(index, 3)) - 0.5;
}

vec2 fsr2CurrentJitterPixels() {
    return fsr2JitterPixelsForFrame(frameCounter);
}

vec2 fsr2PreviousJitterPixels() {
    return fsr2JitterPixelsForFrame(max(frameCounter - 1, 0));
}

vec2 fsr2CurrentJitterUv() {
    return fsr2Enabled() ? fsr2CurrentJitterPixels() / vec2(fsr2RenderSizePixels()) : vec2(0.0);
}

vec2 fsr2PreviousJitterUv() {
    return fsr2Enabled() ? fsr2PreviousJitterPixels() / vec2(fsr2RenderSizePixels()) : vec2(0.0);
}

vec2 fsr2UnjitterUv(vec2 uv) {
    return uv - fsr2CurrentJitterUv();
}

void fsr2ApplyJitter(inout vec4 clipPosition) {
    if (fsr2Enabled()) {
        clipPosition.xy += clipPosition.w * 2.0 * fsr2CurrentJitterUv();
    }
}

#endif
