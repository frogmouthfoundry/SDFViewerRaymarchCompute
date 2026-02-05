//
//  SculptCompute.metal
//  SDFVolumeEditor
//
//  Compute shader operations for sculpting the SDF volume.
//

#include <metal_stdlib>
#include "definitions.h"
using namespace metal;

// ============================================================================
// Distance Functions (return values in NORMALIZED SDF units)
// ============================================================================

// Distance from a point to a sphere, scaled to SDF units
float distanceFromSphere(float3 position, float3 center, float radius, float sdfScale) {
    return (length(position - center) - radius) * sdfScale;
}

// Distance from a point to a capped line (capsule), scaled to SDF units
float distanceFromCapsule(float3 position, float3 endpointA, float3 endpointB, float radius, float sdfScale) {
    float3 pa = position - endpointA;
    float3 ba = endpointB - endpointA;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return (length(pa - ba * h) - radius) * sdfScale;
}

// ============================================================================
// Smooth Boolean Operations
// ============================================================================

// Smooth union (add material)
float smoothUnion(float distA, float distB, float k) {
    float h = clamp(0.5 + 0.5 * (distB - distA) / k, 0.0, 1.0);
    return mix(distB, distA, h) - k * h * (1.0 - h);
}

// Smooth subtraction (remove material) - subtracts distA from distB
float smoothSubtraction(float distA, float distB, float k) {
    float h = clamp(0.5 - 0.5 * (distB + distA) / k, 0.0, 1.0);
    return mix(distB, -distA, h) + k * h * (1.0 - h);
}

// ============================================================================
// Sculpt Kernel
// ============================================================================

[[kernel]]
void sculptKernel(texture3d<float, access::read> voxelsIn [[texture(0)]],
                  texture3d<float, access::write> voxelsOut [[texture(1)]],
                  constant VolumeParams &volumeParams [[buffer(0)]],
                  constant SculptParams &sculptParams [[buffer(1)]],
                  uint3 voxelCoords [[thread_position_in_grid]]) {
    
    // Get dimensions from explicit fields
    uint3 dimensions = uint3(volumeParams.dimensionsX, 
                             volumeParams.dimensionsY, 
                             volumeParams.dimensionsZ);
    
    // Skip out of bounds threads
    if (any(voxelCoords >= dimensions)) {
        return;
    }
    
    // Read the current voxel value (in normalized SDF units)
    float voxelValue = voxelsIn.read(voxelCoords).r;
    
    // Get voxel size and start position
    float3 voxelSize = float3(volumeParams.voxelSizeX,
                               volumeParams.voxelSizeY,
                               volumeParams.voxelSizeZ);
    float3 startPosition = float3(volumeParams.startPositionX,
                                   volumeParams.startPositionY,
                                   volumeParams.startPositionZ);
    
    // Get the position of the current voxel in world space (meters)
    float3 position = startPosition + (float3(voxelCoords) + 0.5) * voxelSize;
    
    // Get the tool position and radius (in meters)
    float3 toolPosition = float3(sculptParams.toolPositionX, 
                                  sculptParams.toolPositionY, 
                                  sculptParams.toolPositionZ);
    float3 previousPosition = float3(sculptParams.previousPositionX,
                                      sculptParams.previousPositionY,
                                      sculptParams.previousPositionZ);
    float toolRadius = sculptParams.radius;  // in meters
    bool hasPreviousPosition = sculptParams.hasPreviousPosition != 0;
    float smoothFactor = sculptParams.smoothFactor;
    
    // Calculate the scale factor to convert meters to normalized SDF units
    // The volume physical size = voxelSize * dimensions
    // SDF is normalized by dividing by dimensions, so:
    // sdfScale = 1.0 / (voxelSize.x * dimensions.x) = 1.0 / volumePhysicalSize
    float volumePhysicalSize = voxelSize.x * float(dimensions.x);
    float sdfScale = 1.0 / volumePhysicalSize;
    
    // Get the distance to the tool shape (in normalized SDF units)
    float distance;
    if (hasPreviousPosition) {
        distance = distanceFromCapsule(position, toolPosition, previousPosition, toolRadius, sdfScale);
    } else {
        distance = distanceFromSphere(position, toolPosition, toolRadius, sdfScale);
    }
    
    // Scale smooth factor to SDF units as well
    float scaledSmoothFactor = smoothFactor * sdfScale;
    
    // Combine the distance with the existing voxel value based on sculpt mode
    if (sculptParams.mode == 0) {  // Add
        voxelValue = smoothUnion(distance, voxelValue, scaledSmoothFactor);
    } else {
        // Remove (default)
        voxelValue = smoothSubtraction(distance, voxelValue, scaledSmoothFactor);
    }
    
    // Write the result back to the voxel texture
    voxelsOut.write(voxelValue, voxelCoords);
}

// ============================================================================
// Copy Kernel (for double buffering)
// ============================================================================

[[kernel]]
void copyVoxels(texture3d<float, access::read> voxelsIn [[texture(0)]],
                texture3d<float, access::write> voxelsOut [[texture(1)]],
                constant VolumeParams &volumeParams [[buffer(0)]],
                uint3 voxelCoords [[thread_position_in_grid]]) {
    
    uint3 dimensions = uint3(volumeParams.dimensionsX, 
                             volumeParams.dimensionsY, 
                             volumeParams.dimensionsZ);
    
    if (any(voxelCoords >= dimensions)) {
        return;
    }
    
    float value = voxelsIn.read(voxelCoords).r;
    voxelsOut.write(value, voxelCoords);
}
