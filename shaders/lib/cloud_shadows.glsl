#ifndef LIGHT_AND_SHADOW_CLOUD_SHADOWS_GLSL
#define LIGHT_AND_SHADOW_CLOUD_SHADOWS_GLSL

uniform sampler2D vanillaCloudPattern;
uniform float cloudHeight;
uniform float cloudTime;
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;

// Vanilla fancy clouds: 12 x 4 x 12 blocks per occupied texture cell.
// This is one cloud-layer transmission, not 0.5 per face or per crossed cell.
const float CLOUD_SUN_TRANSMISSION = 0.5;

float findCloudBlockerDistance(vec3 playerPos, vec3 lightDir, ivec2 patternSize) {
    float receiverY = float(cameraPositionInt.y) + cameraPositionFract.y + playerPos.y;
    float entryT = max((cloudHeight - receiverY) / lightDir.y, 0.0);
    float exitT = (cloudHeight + 4.0 - receiverY) / lightDir.y;
    if (exitT <= entryT) return -1.0;

    ivec2 period = patternSize * 12;
    // Use the unshifted integer camera position before converting to float.
    // Iris cameraPosition rebasing and negative world coordinates must not
    // move the shadow relative to Minecraft's cloud mesh.
    ivec2 wrappedCamera = ((cameraPositionInt.xz % period) + period) % period;
    vec2 origin = (vec2(wrappedCamera) + cameraPositionFract.xz + playerPos.xz +
        vec2(cloudTime, 3.96) + lightDir.xz * entryT) / 12.0;
    vec2 direction = lightDir.xz / 12.0;
    float segmentLength = exitT - entryT;
    ivec2 cell = ivec2(floor(origin));
    ivec2 stepCell = ivec2(sign(direction));
    vec2 nextT = vec2(1e30);
    vec2 deltaT = vec2(1e30);
    for (int axis = 0; axis < 2; ++axis) {
        if (abs(direction[axis]) > 1e-8) {
            float boundary = float(cell[axis]) + (direction[axis] > 0.0 ? 1.0 : 0.0);
            nextT[axis] = (boundary - origin[axis]) / direction[axis];
            deltaT[axis] = 1.0 / abs(direction[axis]);
        }
    }
    // Traverse only the four-block-thick cloud slab, not the distance to it.
    // At the minimum elevation this crosses fewer than 100 horizontal cells.
    float travelledT = 0.0;
    for (int i = 0; i < 128; ++i) {
        ivec2 texel = ((cell % patternSize) + patternSize) % patternSize;
        // CloudRenderer regards alpha >= 10/255 as an occupied cell. Cloud
        // display alpha/color do not set the requested 50% shadow strength.
        if (texelFetch(vanillaCloudPattern, texel, 0).a >= 10.0 / 255.0)
            return entryT + travelledT;
        float crossingT = min(nextT.x, nextT.y);
        if (crossingT >= segmentLength) break;
        travelledT = max(crossingT, 0.0);
        if (nextT.x <= nextT.y) {
            nextT.x += deltaT.x;
            cell.x += stepCell.x;
        } else {
            nextT.y += deltaT.y;
            cell.y += stepCell.y;
        }
    }
    return -1.0;
}


float getCloudSunVisibility(vec3 playerPos) {
    if (!sceneHasSkyLight() || sunAngle >= 0.5 ||
        !(cloudHeight > -1000000.0 && cloudHeight < 1000000.0)) return 1.0;
    vec3 lightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    if (lightDir.y < 0.005) return 1.0;
    float receiverY = float(cameraPositionInt.y) + cameraPositionFract.y + playerPos.y;
    float slabExitT = (cloudHeight + 4.0 - receiverY) / lightDir.y;
    if (slabExitT <= 0.0) return 1.0;
    ivec2 patternSize = textureSize(vanillaCloudPattern, 0);
    if (any(lessThanEqual(patternSize, ivec2(0)))) return 1.0;

    // Directional-light PCSS in world units. Clouds have no shadow-map depth,
    // so the slab traversal supplies first-blocker distances for the search.
    const float sunAngularRadius = 0.00465;
    vec3 tangent = normalize(cross(lightDir,
        abs(lightDir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 bitangent = cross(lightDir, tangent);
    vec2 phase = vec2(cameraPositionInt.xz % 64) + cameraPositionFract.xz + playerPos.xz;
    mat2 rotation = pcssRotation(phase);
    // Include the enlarged footprint at grazing angles: the filter must not
    // extend past the search and end a penumbra with a hard fully-lit rim.
    float searchRadius = slabExitT * sunAngularRadius /
        max(1.0 - sunAngularRadius / lightDir.y, 0.05);
    float centerBlocker = findCloudBlockerDistance(playerPos, lightDir, patternSize);
    float blockerSum = max(centerBlocker, 0.0);
    float blockerCount = centerBlocker >= 0.0 ? 1.0 : 0.0;
    for (int i = 0; i < PCSS_BLOCKER_SAMPLES; ++i) {
        vec2 disk = rotation * POISSON_24[i];
        vec3 offset = (tangent * disk.x + bitangent * disk.y) * searchRadius;
        float blocker = findCloudBlockerDistance(playerPos + offset, lightDir, patternSize);
        if (blocker >= 0.0) {
            blockerSum += blocker;
            blockerCount += 1.0;
        }
    }
    if (blockerCount == 0.0) return 1.0;
    float filterRadius = min(blockerSum / blockerCount * sunAngularRadius, searchRadius);
    if (filterRadius <= 0.0001)
        return centerBlocker >= 0.0 ? CLOUD_SUN_TRANSMISSION : 1.0;
    float blockedWeight = 0.0;
    float totalWeight = 0.0;
    for (int i = 0; i < PCSS_FILTER_SAMPLES; ++i) {
        vec2 disk = rotation * POISSON_24[i];
        float weight = max(1.0 - dot(disk, disk), 0.0);
        weight *= weight;
        vec3 offset = (tangent * disk.x + bitangent * disk.y) * filterRadius;
        float blocker = findCloudBlockerDistance(playerPos + offset, lightDir, patternSize);
        blockedWeight += (blocker >= 0.0 ? 1.0 : 0.0) * weight;
        totalWeight += weight;
    }
    float coverage = clamp(blockedWeight / max(totalWeight, 1e-5), 0.0, 1.0);
    return mix(1.0, CLOUD_SUN_TRANSMISSION, coverage);
}

#endif
