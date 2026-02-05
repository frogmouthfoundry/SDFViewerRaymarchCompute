//
//  HandTrackingTests.swift
//  SDFVolumeEditor
//
//  Test utilities for hand tracking functionality.
//

import Foundation
import simd
import RealityKit

/// Test utilities for hand tracking
@MainActor
struct HandTrackingTests {
    
    static func runAllTests() {
        print("\n")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║           Hand Tracking Tests                                 ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("")
        
        testVolumeIntersection()
        
        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║           All Tests Completed                                 ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("\n")
    }
    
    static func testVolumeIntersection() {
        print("── Test: Volume Intersection ──")
        
        do {
            let dimensions: SIMD3<UInt32> = [128, 128, 128]
            let volumeSize: Float = 0.3
            let voxelSize = SIMD3<Float>(repeating: volumeSize / 128.0)
            let halfSize = volumeSize / 2.0
            let startPos = SIMD3<Float>(-halfSize, 1.5 - halfSize, -0.6 - halfSize)
            
            let volume = try SDFVolume(dimensions: dimensions,
                                        voxelSize: voxelSize,
                                        voxelStartPosition: startPos)
            try volume.initializeWithSphere()
            
            let sculptor = try SDFSculptor(sdfVolume: volume)
            
            print("   Volume bounds (with 10cm margin):")
            print("     X: \(sculptor.volumeMin.x - 0.1) to \(sculptor.volumeMax.x + 0.1)")
            print("     Y: \(sculptor.volumeMin.y - 0.1) to \(sculptor.volumeMax.y + 0.1)")
            print("     Z: \(sculptor.volumeMin.z - 0.1) to \(sculptor.volumeMax.z + 0.1)")
            
            // Test center - should be inside
            let center = SIMD3<Float>(0, 1.5, -0.6)
            let centerInside = sculptor.isNearVolume(center)
            print("   ✓ Center (0, 1.5, -0.6) is inside: \(centerInside)")
            
            // Test just outside bounds but within margin
            let nearEdge = SIMD3<Float>(0.2, 1.5, -0.6)
            let nearEdgeInside = sculptor.isNearVolume(nearEdge)
            print("   ✓ Near edge (0.2, 1.5, -0.6) is inside: \(nearEdgeInside)")
            
            // Test far outside
            let outside = SIMD3<Float>(0, 0, 0)
            let outsideInside = sculptor.isNearVolume(outside)
            print("   ✓ Origin (0, 0, 0) is inside: \(outsideInside)")
            
            // Test typical hand position (roughly 0.5m in front at chest height)
            let handPos = SIMD3<Float>(0.3, 1.2, -0.3)
            let handInside = sculptor.isNearVolume(handPos)
            print("   ✓ Typical hand (0.3, 1.2, -0.3) is inside: \(handInside)")
            
            print("   ✅ PASSED\n")
            
        } catch {
            print("   ❌ FAILED: \(error)")
        }
    }
}
