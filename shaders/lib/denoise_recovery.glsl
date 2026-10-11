#ifndef LIGHT_AND_SHADOW_DENOISE_RECOVERY_GLSL
#define LIGHT_AND_SHADOW_DENOISE_RECOVERY_GLSL
// End short-history smoothing early without shortening radiance accumulation.

float denoiseHistoryConfidence(float age) {
    float t = clamp(age / 8.0, 0.0, 1.0);
    return t * t;
}

float denoiseRepairWeight(float age) {
    return 1.0 - smoothstep(1.0, 6.0, age);
}

vec4 denoisePrepareRecovery(vec3 color, vec3 mean, vec3 meanSquare,
                            float age, float varianceScale, float sampleCount) {
    float confidence = denoiseHistoryConfidence(age);
    // A bounded energy-relative floor replaces Sundial's singular early boost.
    // It reaches zero at age 8, independently of the temporal history limit.
    float early = 1.0 - confidence;
    float boost = early * early * (dot(mean, mean) + 0.01) / max(sampleCount, 1.0);
    float variance = varianceScale * dot(max(meanSquare - mean * mean, vec3(0.0)), vec3(1.0));
    // Display-only reconstruction: never written back into temporal radiance.
    return vec4(mix(color, mean, denoiseRepairWeight(age)), max(variance + boost, 1e-5));
}

float denoiseRecoveryColorWeight(vec3 center, vec3 sampleColor, float variance, float confidence) {
    vec3 difference = center - sampleColor;
    float energy = max(max(dot(center, center), dot(sampleColor, sampleColor)), 1e-6);
    return exp(-confidence * dot(difference, difference) * inversesqrt(max(variance * energy, 1e-20)));
}
#endif
