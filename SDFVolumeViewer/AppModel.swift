//
//  AppModel.swift
//  SDFVolumeViewer
//
//  App-wide state management.
//

import SwiftUI
import ARKit

/// Maintains app-wide state.
@MainActor
@Observable
final class AppModel {
    
    let immersiveSpaceID = "SDFVolumeSpace"
    
    enum ImmersiveSpaceState: Equatable {
        case closed
        case inTransition
        case open
        case error(String)
    }
    
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    
    // MARK: - Volume & Raymarching
    
    private(set) var sdfVolume: SDFVolume?
    private(set) var raymarchMesh: SDFRaymarchMesh?
    
    // MARK: - ARKit
    
    private var arSession: ARKitSession?
    private var worldTracking: WorldTrackingProvider?
    
    var isTrackingActive: Bool {
        worldTracking?.state == .running
    }
    
    // MARK: - Error State
    
    var errorMessage: String?
    
    // MARK: - Initialization
    
    func initialize() {
        do {
            // Create volume (128³, 30cm cube)
            let dimensions: SIMD3<UInt32> = [128, 128, 128]
            let volumeSize: Float = 0.3
            let voxelSize = SIMD3<Float>(repeating: volumeSize / 128.0)
            
            // Position volume at eye level (1.5m) and in front of user (-0.6m)
            // This centers the 30cm cube at (0, 1.5, -0.6)
            let halfSize = volumeSize / 2.0
            let startPos = SIMD3<Float>(-halfSize, 1.5 - halfSize, -0.6 - halfSize)
            
            print("🔧 Creating volume...")
            print("   Dimensions: \(dimensions)")
            print("   Volume size: \(volumeSize)m")
            print("   Start position: \(startPos)")
            print("   Volume center: (0, 1.5, -0.6)")
            
            let volume = try SDFVolume(dimensions: dimensions,
                                        voxelSize: voxelSize,
                                        voxelStartPosition: startPos)
            
            // Try to load volume file, or create default sphere
            if let url = Bundle.main.url(forResource: "MyModel", withExtension: "volume") {
                try volume.loadData(from: url)
                print("✅ Loaded MyModel.volume")
            } else {
                try volume.initializeWithSphere()
                print("✅ Created default sphere SDF")
            }
            
            self.sdfVolume = volume
            
            // Create raymarch mesh
            print("🔧 Creating raymarch mesh...")
            self.raymarchMesh = try SDFRaymarchMesh(sdfVolume: volume)
            print("✅ Raymarch mesh created")
            
            errorMessage = nil
            print("✅ AppModel initialized successfully")
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Initialization failed: \(error)")
        }
    }
    
    // MARK: - ARKit Tracking
    
    func startTracking() async throws {
        let session = ARKitSession()
        let tracking = WorldTrackingProvider()
        
        self.arSession = session
        self.worldTracking = tracking
        
        try await session.run([tracking])
        print("✅ ARKit tracking started")
    }
    
    func stopTracking() {
        arSession?.stop()
        arSession = nil
        worldTracking = nil
    }
    
    func queryDeviceAnchor(at timestamp: TimeInterval) -> DeviceAnchor? {
        guard let tracking = worldTracking, tracking.state == .running else {
            return nil
        }
        return tracking.queryDeviceAnchor(atTimestamp: timestamp)
    }
}
