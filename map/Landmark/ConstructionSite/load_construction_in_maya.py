# ================================================================================
# AUTODESK MAYA LOADER: SILOM CONSTRUCTION SITE
# Thailand Summer GameJam 2026 - Songkran Hazard: 4Lom
# ================================================================================
# Usage:
# 1. Open Autodesk Maya.
# 2. Open the Script Editor (Python tab).
# 3. Open or paste this script and execute (Ctrl + Enter).
# ================================================================================

import maya.cmds as cmds
import os

def find_asset_dir():
    # 1. Check if __file__ exists (running as file)
    if '__file__' in globals() and globals()['__file__']:
        d = os.path.dirname(os.path.abspath(globals()['__file__'])).replace('\\', '/')
        if os.path.exists(os.path.join(d, "Landmark_ConstructionSite.obj")):
            return d

    # 2. Check current working directory
    cwd = os.getcwd().replace('\\', '/')
    if os.path.exists(os.path.join(cwd, "Landmark_ConstructionSite.obj")):
        return cwd

    # 3. Check Maya current project directory
    try:
        ws = cmds.workspace(q=True, rootDirectory=True)
        if ws:
            ws = ws.replace('\\', '/')
            if os.path.exists(os.path.join(ws, "Landmark_ConstructionSite.obj")):
                return ws
    except Exception:
        pass

    # 4. Fallback: prompt user to select the OBJ file
    print("[Maya Loader] Prompting for Landmark_ConstructionSite.obj location...")
    res = cmds.fileDialog2(fileMode=1, caption="Locate Landmark_ConstructionSite.obj", fileFilter="OBJ Files (*.obj)")
    if res and len(res) > 0:
        return os.path.dirname(res[0]).replace('\\', '/')

    # 5. Last resort fallback
    return "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Landmark"

LANDMARK_DIR = find_asset_dir()
OBJ_PATH = f"{LANDMARK_DIR}/Landmark_ConstructionSite.obj"
MB_PATH = f"{LANDMARK_DIR}/landmark_constructionsite.mb"

MAT_CONFIGS = [
    ("Mat_Construction_Site", "Construction_Site_BaseColor.png", "Construction_Site_RoughnessMetallic.png", "Construction_Site_Normal.png", 0.4),
    ("Mat_Construction_Equipment", "Construction_Equipment_BaseColor.png", "Construction_Equipment_RoughnessMetallic.png", "Construction_Equipment_Normal.png", 0.35),
    ("Mat_Construction_Crane", "Construction_Crane_BaseColor.png", "Construction_Crane_RoughnessMetallic.png", "Construction_Crane_Normal.png", 0.35)
]

print(f"[Maya Loader] Loading Construction Site from: {LANDMARK_DIR}")

cmds.file(new=True, force=True)
cmds.file(OBJ_PATH, i=True, type="OBJ", ignoreVersion=True, ra=True, mergeNamespacesOnClash=False, options="mo=1")

for mat_name, alb_fn, orm_fn, nrm_fn, rough_val in MAT_CONFIGS:
    alb_path = f"{LANDMARK_DIR}/{alb_fn}"
    
    if not cmds.objExists(mat_name):
        shd = cmds.shadingNode("standardSurface", asShader=True, name=mat_name)
        sg = cmds.sets(renderable=True, noSurfaceShader=True, empty=True, name=f"{mat_name}SG")
        cmds.connectAttr(f"{shd}.outColor", f"{sg}.surfaceShader", force=True)

        if os.path.exists(alb_path):
            file_node = cmds.shadingNode("file", asTexture=True, name=f"file_{mat_name}_BaseColor")
            p2t_node = cmds.shadingNode("place2dTexture", asUtility=True, name=f"place2d_{mat_name}")
            for attr in ['coverage', 'translateFrame', 'rotateFrame', 'mirrorU', 'mirrorV', 'stagger', 'wrapU', 'wrapV', 'repeatUV', 'offset', 'rotateUV']:
                cmds.connectAttr(f"{p2t_node}.{attr}", f"{file_node}.{attr}", force=True)
            cmds.connectAttr(f"{p2t_node}.outUV", f"{file_node}.uvCoord", force=True)
            cmds.connectAttr(f"{p2t_node}.outUvFilterSize", f"{file_node}.uvFilterSize", force=True)
            cmds.setAttr(f"{file_node}.fileTextureName", alb_path, type="string")
            cmds.connectAttr(f"{file_node}.outColor", f"{shd}.baseColor", force=True)
            cmds.setAttr(f"{shd}.base", 1.0)
            cmds.setAttr(f"{shd}.specularRoughness", rough_val)

cmds.file(rename=MB_PATH)
try:
    cmds.file(save=True, type="mayaBinary")
    print(f"[Maya Loader] Successfully loaded Modular Construction Site and saved {MB_PATH}!")
except Exception as e:
    print(f"[Maya Loader] Loaded Modular Construction Site in Maya memory. Note: {e}")
