#version 330 compatibility
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#include "fsr2/ffx_fsr2_config.glsl"
out vec2 texcoord;
out vec4 glcolor;
out float skyAccess;
void main() {
    gl_Position = ftransform();
    // Match scene depth for visibility testing; the final pass removes jitter.
    fsr2ApplyJitter(gl_Position);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
    float skyCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).y;
    skyAccess = clamp((skyCoord - 0.03125) / 0.9375, 0.0, 1.0);
}
