import os, math
import numpy as np
from mesh_compiler import MeshTopologyCompiler

LANDMARK_DIR = "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Landmark"
OBJ_PATH = os.path.join(LANDMARK_DIR, "Landmark_BangkokBank_HeadOffice.obj")
MTL_PATH = os.path.join(LANDMARK_DIR, "Landmark_BangkokBank_HeadOffice.mtl")

print("Compiling Bangkok Bank Head Office (Silom) - Cortex 3.8 Modular Multi-Material Mesh...")

compiler = MeshTopologyCompiler(name="Landmark_BangkokBank_HeadOffice", weld_epsilon=1e-4)

def px_uv(px, py):
    return (float(px) / 2048.0, 1.0 - (float(py) / 2048.0))

# Material Slot Names
MAT_TOWER = "Mat_BBL_Tower"
MAT_PODIUM = "Mat_BBL_Podium"
MAT_ARCADE = "Mat_BBL_Arcade"

# ==============================================================================
# 1. GROUND PLAZA & STREET COLONNADE ARCADE (Mat_BBL_Arcade)
# ==============================================================================
def build_ground_plaza_and_arcade():
    print("  Building Component 1: Ground Plaza & Arcade...")
    
    # 1A. Plaza Foundation Slab & Steps (Y: 0.0 to 0.6)
    # Ground Base Slab facing -Y
    compiler.add_quad(
        [-18.0, 0.0, -16.0], [18.0, 0.0, -16.0], [18.0, 0.0, 13.5], [-18.0, 0.0, 13.5],
        px_uv(1040, 2048), px_uv(2048, 2048), px_uv(2048, 1660), px_uv(1040, 1660),
        normal=[0, -1, 0], mat=MAT_ARCADE
    )
    # Plaza Front Step Riser (Z = 13.5, Y: 0.0..0.6)
    compiler.add_quad(
        [-18.0, 0.0, 13.5], [18.0, 0.0, 13.5], [18.0, 0.6, 13.5], [-18.0, 0.6, 13.5],
        px_uv(1040, 2048), px_uv(2048, 2048), px_uv(2048, 2000), px_uv(1040, 2000),
        normal=[0, 0, 1], mat=MAT_ARCADE
    )
    # Plaza Left Riser (X = -18.0, Y: 0.0..0.6)
    compiler.add_quad(
        [-18.0, 0.0, -16.0], [-18.0, 0.0, 13.5], [-18.0, 0.6, 13.5], [-18.0, 0.6, -16.0],
        px_uv(1040, 2048), px_uv(1500, 2048), px_uv(1500, 2000), px_uv(1040, 2000),
        normal=[-1, 0, 0], mat=MAT_ARCADE
    )
    # Plaza Right Riser (X = +18.0, Y: 0.0..0.6)
    compiler.add_quad(
        [18.0, 0.0, 13.5], [18.0, 0.0, -16.0], [18.0, 0.6, -16.0], [18.0, 0.6, 13.5],
        px_uv(1040, 2048), px_uv(1500, 2048), px_uv(1500, 2000), px_uv(1040, 2000),
        normal=[1, 0, 0], mat=MAT_ARCADE
    )
    # Plaza Rear Step Riser (Z = -16.0, Y: 0.0..0.6) - 100% SEALED BACK PERIMETER!
    compiler.add_quad(
        [18.0, 0.0, -16.0], [-18.0, 0.0, -16.0], [-18.0, 0.6, -16.0], [18.0, 0.6, -16.0],
        px_uv(1040, 2048), px_uv(2048, 2048), px_uv(2048, 2000), px_uv(1040, 2000),
        normal=[0, 0, -1], mat=MAT_ARCADE
    )
    # Plaza Granite Pavement Floor (Y = 0.6, Z: 4.5..13.5, X: -18.0..18.0)
    compiler.add_quad(
        [-18.0, 0.6, 13.5], [18.0, 0.6, 13.5], [18.0, 0.6, 4.5], [-18.0, 0.6, 4.5],
        px_uv(1040, 2048), px_uv(2048, 2048), px_uv(2048, 1660), px_uv(1040, 1660),
        normal=[0, 1, 0], mat=MAT_ARCADE
    )
    # Left Flank Sidewalk Apron Floor (Y = 0.6, Z: -16.0..4.5, X: -18.0..-17.0) - ZERO VOIDS!
    compiler.add_quad(
        [-18.0, 0.6, 4.5], [-17.0, 0.6, 4.5], [-17.0, 0.6, -16.0], [-18.0, 0.6, -16.0],
        px_uv(1040, 2048), px_uv(1200, 2048), px_uv(1200, 1660), px_uv(1040, 1660),
        normal=[0, 1, 0], mat=MAT_ARCADE
    )
    # Right Flank Sidewalk Apron Floor (Y = 0.6, Z: -16.0..4.5, X: 17.0..18.0) - ZERO VOIDS!
    compiler.add_quad(
        [17.0, 0.6, -16.0], [17.0, 0.6, 4.5], [18.0, 0.6, 4.5], [18.0, 0.6, -16.0],
        px_uv(1040, 2048), px_uv(1200, 2048), px_uv(1200, 1660), px_uv(1040, 1660),
        normal=[0, 1, 0], mat=MAT_ARCADE
    )

    # 1B. Recessed Banking Hall Glazing, Doors & ATM Center (Z = 4.5, Y: 0.6 to 5.5)
    # Central Bay: Double Bronze Entrance Doors & Upper Transom Glass (X: -2.5..2.5, 5.0m wide x 4.9m high)
    # Perfectly framed between columns at X = -2.5 and X = 2.5!
    compiler.add_quad(
        [-2.5, 0.6, 4.5], [2.5, 0.6, 4.5], [2.5, 5.5, 4.5], [-2.5, 5.5, 4.5],
        px_uv(0, 2048), px_uv(1024, 2048), px_uv(1024, 1040), px_uv(0, 1040),
        normal=[0, 0, 1], mat=MAT_ARCADE
    )
    # Dedicated ATM Bay: 3 Ergonomic ATM Kiosks & Navy ATM Signboard (X: -7.5..-2.5, 5.0m wide)
    # Perfectly framed between columns at X = -7.5 and X = -2.5!
    compiler.add_quad(
        [-7.5, 0.6, 4.5], [-2.5, 0.6, 4.5], [-2.5, 5.5, 4.5], [-7.5, 5.5, 4.5],
        px_uv(1040, 1640), px_uv(2048, 1640), px_uv(2048, 1040), px_uv(1040, 1040),
        normal=[0, 0, 1], mat=MAT_ARCADE
    )
    # Left Outer Glazing Bay: Bronze-Framed Banking Lobby Windows (X: -17.0..-7.5, 9.5m wide)
    compiler.add_quad(
        [-17.0, 0.6, 4.5], [-7.5, 0.6, 4.5], [-7.5, 5.5, 4.5], [-17.0, 5.5, 4.5],
        px_uv(1040, 1024), px_uv(2048, 1024), px_uv(2048, 40), px_uv(1040, 40),
        normal=[0, 0, 1], mat=MAT_ARCADE
    )
    # Right Wing Glazing Bay: Bronze-Framed Banking Lobby Windows (X: 2.5..17.0, 14.5m wide)
    compiler.add_quad(
        [2.5, 0.6, 4.5], [17.0, 0.6, 4.5], [17.0, 5.5, 4.5], [2.5, 5.5, 4.5],
        px_uv(1040, 1024), px_uv(2048, 1024), px_uv(2048, 40), px_uv(1040, 40),
        normal=[0, 0, 1], mat=MAT_ARCADE
    )

    # 1C. 6 Sculptural Parabolic/Curved Concrete Arcade Arches
    # 6 Piers spaced at X = -12.5, -7.5, -2.5, 2.5, 7.5, 12.5 (5.0m wide grand center opening!)
    pier_centers = [-12.5, -7.5, -2.5, 2.5, 7.5, 12.5]
    pier_w = 0.8 # 0.8m wide
    for cx in pier_centers:
        px0, px1 = cx - pier_w/2, cx + pier_w/2
        pz0, pz1 = 8.0, 9.0
        # Pier Front (+Z)
        compiler.add_quad(
            [px0, 0.6, pz1], [px1, 0.6, pz1], [px1, 5.5, pz1], [px0, 5.5, pz1],
            px_uv(ax:=int(abs(cx)*50)%800, 1024), px_uv(ax+70, 1024), px_uv(ax+70, 0), px_uv(ax, 0),
            normal=[0, 0, 1], mat=MAT_ARCADE
        )
        # Pier Left (-X)
        compiler.add_quad(
            [px0, 0.6, pz0], [px0, 0.6, pz1], [px0, 5.5, pz1], [px0, 5.5, pz0],
            px_uv(200, 1024), px_uv(300, 1024), px_uv(300, 0), px_uv(200, 0),
            normal=[-1, 0, 0], mat=MAT_ARCADE
        )
        # Pier Right (+X)
        compiler.add_quad(
            [px1, 0.6, pz1], [px1, 0.6, pz0], [px1, 5.5, pz0], [px1, 5.5, pz1],
            px_uv(300, 1024), px_uv(400, 1024), px_uv(400, 0), px_uv(300, 0),
            normal=[1, 0, 0], mat=MAT_ARCADE
        )
        # Pier Back (-Z, facing banking hall)
        compiler.add_quad(
            [px1, 0.6, pz0], [px0, 0.6, pz0], [px0, 5.5, pz0], [px1, 5.5, pz0],
            px_uv(200, 1024), px_uv(270, 1024), px_uv(270, 0), px_uv(200, 0),
            normal=[0, 0, -1], mat=MAT_ARCADE
        )

    # Arched Spandrels between Piers (Upper Arch Vaults: Y: 4.2 to 5.5, Z = 8.5)
    for i in range(len(pier_centers) - 1):
        x_left = pier_centers[i] + pier_w/2
        x_right = pier_centers[i+1] - pier_w/2
        # Front Arch Spandrel
        compiler.add_quad(
            [x_left, 4.2, 9.0], [x_right, 4.2, 9.0], [x_right, 5.5, 9.0], [x_left, 5.5, 9.0],
            px_uv(100, 400), px_uv(700, 400), px_uv(700, 0), px_uv(100, 0),
            normal=[0, 0, 1], mat=MAT_ARCADE
        )
        # Vaulted Arch Soffit Underside (facing -Y)
        compiler.add_quad(
            [x_left, 4.2, 8.0], [x_right, 4.2, 8.0], [x_right, 4.2, 9.0], [x_left, 4.2, 9.0],
            px_uv(100, 400), px_uv(700, 400), px_uv(700, 300), px_uv(100, 300),
            normal=[0, -1, 0], mat=MAT_ARCADE
        )

    # Flank End Spandrels (from outermost piers to X = ±17.0m)
    # Left Flank Spandrel (X: -17.0 to -12.9)
    compiler.add_quad(
        [-17.0, 4.2, 9.0], [-12.9, 4.2, 9.0], [-12.9, 5.5, 9.0], [-17.0, 5.5, 9.0],
        px_uv(100, 400), px_uv(700, 400), px_uv(700, 0), px_uv(100, 0),
        normal=[0, 0, 1], mat=MAT_ARCADE
    )
    compiler.add_quad(
        [-17.0, 4.2, 8.0], [-12.9, 4.2, 8.0], [-12.9, 4.2, 9.0], [-17.0, 4.2, 9.0],
        px_uv(100, 400), px_uv(700, 400), px_uv(700, 300), px_uv(100, 300),
        normal=[0, -1, 0], mat=MAT_ARCADE
    )
    # Right Flank Spandrel (X: 12.9 to 17.0)
    compiler.add_quad(
        [12.9, 4.2, 9.0], [17.0, 4.2, 9.0], [17.0, 5.5, 9.0], [12.9, 5.5, 9.0],
        px_uv(100, 400), px_uv(700, 400), px_uv(700, 0), px_uv(100, 0),
        normal=[0, 0, 1], mat=MAT_ARCADE
    )
    compiler.add_quad(
        [12.9, 4.2, 8.0], [17.0, 4.2, 8.0], [17.0, 4.2, 9.0], [12.9, 4.2, 9.0],
        px_uv(100, 400), px_uv(700, 400), px_uv(700, 300), px_uv(100, 300),
        normal=[0, -1, 0], mat=MAT_ARCADE
    )

    # 1D. Arcade Ceiling Soffit (Y = 5.5, Z: 4.5 to 9.0, X: -17.0..17.0)
    # 100% Solid Enclosed Ceiling Soffit across all 34m - ZERO SEE-THROUGH HOLES!
    compiler.add_quad(
        [-17.0, 5.5, 4.5], [17.0, 5.5, 4.5], [17.0, 5.5, 9.0], [-17.0, 5.5, 9.0],
        px_uv(0, 1024), px_uv(1024, 1024), px_uv(1024, 600), px_uv(0, 600),
        normal=[0, -1, 0], mat=MAT_ARCADE
    )

    # 1E. Arcade End-Walls (Left & Right, Y: 0.6..5.5, Z: 4.5..9.0 at X = ±17.0m)
    # Left arcade closure wall (X = -17.0) - SEALS FLANK 100%!
    compiler.add_quad(
        [-17.0, 0.6, 4.5], [-17.0, 0.6, 9.0], [-17.0, 5.5, 9.0], [-17.0, 5.5, 4.5],
        px_uv(0, 1024), px_uv(400, 1024), px_uv(400, 0), px_uv(0, 0),
        normal=[-1, 0, 0], mat=MAT_ARCADE
    )
    # Right arcade closure wall (X = +17.0) - SEALS FLANK 100%!
    compiler.add_quad(
        [17.0, 0.6, 9.0], [17.0, 0.6, 4.5], [17.0, 5.5, 4.5], [17.0, 5.5, 9.0],
        px_uv(0, 1024), px_uv(400, 1024), px_uv(400, 0), px_uv(0, 0),
        normal=[1, 0, 0], mat=MAT_ARCADE
    )

# ==============================================================================
# 2. CANTED BRUTALIST PODIUM & ROYAL GARUDA (Mat_BBL_Podium)
# ==============================================================================
def build_canted_podium():
    print("  Building Component 2: 15° Canted Brutalist Podium & Garuda...")
    
    # 2A. 15° Forward-Sloping Fluted Podium Facade (Y: 5.5 to 14.0)
    # Bottom: Y = 5.5, Z = 9.0. Mid: Y = 7.2, Z = 9.50. Top: Y = 14.0, Z = 11.50.
    # Subdivided at Y = 7.2m to ensure 100% coplanar welded topology with Garuda emblem!
    
    # Left Fluted Wing - Bottom (X: -17.0 to -3.5, Y: 5.5 to 7.2, Width = 13.5m = 27 flutes)
    compiler.add_quad(
        [-17.0, 5.5, 9.0], [-3.5, 5.5, 9.0], [-3.5, 7.2, 9.50], [-17.0, 7.2, 9.50],
        px_uv(0, 500), px_uv(1728, 500), px_uv(1728, 380), px_uv(0, 380),
        normal=[0.0, 0.282, 0.959], mat=MAT_PODIUM
    )
    # Left Fluted Wing - Top (X: -17.0 to -3.5, Y: 7.2 to 14.0, Width = 13.5m = 27 flutes)
    compiler.add_quad(
        [-17.0, 7.2, 9.50], [-3.5, 7.2, 9.50], [-3.5, 14.0, 11.50], [-17.0, 14.0, 11.50],
        px_uv(0, 380), px_uv(1728, 380), px_uv(1728, 0), px_uv(0, 0),
        normal=[0.0, 0.282, 0.959], mat=MAT_PODIUM
    )
    
    # Center Inset - Bottom (X: -3.5 to 3.5, Y: 5.5 to 7.2, Width = 7.0m = 14 flutes)
    # Perfectly continuous 14 flutes sharing EXACT same UVs as Garuda emblem above!
    compiler.add_quad(
        [-3.5, 5.5, 9.0], [3.5, 5.5, 9.0], [3.5, 7.2, 9.50], [-3.5, 7.2, 9.50],
        px_uv(576, 1530), px_uv(1472, 1530), px_uv(1472, 1330), px_uv(576, 1330),
        normal=[0.0, 0.282, 0.959], mat=MAT_PODIUM
    )
    
    # 2B. Dedicated 1:1 Royal Golden Garuda Emblem (X: -3.5 to 3.5, Y: 7.2 to 14.0)
    # TRUE 1:1 SQUARE (7.0m x 7.09m), welded at Y = 7.2m with ZERO seam or phase jump!
    compiler.add_quad(
        [-3.5, 7.2, 9.50], [3.5, 7.2, 9.50], [3.5, 14.0, 11.50], [-3.5, 14.0, 11.50],
        px_uv(576, 1330), px_uv(1472, 1330), px_uv(1472, 512), px_uv(576, 512),
        normal=[0.0, 0.282, 0.959], mat=MAT_PODIUM
    )
    
    # Right Fluted Wing - Bottom (X: 3.5 to 17.0, Y: 5.5 to 7.2, Width = 13.5m = 27 flutes)
    compiler.add_quad(
        [3.5, 5.5, 9.0], [17.0, 5.5, 9.0], [17.0, 7.2, 9.50], [3.5, 7.2, 9.50],
        px_uv(0, 500), px_uv(1728, 500), px_uv(1728, 380), px_uv(0, 380),
        normal=[0.0, 0.282, 0.959], mat=MAT_PODIUM
    )
    # Right Fluted Wing - Top (X: 3.5 to 17.0, Y: 7.2 to 14.0, Width = 13.5m = 27 flutes)
    compiler.add_quad(
        [3.5, 7.2, 9.50], [17.0, 7.2, 9.50], [17.0, 14.0, 11.50], [3.5, 14.0, 11.50],
        px_uv(0, 380), px_uv(1728, 380), px_uv(1728, 0), px_uv(0, 0),
        normal=[0.0, 0.282, 0.959], mat=MAT_PODIUM
    )

    # 2C. Canted Podium Left & Right Sloped Return Caps - PLANAR UV PROJECTION
    # Left Return (X = -17.0, from Z = 4.5 to sloped front)
    compiler.add_quad(
        [-17.0, 5.5, 4.5], [-17.0, 5.5, 9.0], [-17.0, 14.0, 11.50], [-17.0, 14.0, 4.5],
        px_uv(0, 500), px_uv(576, 500), px_uv(896, 0), px_uv(0, 0),
        normal=[-1, 0, 0], mat=MAT_PODIUM
    )
    # Right Return (X = +17.0, from sloped front to Z = 4.5)
    compiler.add_quad(
        [17.0, 5.5, 9.0], [17.0, 5.5, 4.5], [17.0, 14.0, 4.5], [17.0, 14.0, 11.50],
        px_uv(576, 500), px_uv(0, 500), px_uv(0, 0), px_uv(896, 0),
        normal=[1, 0, 0], mat=MAT_PODIUM
    )

    # 2D. Rear Parking Garage Body - Dedicated Brutalist Concrete Horizontal Louvers
    # Left Garage Wall (X = -17.0, Z: -16.0..4.5, Y: 0.6 to 14.0)
    compiler.add_quad(
        [-17.0, 0.6, -16.0], [-17.0, 0.6, 4.5], [-17.0, 14.0, 4.5], [-17.0, 14.0, -16.0],
        px_uv(0, 1536), px_uv(512, 1536), px_uv(512, 512), px_uv(0, 512),
        normal=[-1, 0, 0], mat=MAT_PODIUM
    )
    # Right Garage Wall (X = +17.0, Z: 4.5..-16.0, Y: 0.6 to 14.0)
    compiler.add_quad(
        [17.0, 0.6, 4.5], [17.0, 0.6, -16.0], [17.0, 14.0, -16.0], [17.0, 14.0, 4.5],
        px_uv(0, 1536), px_uv(512, 1536), px_uv(512, 512), px_uv(0, 512),
        normal=[1, 0, 0], mat=MAT_PODIUM
    )
    # Rear Garage Wall - Split into Louver Bay (Right) and Service Door Bay (Left)
    # Rear Bay 1 (X: 17.0 to 0.0, Z = -16.0, Y: 0.6..14.0)
    compiler.add_quad(
        [17.0, 0.6, -16.0], [0.0, 0.6, -16.0], [0.0, 14.0, -16.0], [17.0, 14.0, -16.0],
        px_uv(0, 1536), px_uv(512, 1536), px_uv(512, 512), px_uv(0, 512),
        normal=[0, 0, -1], mat=MAT_PODIUM
    )
    # Rear Bay 2 (X: 0.0 to -17.0, Z = -16.0, Y: 0.6..14.0)
    compiler.add_quad(
        [0.0, 0.6, -16.0], [-17.0, 0.6, -16.0], [-17.0, 14.0, -16.0], [0.0, 14.0, -16.0],
        px_uv(1536, 1536), px_uv(2048, 1536), px_uv(2048, 512), px_uv(1536, 512),
        normal=[0, 0, -1], mat=MAT_PODIUM
    )

# ==============================================================================
# 3. PODIUM ROOFTOP GARDEN & WATERTIGHT ROOF DECK (Mat_BBL_Podium)
# ==============================================================================
def build_podium_roof_garden_and_ramp():
    print("  Building Component 3: Watertight Roof Deck & Helical Ramp...")
    
    # 3A. Front Landscaped Roof Garden Terrace (Y = 14.0, Z: 5.0 to 11.5, X: -17.0..17.0)
    compiler.add_quad(
        [-17.0, 14.0, 11.5], [17.0, 14.0, 11.5], [17.0, 14.0, 5.0], [-17.0, 14.0, 5.0],
        px_uv(0, 2048), px_uv(1024, 2048), px_uv(1024, 1536), px_uv(0, 1536),
        normal=[0, 1, 0], mat=MAT_PODIUM
    )
    
    # 3B. Front Sunken Core Apron - SEALS THE 0.8m GAP UNDER TOWER GLASS FACADE! (Y = 14.0, X: -9.0..9.0, Z: 4.2..5.0)
    compiler.add_quad(
        [-9.0, 14.0, 5.0], [9.0, 14.0, 5.0], [9.0, 14.0, 4.2], [-9.0, 14.0, 4.2],
        px_uv(80, 1750), px_uv(960, 1750), px_uv(960, 1650), px_uv(80, 1650),
        normal=[0, 1, 0], mat=MAT_PODIUM
    )

    # 3C. West Flank Roof Deck (X: -17.0 to -14.0, Z: -8.0 to 5.0, Y = 14.0)
    compiler.add_quad(
        [-17.0, 14.0, 5.0], [-14.0, 14.0, 5.0], [-14.0, 14.0, -8.0], [-17.0, 14.0, -8.0],
        px_uv(0, 2048), px_uv(300, 2048), px_uv(300, 1536), px_uv(0, 1536),
        normal=[0, 1, 0], mat=MAT_PODIUM
    )

    # 3D. East Flank Roof Deck (X: 14.0 to 17.0, Z: -8.0 to 5.0, Y = 14.0) - SEALS RIGHT SIDE CAVITY!
    compiler.add_quad(
        [14.0, 14.0, 5.0], [17.0, 14.0, 5.0], [17.0, 14.0, -8.0], [14.0, 14.0, -8.0],
        px_uv(1024, 2048), px_uv(1480, 2048), px_uv(1480, 1536), px_uv(1024, 1536),
        normal=[0, 1, 0], mat=MAT_PODIUM
    )

    # 3E. Rear Podium Roof Deck (X: -17.0 to 17.0, Z: -16.0 to -8.0, Y = 14.0) - SEALS REAR CAVITY BEHIND TOWER!
    compiler.add_quad(
        [-17.0, 14.0, -8.0], [17.0, 14.0, -8.0], [17.0, 14.0, -16.0], [-17.0, 14.0, -16.0],
        px_uv(1024, 2048), px_uv(1480, 2048), px_uv(1480, 1536), px_uv(1024, 1536),
        normal=[0, 1, 0], mat=MAT_PODIUM
    )

    # 3F. 3D Circular Helical Parking Ramp Structure (Center at X: 11.5, Z: -12.0, Y: 14.0 to 15.0)
    # 12-sided authentic curved cylindrical parking ramp structure
    cx, cz, cr = 11.5, -12.0, 4.0
    num_segs = 12
    for s in range(num_segs):
        a0 = 2 * math.pi * s / num_segs
        a1 = 2 * math.pi * (s + 1) / num_segs
        p0_x, p0_z = cx + cr * math.cos(a0), cz + cr * math.sin(a0)
        p1_x, p1_z = cx + cr * math.cos(a1), cz + cr * math.sin(a1)
        # Outer Cylindrical Parapet Wall (Y: 14.0 to 15.0)
        compiler.add_quad(
            [p0_x, 14.0, p0_z], [p1_x, 14.0, p1_z], [p1_x, 15.0, p1_z], [p0_x, 15.0, p0_z],
            px_uv(0, 500), px_uv(160, 500), px_uv(160, 420), px_uv(0, 420),
            normal=[math.cos((a0+a1)/2), 0, math.sin((a0+a1)/2)], mat=MAT_PODIUM
        )
        # Parapet Top Cap
        ir = cr - 0.4
        ip0_x, ip0_z = cx + ir * math.cos(a0), cz + ir * math.sin(a0)
        ip1_x, ip1_z = cx + ir * math.cos(a1), cz + ir * math.sin(a1)
        compiler.add_quad(
            [p0_x, 15.0, p0_z], [p1_x, 15.0, p1_z], [ip1_x, 15.0, ip1_z], [ip0_x, 15.0, ip0_z],
            px_uv(0, 420), px_uv(160, 420), px_uv(160, 400), px_uv(0, 400),
            normal=[0, 1, 0], mat=MAT_PODIUM
        )
        # Ramp Roadway Deck Surface (Facing +Y at Y = 14.2)
        compiler.add_triangle(
            [cx, 14.2, cz], [p0_x, 14.2, p0_z], [p1_x, 14.2, p1_z],
            px_uv(1792, 1792),
            px_uv(int(1792 + 240 * math.cos(a0)), int(1792 + 240 * math.sin(a0))),
            px_uv(int(1792 + 240 * math.cos(a1)), int(1792 + 240 * math.sin(a1))),
            normal=[0, 1, 0], mat=MAT_PODIUM
        )

    # 3G. Protective Parapet Walls around Podium Perimeter
    # Front Parapet (Y: 14.0 to 14.8, Z = 11.5, X: -17.0..17.0)
    compiler.add_quad(
        [-17.0, 14.0, 11.5], [17.0, 14.0, 11.5], [17.0, 14.8, 11.5], [-17.0, 14.8, 11.5],
        px_uv(0, 100), px_uv(1024, 100), px_uv(1024, 0), px_uv(0, 0),
        normal=[0, 0, 1], mat=MAT_PODIUM
    )
    # Front Parapet Cap
    compiler.add_quad(
        [-17.0, 14.8, 11.5], [17.0, 14.8, 11.5], [17.0, 14.8, 11.2], [-17.0, 14.8, 11.2],
        px_uv(0, 50), px_uv(1024, 50), px_uv(1024, 0), px_uv(0, 0),
        normal=[0, 1, 0], mat=MAT_PODIUM
    )
    # Left Parapet (Y: 14.0 to 14.8, X = -17.0, Z: -16.0..11.5)
    compiler.add_quad(
        [-17.0, 14.0, -16.0], [-17.0, 14.0, 11.5], [-17.0, 14.8, 11.5], [-17.0, 14.8, -16.0],
        px_uv(0, 100), px_uv(800, 100), px_uv(800, 0), px_uv(0, 0),
        normal=[-1, 0, 0], mat=MAT_PODIUM
    )
    # Right Parapet (Y: 14.0 to 14.8, X = 17.0, Z: 11.5..-16.0)
    compiler.add_quad(
        [17.0, 14.0, 11.5], [17.0, 14.0, -16.0], [17.0, 14.8, -16.0], [17.0, 14.8, 11.5],
        px_uv(0, 100), px_uv(800, 100), px_uv(800, 0), px_uv(0, 0),
        normal=[1, 0, 0], mat=MAT_PODIUM
    )
    # Rear Parapet (Y: 14.0 to 14.8, Z = -16.0, X: 17.0..-17.0)
    compiler.add_quad(
        [17.0, 14.0, -16.0], [-17.0, 14.0, -16.0], [-17.0, 14.8, -16.0], [17.0, 14.8, -16.0],
        px_uv(0, 100), px_uv(1024, 100), px_uv(1024, 0), px_uv(0, 0),
        normal=[0, 0, -1], mat=MAT_PODIUM
    )

# ==============================================================================
# 4. MONOLITHIC TWIN-PYLON TOWER SHAFT (Mat_BBL_Tower)
# ==============================================================================
def build_tower_shaft():
    print("  Building Component 4: Twin Monolithic Pylons & Louver Facade...")
    
    # Tower Dimensions: Y: 14.0 to 56.0 (42.0m tall, 33 stories)
    # Front Core: Z = 4.2. Pylon Front: Z = 5.0. Tower Rear: Z = -8.0.
    
    # 4A. Left Monolithic Vertical Pylon (X: -14.0 to -9.0, Z: -8.0 to 5.0)
    # Front (+Z)
    compiler.add_quad(
        [-14.0, 14.0, 5.0], [-9.0, 14.0, 5.0], [-9.0, 56.0, 5.0], [-14.0, 56.0, 5.0],
        px_uv(1240, 1200), px_uv(1640, 1200), px_uv(1640, 0), px_uv(1240, 0),
        normal=[0, 0, 1], mat=MAT_TOWER
    )
    # Left Exterior Shear Wall (X = -14.0, Z: -8.0 to 5.0)
    compiler.add_quad(
        [-14.0, 14.0, -8.0], [-14.0, 14.0, 5.0], [-14.0, 56.0, 5.0], [-14.0, 56.0, -8.0],
        px_uv(1240, 1200), px_uv(1800, 1200), px_uv(1800, 0), px_uv(1240, 0),
        normal=[-1, 0, 0], mat=MAT_TOWER
    )
    # Inner Right Flank (X = -9.0, Z: 4.2 to 5.0, 0.8m recess return to glass core)
    compiler.add_quad(
        [-9.0, 14.0, 5.0], [-9.0, 14.0, 4.2], [-9.0, 56.0, 4.2], [-9.0, 56.0, 5.0],
        px_uv(1240, 1200), px_uv(1320, 1200), px_uv(1320, 0), px_uv(1240, 0),
        normal=[1, 0, 0], mat=MAT_TOWER
    )

    # 4B. Right Monolithic Vertical Pylon (X: 9.0 to 14.0, Z: -8.0 to 5.0)
    # Front (+Z)
    compiler.add_quad(
        [9.0, 14.0, 5.0], [14.0, 14.0, 5.0], [14.0, 56.0, 5.0], [9.0, 56.0, 5.0],
        px_uv(1240, 1200), px_uv(1640, 1200), px_uv(1640, 0), px_uv(1240, 0),
        normal=[0, 0, 1], mat=MAT_TOWER
    )
    # Right Exterior Shear Wall (X = +14.0, Z: 5.0 to -8.0)
    compiler.add_quad(
        [14.0, 14.0, 5.0], [14.0, 14.0, -8.0], [14.0, 56.0, -8.0], [14.0, 56.0, 5.0],
        px_uv(1240, 1200), px_uv(1800, 1200), px_uv(1800, 0), px_uv(1240, 0),
        normal=[1, 0, 0], mat=MAT_TOWER
    )
    # Inner Left Flank (X = 9.0, Z: 4.2 to 5.0, 0.8m recess return to glass core)
    compiler.add_quad(
        [9.0, 14.0, 4.2], [9.0, 14.0, 5.0], [9.0, 56.0, 5.0], [9.0, 56.0, 4.2],
        px_uv(1240, 1200), px_uv(1320, 1200), px_uv(1320, 0), px_uv(1240, 0),
        normal=[-1, 0, 0], mat=MAT_TOWER
    )

    # 4C. Central Recessed Sunshade & Ribbon Window Facade (X: -9.0 to 9.0, Z = 4.2, Y: 14.0 to 56.0)
    # 24 rhythmic horizontal white brise-soleil sunshades & dark reflective glass
    compiler.add_quad(
        [-9.0, 14.0, 4.2], [9.0, 14.0, 4.2], [9.0, 56.0, 4.2], [-9.0, 56.0, 4.2],
        px_uv(0, 1200), px_uv(1200, 1200), px_uv(1200, 0), px_uv(0, 0),
        normal=[0, 0, 1], mat=MAT_TOWER
    )

    # 4D. Continuous Rear Tower Wall (Z = -8.0, X: 14.0 to -14.0, Y: 14.0 to 56.0)
    compiler.add_quad(
        [14.0, 14.0, -8.0], [-14.0, 14.0, -8.0], [-14.0, 56.0, -8.0], [14.0, 56.0, -8.0],
        px_uv(1240, 1200), px_uv(2040, 1200), px_uv(2040, 0), px_uv(1240, 0),
        normal=[0, 0, -1], mat=MAT_TOWER
    )

# ==============================================================================
# 5. ROOFTOP SUMMIT, CIRCULAR HELIPAD & PENTHOUSE (Mat_BBL_Tower)
# ==============================================================================
def build_rooftop_helipad_and_penthouse():
    print("  Building Component 5: Summit Helipad, Penthouse & Parapets...")
    
    # 5A. Tower Summit Roof Deck Floor (Y = 56.0, X: -14.0..14.0, Z: -8.0..5.0)
    # Watertight horizontal roof deck facing +Y
    compiler.add_quad(
        [-14.0, 56.0, 5.0], [14.0, 56.0, 5.0], [14.0, 56.0, -8.0], [-14.0, 56.0, -8.0],
        px_uv(0, 2048), px_uv(1200, 2048), px_uv(1200, 1460), px_uv(0, 1460),
        normal=[0, 1, 0], mat=MAT_TOWER
    )

    # 5B. Top Front Parapet with "Bangkok Bank" Corporate Signboard (Y: 56.0 to 58.0, Z = 5.0)
    # Front Face (X: -14.0 to 14.0, 28m wide x 2.0m tall) - THE ONLY FACE AT Z = 5.0! ZERO Z-FIGHTING!
    compiler.add_quad(
        [-14.0, 56.0, 5.0], [14.0, 56.0, 5.0], [14.0, 58.0, 5.0], [-14.0, 58.0, 5.0],
        px_uv(40, 1440), px_uv(1160, 1440), px_uv(1160, 1240), px_uv(40, 1240),
        normal=[0, 0, 1], mat=MAT_TOWER
    )
    # Front Parapet Top Cap (Y = 58.0, X: -14.0..14.0, Z: 5.0..4.6)
    compiler.add_quad(
        [-14.0, 58.0, 5.0], [14.0, 58.0, 5.0], [14.0, 58.0, 4.6], [-14.0, 58.0, 4.6],
        px_uv(40, 1240), px_uv(1160, 1240), px_uv(1160, 1220), px_uv(40, 1220),
        normal=[0, 1, 0], mat=MAT_TOWER
    )
    # Front Parapet Inner Face (facing -Z towards roof: Z = 4.6, X: 14.0..-14.0, Y: 56.0..58.0)
    compiler.add_quad(
        [14.0, 56.0, 4.6], [-14.0, 56.0, 4.6], [-14.0, 58.0, 4.6], [14.0, 58.0, 4.6],
        px_uv(40, 1440), px_uv(1160, 1440), px_uv(1160, 1240), px_uv(40, 1240),
        normal=[0, 0, -1], mat=MAT_TOWER
    )
    # Front Parapet Left End Cap (facing -X at X = -14.0, Z: 4.6..5.0, Y: 56.0..58.0)
    compiler.add_quad(
        [-14.0, 56.0, 4.6], [-14.0, 56.0, 5.0], [-14.0, 58.0, 5.0], [-14.0, 58.0, 4.6],
        px_uv(1240, 1200), px_uv(1300, 1200), px_uv(1300, 1240), px_uv(1240, 1240),
        normal=[-1, 0, 0], mat=MAT_TOWER
    )
    # Front Parapet Right End Cap (facing +X at X = 14.0, Z: 5.0..4.6, Y: 56.0..58.0)
    compiler.add_quad(
        [14.0, 56.0, 5.0], [14.0, 56.0, 4.6], [14.0, 58.0, 4.6], [14.0, 58.0, 5.0],
        px_uv(1240, 1200), px_uv(1300, 1200), px_uv(1300, 1240), px_uv(1240, 1240),
        normal=[1, 0, 0], mat=MAT_TOWER
    )

    # 5C. Left, Right & Rear Roof Parapet Walls (Y: 56.0 to 57.2) - ZERO OVERLAP WITH FRONT SIGN!
    # Left Parapet (X: -14.0 to -13.6, Z: -8.0 to 4.6)
    # Left Exterior Wall (facing -X)
    compiler.add_quad(
        [-14.0, 56.0, -8.0], [-14.0, 56.0, 4.6], [-14.0, 57.2, 4.6], [-14.0, 57.2, -8.0],
        px_uv(1240, 1200), px_uv(1600, 1200), px_uv(1600, 1240), px_uv(1240, 1240),
        normal=[-1, 0, 0], mat=MAT_TOWER
    )
    # Left Inner Wall (facing +X)
    compiler.add_quad(
        [-13.6, 56.0, 4.6], [-13.6, 56.0, -7.6], [-13.6, 57.2, -7.6], [-13.6, 57.2, 4.6],
        px_uv(1240, 1200), px_uv(1600, 1200), px_uv(1600, 1240), px_uv(1240, 1240),
        normal=[1, 0, 0], mat=MAT_TOWER
    )
    # Left Parapet Top Cap
    compiler.add_quad(
        [-14.0, 57.2, 4.6], [-13.6, 57.2, 4.6], [-13.6, 57.2, -8.0], [-14.0, 57.2, -8.0],
        px_uv(1240, 1200), px_uv(1300, 1200), px_uv(1300, 1240), px_uv(1240, 1240),
        normal=[0, 1, 0], mat=MAT_TOWER
    )

    # Right Parapet (X: 13.6 to 14.0, Z: -8.0 to 4.6)
    # Right Exterior Wall (facing +X)
    compiler.add_quad(
        [14.0, 56.0, 4.6], [14.0, 56.0, -8.0], [14.0, 57.2, -8.0], [14.0, 57.2, 4.6],
        px_uv(1240, 1200), px_uv(1600, 1200), px_uv(1600, 1240), px_uv(1240, 1240),
        normal=[1, 0, 0], mat=MAT_TOWER
    )
    # Right Inner Wall (facing -X)
    compiler.add_quad(
        [13.6, 56.0, -7.6], [13.6, 56.0, 4.6], [13.6, 57.2, 4.6], [13.6, 57.2, -7.6],
        px_uv(1240, 1200), px_uv(1600, 1200), px_uv(1600, 1240), px_uv(1240, 1240),
        normal=[-1, 0, 0], mat=MAT_TOWER
    )
    # Right Parapet Top Cap
    compiler.add_quad(
        [13.6, 57.2, 4.6], [14.0, 57.2, 4.6], [14.0, 57.2, -8.0], [13.6, 57.2, -8.0],
        px_uv(1240, 1200), px_uv(1300, 1200), px_uv(1300, 1240), px_uv(1240, 1240),
        normal=[0, 1, 0], mat=MAT_TOWER
    )

    # Rear Parapet (Z: -8.0 to -7.6, X: -14.0 to 14.0)
    # Rear Exterior Wall (facing -Z)
    compiler.add_quad(
        [14.0, 56.0, -8.0], [-14.0, 56.0, -8.0], [-14.0, 57.2, -8.0], [14.0, 57.2, -8.0],
        px_uv(1240, 1200), px_uv(1600, 1200), px_uv(1600, 1240), px_uv(1240, 1240),
        normal=[0, 0, -1], mat=MAT_TOWER
    )
    # Rear Inner Wall (facing +Z)
    compiler.add_quad(
        [-13.6, 56.0, -7.6], [13.6, 56.0, -7.6], [13.6, 57.2, -7.6], [-13.6, 57.2, -7.6],
        px_uv(1240, 1200), px_uv(1600, 1200), px_uv(1600, 1240), px_uv(1240, 1240),
        normal=[0, 0, 1], mat=MAT_TOWER
    )
    # Rear Parapet Top Cap
    compiler.add_quad(
        [-13.6, 57.2, -7.6], [13.6, 57.2, -7.6], [13.6, 57.2, -8.0], [-13.6, 57.2, -8.0],
        px_uv(1240, 1200), px_uv(1300, 1200), px_uv(1300, 1240), px_uv(1240, 1240),
        normal=[0, 1, 0], mat=MAT_TOWER
    )

    # 5D. Circular Emerald Green Helipad ("H")
    # Raised platform box: X: -5.0 to 5.0 (10m wide), Z: -4.5 to 3.5 (8m deep), Y: 56.0 to 56.35
    # Platform Top (+Y) - 1:1 Aspect Ratio Helipad Target!
    compiler.add_quad(
        [-5.0, 56.35, 3.5], [5.0, 56.35, 3.5], [5.0, 56.35, -4.5], [-5.0, 56.35, -4.5],
        px_uv(1240, 2040), px_uv(2040, 2040), px_uv(2040, 1240), px_uv(1240, 1240),
        normal=[0, 1, 0], mat=MAT_TOWER
    )
    # Platform Sides
    compiler.add_quad([-5.0, 56.0, 3.5], [5.0, 56.0, 3.5], [5.0, 56.35, 3.5], [-5.0, 56.35, 3.5], px_uv(1240, 1300), px_uv(2040, 1300), px_uv(2040, 1240), px_uv(1240, 1240), normal=[0, 0, 1], mat=MAT_TOWER)
    compiler.add_quad([5.0, 56.0, -4.5], [-5.0, 56.0, -4.5], [-5.0, 56.35, -4.5], [5.0, 56.35, -4.5], px_uv(1240, 1300), px_uv(2040, 1300), px_uv(2040, 1240), px_uv(1240, 1240), normal=[0, 0, -1], mat=MAT_TOWER)
    compiler.add_quad([-5.0, 56.0, -4.5], [-5.0, 56.0, 3.5], [-5.0, 56.35, 3.5], [-5.0, 56.35, -4.5], px_uv(1240, 1300), px_uv(2040, 1300), px_uv(2040, 1240), px_uv(1240, 1240), normal=[-1, 0, 0], mat=MAT_TOWER)
    compiler.add_quad([5.0, 56.0, 3.5], [5.0, 56.0, -4.5], [5.0, 56.35, -4.5], [5.0, 56.35, 3.5], px_uv(1240, 1300), px_uv(2040, 1300), px_uv(2040, 1240), px_uv(1240, 1240), normal=[1, 0, 0], mat=MAT_TOWER)

    # 5E. Rooftop Elevator Penthouse & HVAC Cooling Tower Boxes
    # Elevator Penthouse Box (X: -3.5..3.5, Z: -7.5..-4.8, Y: 56.0..60.5)
    compiler.add_box([-3.5, 56.0, -7.5], [3.5, 60.5, -4.8], (1240, 0, 2040, 600), px_uv, mat=MAT_TOWER)
    # Right HVAC Chiller Plant Box (X: 6.0..11.0, Z: -7.2..-2.0, Y: 56.0..58.8)
    compiler.add_box([6.0, 56.0, -7.2], [11.0, 58.8, -2.0], (1240, 0, 2040, 600), px_uv, mat=MAT_TOWER)
    # Left Service Penthouse Box (X: -11.0..-6.0, Z: -7.2..-2.0, Y: 56.0..58.2)
    compiler.add_box([-11.0, 56.0, -7.2], [-6.0, 58.2, -2.0], (1240, 0, 2040, 600), px_uv, mat=MAT_TOWER)

    # 5F. Summit Communications Spire / Antenna Mast (X: -0.2..0.2, Z: -6.2..-5.8, Y: 60.5..66.0)
    compiler.add_box([-0.2, 60.5, -6.2], [0.2, 66.0, -5.8], (1240, 600, 1300, 700), px_uv, mat=MAT_TOWER)

# ==============================================================================
# EXECUTE MODULAR ASSEMBLY
# ==============================================================================
build_ground_plaza_and_arcade()
build_canted_podium()
build_podium_roof_garden_and_ramp()
build_tower_shaft()
build_rooftop_helipad_and_penthouse()

# Write Multi-Material MTL File
with open(MTL_PATH, "w") as f:
    f.write("# Bangkok Bank Head Office (Silom) Materials\n\n")
    # Slot 1: Tower
    f.write(f"newmtl {MAT_TOWER}\n")
    f.write("Ka 1.0 1.0 1.0\nKd 1.0 1.0 1.0\nKs 0.2 0.2 0.2\nd 1.0\nillum 2\n")
    f.write("map_Kd BBL_Tower_BaseColor.png\nmap_refl BBL_Tower_RoughnessMetallic.png\nbump BBL_Tower_Normal.png\n\n")
    # Slot 2: Podium
    f.write(f"newmtl {MAT_PODIUM}\n")
    f.write("Ka 1.0 1.0 1.0\nKd 1.0 1.0 1.0\nKs 0.2 0.2 0.2\nd 1.0\nillum 2\n")
    f.write("map_Kd BBL_Podium_BaseColor.png\nmap_refl BBL_Podium_RoughnessMetallic.png\nbump BBL_Podium_Normal.png\n\n")
    # Slot 3: Arcade
    f.write(f"newmtl {MAT_ARCADE}\n")
    f.write("Ka 1.0 1.0 1.0\nKd 1.0 1.0 1.0\nKs 0.2 0.2 0.2\nd 1.0\nillum 2\n")
    f.write("map_Kd BBL_Arcade_BaseColor.png\nmap_refl BBL_Arcade_RoughnessMetallic.png\nbump BBL_Arcade_Normal.png\n")

compiler.export_obj(OBJ_PATH, os.path.basename(MTL_PATH))
print(f"Successfully compiled Bangkok Bank Head Office (Silom): {OBJ_PATH}")
