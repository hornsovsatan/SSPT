#version 330 compatibility
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
out vec2 texcoord;
#include "fsr2/ffx_fsr2_config.glsl"
void main() {
	gl_Position = ftransform();
	if (fsr2Enabled()) {
		vec2 fraction = fsr2RenderFraction();
		gl_Position.xy = gl_Position.xy * fraction +
			gl_Position.w * (fraction - vec2(1.0));
	}
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
