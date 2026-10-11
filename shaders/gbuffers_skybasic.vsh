#version 330 compatibility

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#include "fsr2/ffx_fsr2_config.glsl"

out vec4 glcolor;

void main() {
	gl_Position = ftransform();
	fsr2ApplyJitter(gl_Position);
	glcolor = gl_Color;
}
