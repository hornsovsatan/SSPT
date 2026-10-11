in vec4 at_midBlock;
#include "/lib/block_emission.glsl"
in vec4 mc_Entity;
out vec2 vTexcoord;
out vec4 vGlcolor;
out vec3 vTracePlayerPos;
out vec4 vTraceSkyLight;
out float vTraceEmission;
out vec3 vTraceBlockCenter;
flat out uint vTracePointLight;
flat out uint vTraceValid;
flat out int vTraceQuadMarker;
uniform mat4 shadowModelViewInverse;
uniform vec3 cameraPosition;
uniform sampler2D gtexture;
#include "/lib/scene_lighting.glsl"
vec3 getTracePlayerPos() {
    vec4 shadowViewPos = gl_ModelViewMatrix * gl_Vertex;
    return (shadowModelViewInverse * shadowViewPos).xyz;
}
void main() {
    int blockId = int(mc_Entity.x);
    vTracePointLight = hasTerrainBlockAttributes() && blockId >= 32000 && blockId <= 32015 ? uint(blockId - 31999) : 0u;
    gl_Position = ftransform();
    gl_Position.xyz = distortShadowClipPos(gl_Position.xyz);
    vTexcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vGlcolor = gl_Color;
    vec3 tracePlayerPos = getTracePlayerPos() + fract(cameraPosition);
    vTracePlayerPos = tracePlayerPos;
    vTraceBlockCenter = tracePlayerPos + (hasTerrainBlockAttributes() ? at_midBlock.xyz / 64.0 : vec3(0.0));
    float emission = terrainBlockEmission(at_midBlock);
    vec4 albedo = textureLod(gtexture, vTexcoord, 0.0) * vGlcolor;
    float skyAccess = 0.0;
    if (sceneStoresSkyAccess()) {
        float skyCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).y;
        skyAccess = clamp((skyCoord - 0.03125) / 0.9375, 0.0, 1.0);
    }
    // Trace payload stores sky access, not lightmap RGB.
    vTraceSkyLight = vec4(vec3(skyAccess), skyAccess);
    vTraceEmission = emission;
    vTraceValid = albedo.a >= 0.1 ? 1u : 0u;
    // Iris uses mc_Entity.y == 0 for the ordinary paired triangles emitted
    // from a Minecraft quad.  The geometry stage rejects the second member.
    vTraceQuadMarker = hasTerrainBlockAttributes() ? int(mc_Entity.y) : 1;
}
