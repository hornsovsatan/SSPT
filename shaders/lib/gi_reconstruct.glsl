#ifndef LIGHT_AND_SHADOW_GI_RECONSTRUCT_GLSL
#define LIGHT_AND_SHADOW_GI_RECONSTRUCT_GLSL
#include "/lib/gi_common.glsl"
#include "/lib/gi_geometry.glsl"
#include "/lib/pbr_material.glsl"
#include "/lib/di_filter.glsl"

// Metadata describes the last reconstruction, not merely the raster material.
bool ptReconstructionValid = false;
int ptReconstructionClass = 0;
vec3 ptReconstructionPosition = vec3(0.0);
vec3 ptReconstructionNormal = vec3(0.0);
vec3 giViewRay(vec2 screenUv) {
    vec4 p = gbufferProjectionInverse *
        vec4(fsr2UnjitterUv(screenUv) * 2.0 - 1.0, 1.0, 1.0);
    return p.xyz;
}

float ptRasterDepth(ivec2 p) {
    vec4 front = texelFetch(colortex11, p, 0);
    if (texelFetch(colortex12, p, 0).a > 0.5 && front.r > 0.0 && front.r < 1.0) return front.r;
    return texelFetch(depthtex0, p, 0).r;
}

vec3 ptRasterFactor(ivec2 p) {
    return texelFetch(colortex0, p, 0).rgb;
}

vec3 ptRasterPosition(ivec2 p, float depth) {
    vec2 uv = (vec2(p) + 0.5) / vec2(textureSize(depthtex0, 0));
    vec4 v = gbufferProjectionInverse * vec4(fsr2UnjitterUv(uv) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}

vec3 giReconstructFiltered(vec2 screenUv) {
    ptReconstructionValid = false;
    ptReconstructionClass = 0;
    screenUv = giRasterUv(screenUv);
    ivec2 g = giGeometryPixel(screenUv);
    float depth = ptRasterDepth(g);
    if (depth >= 1.0) return vec3(0.0);
    ivec2 size = giRenderSizePixels();
    vec2 grid = giRenderStorageUv(screenUv) / giRenderFraction() * vec2(size) - 0.5;
    if (offlineCameraIsStill()) {
        ivec2 q = clamp(ivec2(round(grid)), ivec2(0), size - 1);
        return (giFiniteLight(texelFetch(colortex8, q, 0).rgb)+diFilteredLight(q)) * ptRasterFactor(giReceiverPixel(q));
    }
    vec3 pos = ptRasterPosition(g, depth);
    vec3 normal = giGeometricNormal(g);
    ivec2 base = ivec2(floor(grid));
    vec2 f = fract(grid);
    // Select a guide on the same *physical* receiver first. Comparing the
    // receiver to virtual mirror depth would reject every replacement surface.
    ivec2 anchor = ivec2(-1);
    float best = 1e30;
    for (int y = -1; y <= 2; ++y) {
        for (int x = -1; x <= 2; ++x) {
            ivec2 q = base + ivec2(x,y);
            if (any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,size))) continue;
            vec4 guide = texelFetch(colortex9,q,0);
            if (guide.a == 0.0) continue;
            ivec2 qg = giReceiverPixel(q);
            float d = ptRasterDepth(qg);
            if (d >= 1.0) continue;
            float w = giGeometryWeight(pos, normal, ptRasterPosition(qg,d), giGeometricNormal(qg));
            if (w < 0.05) continue;
            float score = dot(vec2(q)-grid,vec2(q)-grid) + 1.0-w;
            if (score < best) { best=score; anchor=q; }
        }
    }
    if (anchor.x < 0) return vec3(0.0);
    vec4 centerGuide = texelFetch(colortex9,anchor,0);
    ptReconstructionClass = ptSurfaceClass(centerGuide);
    vec3 centerNormal = normalize(mat3(gbufferModelView) * giUnpackNormal(centerGuide.r));
    vec3 centerPos = ptSurfaceViewPosition(anchor,centerGuide);
    vec3 targetRay = giViewRay(screenUv);
    float denom = dot(targetRay,centerNormal);
    // Intersect the full-resolution viewing ray with the chosen virtual plane.
    vec3 targetPos = abs(denom) > 1e-6 ? targetRay * (dot(centerPos,centerNormal)/denom) : centerPos;
    vec3 factor = ptSurfaceClass(centerGuide) > 0 && ptSurfaceEnabled()
        ? ptReadFactor(anchor) : ptRasterFactor(g);
    vec3 nearSum=vec3(0), wideSum=vec3(0);
    float nearWeight=0.0, wideWeight=0.0;
    for (int y=-1;y<=2;++y) {
        for (int x=-1;x<=2;++x) {
            ivec2 q=base+ivec2(x,y);
            if (any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,size))) continue;
            vec4 guide=texelFetch(colortex9,q,0);
            if (guide.a==0.0 || ptSurfaceClass(guide)!=ptSurfaceClass(centerGuide)) continue;
            ivec2 qg=giReceiverPixel(q);
            float d=ptRasterDepth(qg);
            if (d>=1.0) continue;
            float w=giGeometryWeight(pos,normal,ptRasterPosition(qg,d),giGeometricNormal(qg));
            vec3 qNormal=normalize(mat3(gbufferModelView)*giUnpackNormal(guide.r));
            w*=giGeometryWeight(targetPos,centerNormal,ptSurfaceViewPosition(q,guide),qNormal);
            vec3 value=(giFiniteLight(texelFetch(colortex8,q,0).rgb)+diFilteredLight(q));
            if(x>=0 && x<=1 && y>=0 && y<=1) {
                vec2 b=mix(1.0-f,f,vec2(x,y));
                float nw=w*b.x*b.y;
                nearSum+=value*nw; nearWeight+=nw;
            }
            vec2 tent=max(1.0-abs(vec2(q)-grid)*0.5,vec2(0));
            float ww=w*tent.x*tent.y;
            wideSum+=value*ww; wideWeight+=ww;
        }
    }
    float supplement=1.0-smoothstep(0.05,0.5,nearWeight);
    float totalWeight = nearWeight + wideWeight * supplement;
    ptReconstructionPosition = targetPos;
    ptReconstructionNormal = centerNormal;
    ptReconstructionValid = ptReconstructionClass > 0 && ptReconstructionClass < 16 &&
        ptSurfaceEnabled() && totalWeight > 1e-6 &&
        texelFetch(ptSurfaceSampler, ptSurfaceAddress(anchor, 1), 0).a > 0.5;
    return (nearSum+wideSum*supplement)/max(totalWeight,1e-8)*factor;
}
#endif
