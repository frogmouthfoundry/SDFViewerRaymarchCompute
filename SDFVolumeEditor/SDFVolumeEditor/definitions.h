//
//  definitions.h
//  SDFVolumeEditor
//
//  Shared types between Metal shaders and Swift code.
//

#ifndef definitions_h
#define definitions_h

#ifdef __METAL_VERSION__
// Metal shader types
#include <metal_stdlib>
using namespace metal;

#else
// C/Swift types
#include <simd/simd.h>

#endif

/// Volume parameters - using explicit layout for Swift/Metal compatibility
struct VolumeParams {
    // Dimensions (12 bytes)
    unsigned int dimensionsX;
    unsigned int dimensionsY;
    unsigned int dimensionsZ;
    
    // Voxel size (12 bytes)
    float voxelSizeX;
    float voxelSizeY;
    float voxelSizeZ;
    
    // Start position (12 bytes)
    float startPositionX;
    float startPositionY;
    float startPositionZ;
    
    // Padding to 16-byte alignment (4 bytes)
    float _pad0;
};

/// Raymarch parameters (passed to compute shader)
struct RaymarchParams {
    // Output size
    unsigned int outputWidth;
    unsigned int outputHeight;
    
    // Camera position (12 bytes)
    float cameraPositionX;
    float cameraPositionY;
    float cameraPositionZ;
    
    // Camera forward (12 bytes)
    float cameraForwardX;
    float cameraForwardY;
    float cameraForwardZ;
    
    // Camera right (12 bytes)
    float cameraRightX;
    float cameraRightY;
    float cameraRightZ;
    
    // Camera up (12 bytes)
    float cameraUpX;
    float cameraUpY;
    float cameraUpZ;
    
    // FOV
    float fov;
    
    // Volume bounds min (12 bytes)
    float volumeMinX;
    float volumeMinY;
    float volumeMinZ;
    
    // Volume bounds max (12 bytes)
    float volumeMaxX;
    float volumeMaxY;
    float volumeMaxZ;
    
    // Volume dimensions (12 bytes)
    unsigned int volumeDimX;
    unsigned int volumeDimY;
    unsigned int volumeDimZ;
    
    // Additional params
    float time;
    float isoValue;
    float _pad0;
};

/// Sculpt parameters (passed to sculpt compute shader)
struct SculptParams {
    // Tool position (12 bytes)
    float toolPositionX;
    float toolPositionY;
    float toolPositionZ;
    
    // Previous position (12 bytes)
    float previousPositionX;
    float previousPositionY;
    float previousPositionZ;
    
    // Parameters (16 bytes)
    float radius;
    float smoothFactor;
    int mode;           // 0 = add, 1 = remove
    int hasPreviousPosition;  // 0 = no, 1 = yes
};

#endif /* definitions_h */
