#version 330 compatibility
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferModelView;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferPreviousProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
out vec2 texcoord;
#include "/lib/gi_common.glsl"
void main() {
	gl_Position = ftransform();
	vec2 fraction = giRenderFraction();
	gl_Position.xy = gl_Position.xy * fraction +
		gl_Position.w * (fraction - vec2(1.0));
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
