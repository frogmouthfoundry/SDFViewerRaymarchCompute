//
//  ContentView.swift
//  SDFVolumeEditor
//
//  Main control panel view.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    @State private var isImmersiveSpaceActive = false
    @State private var sculptRadius: Float = 0.015
    
    var body: some View {
        VStack(spacing: 12) {
            
            Text("SDF Volume Editor")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Status indicators - single row
            HStack(spacing: 8) {
                StatusIndicator(title: "World", isActive: appModel.isTrackingActive)
                StatusIndicator(title: "Hand", isActive: appModel.isHandTrackingActive)
                StatusIndicator(title: "Tracking", isActive: appModel.handTrackingTool.isTracking)
                StatusIndicator(title: "In Bounds", isActive: appModel.handTrackingTool.isInVolumeBounds)
                StatusIndicator(title: "Sculpting", isActive: appModel.handTrackingTool.isSculpting)
            }
            
            if let error = appModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Sculpting controls (only show when in immersive mode)
            if isImmersiveSpaceActive {
                Divider()
                
                VStack(spacing: 10) {
                    Text("Sculpting Controls")
                        .font(.headline)
                    
                    HStack(spacing: 10) {
                        Button(action: { appModel.toggleSculptMode() }) {
                            VStack(spacing: 4) {
                                Image(systemName: appModel.sculptor?.mode == 0 ? "plus.circle.fill" : "minus.circle.fill")
                                    .font(.title2)
                                Text(appModel.sculptor?.mode == 0 ? "Add" : "Remove")
                                    .font(.caption2)
                            }
                            .foregroundStyle(appModel.sculptor?.mode == 0 ? .green : .red)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { appModel.handTrackingTool.toggleHand() }) {
                            VStack(spacing: 4) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.title2)
                                Text(appModel.handTrackingTool.useLeftHand ? "Left" : "Right")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { appModel.startDebugAnimation() }) {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title2)
                                Text("Test")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { appModel.handTrackingTool.stopDebugAnimation() }) {
                            VStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.title2)
                                Text("Stop")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Brush: \(Int(sculptRadius * 1000))mm")
                            .font(.caption)
                        Slider(value: $sculptRadius, in: 0.005...0.05, step: 0.005)
                            .onChange(of: sculptRadius) { _, newValue in
                                appModel.setSculptRadius(newValue)
                            }
                    }
                    .padding(.horizontal)
                    
                    // Debug info
                    VStack(alignment: .leading, spacing: 1) {
                        let pos = appModel.handTrackingTool.toolPosition
                        let dist = appModel.handTrackingTool.distanceToVolume
                        
                        Text("Finger Position:")
                            .font(.caption).bold()
                        Text("  X: \(String(format: "%+.3f", pos.x))  Y: \(String(format: "%+.3f", pos.y))  Z: \(String(format: "%+.3f", pos.z))")
                            .font(.system(size: 11, design: .monospaced))
                        
                        if let sculptor = appModel.sculptor {
                            Text("Volume Bounds (put finger inside):")
                                .font(.caption).bold()
                            Text("  X: \(String(format: "%.2f", sculptor.volumeMin.x)) to \(String(format: "%.2f", sculptor.volumeMax.x))")
                                .font(.system(size: 11, design: .monospaced))
                            Text("  Y: \(String(format: "%.2f", sculptor.volumeMin.y)) to \(String(format: "%.2f", sculptor.volumeMax.y))")
                                .font(.system(size: 11, design: .monospaced))
                            Text("  Z: \(String(format: "%.2f", sculptor.volumeMin.z)) to \(String(format: "%.2f", sculptor.volumeMax.z))")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        
                        Text("Distance to center: \(String(format: "%.2f", dist))m")
                            .font(.system(size: 11, design: .monospaced))
                        Text("Updates: \(appModel.handTrackingTool.updateCount)")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
            
            Toggle("Enter Immersive View", isOn: $isImmersiveSpaceActive)
                .toggleStyle(.button)
                .controlSize(.large)
                .disabled(appModel.raymarchMesh == nil)
                .onChange(of: isImmersiveSpaceActive) { _, isActive in
                    Task { await handleToggle(isActive: isActive) }
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("• Move finger INTO the orange sphere")
                Text("• 'In Bounds' turns green when ready")
                Text("• 'Sculpting' turns green when carving")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 440, height: 680)
        .onAppear {
            appModel.initialize()
        }
        .onChange(of: appModel.immersiveSpaceState) { _, newState in
            if case .closed = newState { isImmersiveSpaceActive = false }
        }
    }
    
    private func handleToggle(isActive: Bool) async {
        if isActive {
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened: appModel.immersiveSpaceState = .open
            case .error: appModel.immersiveSpaceState = .error("Failed to open"); isImmersiveSpaceActive = false
            case .userCancelled: appModel.immersiveSpaceState = .closed; isImmersiveSpaceActive = false
            @unknown default: appModel.immersiveSpaceState = .closed; isImmersiveSpaceActive = false
            }
        } else {
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
            appModel.immersiveSpaceState = .closed
        }
    }
}

struct StatusIndicator: View {
    let title: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(isActive ? .green : .red).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
