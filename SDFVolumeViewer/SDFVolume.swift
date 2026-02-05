//
//  SDFVolume.swift
//  SDFVolumeViewer
//
//  A 3D texture representing an SDF volume.
//  Follows the VoxelVolume pattern from MarchingCubes-Test.
//

import RealityKit
import Metal

/// A 3D texture that represents an SDF volume.
@MainActor
final class SDFVolume {
    
    var voxelTexture: MTLTexture
    
    let dimensions: SIMD3<UInt32>
    let voxelSize: SIMD3<Float>
    let voxelStartPosition: SIMD3<Float>
    
    var volumeParams: VolumeParams {
        VolumeParams(dimensions: dimensions,
                     voxelSize: voxelSize,
                     voxelStartPosition: voxelStartPosition)
    }
    
    let idealThreadgroupCount: MTLSize
    let idealThreadsPerThreadgroup: MTLSize
    
    init(dimensions: SIMD3<UInt32>,
         voxelSize: SIMD3<Float>,
         voxelStartPosition: SIMD3<Float>) throws {
        
        self.dimensions = dimensions
        self.voxelSize = voxelSize
        self.voxelStartPosition = voxelStartPosition
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r32Float
        descriptor.width = Int(dimensions.x)
        descriptor.height = Int(dimensions.y)
        descriptor.depth = Int(dimensions.z)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        
        guard let texture = metalDevice?.makeTexture(descriptor: descriptor) else {
            throw VolumeError.failedToCreateTexture
        }
        
        self.voxelTexture = texture
        
        self.idealThreadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 8)
        self.idealThreadgroupCount = MTLSize(
            width: (Int(dimensions.x) + 7) / 8,
            height: (Int(dimensions.y) + 7) / 8,
            depth: (Int(dimensions.z) + 7) / 8
        )
    }
    
    func loadData(from url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let expectedBytes = Int(dimensions.x * dimensions.y * dimensions.z) * MemoryLayout<Float>.size
        
        guard data.count == expectedBytes else {
            throw VolumeError.sizeMismatch(expected: expectedBytes, actual: data.count)
        }
        
        guard let device = metalDevice,
              let queue = device.makeCommandQueue(),
              let cmd = queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else {
            throw VolumeError.noMetalDevice
        }
        
        let staging = device.makeBuffer(bytes: (data as NSData).bytes,
                                        length: data.count,
                                        options: .storageModeShared)!
        
        blit.copy(from: staging, sourceOffset: 0,
                  sourceBytesPerRow: Int(dimensions.x) * 4,
                  sourceBytesPerImage: Int(dimensions.x * dimensions.y) * 4,
                  sourceSize: MTLSize(width: Int(dimensions.x), height: Int(dimensions.y), depth: Int(dimensions.z)),
                  to: voxelTexture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }
    
    func initializeWithSphere() throws {
        guard let device = metalDevice,
              let queue = device.makeCommandQueue(),
              let cmd = queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else {
            throw VolumeError.noMetalDevice
        }
        
        let count = Int(dimensions.x * dimensions.y * dimensions.z)
        var data = [Float](repeating: 0, count: count)
        
        let center = SIMD3<Float>(dimensions) / 2.0
        let radius = Float(min(dimensions.x, dimensions.y, dimensions.z)) * 0.35
        
        var index = 0
        for z in 0..<Int(dimensions.z) {
            for y in 0..<Int(dimensions.y) {
                for x in 0..<Int(dimensions.x) {
                    let pos = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                    data[index] = (simd_length(pos - center) - radius) / Float(dimensions.x)
                    index += 1
                }
            }
        }
        
        let staging = device.makeBuffer(bytes: data, length: count * 4, options: .storageModeShared)!
        
        blit.copy(from: staging, sourceOffset: 0,
                  sourceBytesPerRow: Int(dimensions.x) * 4,
                  sourceBytesPerImage: Int(dimensions.x * dimensions.y) * 4,
                  sourceSize: MTLSize(width: Int(dimensions.x), height: Int(dimensions.y), depth: Int(dimensions.z)),
                  to: voxelTexture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }
}
