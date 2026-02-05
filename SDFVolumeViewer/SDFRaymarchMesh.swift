//
//  SDFRaymarchMesh.swift
//  SDFVolumeViewer
//
//  Manages raymarching output to a LowLevelTexture.
//

import RealityKit
import Metal

/// Manages raymarching to a LowLevelTexture for RealityKit display.
@MainActor
final class SDFRaymarchMesh {
    
    // MARK: - Configuration
    
    static let outputWidth = 2048
    static let outputHeight = 2048
    
    // MARK: - Metal Resources
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let raymarchPipeline: MTLComputePipelineState
    
    // MARK: - Output Texture
    
    let outputTexture: LowLevelTexture
    let textureResource: TextureResource
    
    // MARK: - Volume Reference
    
    let sdfVolume: SDFVolume
    let volumeCenter: SIMD3<Float>
    let volumeHalfExtent: Float  // Half the diagonal of the volume bounding box
    
    // MARK: - Raymarching Parameters
    
    var params: RaymarchParams
    
    // MARK: - Thread Configuration
    
    let threadgroups: MTLSize
    let threadsPerThreadgroup: MTLSize
    
    // MARK: - Initialization
    
    init(sdfVolume: SDFVolume) throws {
        guard let device = metalDevice else {
            throw NSError(domain: "SDFRaymarchMesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "SDFRaymarchMesh", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
        }
        self.commandQueue = queue
        
        guard let pipeline = makeComputePipeline(named: "raymarchKernel") else {
            throw NSError(domain: "SDFRaymarchMesh", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create compute pipeline"])
        }
        self.raymarchPipeline = pipeline
        
        self.sdfVolume = sdfVolume
        
        // Calculate volume bounds and center
        let volumeSize = sdfVolume.voxelSize * SIMD3<Float>(sdfVolume.dimensions)
        let volumeMin = sdfVolume.voxelStartPosition
        let volumeMax = volumeMin + volumeSize * 1.2 //orig 1.8
        self.volumeCenter = volumeMin + volumeSize / 2.0
        
        // Half extent is the radius of the bounding sphere
        self.volumeHalfExtent = simd_length(volumeSize) / 2.0
        
        // Create LowLevelTexture for compute output
        let descriptor = LowLevelTexture.Descriptor(
            textureType: .type2D,
            pixelFormat: .rgba8Unorm,
            width: Self.outputWidth,
            height: Self.outputHeight,
            depth: 1,
            mipmapLevelCount: 1,
            textureUsage: [.shaderRead, .shaderWrite]
        )
        
        self.outputTexture = try LowLevelTexture(descriptor: descriptor)
        self.textureResource = try TextureResource(from: outputTexture)
        
        // Default camera: at user's approximate head position, looking at volume
        let defaultCamPos = SIMD3<Float>(0, 1.7, 0)
        let forward = simd_normalize(volumeCenter - defaultCamPos)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        
        // Plane size should be large enough to show the entire volume from any angle
        // Use 2.5x the bounding sphere diameter for safety margin
        let effectivePlaneSize = volumeHalfExtent * 10.0 //orig 5.0
        
        self.params = RaymarchParams(
            outputWidth: UInt32(Self.outputWidth),
            outputHeight: UInt32(Self.outputHeight),
            cameraPosition: defaultCamPos,
            cameraForward: forward,
            cameraRight: right,
            cameraUp: up,
            fov: 2.0 * atan(effectivePlaneSize / 2.0 / 0.6),
            volumeMin: volumeMin,
            volumeMax: volumeMax,
            volumeDim: sdfVolume.dimensions,
            time: 0,
            isoValue: 0
        )
        
        // Calculate thread configuration
        self.threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        self.threadgroups = MTLSize(
            width: (Self.outputWidth + 15) / 16,
            height: (Self.outputHeight + 15) / 16,
            depth: 1
        )
        
        print("✅ SDFRaymarchMesh initialized")
        print("   Output size: \(Self.outputWidth) x \(Self.outputHeight)")
        print("   Volume bounds: \(params.volumeMin) to \(params.volumeMax)")
        print("   Volume center: \(volumeCenter)")
        print("   Volume half extent: \(volumeHalfExtent)")
        print("   Effective plane size: \(effectivePlaneSize)")
        print("   Struct size: \(MemoryLayout<RaymarchParams>.size) bytes")
    }
    
    // MARK: - Render
    
    private var frameCount = 0
    
    /// Perform raymarching and update the texture
    func render() {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("❌ Failed to create command buffer")
            return
        }
        
        // Get writable texture from LowLevelTexture
        let outputMTLTexture = outputTexture.replace(using: commandBuffer)
        
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("❌ Failed to create compute encoder")
            return
        }
        
        computeEncoder.setComputePipelineState(raymarchPipeline)
        computeEncoder.setBytes(&params, length: MemoryLayout<RaymarchParams>.stride, index: 0)
        computeEncoder.setTexture(sdfVolume.voxelTexture, index: 0)
        computeEncoder.setTexture(outputMTLTexture, index: 1)
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        
        // Update time for animation
        params.time += 1.0 / 30.0
        
        frameCount += 1
        if frameCount % 30 == 0 {
            print("🎬 Rendered frame \(frameCount)")
        }
    }
    
    // MARK: - Camera Control
    
    func setCamera(from transform: simd_float4x4) {
        // Get head position
        let headPos = SIMD3<Float>(transform.columns.3.x,
                                    transform.columns.3.y,
                                    transform.columns.3.z)
        
        // Camera looks at volume center from head position
        params.cameraPosition = headPos
        
        let toVolume = volumeCenter - headPos
        let distance = simd_length(toVolume)
        let forward = toVolume / distance
        
        params.cameraForward = forward
        
        let worldUp = SIMD3<Float>(0, 1, 0)
        var right = simd_cross(forward, worldUp)
        let rightLen = simd_length(right)
        if rightLen < 0.001 {
            right = simd_normalize(simd_cross(forward, SIMD3<Float>(1, 0, 0)))
        } else {
            right = right / rightLen
        }
        params.cameraRight = right
        
        let up = simd_cross(right, forward)
        params.cameraUp = up
        
        // Plane is positioned behind the volume (at volumeHalfExtent behind center)
        // Plane size is 2.5x the bounding sphere diameter for safety margin
        let planeOffset = volumeHalfExtent
        let planeDistance = distance + planeOffset
        let effectivePlaneSize = volumeHalfExtent * 5.0
        params.fov = 2.0 * atan((effectivePlaneSize / 2.0) / planeDistance)
    }
    
    func setCamera(position: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) {
        params.cameraPosition = position
        
        let forward = simd_normalize(target - position)
        params.cameraForward = forward
        
        let right = simd_normalize(simd_cross(forward, up))
        params.cameraRight = right
        
        let camUp = simd_cross(right, forward)
        params.cameraUp = camUp
    }
}
