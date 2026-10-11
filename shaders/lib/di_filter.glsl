#ifndef DI_FILTER_GLSL
#define DI_FILTER_GLSL
#include "/lib/di_options.glsl"
// Reduced Sundial DI profile; GI keeps its original independent constants.
const float DI_HISTORY_STILL = 16.0;
const float DI_HISTORY_MOVING = 8.0;
const int DI_SUNDIAL_RADIUS = 2;
uniform sampler2D diFilterSampler;
#ifdef DI_FILTER_WRITE
layout(rgba32f) uniform writeonly image2D diFilter;
#endif
ivec2 diFilterAddress(ivec2 p,int plane) {
    ivec2 size=giRenderSizePixels();
    int index=(plane*size.y+p.y)*size.x+p.x;
    int width=textureSize(diFilterSampler,0).x;
    return ivec2(index%width,index/width);
}
vec4 diFilterRead(ivec2 p,int plane) {
    return texelFetch(diFilterSampler,diFilterAddress(p,plane),0);
}
#ifdef DI_FILTER_WRITE
void diFilterStore(ivec2 p,int plane,vec4 value) {
    imageStore(diFilter,diFilterAddress(p,plane),value);
}
#endif
bool diFilterEnabled() {
    ivec2 s=giRenderSizePixels(),a=textureSize(diFilterSampler,0);
    return DI_QUALITY>0 && !offlineCameraIsStill() && s.x*s.y<=a.x*a.y/7;
}
int diTemporalPlane() { return 1+2*(frameCounter&1); }
vec3 diFilteredLight(ivec2 p) {
    if(DI_QUALITY==0) return vec3(0.0);
    return giFiniteLight(diFilterRead(p,diFilterEnabled()?5:0).rgb);
}
#endif
