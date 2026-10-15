================================================================================
Bangkok Bank Head Office (Silom Road) - 3D Landmark Asset Package
Game: Songkran Hazard: 4Lom (Thailand Summer Jam 2026)
Style: Low-Poly Retro PS1 Arcade Brutalist Architectural Style
Engine Compatibility: Godot 4.x / Unity / Unreal Engine / WebGL
================================================================================

PACKAGE CONTENTS:
1. 3D Model:
   - Landmark_BangkokBank_HeadOffice.glb : Standalone binary glTF with embedded textures, 
                                          doubleSided enabled, optimized for real-time rendering.
   - Landmark_BangkokBank_HeadOffice.obj : Standard Wavefront OBJ format.
   - Landmark_BangkokBank_HeadOffice.mtl : Standard Material Template Library.

2. Modular PBR Textures (2048x2048 PNG):
   - Mat_BBL_Tower  : BaseColor, RoughnessMetallic, Normal (Tower Louvers, Helipad, Plant Rooms)
   - Mat_BBL_Podium : BaseColor, RoughnessMetallic, Normal (15° Canted Facade, Garuda, Garage, Ramp)
   - Mat_BBL_Arcade : BaseColor, RoughnessMetallic, Normal (Parabolic Arches, Bronze Doors, ATM Center)

3. High-Resolution Renders & Inspection Previews:
   - bbl_ho_street_hero.png         : Street level hero view
   - bbl_ho_hero_aerial.png          : High aerial 3/4 overview
   - bbl_ho_colonnade_doors_atm.png  : Colonnade double doors & ATM center
   - bbl_ho_garuda_true_1to1.png     : Royal Golden Garuda emblem (1:1 circular halo)
   - bbl_ho_podium_return_cap.png    : Vertical planar fluted return cap
   - bbl_ho_ground_flank_left.png    : Manifold sealed foundation plinth & garage flank
   - bbl_ho_helical_ramp.png         : Spiral vehicular parking ramp
   - bbl_ho_roof_garden.png          : Landscaped podium roof terrace
   - bbl_ho_helipad_topdown.png      : Summit helipad & antenna mast

4. Procedural Source Pipeline Scripts:
   - build_bbl_ho_model.py       : Universal Mesh Compiler script defining full 3D topology
   - generate_bbl_ho_textures.py : Modular PBR texture atlas generator
   - export_bbl_ho_glb.py        : glTF/GLB packager with multi-material support
   - render_bbl_ho_views.py      : Software renderer for multi-angle inspection
   - mesh_compiler.py            : Universal Mesh Compiler engine

ARCHITECTURAL SPECIFICATIONS:
- Base Width (X)    : 34.0 meters (X: -17.0m to +17.0m)
- Total Depth (Z)   : 29.5 meters (Z: -16.0m to +13.5m)
- Total Height (Y)  : 139.0 meters (33 storeys + core penthouse & communications mast)
- Vertices          : 253 unique welded vertices (0 duplicate vertices, 100% shared topology)
- Triangles         : 314 triangles (Optimized low-poly retro performance)
- Scale             : 1 unit = 1 meter
================================================================================
