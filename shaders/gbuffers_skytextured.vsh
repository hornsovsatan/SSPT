#version 330 compatibility

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#include "fsr2/ffx_fsr2_config.glsl"

#if defined(IS_IRIS) && MC_VERSION >= 260200
uniform vec3 endFlashPosition;

vec4 restoreEndSkyTint(vec4 vertexColor, vec3 position, vec3 flashPosition) {
    // Iris 1.11.4 maps END_SKY to SKY_TEXTURED (POSITION_TEX), dropping
    // Minecraft's 0xff282828 vertex color. Its sky cube has +/-100 corners;
    // celestial/flash quads have local y=0. Only repair the missing white tint.
    bool endSkyCube = dot(flashPosition, flashPosition) > 1.0 &&
        all(lessThan(abs(abs(position) - vec3(100.0)), vec3(0.01)));
    if (endSkyCube && all(equal(vertexColor.rgb, vec3(1.0)))) {
        vertexColor.rgb = vec3(40.0 / 255.0);
    }
    return vertexColor;
}
#endif

out vec2 texcoord;
out vec4 glcolor;

void main() {
    gl_Position = ftransform();
    fsr2ApplyJitter(gl_Position);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
#if defined(IS_IRIS) && MC_VERSION >= 260200
    glcolor = restoreEndSkyTint(glcolor, gl_Vertex.xyz, endFlashPosition);
#endif
}
