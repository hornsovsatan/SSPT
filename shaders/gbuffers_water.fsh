#version 330 compatibility

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform vec3 shadowLightPosition;
uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 tangent;
in float vEmission;
#include "/lib/scene_lighting.glsl"

/* RENDERTARGETS: 0,1,3,5,11,12,13,15 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;
layout(location = 3) out vec4 ambientData;
layout(location = 4) out vec4 translucentSurfaceData;
layout(location = 5) out vec4 translucentNormalData;
layout(location = 6) out vec4 translucentColorData;

layout(location = 7) out vec4 geometricData;

void main() {
    geometricData = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
    vec4 surfaceColor = texture(gtexture, texcoord) * glcolor;
    surfaceColor.rgb = srgbToLinear(surfaceColor.rgb);
    if (surfaceColor.a < alphaTestRef) discard;

    vec4 specTex = texture(specular, texcoord);
    float specA255 = floor(clamp(specTex.a, 0.0, 1.0) * 255.0 + 0.5);
    float labEmission = specA255 < 255.0 ? specA255 / 254.0 : 0.0;
    float emission = labEmission;
    float smoothness = clamp(specTex.r, 0.0, 1.0);
    float roughness = (1.0 - smoothness) * (1.0 - smoothness);
    float materialValue = clamp(specTex.g, 0.0, 1.0);
    float blockLightLevel = vEmission;

    vec3 baseNormal = normalize(normal);
    vec3 tangentDir = normalize(tangent);
    vec3 bitangent = normalize(cross(baseNormal, tangentDir));
    mat3 TBN = mat3(tangentDir, bitangent, baseNormal);
    vec4 normalTex = texture(normals, texcoord);
    vec2 mappedXY = normalTex.rg * 2.0 - 1.0;
    mappedXY.y = -mappedXY.y;
    vec3 tangentNormal = normalize(vec3(
        mappedXY,
        sqrt(max(0.0, 1.0 - dot(mappedXY, mappedXY)))
    ));
    vec3 mappedNormal = normalize(TBN * tangentNormal);

    float NdotL = 1.0;
    if (sceneHasDirectLight()) {
        NdotL = clamp(
            dot(normalize(shadowLightPosition), mappedNormal),
            0.0, 1.0
        );
    }
    float skyVisibility = sceneStoresSkyAccess()
        ? clamp((lmcoord.g - 0.03125) / 0.9375, 0.0, 1.0)
        : 0.0;

    color = surfaceColor;
    normalData = vec4(mappedNormal * 0.5 + 0.5, normalTex.b);
    materialData = vec4(
        emission,
        roughness,
        materialValue,
        blockLightLevel
    );
    ambientData = vec4(getSceneDirectLight() * sceneDirectSkyAccess(skyVisibility) * NdotL, skyVisibility);

    // These three attachments use blending=off. The closest translucent
    // terrain fragment therefore keeps its own surface data instead of being
    // diluted by the opaque geometry behind it.
    translucentSurfaceData = vec4(
        gl_FragCoord.z,
        surfaceColor.a,
        roughness,
        materialValue
    );
    // Alpha stays above the validity threshold and also carries the
    // at_midBlock.w seed for the final out-of-volume composition fallback.
    translucentNormalData = vec4(
        mappedNormal * 0.5 + 0.5,
        1.0 + blockLightLevel
    );
    translucentColorData = vec4(surfaceColor.rgb, emission);
}
