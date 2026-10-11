#version 330 compatibility

uniform sampler2D depthtex0;
uniform vec3 shadowLightPosition;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;

in vec4 dhColor;
in vec2 dhLightmapCoord;
in vec3 dhNormalView;
in vec3 dhViewPos;
flat in float dhEmission;
flat in float dhIsWater;
#include "/lib/scene_lighting.glsl"

/* RENDERTARGETS: 0,1,3,5,15 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;
layout(location = 3) out vec4 ambientData;

layout(location = 4) out vec4 geometricData;

void main() {
    geometricData = vec4(normalize(dhNormalView) * 0.5 + 0.5, 1.0);
    if (length(dhViewPos) < max(far - 16.0, 0.0)) discard;
    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    if (texture(depthtex0, screenUV).r < 1.0) discard;

    vec3 normalView = normalize(dhNormalView);
    float NdotL = 1.0;
    if (sceneHasDirectLight()) {
        NdotL = clamp(dot(normalize(shadowLightPosition), normalView), 0.0, 1.0);
    }
    float skyVisibility = sceneStoresSkyAccess()
        ? clamp((dhLightmapCoord.y - 0.03125) / 0.9375, 0.0, 1.0)
        : 0.0;
    float blockLightLevel = clamp(
        (dhLightmapCoord.x - 0.03125) / 0.9375,
        0.0, 1.0
    );
    float alpha = dhIsWater > 0.5 ? min(dhColor.a, 0.82) : dhColor.a;

    color = vec4(srgbToLinear(dhColor.rgb), alpha);
    normalData = vec4(normalView * 0.5 + 0.5, 1.0);
    materialData = vec4(
        dhEmission,
        dhIsWater > 0.5 ? 0.02 : 1.0,
        0.0,
        blockLightLevel
    );
    ambientData = vec4(getSceneDirectLight() * sceneDirectSkyAccess(skyVisibility) * NdotL, skyVisibility);
}
