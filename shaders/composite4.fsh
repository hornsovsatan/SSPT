#version 330 compatibility
uniform sampler2D colortex4;
uniform sampler2D colortex7;
uniform sampler2D colortex1;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
#include "/lib/gi_common.glsl"

uniform sampler2D giSpatialIntermediateSampler;
uniform sampler2D noisetex;
in vec2 texcoord;
/* RENDERTARGETS: 8 */
layout(location = 0) out vec4 outBlur;
#include "/lib/gi_sundial.glsl"

void main() {
    ivec2 p = ivec2(gl_FragCoord.xy);
    if (offlineCameraIsStill()) {
        outBlur = texelFetch(colortex4, p, 0);
        return;
    }
    outBlur = giFilterScales(p);
}
