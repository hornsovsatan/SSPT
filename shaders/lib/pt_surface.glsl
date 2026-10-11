#ifndef LIGHT_AND_SHADOW_PT_SURFACE_GLSL
#define LIGHT_AND_SHADOW_PT_SURFACE_GLSL

// Two GI-sized planes inside one display-sized image. Offline full-resolution
// samples bypass denoising and this atlas. No extra persistent image is needed:
// colortex9 retains the virtual geometry for temporal reprojection.
uniform sampler2D ptSurfaceSampler;
#ifndef PT_HAS_TRANSLUCENT_UNIFORMS
uniform sampler2D colortex11;
uniform sampler2D colortex12;
#endif

bool ptSurfaceEnabled() {
    ivec2 s = giRenderSizePixels();
    ivec2 a = textureSize(ptSurfaceSampler, 0);
    return !offlineCameraIsStill() && s.x * s.y <= (a.x * a.y) / 2;
}

ivec2 ptSurfaceAddress(ivec2 p, int band) {
    ivec2 s = giRenderSizePixels();
    int index = (band * s.y + p.y) * s.x + p.x;
    int width = textureSize(ptSurfaceSampler, 0).x;
    return ivec2(index % width, index / width);
}

// Low 10 bits retain the raster offset; upper bits identify the mirror chain.
int ptSurfaceClass(vec4 guide) { return int(guide.b) / 1024; }

vec4 ptReadSurface(ivec2 p) {
    if (ptSurfaceEnabled()) return texelFetch(ptSurfaceSampler, ptSurfaceAddress(p, 0), 0);
    ivec2 g = giReceiverPixel(p);
    float depth = texelFetch(depthtex0, g, 0).r;
    vec4 front = texelFetch(colortex11, g, 0);
    vec4 frontNormal = texelFetch(colortex12, g, 0);
    bool translucent = frontNormal.a > 0.5 && front.r > 0.0 && front.r < 1.0;
    if (translucent) depth = front.r;
    if (depth >= 1.0) return vec4(0.0);
    vec2 uv = (vec2(g) + 0.5) / vec2(textureSize(depthtex0, 0));
    vec4 v = gbufferProjectionInverse * vec4(fsr2UnjitterUv(uv) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    // Convert view normals to camera-independent world normals (orthonormal view).
    mat3 toWorld = transpose(mat3(gbufferModelView));
    vec3 n = normalize((translucent ? frontNormal.rgb : texelFetch(colortex1, g, 0).rgb) * 2.0 - 1.0);
    return vec4(giPackNormal(toWorld * giGeometricNormal(g)), giPackNormal(toWorld * n),
        giPackRasterOffset(g, p), v.z / v.w);
}

vec3 ptSurfaceViewPosition(ivec2 p, vec4 guide) {
    vec2 uv = giHistoryRasterUv(p, giRenderSizePixels(), guide.b);
    vec4 ray = gbufferProjectionInverse * vec4(fsr2UnjitterUv(uv) * 2.0 - 1.0, 1.0, 1.0);
    return ray.xyz * (guide.a / ray.z);
}

vec3 ptReadFactor(ivec2 p) {
    return texelFetch(ptSurfaceSampler, ptSurfaceAddress(p, 1), 0).rgb;
}
// Validate the *full-resolution* reflection hit against the reconstructed plane.
bool ptMatchesReplacement(int expectedClass, int actualClass, vec3 expectedPosition,
    vec3 expectedNormal, float actualZ, vec3 actualNormal) {
    return expectedClass == actualClass && expectedClass > 0 && expectedClass < 16 &&
        abs(actualZ - expectedPosition.z) <= max(0.02, abs(expectedPosition.z) * 0.005) &&
        dot(expectedNormal, actualNormal) > 0.95;
}
#endif
