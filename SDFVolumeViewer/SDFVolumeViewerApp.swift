//
//  SDFVolumeViewerApp.swift
//  SDFVolumeViewer
//
//  Main app entry point using RealityKit architecture.
//

import SwiftUI

@main
struct SDFVolumeViewerApp: App {
    
    @State private var appModel = AppModel()
    
    var body: some Scene {
        // Control window
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 450, height: 400)
        
        // Immersive space for 3D viewing
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
