//
//  SDFVolumeEditorApp.swift
//  SDFVolumeEditor
//
//  Main app entry point using RealityKit architecture.
//

import SwiftUI

@main
struct SDFVolumeEditorApp: App {
    
    @State private var appModel = AppModel()
    
    init() {
        // Run tests on launch in debug builds
        #if DEBUG
        print("\n🧪 Running startup tests...\n")
        Task { @MainActor in
            HandTrackingTests.runAllTests()
        }
        #endif
    }
    
    var body: some Scene {
        // Control window
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 480, height: 620)
        
        // Immersive space for 3D viewing
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
