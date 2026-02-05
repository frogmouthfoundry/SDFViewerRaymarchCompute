//
//  MetalHelpers.swift
//  SDFVolumeViewer
//
//  Global Metal device and helper functions following MarchingCubes-Test pattern.
//

import Metal
import RealityKit

// MARK: - Global Metal Device (following MarchingCubes-Test pattern)

/// The shared Metal device used throughout the application.
@MainActor
let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

// MARK: - Compute Pipeline Helper

/// Creates a compute pipeline state from a kernel function name.
@MainActor
func makeComputePipeline(named functionName: String) -> MTLComputePipelineState? {
    guard let device = metalDevice,
          let library = device.makeDefaultLibrary(),
          let function = library.makeFunction(name: functionName) else {
        print("❌ Failed to create compute function: \(functionName)")
        return nil
    }
    
    do {
        return try device.makeComputePipelineState(function: function)
    } catch {
        print("❌ Failed to create compute pipeline for \(functionName): \(error)")
        return nil
    }
}

// MARK: - Volume Loading Errors

enum VolumeError: Error, LocalizedError {
    case sizeMismatch(expected: Int, actual: Int)
    case failedToLoadFile(String)
    case failedToCreateTexture
    case noMetalDevice
    
    var errorDescription: String? {
        switch self {
        case .sizeMismatch(let expected, let actual):
            return "Volume size mismatch: expected \(expected) bytes, got \(actual) bytes"
        case .failedToLoadFile(let filename):
            return "Failed to load volume file: \(filename)"
        case .failedToCreateTexture:
            return "Failed to create 3D texture"
        case .noMetalDevice:
            return "No Metal device available"
        }
    }
}
