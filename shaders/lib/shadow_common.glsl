#ifndef LIGHT_AND_SHADOW_SHADOW_COMMON_GLSL
#define LIGHT_AND_SHADOW_SHADOW_COMMON_GLSL

// Shared shadow map configuration.
const int shadowMapResolution = 2048;
// Iris rotates celestial geometry, light uniforms and shadow matrices together.
const float sunPathRotation = 0.0; // [-60.0 -55.0 -50.0 -45.0 -40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0 55.0 60.0]

// Shadow sampling and clip-space distortion.
const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;
const bool shadowcolor0Nearest = true;

vec3 distortShadowClipPos(vec3 shadowClipPos){
  float distortionFactor = length(shadowClipPos.xy) + 0.1;

  shadowClipPos.xy /= distortionFactor;
  shadowClipPos.z *= 0.5; // Extend light-space depth coverage.
  return shadowClipPos;
}

#endif
