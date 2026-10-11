#version 330 compatibility

uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;
#include "/lib/color_space.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    // Vanilla multiplies texture and vertex tint in display space. Decode the
    // result once before it enters our linear HDR/FSR pipeline; keep alpha.
    vec4 sky = texture(gtexture, texcoord) * glcolor;
    color = vec4(srgbToLinear(sky.rgb), sky.a);
}
