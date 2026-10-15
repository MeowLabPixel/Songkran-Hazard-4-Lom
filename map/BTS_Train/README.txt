========================================================================
BANGKOK BTS SKYTRAIN - 3D ASSET PACKAGE (REVISION 10)
Game Project: Songkran Hazard: 4Lom (Game Jam 2026)
Art Style: Retro Low-Poly / PS1 / Dreamcast Arcade Aesthetic
========================================================================

MODEL SPECIFICATIONS:
---------------------
1. Lead Cab Car (BTS_Train_Cab)
   - Triangle Count: 608 triangles (1,410 vertices)
   - Details: Aerodynamic nose, dual tinted trapezoid windshields, 
              amber destination marquee ('008 SAMRONG'), mechanical wipers,
              boomerang LED daytime running lights, modern chin headlights,
              bogie trucks, rooftop HVAC pod, side passenger doors.

2. Middle Trailer Car (BTS_Train_Middle)
   - Triangle Count: 600 triangles (1,392 vertices)
   - Details: 4 side passenger door bays, dual bogie trucks, rooftop HVAC pods,
              underfloor equipment boxes, sealed gangway bulkheads with bellows.

3. Complete 3-Car Consist (BTS_Train_FullConsist)
   - Triangle Count: 1,816 triangles (4,212 vertices)
   - Layout: Lead Cab Car + Middle Trailer Car + Rear Cab Car (reversible)
   - Dimensions: ~65 meters total length, seamless gangway bellows connections.

TEXTURE SPECIFICATIONS:
-----------------------
- Resolution: 2048 x 2048 (2K) Atlas
- Formats:
  * BTS_Train_BaseColor.png          - 24-bit opaque RGB (Albedo)
  * BTS_Train_RoughnessMetallic.png   - Packed ORM Map (R: Occlusion, G: Roughness, B: Metallic)
  * BTS_Train_Normal.png              - Tangent Space Normal Map
- Livery: Authentic Bangkok BTS Skytrain (Off-white / Silver body, Royal Blue lower
          half, Crimson Red swoop, dark navy undercarriage skirt, tinted glass).

FOLDER STRUCTURE IN THIS ZIP:
-----------------------------
/Models
  /FBX       - FBX 2020 format (Unreal Engine, Unity, Godot, Blender)
  /GLTF_GLB  - Standalone glTF 2.0 Binary (textures embedded, web / engine ready)
  /OBJ       - Wavefront OBJ + MTL (universal 3D format with local texture link)
  /Maya      - Autodesk Maya 2027 Binary (.mb) scenes with Blinn shader network
/Textures    - Master PBR 2K textures
/Previews    - High-resolution verification renders from multiple angles
/Pipeline_Scripts - Python source code for procedural model building and texture generation

========================================================================
