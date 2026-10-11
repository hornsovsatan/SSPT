uniform sampler2D gtexture;
#include "/lib/color_space.glsl"
uniform sampler2D specular;
in vec2 texcoord;
in vec4 glcolor;
flat in uint vTraceCopyMode;
flat in uint vTraceCopyOffset;
flat in uint vTraceCopyStride;
flat in uvec2 vTraceCopySize;
flat in uint vTraceCopyLod;
layout(location = 0) out vec4 color;
struct TraceTextureKey {
    uint hash;
    uint bounds;
};
layout(std430, binding = 4) buffer TraceTextureBuffer {
    uint traceTextureLast;
    uint traceTextureReserved;
    TraceTextureKey traceTextureKeys[16];
    uint traceTextureData[];
};
uint packTraceSurfaceTexel(vec4 albedo, float specularAlpha) {
    uvec3 rgb = uvec3(clamp(albedo.rgb, 0.0, 1.0) * 255.0 + 0.5);
    uint specA255 = uint(floor(clamp(specularAlpha, 0.0, 1.0) * 255.0 + 0.5));
    uint materialByte = albedo.a >= 0.1 ? (specA255 < 255u ? specA255 : 0u) : 255u;
    return (rgb.r & 255u)
        | ((rgb.g & 255u) << 8u)
        | ((rgb.b & 255u) << 16u)
        | ((materialByte & 255u) << 24u);
}
void main() {
    if (vTraceCopyMode != 0u) {
        ivec2 texel = ivec2(gl_FragCoord.xy);
        ivec2 storageSize = ivec2(max(vTraceCopySize, uvec2(1u)));
        if (all(greaterThanEqual(texel, ivec2(0))) && all(lessThan(texel, storageSize))) {
            vec2 sourceUV = (vec2(texel) + vec2(0.5)) / vec2(storageSize);
            float sourceLod = float(vTraceCopyLod);
            vec4 data = textureLod(gtexture, sourceUV, sourceLod);
            float specularAlpha = 1.0; // LabPBR alpha 255 is non-emissive.
#ifdef MC_SPECULAR_MAP
            specularAlpha = textureLod(specular, sourceUV, sourceLod).a;
#endif
            uint packedTexelValue = packTraceSurfaceTexel(data, specularAlpha);
            traceTextureData[vTraceCopyOffset + uint(texel.x) + uint(texel.y) * vTraceCopyStride] = packedTexelValue;
        }
        discard;
    }
    color = texture(gtexture, texcoord) * glcolor;
    color.rgb = srgbToLinear(color.rgb);
    if (color.a < 0.1) {
        discard;
    }
}
