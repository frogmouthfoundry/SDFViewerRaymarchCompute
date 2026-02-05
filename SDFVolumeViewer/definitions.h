//
//  definitions.h
//  SDFVolumeViewer
//
//  Shared types between Metal shaders and Swift code.
//

#ifndef definitions_h
#define definitions_h

#ifdef __METAL_VERSION__
// Metal shader types
#include <metal_stdlib>
using namespace metal;

typedef float3 vec3f;
typedef uint3 vec3u;

#else
// C/Swift types
#include <simd/simd.h>

typedef simd_float3 vec3f;
typedef simd_uint3 vec3u;

#endif

/// Volume parameters (matches SDFVolume.volumeParams)
struct VolumeParams {
    vec3u dimensions;
    vec3f voxelSize;
    vec3f voxelStartPosition;
};

/// Raymarch parameters (passed to compute shader)
struct RaymarchParams {
    // Output size
    unsigned int outputWidth;
    unsigned int outputHeight;
    
    // Camera
    vec3f cameraPosition;
    vec3f cameraForward;
    vec3f cameraRight;
    vec3f cameraUp;
    float fov;
    
    // Volume bounds
    vec3f volumeMin;
    vec3f volumeMax;
    vec3u volumeDim;
    
    // Additional params
    float time;
    float isoValue;
};

#endif /* definitions_h */
