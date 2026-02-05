#!/usr/bin/env python3
"""
create_volume.py - Generate sample SDF volume data for SDFVolumeViewer

This script creates a 128x128x128 volume file with various SDF primitives
that can be used for testing the SDFVolumeViewer app.

Usage:
    python3 create_volume.py [output_file] [shape]
    
Examples:
    python3 create_volume.py MyModel.volume sphere
    python3 create_volume.py MyModel.volume box
    python3 create_volume.py MyModel.volume torus
    python3 create_volume.py MyModel.volume combined
"""

import struct
import math
import sys
from typing import Tuple

# Volume dimensions
WIDTH = 128
HEIGHT = 128
DEPTH = 128

def length(v: Tuple[float, float, float]) -> float:
    """Calculate the length of a 3D vector."""
    return math.sqrt(v[0]**2 + v[1]**2 + v[2]**2)

def length2d(v: Tuple[float, float]) -> float:
    """Calculate the length of a 2D vector."""
    return math.sqrt(v[0]**2 + v[1]**2)

def normalize_position(x: int, y: int, z: int) -> Tuple[float, float, float]:
    """Convert voxel coordinates to normalized [-1, 1] coordinates."""
    return (
        (x + 0.5) / WIDTH * 2.0 - 1.0,
        (y + 0.5) / HEIGHT * 2.0 - 1.0,
        (z + 0.5) / DEPTH * 2.0 - 1.0
    )

# SDF Primitives (following Inigo Quilez's formulas)

def sdf_sphere(p: Tuple[float, float, float], radius: float = 0.7) -> float:
    """Signed distance to a sphere centered at origin."""
    return length(p) - radius

def sdf_box(p: Tuple[float, float, float], size: Tuple[float, float, float] = (0.5, 0.5, 0.5)) -> float:
    """Signed distance to a box centered at origin."""
    qx = abs(p[0]) - size[0]
    qy = abs(p[1]) - size[1]
    qz = abs(p[2]) - size[2]
    
    outside = length((max(qx, 0), max(qy, 0), max(qz, 0)))
    inside = min(max(qx, max(qy, qz)), 0)
    
    return outside + inside

def sdf_torus(p: Tuple[float, float, float], major_radius: float = 0.5, minor_radius: float = 0.2) -> float:
    """Signed distance to a torus centered at origin, lying in XZ plane."""
    # Distance from Y axis in XZ plane
    q = length2d((p[0], p[2])) - major_radius
    return length2d((q, p[1])) - minor_radius

def sdf_cylinder(p: Tuple[float, float, float], height: float = 0.8, radius: float = 0.3) -> float:
    """Signed distance to a vertical cylinder centered at origin."""
    d_xz = length2d((p[0], p[2])) - radius
    d_y = abs(p[1]) - height / 2
    
    outside = length2d((max(d_xz, 0), max(d_y, 0)))
    inside = min(max(d_xz, d_y), 0)
    
    return outside + inside

def sdf_capsule(p: Tuple[float, float, float], height: float = 0.8, radius: float = 0.25) -> float:
    """Signed distance to a vertical capsule centered at origin."""
    # Clamp y to the capsule's line segment
    half_h = height / 2 - radius
    clamped_y = max(-half_h, min(half_h, p[1]))
    
    # Distance to the clamped point on the axis
    return length((p[0], p[1] - clamped_y, p[2])) - radius

def sdf_octahedron(p: Tuple[float, float, float], size: float = 0.6) -> float:
    """Signed distance to an octahedron centered at origin."""
    px, py, pz = abs(p[0]), abs(p[1]), abs(p[2])
    return (px + py + pz - size) * 0.57735027  # 1/sqrt(3)

# SDF Operations

def op_union(d1: float, d2: float) -> float:
    """Union of two SDFs."""
    return min(d1, d2)

def op_subtraction(d1: float, d2: float) -> float:
    """Subtraction: d1 minus d2."""
    return max(d1, -d2)

def op_intersection(d1: float, d2: float) -> float:
    """Intersection of two SDFs."""
    return max(d1, d2)

def op_smooth_union(d1: float, d2: float, k: float = 0.2) -> float:
    """Smooth union of two SDFs."""
    h = max(k - abs(d1 - d2), 0) / k
    return min(d1, d2) - h * h * k * 0.25

# Combined scene

def sdf_combined(p: Tuple[float, float, float]) -> float:
    """A combined scene with multiple primitives."""
    # Main sphere
    sphere = sdf_sphere(p, 0.5)
    
    # Torus around the sphere
    torus = sdf_torus(p, 0.45, 0.1)
    
    # Vertical cylinder through center
    cylinder = sdf_cylinder(p, 1.5, 0.15)
    
    # Combine with smooth union
    result = op_smooth_union(sphere, torus, 0.1)
    result = op_subtraction(result, cylinder)
    
    return result

def sdf_bunny_approximation(p: Tuple[float, float, float]) -> float:
    """A very rough bunny-like shape using primitive combinations."""
    # Body - ellipsoid (stretched sphere)
    body_p = (p[0] / 0.6, (p[1] + 0.1) / 0.5, p[2] / 0.5)
    body = sdf_sphere(body_p, 1.0) * 0.5
    
    # Head
    head_p = (p[0], p[1] - 0.35, p[2] + 0.1)
    head = sdf_sphere(head_p, 0.3)
    
    # Left ear
    ear1_p = (p[0] + 0.1, p[1] - 0.65, p[2] + 0.05)
    ear1 = sdf_capsule(ear1_p, 0.35, 0.06)
    
    # Right ear
    ear2_p = (p[0] - 0.1, p[1] - 0.65, p[2] + 0.05)
    ear2 = sdf_capsule(ear2_p, 0.35, 0.06)
    
    # Combine
    result = op_smooth_union(body, head, 0.15)
    result = op_smooth_union(result, ear1, 0.05)
    result = op_smooth_union(result, ear2, 0.05)
    
    return result

# Volume generation

SHAPES = {
    'sphere': lambda p: sdf_sphere(p, 0.7),
    'box': lambda p: sdf_box(p, (0.5, 0.5, 0.5)),
    'torus': lambda p: sdf_torus(p, 0.5, 0.2),
    'cylinder': lambda p: sdf_cylinder(p, 0.8, 0.3),
    'capsule': lambda p: sdf_capsule(p, 0.8, 0.25),
    'octahedron': lambda p: sdf_octahedron(p, 0.6),
    'combined': sdf_combined,
    'bunny': sdf_bunny_approximation,
}

def generate_volume(sdf_func, output_file: str):
    """Generate a volume file from an SDF function."""
    print(f"Generating {WIDTH}x{HEIGHT}x{DEPTH} volume...")
    
    # Generate SDF values
    values = []
    total = WIDTH * HEIGHT * DEPTH
    
    for z in range(DEPTH):
        for y in range(HEIGHT):
            for x in range(WIDTH):
                # Convert to normalized coordinates
                p = normalize_position(x, y, z)
                
                # Calculate SDF value
                dist = sdf_func(p)
                values.append(dist)
        
        # Progress indicator
        progress = (z + 1) / DEPTH * 100
        print(f"\rProgress: {progress:.1f}%", end='', flush=True)
    
    print()  # New line after progress
    
    # Write to file
    print(f"Writing to {output_file}...")
    with open(output_file, 'wb') as f:
        for value in values:
            f.write(struct.pack('f', value))
    
    file_size = WIDTH * HEIGHT * DEPTH * 4
    print(f"Done! File size: {file_size:,} bytes ({file_size / 1024 / 1024:.2f} MB)")
    print(f"\nCopy {output_file} to your Xcode project to use it in the app.")

def main():
    # Default values
    output_file = "MyModel.volume"
    shape = "combined"
    
    # Parse arguments
    if len(sys.argv) > 1:
        output_file = sys.argv[1]
    if len(sys.argv) > 2:
        shape = sys.argv[2].lower()
    
    # Validate shape
    if shape not in SHAPES:
        print(f"Unknown shape: {shape}")
        print(f"Available shapes: {', '.join(SHAPES.keys())}")
        sys.exit(1)
    
    print(f"Shape: {shape}")
    generate_volume(SHAPES[shape], output_file)

if __name__ == "__main__":
    main()
