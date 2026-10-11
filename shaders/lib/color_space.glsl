#ifndef LIGHT_AND_SHADOW_COLOR_SPACE_GLSL
#define LIGHT_AND_SHADOW_COLOR_SPACE_GLSL

// Decode display-encoded colors at resource boundaries. Alpha and material
// data are not colors and must never pass through these transfer functions.
vec3 srgbToLinear(vec3 value) {
    value = max(value, vec3(0.0));
    return mix(value / 12.92,
        pow((value + 0.055) / 1.055, vec3(2.4)),
        step(vec3(0.04045), value));
}

// Encode once, after linear lighting, exposure, tone mapping and compositing.
vec3 linearToSRGB(vec3 value) {
    value = max(value, vec3(0.0));
    return mix(value * 12.92,
        1.055 * pow(value, vec3(1.0 / 2.4)) - 0.055,
        step(vec3(0.0031308), value));
}

#endif
