#version 330 compatibility
uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform vec3 shadowLightPosition;
uniform float alphaTestRef = 0.1;
in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 tangent;
in float vEmission;
#include "/lib/scene_lighting.glsl"
/* RENDERTARGETS: 0,1,3,5,15 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 n;
layout(location = 2) out vec4 lights;
layout(location = 3) out vec4 ambient;
layout(location = 4) out vec4 geometricData;

void main() {
    geometricData = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
	color = texture(gtexture, texcoord) * glcolor;
    color.rgb = srgbToLinear(color.rgb);
    vec4 specTex = vec4(0.0,0.0,0.0,1.0);
#ifdef MC_SPECULAR_MAP
    specTex = texture(specular, texcoord);
#endif
	float specA255 = floor(clamp(specTex.a, 0.0, 1.0) * 255.0 + 0.5);
	float labEmission = specA255 < 255.0 ? specA255 / 254.0 : 0.0;
	float emission = labEmission;
	float smoothness = specTex.r; 
	float roughness = pow(1.0 - smoothness, 2.0); 
	float metalness = specTex.g;
	// Screen-space fallback seed: use the terrain-provided mid-block light
	// directly. Do not derive this channel from the lightmap coordinate.
	lights = vec4(emission, roughness, metalness, vEmission);
	vec3 lightVector = normalize(shadowLightPosition);
    vec3 bitangent = cross(normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, normal);
	vec4 nTex = texture(normals, texcoord);
	vec2 xy = nTex.rg * 2.0 - 1.0;
	xy.y = -xy.y;
	vec3 tangentNormal = normalize(vec3(
		xy,
		sqrt(max(0.0, 1.0 - dot(xy, xy)))
	));
	vec3 mappedNormal = normalize(TBN * tangentNormal);
	n = vec4(mappedNormal/2+0.5,nTex.b);
	float NdotL = 1.0;
	if (sceneHasDirectLight()) NdotL = clamp(dot(lightVector, mappedNormal), 0.0, 1.0);
	// Vanilla lightmap coordinates address the centre of 16 light levels:
	// level 0 is 1/32 and level 15 is 31/32.
	float decodedSkyLevel = clamp((lmcoord.g - 0.03125) / 0.9375, 0.0, 1.0);
	float skyVisibility = sceneStoresSkyAccess()
		? decodedSkyLevel
		: 0.0;
	// RGB is shaded surface lighting; alpha remains an unshadowed indication
	// that a path is actually connected to the sky.
	ambient = vec4(getSceneDirectLight() * sceneDirectSkyAccess(skyVisibility) * NdotL, skyVisibility);
	if (color.a < alphaTestRef) {
		discard;
	}
}
