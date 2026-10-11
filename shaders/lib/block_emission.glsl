#ifndef BLOCK_EMISSION_GLSL
#define BLOCK_EMISSION_GLSL
// at_midBlock is terrain data, not entity/hand/particle emission metadata.
// https://shaders.properties/current/reference/attributes/at_midblock/
uniform int renderStage;
bool hasTerrainBlockAttributes() {
    return renderStage==MC_RENDER_STAGE_TERRAIN_SOLID ||
        renderStage==MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED ||
        renderStage==MC_RENDER_STAGE_TERRAIN_CUTOUT ||
        renderStage==MC_RENDER_STAGE_TERRAIN_TRANSLUCENT ||
        renderStage==MC_RENDER_STAGE_TRIPWIRE;
}
float terrainBlockEmission(vec4 midBlock) {
    return hasTerrainBlockAttributes() ? clamp(midBlock.w/15.0,0.0,1.0) : 0.0;
}
#endif
