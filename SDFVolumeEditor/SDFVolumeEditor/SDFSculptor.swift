//
//  SDFSculptor.swift
//  SDFVolumeEditor
//
//  Manages sculpting operations on the SDF volume.
//

import RealityKit
import Metal

/// Manages sculpting operations on an SDF volume
@MainActor
final class SDFSculptor {
    
    // MARK: - Metal Resources
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let sculptPipeline: MTLComputePipelineState
    
    // MARK: - Volume Reference
    
    let sdfVolume: SDFVolume
    
    // Double buffer for proper read/write
    private var scratchTexture: MTLTexture
    
    // Volume bounds for intersection testing (in meters)
    let volumeMin: SIMD3<Float>
    let volumeMax: SIMD3<Float>
    let volumeCenter: SIMD3<Float>
    let volumeSize: SIMD3<Float>
    
    // MARK: - Sculpting State
    
    var mode: Int32 = 1  // 0 = add, 1 = remove (default to subtract)
    var radius: Float = 0.015  // 1.5cm default radius (in meters)
    var smoothFactor: Float = 0.008  // Smooth blending factor (in meters)
    
    private var previousPosition: SIMD3<Float>?
    
    // MARK: - Debug
    
    var lastCheckedPosition: SIMD3<Float> = .zero
    var lastDistanceToVolume: Float = 0
    
    // MARK: - Initialization
    
    init(sdfVolume: SDFVolume) throws {
        guard let device = metalDevice else {
            throw NSError(domain: "SDFSculptor", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "SDFSculptor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
        }
        self.commandQueue = queue
        
        guard let sculptPipeline = makeComputePipeline(named: "sculptKernel") else {
            throw NSError(domain: "SDFSculptor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create sculpt pipeline"])
        }
        self.sculptPipeline = sculptPipeline
        
        self.sdfVolume = sdfVolume
        
        // Create scratch texture for double-buffering
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r32Float
        descriptor.width = Int(sdfVolume.dimensions.x)
        descriptor.height = Int(sdfVolume.dimensions.y)
        descriptor.depth = Int(sdfVolume.dimensions.z)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        
        guard let scratch = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "SDFSculptor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create scratch texture"])
        }
        self.scratchTexture = scratch
        
        // Calculate volume bounds in world space (meters)
        self.volumeSize = sdfVolume.voxelSize * SIMD3<Float>(sdfVolume.dimensions)
        self.volumeMin = sdfVolume.voxelStartPosition
        self.volumeMax = volumeMin + volumeSize
        self.volumeCenter = volumeMin + volumeSize * 0.5
        
        print("✅ SDFSculptor initialized")
        print("   Mode: \(mode == 0 ? "Add" : "Remove")")
        print("   Radius: \(radius * 100)cm")
        print("   Volume min: \(volumeMin)")
        print("   Volume max: \(volumeMax)")
        print("   Volume center: \(volumeCenter)")
        print("   Volume size: \(volumeSize)")
    }
    
    // MARK: - Volume Intersection
    
    /// Check if a position is inside or near the volume bounds
    /// Uses a generous margin to make sculpting easier
    func isNearVolume(_ position: SIMD3<Float>) -> Bool {
        lastCheckedPosition = position
        
        // Use a larger margin (10cm) to make it easier to start sculpting
        let margin: Float = 0.10
        
        let expandedMin = volumeMin - SIMD3<Float>(repeating: margin)
        let expandedMax = volumeMax + SIMD3<Float>(repeating: margin)
        
        let isInside = position.x >= expandedMin.x && position.x <= expandedMax.x &&
                       position.y >= expandedMin.y && position.y <= expandedMax.y &&
                       position.z >= expandedMin.z && position.z <= expandedMax.z
        
        // Calculate distance to volume center for debugging
        lastDistanceToVolume = simd_distance(position, volumeCenter)
        
        return isInside
    }
    
    /// Get distance from position to volume center (for UI feedback)
    func distanceToVolumeCenter(_ position: SIMD3<Float>) -> Float {
        return simd_distance(position, volumeCenter)
    }
    
    // MARK: - Sculpting
    
    /// Begin a sculpting stroke
    func beginStroke() {
        previousPosition = nil
        print("🎨 Stroke started")
    }
    
    /// End a sculpting stroke
    func endStroke() {
        previousPosition = nil
        print("🎨 Stroke ended")
    }
    
    /// Sculpt at the given position (in world space, meters)
    func sculpt(at position: SIMD3<Float>) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("❌ Failed to create command buffer")
            return
        }
        
        // Step 1: Run sculpt kernel (read from main, write to scratch)
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("❌ Failed to create compute encoder")
            return
        }
        
        var sculptParams = SculptParams(
            toolPositionX: position.x,
            toolPositionY: position.y,
            toolPositionZ: position.z,
            previousPositionX: previousPosition?.x ?? position.x,
            previousPositionY: previousPosition?.y ?? position.y,
            previousPositionZ: previousPosition?.z ?? position.z,
            radius: radius,
            smoothFactor: smoothFactor,
            mode: mode,
            hasPreviousPosition: previousPosition != nil ? 1 : 0
        )
        
        var volumeParams = sdfVolume.volumeParams
        
        computeEncoder.setComputePipelineState(sculptPipeline)
        computeEncoder.setTexture(sdfVolume.voxelTexture, index: 0)  // Read from main
        computeEncoder.setTexture(scratchTexture, index: 1)          // Write to scratch
        computeEncoder.setBytes(&volumeParams, length: MemoryLayout<VolumeParams>.stride, index: 0)
        computeEncoder.setBytes(&sculptParams, length: MemoryLayout<SculptParams>.stride, index: 1)
        
        computeEncoder.dispatchThreadgroups(sdfVolume.idealThreadgroupCount,
                                            threadsPerThreadgroup: sdfVolume.idealThreadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        // Step 2: Copy scratch back to main texture
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            print("❌ Failed to create blit encoder")
            return
        }
        
        blitEncoder.copy(from: scratchTexture, to: sdfVolume.voxelTexture)
        blitEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Update state for next frame
        previousPosition = position
    }
    
    /// Toggle between add and remove modes
    func toggleMode() {
        mode = (mode == 0) ? 1 : 0
        print("🔄 Sculpt mode: \(mode == 0 ? "Add" : "Remove")")
    }
    
    /// Set the sculpting radius (in meters)
    func setRadius(_ newRadius: Float) {
        radius = max(0.005, min(0.05, newRadius))
        print("📏 Sculpt radius: \(radius * 100)cm")
    }
}
