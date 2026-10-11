#version 330 compatibility

#ifndef DISTANT_HORIZONS
#define DISTANT_HORIZONS
in int dhMaterialId;
#define DH_BLOCK_LAVA 7
#define DH_BLOCK_ILLUMINATED 15
#endif

uniform mat4 dhProjection;
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#include "fsr2/ffx_fsr2_config.glsl"

out vec4 dhColor;
out vec2 dhLightmapCoord;
out vec3 dhNormalView;
out vec3 dhViewPos;
flat out float dhEmission;

void main() {
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = dhProjection * viewPos;
    fsr2ApplyJitter(gl_Position);
    dhColor = gl_Color;
    dhLightmapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    dhNormalView = normalize(gl_NormalMatrix * gl_Normal);
    dhViewPos = viewPos.xyz;
    dhEmission = (dhMaterialId == DH_BLOCK_LAVA ||
                  dhMaterialId == DH_BLOCK_ILLUMINATED) ? 1.0 : 0.0;
}
