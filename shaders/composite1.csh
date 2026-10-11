#version 430 compatibility
layout(local_size_x=256) in;
const ivec3 workGroups=ivec3(1,1,1);
#include "/lib/di_lights.glsl"
#include "/lib/emission_area.glsl"
shared float blockSum[256];
void main() {
    if(DI_QUALITY==0) return;
    uint lane=gl_LocalInvocationID.x,count=min(diLightCount,diLightCapacity);
    uint start=lane*64u,end=min(start+64u,count);
    float sum=0.0;
    for(uint i=start;i<end;++i) {
        float power=diLightProxy[i].w*emissionAreaGain(diLights[i].meta.y);
        diLightProxy[i].w=power;
        sum+=power;diLightCDF[i]=sum;
    }
    blockSum[lane]=sum;
    barrier();
    if(lane==0u) {
        float prefix=0.0;
        for(uint i=0u;i<256u;++i) {float v=blockSum[i];blockSum[i]=prefix;prefix+=v;}
    }
    barrier();
    for(uint i=start;i<end;++i) diLightCDF[i]+=blockSum[lane];
}
