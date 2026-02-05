//
//  RaymarchCompute.metal
//  SDFVolumeViewer
//
//  Compute shader for raymarching a 3D SDF volume texture.
//

#include <metal_stdlib>
#include "definitions.h"
using namespace metal;

// ============================================================================
// Constants
// ============================================================================

constant float3 LIGHT_DIR = float3(0.43643578, 0.87287156, 0.26186147); // normalized (0.5, 1.0, 0.3)
//constant float3 BASE_COLOR = float3(0.8, 0.2, 0.1); orange-red
constant float3 BASE_COLOR = float3(0.949, 0.921, 0.890); //bone-ish color
constant float4 BACKGROUND_COLOR = float4(0.1, 0.1, 0.2, 1.0);  // Dark blue background so we can see something

constant int MAX_STEPS = 128;
constant float SURFACE_EPSILON = 0.002;
constant float STEP_SAFETY = 0.8;

// ============================================================================
// Helper Functions
// ============================================================================

inline float3 worldToUVW(float3 pos, float3 volumeMin, float3 volumeMax) {
    return saturate((pos - volumeMin) / (volumeMax - volumeMin));
}

inline float sampleSDF(float3 pos, float3 volumeMin, float3 volumeMax,
                       texture3d<float, access::sample> volumeTex,
                       sampler samp) {
    float3 uvw = worldToUVW(pos, volumeMin, volumeMax);
    return volumeTex.sample(samp, uvw).r;
}

inline float2 rayBoxIntersect(float3 ro, float3 rd, float3 boxMin, float3 boxMax) {
    float3 invDir = 1.0 / rd;
    float3 t0 = (boxMin - ro) * invDir;
    float3 t1 = (boxMax - ro) * invDir;
    float3 tMin = min(t0, t1);
    float3 tMax = max(t0, t1);
    float tNear = max(max(tMin.x, tMin.y), tMin.z);
    float tFar = min(min(tMax.x, tMax.y), tMax.z);
    return (tNear > tFar || tFar < 0.0) ? float2(-1.0) : float2(max(tNear, 0.0), tFar);
}

inline float3 calculateNormal(float3 pos, float3 volumeMin, float3 volumeMax,
                              texture3d<float, access::sample> volumeTex,
                              sampler samp) {
    float eps = 0.002;
    float gx = sampleSDF(pos + float3(eps,0,0), volumeMin, volumeMax, volumeTex, samp)
             - sampleSDF(pos - float3(eps,0,0), volumeMin, volumeMax, volumeTex, samp);
    float gy = sampleSDF(pos + float3(0,eps,0), volumeMin, volumeMax, volumeTex, samp)
             - sampleSDF(pos - float3(0,eps,0), volumeMin, volumeMax, volumeTex, samp);
    float gz = sampleSDF(pos + float3(0,0,eps), volumeMin, volumeMax, volumeTex, samp)
             - sampleSDF(pos - float3(0,0,eps), volumeMin, volumeMax, volumeTex, samp);
    return normalize(float3(gx, gy, gz));
}

inline float3 shade(float3 pos, float3 normal, float3 camPos) {
    float diffuse = max(dot(normal, LIGHT_DIR), 0.0);
    float ambient = 0.25;
    float3 viewDir = normalize(camPos - pos);
    float3 halfDir = normalize(LIGHT_DIR + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), 64.0) * 0.4;
    return BASE_COLOR * (ambient + diffuse * 0.7) + spec;
}

// ============================================================================
// Main Kernel
// ============================================================================

[[kernel]]
void raymarchKernel(uint2 gid [[thread_position_in_grid]],
                    constant RaymarchParams& params [[buffer(0)]],
                    texture3d<float, access::sample> volumeTex [[texture(0)]],
                    texture2d<float, access::write> outputTex [[texture(1)]]) {
    
    if (gid.x >= params.outputWidth || gid.y >= params.outputHeight) {
        return;
    }
    
    // Get camera and volume parameters directly from struct
    float3 camPos = params.cameraPosition;
    float3 camFwd = params.cameraForward;
    float3 camRight = params.cameraRight;
    float3 camUp = params.cameraUp;
    float3 volMin = params.volumeMin;
    float3 volMax = params.volumeMax;
    uint3 volDims = params.volumeDim;
    float fov = params.fov;
    
    constexpr sampler samp(coord::normalized, address::clamp_to_edge, filter::linear);
    
    // Calculate ray direction
    float2 uv = (float2(gid) + 0.5) / float2(params.outputWidth, params.outputHeight);
    float2 ndc = uv * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    float aspect = float(params.outputWidth) / float(params.outputHeight);
    float tanHalfFov = tan(fov * 0.5);
    
    float3 rd = normalize(camFwd +
                          camRight * (ndc.x * tanHalfFov * aspect) +
                          camUp * (ndc.y * tanHalfFov));
    
    float3 ro = camPos;
    
    // Ray-box intersection
    float2 tHit = rayBoxIntersect(ro, rd, volMin, volMax);
    
    if (tHit.x < 0.0) {
        // Ray missed volume - transparent
        outputTex.write(float4(0.0, 0.0, 0.0, 0.0), gid);
        return;
    }
    
    // Raymarch
    float3 volumeSize = volMax - volMin;
    float voxelSize = min(volumeSize.x, min(volumeSize.y, volumeSize.z)) / float(max(volDims.x, max(volDims.y, volDims.z)));
    float minStep = voxelSize * 0.1;
    float surfaceEps = voxelSize * 0.5;
    
    float t = tHit.x + surfaceEps * 0.5;
    float tMax = tHit.y;
    float tPrev = t;
    float dPrev = 1e9;
    
    for (int i = 0; i < MAX_STEPS; i++) {
        float3 pos = ro + rd * t;
        
        if (t > tMax) break;
        
        float d = sampleSDF(pos, volMin, volMax, volumeTex, samp);
        
        if (abs(d) < surfaceEps) {
            float3 n = calculateNormal(pos, volMin, volMax, volumeTex, samp);
            float3 col = shade(pos, n, ro);
            outputTex.write(float4(col, 1.0), gid);
            return;
        }
        
        if (d < 0.0 && dPrev > 0.0) {
            float a = tPrev, b = t;
            for (int j = 0; j < 6; j++) {
                float m = 0.5 * (a + b);
                float dm = sampleSDF(ro + rd * m, volMin, volMax, volumeTex, samp);
                if (dm > 0.0) a = m; else b = m;
            }
            float3 hitPos = ro + rd * (0.5 * (a + b));
            float3 n = calculateNormal(hitPos, volMin, volMax, volumeTex, samp);
            float3 col = shade(hitPos, n, ro);
            outputTex.write(float4(col, 1.0), gid);
            return;
        }
        
        tPrev = t;
        dPrev = d;
        t += max(abs(d) * STEP_SAFETY, minStep);
    }
    
    // Ray traversed volume but didn't find surface - transparent
    outputTex.write(float4(0.0, 0.0, 0.0, 0.0), gid);
}
