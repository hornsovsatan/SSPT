#ifndef LIGHT_AND_SHADOW_PBR_MATERIAL_GLSL
#define LIGHT_AND_SHADOW_PBR_MATERIAL_GLSL

#define PBR_DIELECTRIC_F0 0.04
#define PBR_LABPBR_HARDCODED_METALS 1
#define PBR_GGX_MIN_ALPHA 0.002

vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    float f = pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
    return F0 + (1.0 - F0) * f;
}
struct LabPBRSpecularData {
    vec3 F0;
    vec3 eta;
    vec3 k;
    vec3 reflectionTint;
    float metalness;
    float hardcodedMetal;
};
vec3 fresnelConductor(float cosTheta, vec3 eta, vec3 k) {
    float c = clamp(cosTheta, 0.0, 1.0);
    float cos2 = c * c;
    float sin2 = 1.0 - cos2;
    vec3 eta2 = eta * eta;
    vec3 k2 = k * k;
    vec3 t0 = eta2 - k2 - vec3(sin2);
    vec3 a2PlusB2 = sqrt(max(t0 * t0 + 4.0 * eta2 * k2, vec3(0.0)));
    vec3 t1 = a2PlusB2 + vec3(cos2);
    vec3 a = sqrt(max(0.5 * (a2PlusB2 + t0), vec3(0.0)));
    vec3 t2 = 2.0 * c * a;
    vec3 Rs = (t1 - t2) / max(t1 + t2, vec3(1e-7));
    vec3 t3 = cos2 * a2PlusB2 + vec3(sin2 * sin2);
    vec3 t4 = t2 * sin2;
    vec3 Rp = Rs * (t3 - t4) / max(t3 + t4, vec3(1e-7));
    return clamp(0.5 * (Rp + Rs), vec3(0.0), vec3(1.0));
}
void getLabPBRHardcodedMetalIOR(int materialByte, out vec3 eta, out vec3 k) {
    // LabPBR predefined conductor optical constants (N/K), IDs 230-237.
    if (materialByte == 230) { // Iron
        eta = vec3(2.9114, 2.9497, 2.5845);
        k = vec3(3.0893, 2.9318, 2.7670);
    } else if (materialByte == 231) { // Gold
        eta = vec3(0.18299, 0.42108, 1.3734);
        k = vec3(3.4242, 2.3459, 1.7704);
    } else if (materialByte == 232) { // Aluminum
        eta = vec3(1.3456, 0.96521, 0.61722);
        k = vec3(7.4746, 6.3995, 5.3031);
    } else if (materialByte == 233) { // Chrome
        eta = vec3(3.1071, 3.1812, 2.3230);
        k = vec3(3.3314, 3.3291, 3.1350);
    } else if (materialByte == 234) { // Copper
        eta = vec3(0.27105, 0.67693, 1.3164);
        k = vec3(3.6092, 2.6248, 2.2921);
    } else if (materialByte == 235) { // Lead
        eta = vec3(1.9100, 1.8300, 1.4400);
        k = vec3(3.5100, 3.4000, 3.1800);
    } else if (materialByte == 236) { // Platinum
        eta = vec3(2.3757, 2.0847, 1.8453);
        k = vec3(4.2655, 3.7153, 3.1365);
    } else { // 237, Silver
        eta = vec3(0.15943, 0.14512, 0.13547);
        k = vec3(3.9291, 3.1900, 2.3808);
    }
}
LabPBRSpecularData decodeLabPBRSpecular(float encodedGreen, vec3 baseColor) {
    LabPBRSpecularData data;
    data.F0 = vec3(PBR_DIELECTRIC_F0);
    data.eta = vec3(1.0);
    data.k = vec3(0.0);
    data.reflectionTint = vec3(1.0);
    data.metalness = 0.0;
    data.hardcodedMetal = 0.0;
#if PBR_LABPBR_HARDCODED_METALS == 1
    int materialByte = int(floor(clamp(encodedGreen, 0.0, 1.0) * 255.0 + 0.5));
    if (materialByte <= 229) {
        data.F0 = vec3(max(float(materialByte) / 255.0, PBR_DIELECTRIC_F0));
    } else {
        data.metalness = 1.0;
        if (materialByte <= 237) {
            getLabPBRHardcodedMetalIOR(materialByte, data.eta, data.k);
            data.reflectionTint = clamp(baseColor, vec3(0.0), vec3(1.0));
            data.F0 = fresnelConductor(1.0, data.eta, data.k) * data.reflectionTint;
            data.hardcodedMetal = 1.0;
        } else {
            data.F0 = clamp(baseColor, vec3(0.0), vec3(1.0));
        }
    }
#else
    data.metalness = clamp(encodedGreen, 0.0, 1.0);
    data.F0 = mix(vec3(PBR_DIELECTRIC_F0), baseColor, data.metalness);
#endif
    return data;
}
vec3 fresnelLabPBR(
    float cosTheta,
    vec3 F0,
    vec3 eta,
    vec3 k,
    vec3 reflectionTint,
    float hardcodedMetal
) {
    if (hardcodedMetal > 0.5) {
        return fresnelConductor(cosTheta, eta, k) * reflectionTint;
    }
    return fresnelSchlick(cosTheta, F0);
}

// pi * Lambert BRDF with conservative Fresnel attenuation on both sides.
// The GI cosine PDF cancels the incident cosine and 1/pi.
vec3 pbrDiffuseWeight(vec3 baseColor, LabPBRSpecularData material, float NoV, float NoL) {
    if (NoV <= 0.0 || NoL <= 0.0 || material.metalness >= 1.0) return vec3(0.0);
    vec3 exitTransmission = vec3(1.0) - fresnelSchlick(NoV, material.F0);
    vec3 entryTransmission = vec3(1.0) - fresnelSchlick(NoL, material.F0);
    return clamp(baseColor, vec3(0.0), vec3(1.0)) * (1.0 - material.metalness)
        * exitTransmission * entryTransmission;
}

// Directional sunlight approximation: baseline plus a broad reflection lobe.
// Uses the raw specular green channel, not decoded LabPBR metalness.
vec2 pbrSunReflectionWeights(vec3 N, vec3 rayDirection, vec3 L, float roughness, float rawMetalness) {
    float smoothness = 1.0 - sqrt(clamp(roughness, 0.0, 1.0));
    float smoothFactor = clamp(smoothness * 10.0 - 7.0, 0.0, 1.0);
    float materialWeight = clamp(rawMetalness, 0.0, 1.0) * 0.98 + 0.02;
    float alignment = dot(L, reflect(rayDirection, N));
    float directional = 250.0 * smoothFactor
        * max(alignment - 0.9 * smoothFactor, 0.0) * materialWeight;
    return vec2(1.0 - smoothFactor * materialWeight, directional);
}

bool ptPureMirror(float roughness, LabPBRSpecularData material) {
#ifdef MC_SPECULAR_MAP
    return roughness <= PBR_GGX_MIN_ALPHA &&
        (material.metalness > 0.999 || all(greaterThanEqual(material.F0, vec3(0.999))));
#else
    return false;
#endif
}


#endif
