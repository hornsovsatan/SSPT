#version 430 compatibility

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#include "/fsr2/ffx_fsr2_config.glsl"

out vec4 cloudColor;
out float cloudViewDepth;

void main() {
    gl_Position = ftransform();
    fsr2ApplyJitter(gl_Position);
    cloudColor = gl_Color;
    cloudViewDepth = -(gl_ModelViewMatrix * gl_Vertex).z;
}
