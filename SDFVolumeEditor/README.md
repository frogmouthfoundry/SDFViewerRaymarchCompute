# SDF Volume Editor for Apple Vision Pro

A RealityKit-based application that renders and edits 3D volumetric data using raymarching with signed distance fields (SDFs). Supports hand tracking for sculpting.

## Features

- **Real-time SDF Raymarching** - Renders volumetric data using compute shaders
- **Hand Tracking Sculpting** - Use pinch gestures to sculpt the volume
- **Add/Remove Modes** - Toggle between adding and removing material
- **Variable Brush Size** - Adjustable sculpting radius
- **Smooth Strokes** - Capsule-based blending for continuous sculpting

## Architecture

### Key Components

| File | Description |
|------|-------------|
| `SDFVolume.swift` | 3D texture management (follows `VoxelVolume` pattern) |
| `SDFRaymarchMesh.swift` | Raymarching compute output with `LowLevelTexture` |
| `SDFSculptor.swift` | Sculpting compute operations |
| `HandTrackingSculptTool.swift` | Hand tracking for index finger sculpting |
| `RaymarchCompute.metal` | Raymarching compute kernel |
| `SculptCompute.metal` | Sculpting compute kernel |
| `definitions.h` | Shared types between Metal and Swift |

### Hand Tracking Sculpting

- **Pinch (index + thumb)**: Activate sculpting
- **Move while pinching**: Continuous stroke
- **Release pinch**: End stroke
- **Toggle Mode**: Switch between Add (green) and Remove (red)
- **Brush Size Slider**: Adjust sculpting radius (5mm - 50mm)
- **Toggle Hand**: Switch between right and left hand

## Volume File Format

- **File**: `MyModel.volume`
- **Format**: Raw 32-bit float, little-endian
- **Size**: 128 × 128 × 128 × 4 bytes = 8 MB
- **Values**: Signed distance (negative inside, positive outside)

## Building

1. Open `SDFVolumeEditor.xcodeproj` in Xcode 15.4+
2. Select visionOS target
3. Build and run on Apple Vision Pro

## Required Permissions

- **World Sensing**: Head tracking for 3D viewing
- **Hand Tracking**: Finger tracking for sculpting

## File Structure

```
SDFVolumeEditor/
├── SDFVolumeEditor/
│   ├── SDFVolumeEditorApp.swift    # App entry
│   ├── ContentView.swift            # Controls + sculpting UI
│   ├── ImmersiveView.swift          # RealityView
│   ├── AppModel.swift               # State management
│   ├── SDFVolume.swift              # 3D texture
│   ├── SDFRaymarchMesh.swift        # Raymarch rendering
│   ├── SDFSculptor.swift            # Sculpting operations
│   ├── HandTrackingSculptTool.swift # Hand tracking
│   ├── MetalHelpers.swift           # Metal utilities
│   ├── RaymarchCompute.metal        # Raymarch shader
│   ├── SculptCompute.metal          # Sculpt shader
│   ├── definitions.h                # Shared types
│   ├── Header.h                     # Bridging header
│   └── MyModel.volume               # Sample SDF data
└── README.md
```

## License

MIT License
