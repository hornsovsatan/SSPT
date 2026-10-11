#version 330 compatibility

uniform int renderStage;
uniform float viewHeight;
uniform float viewWidth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int frameCounter;

#include "fsr2/ffx_fsr2_config.glsl"
#include "/lib/color_space.glsl"

in vec4 glcolor;

float fogify(float x, float w) {
	return w / (x * x + w);
}

vec3 calcSkyColor(vec3 pos) {
	float upDot = dot(pos, gbufferModelView[1].xyz); //not much, what's up with you?
	return mix(srgbToLinear(skyColor), srgbToLinear(fogColor), fogify(max(upDot, 0.0), 0.25));
}

vec3 screenToView(vec3 screenPos) {
	vec4 ndcPos = vec4(screenPos, 1.0) * 2.0 - 1.0;
	vec4 tmp = gbufferProjectionInverse * ndcPos;
	return tmp.xyz / tmp.w;
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	if (renderStage == MC_RENDER_STAGE_STARS) {
		color = vec4(srgbToLinear(glcolor.rgb), glcolor.a);
	} else {
		vec2 sampleUv = fsr2UnjitterUv(
			gl_FragCoord.xy / vec2(viewWidth, viewHeight)
		);
		vec3 pos = screenToView(vec3(sampleUv, 1.0));
		color = vec4(calcSkyColor(normalize(pos)), 1.0);
	}
}
