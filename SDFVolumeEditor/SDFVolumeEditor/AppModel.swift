//
//  AppModel.swift
//  SDFVolumeEditor
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
    
    // MARK: - Sculpting
    
    private(set) var sculptor: SDFSculptor?
    let handTrackingTool = HandTrackingSculptTool()
    
    // MARK: - ARKit (Single Session for all providers)
    
    private var arSession: ARKitSession?
    private var worldTracking: WorldTrackingProvider?
    private var handTracking: HandTrackingProvider?
    
    var isTrackingActive: Bool {
        worldTracking?.state == .running
    }
    
    var isHandTrackingActive: Bool {
        handTracking?.state == .running
    }
    
    // MARK: - Error State
    
    var errorMessage: String?
    
    // MARK: - Initialization
    
    func initialize() {
        print("\n========== AppModel Initialization ==========\n")
        
        do {
            // Create volume (128³, 30cm cube)
            let dimensions: SIMD3<UInt32> = [128, 128, 128]
            let volumeSize: Float = 0.3
            let voxelSize = SIMD3<Float>(repeating: volumeSize / 128.0)
            
            // Position volume at eye level (1.5m) and in front of user (-0.6m)
            let halfSize = volumeSize / 2.0
            let startPos = SIMD3<Float>(-halfSize, 1.5 - halfSize, -0.6 - halfSize)
            
            print("🔧 Creating volume...")
            print("   Dimensions: \(dimensions)")
            print("   Volume size: \(volumeSize)m")
            print("   Voxel size: \(voxelSize.x * 1000)mm")
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
            
            // Create sculptor
            print("🔧 Creating sculptor...")
            self.sculptor = try SDFSculptor(sdfVolume: volume)
            
            // Connect hand tracking to sculptor
            handTrackingTool.sculptor = sculptor
            print("✅ Sculptor connected to hand tracking tool")
            
            errorMessage = nil
            print("\n========== AppModel Initialized Successfully ==========\n")
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Initialization failed: \(error)")
        }
    }
    
    // MARK: - ARKit Tracking (Single Session)
    
    func startTracking() async throws {
        print("\n========== Starting ARKit Tracking ==========\n")
        
        let session = ARKitSession()
        
        // Create providers first
        let worldProvider = WorldTrackingProvider()
        let handProvider = HandTrackingProvider()
        
        // Check if the device supports these providers
        print("🔍 Checking data provider support...")
        print("   WorldTrackingProvider supported: \(WorldTrackingProvider.isSupported)")
        print("   HandTrackingProvider supported: \(HandTrackingProvider.isSupported)")
        
        // Request authorization (this will prompt the user if needed)
        print("🔐 Requesting authorization...")
        let authResults = await session.requestAuthorization(for: [.worldSensing, .handTracking])
        
        for (authType, status) in authResults {
            print("   \(authType): \(status)")
        }
        
        // Check if we got authorization
        let worldAuthStatus = authResults[.worldSensing] ?? .notDetermined
        let handAuthStatus = authResults[.handTracking] ?? .notDetermined
        
        if worldAuthStatus != .allowed {
            print("⚠️ World sensing not fully authorized: \(worldAuthStatus)")
            // Continue anyway - on visionOS, world tracking may work without explicit permission
        }
        
        if handAuthStatus != .allowed {
            print("⚠️ Hand tracking not fully authorized: \(handAuthStatus)")
            // Continue anyway - let's try to run and see what happens
        }
        
        print("🚀 Starting ARKit session with providers...")
        
        do {
            // Try to run both providers
            try await session.run([worldProvider, handProvider])
            
            self.arSession = session
            self.worldTracking = worldProvider
            self.handTracking = handProvider
            
            print("✅ ARKit session running successfully!")
            print("   World tracking state: \(worldProvider.state)")
            print("   Hand tracking state: \(handProvider.state)")
            
            // Start hand tracking update loop
            print("🖐️ Starting hand tracking update processing...")
            handTrackingTool.startProcessingUpdates(from: handProvider)
            
            print("\n========== ARKit Tracking Started ==========\n")
            
        } catch {
            print("❌ Failed to run ARKit session: \(error)")
            
            // Try with just hand tracking if world tracking failed
            print("🔄 Trying with just hand tracking...")
            do {
                try await session.run([handProvider])
                
                self.arSession = session
                self.handTracking = handProvider
                
                print("✅ ARKit session running with hand tracking only")
                print("   Hand tracking state: \(handProvider.state)")
                
                handTrackingTool.startProcessingUpdates(from: handProvider)
                
            } catch {
                print("❌ Failed to run ARKit session with hand tracking: \(error)")
                throw error
            }
        }
    }
    
    func stopTracking() {
        print("🛑 Stopping ARKit tracking...")
        arSession?.stop()
        arSession = nil
        worldTracking = nil
        handTracking = nil
        handTrackingTool.stopProcessingUpdates()
        print("✅ ARKit tracking stopped")
    }
    
    func queryDeviceAnchor(at timestamp: TimeInterval) -> DeviceAnchor? {
        guard let tracking = worldTracking, tracking.state == .running else {
            return nil
        }
        return tracking.queryDeviceAnchor(atTimestamp: timestamp)
    }
    
    // MARK: - Sculpting Controls
    
    func toggleSculptMode() {
        sculptor?.toggleMode()
        handTrackingTool.updateToolTipAppearance()
    }
    
    func setSculptRadius(_ radius: Float) {
        sculptor?.setRadius(radius)
        handTrackingTool.updateToolTipAppearance()
    }
    
    // MARK: - Debug
    
    func startDebugAnimation() {
        print("🧪 Starting debug animation from AppModel")
        handTrackingTool.startDebugAnimation()
    }
    
    func runTests() {
        print("🧪 Running tests...")
        HandTrackingTests.runAllTests()
    }
}
