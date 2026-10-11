#version 330 compatibility
uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;
in float skyAccess;
#include "/lib/scene_lighting.glsl"

/*
const int colortex14Format = RGBA16F;
*/
const bool colortex14Clear = true;
const vec4 colortex14ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
/* RENDERTARGETS: 14 */
layout(location = 0) out vec4 weatherColor;
void main() {
    vec4 particle = texture(gtexture, texcoord) * glcolor;
    particle.rgb = srgbToLinear(particle.rgb);
    if (particle.a <= 0.001) discard;
    vec3 illumination = vec3(0.08);
    if (sceneHasDirectLight()) {
        illumination += getSceneDirectLight() * sceneDirectSkyAccess(skyAccess);
    }
    // No terrain normal, specular texture or at_midBlock emission attributes.
    // Alpha blending into a cleared buffer stores premultiplied layer RGB.
    weatherColor = vec4(particle.rgb * illumination, clamp(particle.a, 0.0, 1.0));
}
