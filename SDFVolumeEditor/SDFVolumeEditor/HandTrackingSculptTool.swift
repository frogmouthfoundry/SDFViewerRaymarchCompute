//
//  HandTrackingSculptTool.swift
//  SDFVolumeEditor
//
//  Hand tracking for sculpting using index finger tip.
//

import RealityKit
import ARKit
import SwiftUI

/// Manages hand tracking for sculpting tool
@MainActor
@Observable
final class HandTrackingSculptTool {
    
    // MARK: - Update Task
    
    private var updateTask: Task<Void, Never>?
    private var debugAnimationTask: Task<Void, Never>?
    
    // MARK: - Tool State (Observable)
    
    var isTracking = false
    var toolPosition: SIMD3<Float> = .zero
    var isSculpting = false
    var distanceToVolume: Float = 999.0
    var isInVolumeBounds = false
    
    var useLeftHand = false
    
    // MARK: - Debug
    
    var updateCount = 0
    
    // MARK: - Tool Visualization
    
    var toolTipEntity: ModelEntity?
    private let baseToolRadius: Float = 0.015
    
    // MARK: - Sculpting Reference
    
    weak var sculptor: SDFSculptor?
    
    // MARK: - Initialization
    
    init() {
        print("✅ HandTrackingSculptTool initialized")
    }
    
    // MARK: - Setup
    
    func createToolTipEntity() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: baseToolRadius)
        var material = UnlitMaterial()
        material.color = .init(tint: .red)
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "SculptToolTip"
        entity.position = SIMD3<Float>(0, 1.5, -0.6)
        
        toolTipEntity = entity
        print("✅ Tool tip entity created")
        return entity
    }
    
    func updateToolTipAppearance() {
        guard let toolTipEntity = toolTipEntity else { return }
        
        var material = UnlitMaterial()
        
        if let sculptor = sculptor {
            // Color based on mode and sculpting state
            if isSculpting {
                // Bright color when actively sculpting
                material.color = .init(tint: sculptor.mode == 0 ? .green : .red)
            } else if isInVolumeBounds {
                // Medium color when in bounds but not sculpting
                material.color = .init(tint: sculptor.mode == 0 ? 
                    UIColor(red: 0.5, green: 1.0, blue: 0.5, alpha: 1.0) : 
                    UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0))
            } else {
                // Dim color when outside bounds
                material.color = .init(tint: sculptor.mode == 0 ? 
                    UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1.0) : 
                    UIColor(red: 0.5, green: 0.2, blue: 0.2, alpha: 1.0))
            }
            
            let scale = sculptor.radius / baseToolRadius
            toolTipEntity.scale = SIMD3<Float>(repeating: scale)
        } else {
            material.color = .init(tint: .gray)
        }
        
        toolTipEntity.model?.materials = [material]
    }
    
    // MARK: - Position Update
    
    func updatePosition(_ position: SIMD3<Float>) {
        toolPosition = position
        updateCount += 1
        
        // Update entity position
        toolTipEntity?.position = position
        
        // Check if in volume bounds
        if let sculptor = sculptor {
            isInVolumeBounds = sculptor.isNearVolume(position)
            distanceToVolume = sculptor.distanceToVolumeCenter(position)
        }
    }
    
    // MARK: - Hand Tracking
    
    func startProcessingUpdates(from handProvider: HandTrackingProvider) {
        print("🔄 Starting hand tracking update processing...")
        
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self = self else { return }
            
            print("📡 Waiting for hand anchor updates...")
            
            for await update in handProvider.anchorUpdates {
                await MainActor.run {
                    self.processHandUpdate(update)
                }
            }
            
            print("📡 Hand anchor updates stream ended")
        }
        
        print("✅ Hand tracking update task started")
    }
    
    func stopProcessingUpdates() {
        updateTask?.cancel()
        updateTask = nil
        debugAnimationTask?.cancel()
        debugAnimationTask = nil
        isTracking = false
        isSculpting = false
        print("🛑 Hand tracking update processing stopped")
    }
    
    private func processHandUpdate(_ update: AnchorUpdate<HandAnchor>) {
        let anchor = update.anchor
        
        // Check chirality
        let targetChirality: HandAnchor.Chirality = useLeftHand ? .left : .right
        guard anchor.chirality == targetChirality else { return }
        
        guard anchor.isTracked else {
            if isTracking {
                isTracking = false
                if isSculpting {
                    sculptor?.endStroke()
                    isSculpting = false
                }
            }
            return
        }
        
        // Get skeleton
        guard let skeleton = anchor.handSkeleton else { return }
        
        // Get index finger tip
        let indexTip = skeleton.joint(.indexFingerTip)
        guard indexTip.isTracked else { return }
        
        // Calculate world position
        let jointTransform = anchor.originFromAnchorTransform * indexTip.anchorFromJointTransform
        let position = SIMD3<Float>(
            jointTransform.columns.3.x,
            jointTransform.columns.3.y,
            jointTransform.columns.3.z
        )
        
        let wasTracking = isTracking
        isTracking = true
        
        if !wasTracking {
            print("👋 Hand tracking started at \(position)")
        }
        
        // Update position
        updatePosition(position)
        
        // Sculpting logic - sculpt when inside volume bounds
        if let sculptor = sculptor {
            let wasSculpting = isSculpting
            isSculpting = isInVolumeBounds  // Sculpt whenever in bounds
            
            if isSculpting && !wasSculpting {
                sculptor.beginStroke()
                print("🎨 Started sculpting at \(position)")
            } else if !isSculpting && wasSculpting {
                sculptor.endStroke()
                print("🎨 Stopped sculpting")
            }
            
            if isSculpting {
                sculptor.sculpt(at: position)
            }
        }
        
        updateToolTipAppearance()
    }
    
    // MARK: - Debug Animation
    
    func startDebugAnimation() {
        print("🧪 Starting debug animation...")
        
        debugAnimationTask?.cancel()
        debugAnimationTask = Task { @MainActor in
            var angle: Float = 0
            let center = SIMD3<Float>(0, 1.5, -0.6)
            let animRadius: Float = 0.08
            
            // Start a stroke
            sculptor?.beginStroke()
            
            while !Task.isCancelled {
                angle += 0.03
                let x = center.x + cos(angle) * animRadius
                let z = center.z + sin(angle) * animRadius
                let position = SIMD3<Float>(x, center.y, z)
                
                updatePosition(position)
                
                // Sculpt during animation
                if let sculptor = sculptor, isInVolumeBounds {
                    isSculpting = true
                    sculptor.sculpt(at: position)
                }
                
                updateToolTipAppearance()
                
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            
            sculptor?.endStroke()
        }
    }
    
    func stopDebugAnimation() {
        debugAnimationTask?.cancel()
        debugAnimationTask = nil
        if isSculpting {
            sculptor?.endStroke()
            isSculpting = false
        }
    }
    
    // MARK: - Mode Control
    
    func toggleHand() {
        useLeftHand = !useLeftHand
        print("🤚 Using \(useLeftHand ? "left" : "right") hand")
    }
}
