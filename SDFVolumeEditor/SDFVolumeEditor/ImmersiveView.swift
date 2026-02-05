//
//  ImmersiveView.swift
//  SDFVolumeEditor
//
//  RealityKit immersive view displaying the raymarched SDF volume.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    
    @Environment(AppModel.self) private var appModel
    @State private var displayEntity: ModelEntity?
    @State private var renderTask: Task<Void, Never>?
    @State private var debugTask: Task<Void, Never>?
    
    var body: some View {
        RealityView { content in
            guard let raymarchMesh = appModel.raymarchMesh else {
                print("❌ No raymarchMesh available")
                return
            }
            
            print("✅ ImmersiveView: Setting up RealityView")
            
            // Plane size is 2.5x the bounding sphere diameter
            let planeSize = raymarchMesh.volumeHalfExtent * 5.0
            
            // Create display plane
            let mesh = MeshResource.generatePlane(width: planeSize, height: planeSize)
            var material = UnlitMaterial()
            material.color = .init(texture: .init(raymarchMesh.textureResource))
            material.blending = .transparent(opacity: 1.0)
            material.opacityThreshold = 0.1
            material.faceCulling = .none
            
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = raymarchMesh.volumeCenter
            
            displayEntity = entity
            content.add(entity)
            print("✅ Display entity added at \(raymarchMesh.volumeCenter)")
            
            // Create tool tip entity FIRST
            let toolTip = appModel.handTrackingTool.createToolTipEntity()
            content.add(toolTip)
            print("✅ Tool tip entity added to scene")
            print("   Tool tip initial position: \(toolTip.position)")
            
            // Verify the entity is in the scene
            print("   Tool tip parent: \(String(describing: toolTip.parent))")
            
            // Do initial render
            raymarchMesh.render()
            
            // Start ARKit tracking
            Task {
                do {
                    try await appModel.startTracking()
                    print("✅ ARKit tracking started successfully")
                } catch {
                    print("❌ Failed to start ARKit tracking: \(error)")
                    print("   Starting debug animation as fallback...")
                    // Start debug animation if tracking fails
                    appModel.handTrackingTool.startDebugAnimation()
                }
            }
            
        } update: { content in
            // Update raymarch material
            guard let entity = displayEntity,
                  let raymarchMesh = appModel.raymarchMesh else { return }
            
            var material = UnlitMaterial()
            material.color = .init(texture: .init(raymarchMesh.textureResource))
            material.blending = .transparent(opacity: 1.0)
            material.opacityThreshold = 0.1
            material.faceCulling = .none
            entity.model?.materials = [material]
        }
        .onAppear {
            print("🎬 ImmersiveView appeared")
            startRenderLoop()
        }
        .onDisappear {
            print("🎬 ImmersiveView disappeared")
            renderTask?.cancel()
            debugTask?.cancel()
            appModel.stopTracking()
        }
    }
    
    private func startRenderLoop() {
        renderTask = Task { @MainActor in
            print("🎬 Render loop started")
            var frameCount = 0
            
            while !Task.isCancelled {
                renderFrame()
                frameCount += 1
                
                // Log every 5 seconds (~450 frames at 90fps)
                if frameCount % 450 == 0 {
                    print("🎬 Rendered \(frameCount) frames")
                    if let toolTip = appModel.handTrackingTool.toolTipEntity {
                        print("   Tool tip position: \(toolTip.position)")
                        print("   Hand tracking active: \(appModel.handTrackingTool.isTracking)")
                    }
                }
                
                try? await Task.sleep(nanoseconds: 11_111_111) // ~90 FPS
            }
        }
    }
    
    @MainActor
    private func renderFrame() {
        guard let raymarchMesh = appModel.raymarchMesh,
              let entity = displayEntity else { return }
        
        // Get head position from tracking
        let timestamp = CACurrentMediaTime()
        if let anchor = appModel.queryDeviceAnchor(at: timestamp) {
            let headPos = SIMD3<Float>(
                anchor.originFromAnchorTransform.columns.3.x,
                anchor.originFromAnchorTransform.columns.3.y,
                anchor.originFromAnchorTransform.columns.3.z
            )
            
            let volumeCenter = raymarchMesh.volumeCenter
            let volumeHalfExtent = raymarchMesh.volumeHalfExtent
            
            // Calculate direction from camera to volume
            let toVolume = simd_normalize(volumeCenter - headPos)
            
            // Position plane at the BACK of the volume
            let planePosition = volumeCenter + toVolume * volumeHalfExtent
            entity.position = planePosition
            
            // Make plane face the camera
            let defaultNormal = SIMD3<Float>(0, 0, 1)
            let rotation = simd_quatf(from: defaultNormal, to: -toVolume)
            entity.orientation = rotation
            
            // Update raymarching camera
            raymarchMesh.setCamera(from: anchor.originFromAnchorTransform)
        }
        
        // Perform raymarching
        raymarchMesh.render()
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
