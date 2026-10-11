#ifndef DI_SAMPLING_GLSL
#define DI_SAMPLING_GLSL
#include "/lib/di_options.glsl"
const float DI_PI = 3.14159265359;
layout(rgba32f) uniform writeonly image2D diReservoir0;
layout(rgba32f) uniform writeonly image2D diReservoir1;
uniform sampler2D diReservoirSampler0;
uniform sampler2D diReservoirSampler1;
bool diActive(vec3 position) {
    return DI_QUALITY > 0 && diLightCount > 0u &&
        traceVoxelInside(traceVoxelHalf + ivec3(floor(position)));
}
uint diCount() { return min(diLightCount,diLightCapacity); }
// A power proposal for large light sets; receiver-distance weighting for small
// scenes. Uniform mixture retains support when a textured power estimate misses
// a tiny emitting texel or the floating-point CDF loses a small increment.
const float DI_UNIFORM_MIX = 0.05;
float diLocalCDF[64];
bool diLocalProposal=false;
float diProposalTotal=0.0;
float diMISCount=1.0;
void diPrepareProposal(vec3 origin,bool reuse,bool secondary) {
    uint count=diCount();
    diLocalProposal=count<=64u;
    diProposalTotal=0.0;
    diMISCount=float(max(DI_QUALITY,1));
    if(diLocalProposal) {
        for(uint i=0u;i<count;++i) {
            vec4 proxy=diLightProxy[i];
            vec3 delta=proxy.xyz-origin;
            // Finite-area softening prevents a receiver on an emitter from
            // monopolizing the proposal at zero distance.
            float weight=proxy.w/max(dot(delta,delta)+diLights[i].p0.w,1e-4);
            diProposalTotal+=weight;diLocalCDF[i]=diProposalTotal;
        }
    } else diProposalTotal=diLightCDF[count-1u];
}
float diCDF(uint index) {
    if(diLocalProposal) return diLocalCDF[index];
    return diLightCDF[index];
}
float diSelectionPdf(uint id) {
    float uniformPdf=1.0/float(diCount());
    if(diProposalTotal<=0.0) return uniformPdf;
    float interval=max(diCDF(id)-(id==0u ? 0.0 : diCDF(id-1u)),0.0);
    return DI_UNIFORM_MIX*uniformPdf+(1.0-DI_UNIFORM_MIX)*interval/diProposalTotal;
}
uint diSelectLight(float u) {
    uint count=diCount();
    if(diProposalTotal<=0.0) return min(uint(u*float(count)),count-1u);
    if(u<DI_UNIFORM_MIX) return min(uint(u/DI_UNIFORM_MIX*float(count)),count-1u);
    float value=(u-DI_UNIFORM_MIX)/(1.0-DI_UNIFORM_MIX)*diProposalTotal;
    uint low=0u,high=count-1u;
    while(low<high) {
        uint mid=(low+high)/2u;
        if(value<diCDF(mid)) high=mid;else low=mid+1u;
    }
    return low;
}
// Matching power-heuristic partitions on both NEE and emitter-hit paths.
// The fixed candidate count steers energy toward the resampled estimator;
// it is not treated as the unknown post-resampling PDF.
float diNEEWeight(float lightPdf,float bsdfPdf) {
    float a=diMISCount*lightPdf,b=bsdfPdf;
    float scale=max(max(a,b),1e-20);a/=scale;b/=scale;
    return a*a/max(a*a+b*b,1e-20);
}
ivec2 diAddress(ivec2 p,int plane) {
    ivec2 s=giRenderSizePixels();
    int i=(plane*s.y+p.y)*s.x+p.x;
    int width=textureSize(diReservoirSampler0,0).x;
    return ivec2(i%width,i/width);
}
bool diStorageEnabled() {
    if(DI_QUALITY==0) return false;
    ivec2 s=giRenderSizePixels(), a=textureSize(diReservoirSampler0,0);
    return s.x*s.y <= a.x*a.y/3;
}
vec4 diPrevious(ivec2 p,int plane) {
    return (frameCounter&1)==0 ? texelFetch(diReservoirSampler1,diAddress(p,plane),0)
        : texelFetch(diReservoirSampler0,diAddress(p,plane),0);
}
void diWrite(ivec2 p,int plane,vec4 v) {
    if (!diStorageEnabled()) return;
    if ((frameCounter&1)==0) imageStore(diReservoir0,diAddress(p,plane),v);
    else imageStore(diReservoir1,diAddress(p,plane),v);
}
// Area-domain sample. The UV square maps uniformly to a triangle or quad.
void diSample(uint id,vec2 xi,out vec3 point,out vec3 normal,out vec3 emission) {
    DILight l=diLights[id];
    vec2 b=xi;
    if (l.meta.z==0u) { float r=sqrt(xi.x); b=vec2(r*(1.0-xi.y),r*xi.y); }
    point=l.p0.xyz+l.e1.xyz*b.x+l.e2.xyz*b.y;
    normal=normalize(cross(l.e1.xyz,l.e2.xyz));
    bool atlas=getTracePrimitiveTextureIndex(l.data.w)==TRACE_TEXTURE_INDEX_ATLAS;
    vec2 uv0=unpackTraceUV(l.data.x,atlas),uv1=unpackTraceUV(l.data.y,atlas),uv2=unpackTraceUV(l.data.z,atlas);
    vec2 uv=uv0+(uv1-uv0)*b.x+(l.meta.z!=0u ? uv2-uv1 : uv2-uv0)*b.y;
    if (atlas) {
        vec2 uv3=uv0+uv2-uv1;
        vec2 lo=min(uv0,min(uv1,uv2)),hi=max(uv0,max(uv1,uv2));
        if(l.meta.z!=0u){lo=min(lo,uv3);hi=max(hi,uv3);}
        vec2 inset=min(0.5/vec2(textureSize(traceBlockAtlas,0)),(hi-lo)*0.5);
        uv=clamp(uv,lo+inset,hi-inset);
    }
    TraceSurfaceSample s=sampleTracePrimitiveSurface(getTracePrimitiveTextureIndex(l.data.w),uv,l.data.w);
    float e=clamp(unpackTracePrimitiveEmission(l.data.w)+s.labEmission,0.0,1.0);
    emission=s.albedo.rgb*e*emissionAreaGain(l.meta.y)*LABPBR_EMISSION_STRENGTH;
    // Matches traceTriangleWorld: transmitting faces do not terminate a path.
    if(s.albedo.a<TRACE_TRANSPARENT_ALPHA) emission=vec3(0.0);
}
float diLightPdf(uint id,vec3 origin,vec3 point,vec3 lightNormal) {
    vec3 d=point-origin;float d2=dot(d,d);
    float c=abs(dot(lightNormal,normalize(d)));
    return diSelectionPdf(id)*d2/max(c*diLights[id].p0.w,1e-20);
}
vec3 diIntegrand(uint id,vec2 xi,vec3 origin,vec3 normal,vec3 baseColor,
    LabPBRSpecularData material,float NoV,bool secondary,out vec3 point) {
    vec3 ln,le;diSample(id,xi,point,ln,le);
    vec3 delta=point-origin;float d2=dot(delta,delta);
    if(d2<1e-8) return vec3(0.0);
    vec3 direction=delta*inversesqrt(d2);
    float cosine=max(dot(normal,direction),0.0), lc=abs(dot(ln,direction));
    float bsdfPdf=cosine/DI_PI;
    float lightPdf=diLightPdf(id,origin,point,ln);
    // Match the emitter-hit partition using this receiver's exact proposal PDF.
    float mis=diNEEWeight(lightPdf,bsdfPdf);
    vec3 f=le*(cosine*lc/(DI_PI*d2))*mis;
#ifdef MC_SPECULAR_MAP
    if(secondary) f*=pbrDiffuseWeight(baseColor,material,NoV,cosine);
#endif
    return f;
}
vec3 diVisibility(vec3 origin,vec3 point,uint id) {
    vec3 d=point-origin;float distance=length(d);
    if(distance<1e-4) return vec3(0.0);
    TriHit h=traceTriangleWorld(origin,d/distance,distance+0.025);
    return h.hit && h.diLight==id && abs(h.t-distance)<0.025 ? h.transmittance : vec3(0.0);
}
float diBSDFWeight(TriHit hit,vec3 origin,vec3 normal,vec3 direction) {
    if(!diActive(origin) || !hit.hit || hit.screenSpace || hit.diLight>=diCount()) return 1.0;
    float pb=max(dot(normal,direction),0.0)/DI_PI;
    float pl=diLightPdf(hit.diLight,origin,hit.position,hit.normal);
    return 1.0-diNEEWeight(pl,pb);
}
struct DIReservoir { uint id; vec2 xi; float sum; float M; float target; };
// Strictly positive unoccluded target retains support across receiver normals.
float diTarget(vec3 f) { return max(luminance3(f),1e-10); }
bool diUpdate(inout DIReservoir r,uint id,vec2 xi,float weight,float count,float target,float randomValue) {
    if(isnan(weight)||isinf(weight)||weight<0.0||count<=0.0) return false;
    r.M+=count;r.sum+=weight;
    if(weight>0.0 && randomValue*r.sum<weight) { r.id=id;r.xi=xi;r.target=target; return true; }
    return false;
}
vec3 diEstimate(vec3 position,vec3 normal,vec3 baseColor,LabPBRSpecularData material,
    float NoV,bool secondary,uint dimension,bool reuse) {
    vec3 origin=position+normal*TRIANGLE_GI_NORMAL_BIAS;
    if(!diActive(origin)) return vec3(0.0);
    diPrepareProposal(origin,reuse,secondary);
    ivec2 pixel=ivec2(gl_FragCoord.xy);
    DIReservoir r=DIReservoir(DI_INVALID,vec2(0.0),0.0,0.0,0.0);
    int candidates=max(DI_QUALITY,1);
    for(int k=0;k<candidates;++k) {
        vec2 choose=ptRandomPair(pixel,frameCounter,dimension+uint(k)*3u);
        uint id=diSelectLight(choose.x);
        vec2 xi=ptRandomPair(pixel,frameCounter,dimension+uint(k)*3u+1u);
        vec3 point;vec3 f=diIntegrand(id,xi,origin,normal,baseColor,material,NoV,secondary,point);
        float target=diTarget(f);
        diUpdate(r,id,xi,target*diLights[id].p0.w/diSelectionPdf(id),1.0,target,choose.y);
    }
    if(r.id==DI_INVALID || r.M<=0.0) return vec3(0.0);
    vec3 selectedPoint;
    vec3 unoccluded=diIntegrand(r.id,r.xi,origin,normal,baseColor,material,NoV,secondary,selectedPoint);
    vec3 selectedValue=unoccluded;
    if(luminance3(unoccluded)>0.0) selectedValue*=diVisibility(origin,selectedPoint,r.id);
    // Convert the fresh RIS group to a visibility-aware proposal before merging
    // history. Retain positive support for a formerly hidden sample becoming lit.
    float initialW=r.sum/(r.M*r.target);
    r.target=diTarget(selectedValue)+0.02*luminance3(unoccluded);
    r.sum=r.target*initialW*r.M;
    bool historyAllowed=reuse && DI_QUALITY>0 && diStorageEnabled() && frameCounter>1 && !sceneLightHistoryChanged();
    if(historyAllowed) {
        vec3 prevPlayer=position-fract(cameraPosition)+cameraPosition-previousCameraPosition;
        vec4 clip=gbufferPreviousProjection*gbufferPreviousModelView*vec4(prevPlayer,1.0);
        vec2 uv=clip.xy/max(clip.w,1e-8)*0.5+0.5;
        ivec2 center=ivec2(floor(uv*vec2(giRenderSizePixels())));
        for(int j=0;j<3;++j) {
            vec2 randomOffset=ptRandomPair(pixel,frameCounter,dimension+200u+uint(j));
            ivec2 offset=j==0 ? ivec2(0) : ivec2(round((randomOffset*2.0-1.0)*4.0));
            if(j>0 && all(equal(offset,ivec2(0)))) continue;
            ivec2 q=center+offset;
            if(clip.w<=0.0||any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,giRenderSizePixels()))) continue;
            vec4 a=diPrevious(q,0),b=diPrevious(q,1),c=diPrevious(q,2);
            // Numeric ID/hash halves avoid NaN payloads in RGBA32F images.
            if(c.w!=float(frameCounter-1)||b.w<=0.0||a.w<=0.0) continue;
            uint id=uint(a.x);
            uint hash=uint(c.y)|(uint(c.z)<<16u);
            if(id>=diCount() || hash!=diLights[id].meta.x) {
                id=DI_INVALID;
                for(uint probe=0u;probe<32u;++probe) {
                    uint candidate=diLightLookup[(hash+probe)&32767u];
                    if(candidate==DI_INVALID) break;
                    if(candidate<diCount() && diLights[candidate].meta.x==hash) {id=candidate;break;}
                }
            }
            if(id>=diCount() || dot(normal,giUnpackNormal(c.x))<0.97) continue;
            vec3 prevPosition=b.xyz+floor(previousCameraPosition)-floor(cameraPosition);
            vec3 delta=prevPosition-position;
            if(abs(dot(delta,normal))>0.03 || length(delta)>1.0) continue;
            vec3 point;vec3 f=diIntegrand(id,a.yz,origin,normal,baseColor,material,NoV,secondary,point);
            vec3 visible=f;
            if(luminance3(f)>0.0) visible*=diVisibility(origin,point,id);
            float target=diTarget(visible)+0.02*luminance3(f);
            float count=min(b.w,j==0 ? 32.0 : 8.0);
            if(diUpdate(r,id,a.yz,target*a.w*count,count,target,
                ptRandomPair(pixel,frameCounter,dimension+300u+uint(j)).x)) selectedValue=visible;
        }
    }
    if(r.id==DI_INVALID || r.M<=0.0) return vec3(0.0);
    float W=r.sum/(r.M*r.target);
    if(isnan(W)||isinf(W)) return vec3(0.0);
    if(reuse && DI_QUALITY>0) {
        uint hash=diLights[r.id].meta.x;
        diWrite(pixel,0,vec4(float(r.id),r.xi,W));
        diWrite(pixel,1,vec4(position,min(r.M,64.0)));
        diWrite(pixel,2,vec4(giPackNormal(normal),float(hash&65535u),float(hash>>16u),float(frameCounter)));
    }
    // selectedValue already contains this frame's verified visibility.
    return selectedValue*W;
}
#endif
