================================================================================
THAILAND SUMMER GAMEJAM 2026 - SONGKRAN HAZARD: 4LOM
LANDMARK 3D ASSET: SILOM CONSTRUCTION SITE (MODULAR & DE-SQUARED)
================================================================================

1. OVERVIEW & LOCATION
--------------------------------------------------------------------------------
This asset reconstructs the active high-rise construction site located directly on 
Silom Road, Bangkok (138 Si Lom Road, across from Bangkok Bank Head Office).
Google Maps Reference: https://maps.app.goo.gl/JV8xZm7vT4k4J4YD6

Rendered in the retro PS1 arcade racing aesthetic with soft low-poly styling,
de-squared vehicles, cylindrical wheels, and open structural lattice work.

2. MODULAR 3-MATERIAL ARCHITECTURE
--------------------------------------------------------------------------------
Split into 3 dedicated high-resolution 2048x2048 PBR texture sets:

A. Mat_Construction_Site:
   - Corrugated hoarding walls with green dust scrim netting trim and copings.
   - Official 3D Thai signboards (ITD contractor header, Green/White SAFETY FIRST 
     with 4 circular blue PPE pictograms, Deep Blue Project Spec board, Danger warning,
     and PYLON brand board).
   - Overhead white steel lattice truss gantry and clearance hazard bar.
   - Pedestrian sidewalk tiles, raised green planter hedge, and street curb drop.
   - Sloped driveway apron paved with wet dark interlocking heavy steel road plates.
   - Active foundation pit: compacted red-brown Bangkok clay, timber formwork border,
     troweled concrete mudmat pad, tied rebar reinforcement grid, and chipped bored pile caps.
   - Multi-tiered, faceted low-poly tropical tree canopy volumes.
   - Clean, open sidewalk & gate area ready for user's manual prop placement!

B. Mat_Construction_Equipment:
   - Heavy-duty diesel generator / air compressor power unit (Denyo blue, louvers, exhaust).
   - ISO 20ft contractor storage & office container (ocean blue, corrugated panels, door latch).
   - Galvanized wheel-wash rumble grid station with yellow hazard guide curbs.

C. Mat_Construction_Crane:
   - Mobile all-terrain crane carrier: heavy 8x8 chassis, 12-sided all-terrain wheels,
     driver cab, outrigger beams and ground stabilizer pads.
   - Slewing upperworks superstructure with counterweight ballast and glazed operator cab.
   - Telescoping 4-stage boom elevated at 62 degrees: Stage 1 with bold ITD LIEBHERR branding,
     Stages 2 & 3 clean Liebherr yellow, boom head with hazard chevrons, steel cable & 50t hook.

3. TECHNICAL METRICS & VALIDATION
--------------------------------------------------------------------------------
- Geometry:
  * Total Unique Welded Vertices: 1,640
  * Total Triangles: 3,064
    - Mat_Construction_Site:       1,128 triangles
    - Mat_Construction_Equipment:    468 triangles
    - Mat_Construction_Crane:      1,468 triangles
  * 100% Watertight Manifold Topology, Zero duplicate vertices
- Textures (3 Sets of 2048x2048 PBR):
  * Construction_Site_BaseColor.png / RoughnessMetallic.png / Normal.png
  * Construction_Equipment_BaseColor.png / RoughnessMetallic.png / Normal.png
  * Construction_Crane_BaseColor.png / RoughnessMetallic.png / Normal.png
- Dimensions:
  * Width (X): 24.0 m (-12.0m to +12.0m)
  * Depth (Z): 18.0 m (-16.0m to +2.0m)
  * Height (Y): 22.0 m (Street level Y=0.0m, Pit floor Y=-2.0m, Crane tip Y=22.0m)

4. FILE MANIFEST
--------------------------------------------------------------------------------
- Landmark_ConstructionSite.glb             (Multi-material glTF 2.0 with all 3 materials)
- Landmark_ConstructionSite.obj             (Multi-material Wavefront OBJ)
- Landmark_ConstructionSite.mtl             (Material definition file)
- Construction_Site_*.png                   (Site PBR maps: BaseColor, ORM, Normal)
- Construction_Equipment_*.png              (Equipment PBR maps: BaseColor, ORM, Normal)
- Construction_Crane_*.png                  (Crane PBR maps: BaseColor, ORM, Normal)
- load_construction_in_maya.py              (Maya multi-material automated loader)
- README_CONSTRUCTION_SITE.txt              (This documentation)

5. AUTODESK MAYA SETUP
--------------------------------------------------------------------------------
1. Open Autodesk Maya.
2. Open Script Editor (Python tab).
3. Paste and run load_construction_in_maya.py.
4. The script builds standardSurface shaders for all 3 materials, links all textures,
   and saves landmark_constructionsite.mb automatically.
================================================================================
