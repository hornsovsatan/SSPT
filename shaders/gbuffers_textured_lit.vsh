#version 330 compatibility
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#include "fsr2/ffx_fsr2_config.glsl"
in vec4 at_midBlock;
#include "/lib/block_emission.glsl"
in vec4 at_tangent;
out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 normal;
out vec3 tangent;
out float vEmission;
void main() {
	gl_Position = ftransform();
	fsr2ApplyJitter(gl_Position);
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;
	normal = gl_NormalMatrix * gl_Normal;
	tangent = gl_NormalMatrix * at_tangent.xyz;
    vEmission = terrainBlockEmission(at_midBlock);
}
