#version 430 compatibility
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const vec2 workGroupsRender = vec2(0.5, 0.5);
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

layout(rgba32f) uniform writeonly image2D giSpatialIntermediate;
uniform sampler2D giSpatialIntermediateSampler;
uniform sampler2D noisetex;
#define GI_SPATIAL_COMPUTE
#include "/lib/gi_sundial.glsl"

void main() {
    if (!giSundialFilterEnabled()) return;
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, giRenderSizePixels()))) return;
    imageStore(giSpatialIntermediate, giScaleAddress(p, 1), giSundialFilter(p, 2));
}
