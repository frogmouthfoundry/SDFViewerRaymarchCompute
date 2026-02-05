//
//  ImmersiveView.swift
//  SDFVolumeViewer
//
//  RealityKit immersive view displaying the raymarched SDF volume.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    
    @Environment(AppModel.self) private var appModel
    @State private var displayEntity: ModelEntity?
    @State private var renderTask: Task<Void, Never>?
    
    var body: some View {
        ZStack{
            
            RealityView { content in
                
                guard let testEntity = try? Entity.load(named: "Test") else {
                    print("❌ Failed to find Test Entity")
                    return }
                
                testEntity.scale *= 0.45
                testEntity.transform.translation += SIMD3(-0.17,1.4,-0.1)
                content.add(testEntity)
            }
            
            SDFView()
        }
    }
    
    func SDFView()-> some View {
        RealityView { content in
            guard let raymarchMesh = appModel.raymarchMesh else {
                print("❌ No raymarchMesh available")
                return
            }
            
            print("✅ Creating display entity")
            
            // Plane size is 2.5x the bounding sphere diameter
            let planeSize = raymarchMesh.volumeHalfExtent * 5.0
            
            // Create display plane - large enough to show volume from any angle
            let mesh = MeshResource.generatePlane(width: planeSize, height: planeSize)
            var material = UnlitMaterial()
            material.color = .init(texture: .init(raymarchMesh.textureResource))
            material.blending = .transparent(opacity: 1.0)
            material.opacityThreshold = 0.1
            material.faceCulling = .none
            
            let entity = ModelEntity(mesh: mesh, materials: [material])
            
            // Position at volume center initially
            entity.position = raymarchMesh.volumeCenter
            
            displayEntity = entity
            content.add(entity)
            
            print("✅ Entity added")
            print("   Plane size: \(planeSize)")
            print("   Volume center: \(raymarchMesh.volumeCenter)")
            print("   Volume half extent: \(raymarchMesh.volumeHalfExtent)")
            
            // Do initial render
            raymarchMesh.render()
            
            // Start tracking
            Task {
                try? await appModel.startTracking()
            }
            
        } update: { content in
            // Update material
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
            startRenderLoop()
        }
        .onDisappear {
            renderTask?.cancel()
            appModel.stopTracking()
        }
    }
    
    private func startRenderLoop() {
        renderTask = Task { @MainActor in
            while !Task.isCancelled {
                renderFrame()
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
            
            // Position plane at the BACK of the volume (furthest from camera)
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
