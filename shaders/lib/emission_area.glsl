#ifndef EMISSION_AREA_GLSL
#define EMISSION_AREA_GLSL
// Fixed-point area, accumulated once per submitted surface, not per voxel copy.
// Owner indirection preserves block identity for protruding/wall-mounted models.
const uint emissionAreaCellCount = 2097152u;
const float emissionAreaUnits = 65536.0;
layout(std430, binding = 3) buffer EmissionAreaBuffer {
    uint emissionBlockArea[2097152];
    uint emissionBlockShape[2097152];
    uint emissionPrimitiveOwner[];
};
float emissionAreaGain(uint owner) {
    if (owner >= emissionAreaCellCount) return 1.0;
    // A full cube's surviving faces must not be boosted when hidden faces
    // were culled by Minecraft. Any partial/model face cancels this exception.
    if (emissionBlockShape[owner] == 1u) return 1.0;
    uint area = emissionBlockArea[owner];
    if (area == 0u) return 1.0;
    return 6.0 * emissionAreaUnits / float(area);
}
#endif
