// Adapted directly from the existing gi_sundial.glsl Sundial implementation.
// Reduced profile: 2 directional scales, radius <= 2 GI texels, 16/8-frame history.
// GI geometry/noise helpers are shared; radiance, variance and history stay separate.
vec4 diSundialPrepare(ivec2 p) {
    ivec2 size = giRenderSizePixels();
    vec3 color = diFilterRead(p,diTemporalPlane()).rgb;
    vec3 sum = color, sum2 = color * color;
    float neighborhoodWeight = 1.0;
    vec4 geometry = giSundialGeometryRecord(p);
    if (geometry.a < 0.5) return vec4(0.0);
    vec3 geo = giUnpackNormal(geometry.r);
    vec3 pos = giSundialViewPosition(p, geometry.b);
    const ivec2 neighbors[8] = ivec2[8](ivec2(0,-1), ivec2(1,-1), ivec2(1,0), ivec2(1,1),
        ivec2(0,1), ivec2(-1,1), ivec2(-1,0), ivec2(-1,-1));
    for (int i = 0; i < 8; ++i) {
        ivec2 q = clamp(p + neighbors[i], ivec2(0), size - 1);
        vec3 sampleColor = diFilterRead(q,diTemporalPlane()).rgb;
        vec4 qGeometry = giSundialGeometryRecord(q);
        float w = 0.0;
        if (qGeometry.a == geometry.a) {
            vec3 qPos = giSundialViewPosition(q, qGeometry.b);
            w = giGeometryWeight(pos, geo, qPos, giUnpackNormal(qGeometry.r));
        }
        // Do not borrow a mature neighbor's age across newly exposed surfaces.
        w = clamp(w, 0.0, 1.0);
        sum += sampleColor * w;
        sum2 += sampleColor * sampleColor * w;
        neighborhoodWeight += w;
    }
    return denoisePrepareRecovery(color, sum / neighborhoodWeight, sum2 / neighborhoodWeight,
        max(mod(diFilterRead(p,diTemporalPlane()+1).a,32.0), 1.0), 8.0, 1.0);
}

vec4 diSundialFilter(ivec2 p, int stage) {
    // Keep only Sundial's first horizontal/vertical scales, with bounded jitter.
    const vec2 offsets[2]=vec2[2](vec2(1,0),vec2(0,1));
    ivec2 size = giRenderSizePixels();
    vec4 center = diFilterRead(p,stage==0?5:6);
    vec4 geometry = giSundialGeometryRecord(p);
    if (geometry.w < 0.5) return vec4(0.0);
    vec3 geo, normal;
    giSundialDecodeNormals(geometry, geo, normal);
    vec3 pos = giSundialViewPosition(p, geometry.b);
    // Compare the current spatial result; raw temporal history stays untouched.
    vec3 guide = center.rgb;
    float confidence = denoiseHistoryConfidence(max(mod(diFilterRead(p,diTemporalPlane()+1).a,32.0), 1.0));
    float variance = max(center.a, 1e-20);
    float guideEnergy = dot(guide, guide) + 1e-6;
    float normalFactor = 64.0 * exp2(-0.15 * length(pos) / guideEnergy * variance);
    normalFactor *= confidence;
    // Preserve the source's conversion/rounding, including the negative diagonal.
    ivec2 delta = ivec2(offsets[stage] * (2.0 * giSundialNoise(p) + 1.0) *
        exp(-0.1 / (variance + 0.2)) + 0.5);
    delta=clamp(delta,ivec2(-DI_SUNDIAL_RADIUS),ivec2(DI_SUNDIAL_RADIUS));
    vec3 sum = center.rgb;
    float varianceSum = variance, sumW = 1.0;
    for (int i = 0; i < 2; ++i) {
        ivec2 q = p + delta;
        delta = -delta;
        if (any(greaterThanEqual(uvec2(q), uvec2(size)))) continue;
        vec4 qGeometry = giSundialGeometryRecord(q);
        if (qGeometry.w < 0.5 || qGeometry.w != geometry.w) continue;
        vec3 qGeo, qNormal;
        giSundialDecodeNormals(qGeometry, qGeo, qNormal);
        vec3 qPos = giSundialViewPosition(q, qGeometry.b);
        vec4 qData = diFilterRead(q,stage==0?5:6);
        vec3 qGuide = qData.rgb;
        float colorWeight = denoiseRecoveryColorWeight(guide, qGuide, variance, confidence);
        float weight = colorWeight * exp2(
            -144.269502 * abs(dot(qPos - pos, geo)) +
            normalFactor * log2(clamp(dot(qNormal, normal), 1e-20, 1.0)) +
            64.0 * log2(clamp(dot(qGeo, geo), 1e-20, 1.0)));
        weight = clamp(weight, 0.0, 1.0);
        sum += qData.rgb * weight;
        varianceSum += max(qData.a, 0.0) * weight * weight;
        sumW += weight;
    }
    return vec4(sum / sumW, varianceSum / (sumW * sumW));
}


void diSundialPass(ivec2 p,int stage) {
    if(!diFilterEnabled() || any(greaterThanEqual(p,giRenderSizePixels()))) return;
    if(stage<0) diFilterStore(p,5,diSundialPrepare(p));
    else diFilterStore(p,stage==0?6:5,diSundialFilter(p,stage));
}
