#define SCENE_LIGHTING_EXTERNAL_UNIFORMS
#include "/lib/scene_lighting.glsl"
layout(location = 0) out vec4 vxColor;
layout(location = 1) out vec4 vxNormal;
layout(location = 2) out vec4 vxMaterial;
layout(location = 3) out vec4 vxAmbient;

layout(location = 4) out vec4 vxGeometric;

vec3 vxFaceNormal(uint face) {
    return vec3(
        uint((face >> 1u) == 2u),
        uint((face >> 1u) == 0u),
        uint((face >> 1u) == 1u)
    ) * (float(int(face & 1u)) * 2.0 - 1.0);
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec4 baseColor = parameters.sampledColour * parameters.tinting;
    baseColor.rgb = srgbToLinear(baseColor.rgb);
    vec3 normalView = normalize(mat3(gbufferModelView) * vxFaceNormal(parameters.face));
    vec2 lightUV = clamp(
        parameters.lightMap,
        vec2(0.03125),
        vec2(0.96875)
    );
    vec2 lightLevel = clamp(
        (lightUV - vec2(0.03125)) / 0.9375,
        vec2(0.0),
        vec2(1.0)
    );
    bool skyLightingEnabled = sceneHasDirectLight();
    float NdotL = skyLightingEnabled
        ? clamp(dot(normalize(shadowLightPosition), normalView), 0.0, 1.0)
        : 1.0;
    float skyVisibility = sceneStoresSkyAccess() ? lightLevel.y : 0.0;

    vxColor = vec4(max(baseColor.rgb, vec3(0.0)), 1.0);
    vxNormal = vec4(normalView * 0.5 + 0.5, 1.0);
    vxGeometric = vxNormal;
    vxMaterial = vec4(0.0, 1.0, 0.0, lightLevel.x);
    vxAmbient = vec4(getSceneDirectLight() * sceneDirectSkyAccess(skyVisibility) * NdotL, skyVisibility);
}
