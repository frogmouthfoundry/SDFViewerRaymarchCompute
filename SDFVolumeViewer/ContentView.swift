//
//  ContentView.swift
//  SDFVolumeViewer
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
    
    var body: some View {
        VStack(spacing: 24) {
            
            Text("SDF Volume Viewer")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Raymarching with RealityKit compute")
                .font(.body)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                StatusIndicator(title: "Volume", isActive: appModel.sdfVolume != nil)
                StatusIndicator(title: "Raymarch", isActive: appModel.raymarchMesh != nil)
                StatusIndicator(title: "Tracking", isActive: appModel.isTrackingActive)
            }
            
            if let error = appModel.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            
            Spacer()
            
            Toggle("Enter Immersive View", isOn: $isImmersiveSpaceActive)
                .toggleStyle(.button)
                .controlSize(.large)
                .disabled(appModel.raymarchMesh == nil)
                .onChange(of: isImmersiveSpaceActive) { _, isActive in
                    Task { await handleToggle(isActive: isActive) }
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("• Move your head to view from different angles")
                Text("• Volume displayed at 1.2m height, 50cm in front")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
        }
        .padding(32)
        .frame(width: 450, height: 400)
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
        HStack(spacing: 6) {
            Circle().fill(isActive ? .green : .red).frame(width: 10, height: 10)
            Text(title).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
