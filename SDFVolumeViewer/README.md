# SDF Volume Viewer for Apple Vision Pro

A RealityKit-based application that renders 3D volumetric data using raymarching with signed distance fields (SDFs).

## Architecture

This project follows the MarchingCubes-Test pattern from Apple's sample code:

### Key Components

| File | Description |
|------|-------------|
| `SDFVolume.swift` | 3D texture management (follows `VoxelVolume` pattern) |
| `SDFRaymarchMesh.swift` | Compute output with `LowLevelTexture` (follows `MarchingCubesMesh` pattern) |
| `SDFVolumeSystem` | RealityKit System for compute updates |
| `RaymarchCompute.metal` | Raymarching compute kernel |
| `MetalHelpers.swift` | Global `metalDevice` and helpers |

### RealityKit Integration Pattern

```
┌─────────────────┐     ┌──────────────────────┐
│   SDFVolume     │────▶│   SDFRaymarchMesh    │
│ (3D MTLTexture) │     │ (LowLevelTexture +   │
└─────────────────┘     │  update(context:))   │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │  SDFVolumeSystem     │
                        │ (RealityKit System)  │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │    ModelEntity       │
                        │ (UnlitMaterial +     │
                        │  TextureResource)    │
                        └──────────────────────┘
```

Key features:
- **No DrawableQueue** - Uses `LowLevelTexture` instead
- **No explicit render() calls** - Uses RealityKit's `System` pattern
- **Compute via `ComputeUpdateContext`** - Same pattern as MarchingCubes-Test

## Volume File Format

- **File**: `MyModel.volume`
- **Format**: Raw 32-bit float, little-endian
- **Size**: 128 × 128 × 128 × 4 bytes = 8 MB
- **Values**: Signed distance (negative inside, positive outside)

## Building

1. Open `SDFVolumeViewer.xcodeproj` in Xcode 15.4+
2. Select visionOS target
3. Build and run

## File Structure

```
SDFVolumeViewer/
├── SDFVolumeViewer/
│   ├── SDFVolumeViewerApp.swift   # App entry
│   ├── ContentView.swift           # Controls
│   ├── ImmersiveView.swift         # RealityView + System
│   ├── AppModel.swift              # State
│   ├── SDFVolume.swift             # 3D texture (VoxelVolume pattern)
│   ├── SDFRaymarchMesh.swift       # Compute output (MarchingCubesMesh pattern)
│   ├── MetalHelpers.swift          # Global metalDevice
│   ├── RaymarchCompute.metal       # Compute kernel
│   ├── ShaderTypes.h               # Shared types
│   └── MyModel.volume              # Sample SDF data
├── create_volume.py                # Volume generator
└── README.md
```

## License

MIT License
