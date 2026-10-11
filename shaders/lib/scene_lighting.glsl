#ifndef LIGHT_AND_SHADOW_SCENE_LIGHTING_GLSL
#define LIGHT_AND_SHADOW_SCENE_LIGHTING_GLSL

#include "/lib/shadow_common.glsl"
#include "/lib/color_space.glsl"

// Voxy declares requested uniforms in its generated shader wrapper.
#ifndef SCENE_LIGHTING_EXTERNAL_UNIFORMS
uniform float sunAngle;
uniform float rainStrength;
uniform bool hasCeiling;
uniform bool hasSkylight;
uniform vec3 endFlashPosition;
uniform float endFlashIntensity;
uniform float previousEndFlashIntensity;
#endif

bool sceneUsesEndFlash() {
    // Iris supplies a length-100 vector throughout the End, including between
    // flashes, and zero outside it. Intensity alone cannot identify a quiet End.
    return dot(endFlashPosition, endFlashPosition) > 1.0;
}

float getSceneBaseLight() {
    // Vanilla End uses the flash source; other dimensions use the Overworld.
    return (sceneUsesEndFlash()) ? 0.03 : 0.003;
}

bool sceneHasSkyLight() {
    return !sceneUsesEndFlash() && !bool(hasCeiling) && bool(hasSkylight);
}

bool sceneStoresSkyAccess() {
    return !bool(hasCeiling) && bool(hasSkylight);
}


bool sceneHasDirectLight() {
    return sceneUsesEndFlash() ? endFlashIntensity > 0.0 : sceneHasSkyLight();
}

float sceneDirectSkyAccess(float skyAccess) {
    // End skylight levels do not describe visibility toward a moving flash.
    // PCSS supplies that visibility from the same direction as the light.
    return sceneUsesEndFlash() ? 1.0 : clamp(skyAccess, 0.0, 1.0);
}

bool sceneLightHistoryChanged() {
    return sceneUsesEndFlash() &&
        abs(endFlashIntensity - previousEndFlashIntensity) > 0.0001;
}

// Independent celestial radiance, not sampled vanilla display illumination.
// Callers apply sky access, surface orientation and shadow visibility once.
vec3 getSceneDirectLight() {
    if (sceneUsesEndFlash()) {
        // Flash source only; the End has no steady directional sunlight.
        return vec3(0.8, 0.7, 1.0) * (2.0 * clamp(endFlashIntensity, 0.0, 1.0));
    }
    if (!sceneHasSkyLight()) return vec3(0.0);
    float height = abs(sin(sunAngle * 6.28318530718)) * cos(radians(sunPathRotation));
    float horizonFade = smoothstep(0.0, 0.12, height);
    vec3 radiance;
    if (sunAngle < 0.5) {
        radiance = mix(vec3(1.0, 0.65, 0.35), vec3(1.0, 0.97, 0.91),
            smoothstep(0.0, 0.35, height));
    } else {
        radiance = vec3(0.65, 0.78, 1.0) * 0.08;
    }
    return radiance * horizonFade * mix(1.0, 0.35, clamp(rainStrength, 0.0, 1.0));
}

#endif
