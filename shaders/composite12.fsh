#version 430 compatibility
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex6;
uniform sampler2D colortex12;
uniform sampler2D colortex15;
uniform sampler2D colortex14;
uniform sampler2D depthtex0;
uniform vec3 fogColor;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
in vec2 texcoord;

#include "fsr2/ffx_fsr2_config.glsl"
#include "/lib/cloud_layer.glsl"

#define AUTO_EXPOSURE_HIGHLIGHT_KNEE 1.35

/*
const int colortex0Format = RGBA16F;
const int colortex15Format = RGBA16F;
*/
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

vec3 applyExposure(vec3 value, float exposure) {
    value = max(value * exposure, vec3(0.0));
    vec3 mapped = value * (
        1.0 + value /
        (AUTO_EXPOSURE_HIGHLIGHT_KNEE * AUTO_EXPOSURE_HIGHLIGHT_KNEE)
    ) / (1.0 + value);
    return clamp(mapped, vec3(0.0), vec3(1.0));
}

void main() {
    vec3 sceneColor = fsr2Enabled()
        ? texture(colortex15, texcoord).rgb
        : texture(colortex0, texcoord).rgb;
    vec2 exposureUv = vec2(0.5) * (
        fsr2Enabled() ? fsr2RenderFraction() : vec2(1.0)
    );
    float exposure = texture(colortex6, exposureUv).r;
    // Tone-mapped RGB stays linear until all foreground layers are composed.
    vec3 displayColor = applyExposure(sceneColor, exposure);
    // Clouds retain vanilla vertex color and opacity, outside PT/exposure
    // history. Composite after terrain fog, before foreground precipitation.
    vec4 clouds = sampleCloudLayer(texcoord + fsr2CurrentJitterUv());
    if (clouds.a > 0.0001) {
        displayColor = mix(displayColor,
            applyExposure(clouds.rgb / clouds.a, 1.0), clouds.a);
    }
    // Weather is full-resolution current-frame geometry, independent of FSR
    // and offline scene history. Sample its jittered layer at display UVs.
    vec2 weatherHalfTexel = 0.5 / vec2(textureSize(colortex14, 0));
    vec2 weatherUv = clamp(texcoord + fsr2CurrentJitterUv(),
        weatherHalfTexel, vec2(1.0) - weatherHalfTexel);
    vec4 weatherLayer = texture(colortex14, weatherUv);
    float weatherAlpha = clamp(weatherLayer.a, 0.0, 1.0);
    if (weatherAlpha > 0.0001) {
        vec3 weatherDisplay = applyExposure(weatherLayer.rgb / weatherAlpha, exposure);
        displayColor = mix(displayColor, weatherDisplay, weatherAlpha);
    }
    color = vec4(linearToSRGB(displayColor), 1.0);
}
