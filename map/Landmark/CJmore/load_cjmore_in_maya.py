# ================================================================================
# AUTODESK MAYA LOADER: CJ MORE (SILOM BRANCH)
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
        if os.path.exists(os.path.join(d, "Landmark_CJMore.obj")):
            return d

    # 2. Check current working directory
    cwd = os.getcwd().replace('\\', '/')
    if os.path.exists(os.path.join(cwd, "Landmark_CJMore.obj")):
        return cwd

    # 3. Check Maya current project directory
    try:
        ws = cmds.workspace(q=True, rootDirectory=True)
        if ws:
            ws = ws.replace('\\', '/')
            if os.path.exists(os.path.join(ws, "Landmark_CJMore.obj")):
                return ws
    except Exception:
        pass

    # 4. Fallback: prompt user to select the OBJ file
    print("[Maya Loader] Prompting for Landmark_CJMore.obj location...")
    res = cmds.fileDialog2(fileMode=1, caption="Locate Landmark_CJMore.obj", fileFilter="OBJ Files (*.obj)")
    if res and len(res) > 0:
        return os.path.dirname(res[0]).replace('\\', '/')

    # 5. Last resort fallback
    return "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Landmark"

SCRIPT_DIR = find_asset_dir()
OBJ_PATH = os.path.join(SCRIPT_DIR, "Landmark_CJMore.obj").replace("\\", "/")
MB_PATH = os.path.join(SCRIPT_DIR, "Landmark_CJMore.mb").replace("\\", "/")

MATS = [
    ("Mat_CJMore_Storefront", "CJMore_Storefront_BaseColor.png", "CJMore_Storefront_RoughnessMetallic.png", "CJMore_Storefront_Normal.png"),
    ("Mat_CJMore_CanopySign", "CJMore_CanopySign_BaseColor.png", "CJMore_CanopySign_RoughnessMetallic.png", "CJMore_CanopySign_Normal.png"),
    ("Mat_CJMore_Tower", "CJMore_Tower_BaseColor.png", "CJMore_Tower_RoughnessMetallic.png", "CJMore_Tower_Normal.png")
]

print(f"[Maya Loader] Loading CJ More from: {SCRIPT_DIR}")

cmds.file(new=True, force=True)
cmds.file(OBJ_PATH, i=True, type="OBJ", ignoreVersion=True, ra=True, mergeNamespacesOnClash=False, options="mo=1")

for mat_name, albedo_fn, orm_fn, norm_fn in MATS:
    albedo_path = os.path.join(SCRIPT_DIR, albedo_fn).replace("\\", "/")
    
    if not cmds.objExists(mat_name):
        shd = cmds.shadingNode("standardSurface", asShader=True, name=mat_name)
        sg = cmds.sets(renderable=True, noSurfaceShader=True, empty=True, name=f"{mat_name}SG")
        cmds.connectAttr(f"{shd}.outColor", f"{sg}.surfaceShader", force=True)

        if os.path.exists(albedo_path):
            file_node = cmds.shadingNode("file", asTexture=True, name=f"file_{mat_name}_BaseColor")
            p2t_node = cmds.shadingNode("place2dTexture", asUtility=True, name=f"place2d_{mat_name}")
            for attr in ['coverage', 'translateFrame', 'rotateFrame', 'mirrorU', 'mirrorV', 'stagger', 'wrapU', 'wrapV', 'repeatUV', 'offset', 'rotateUV']:
                cmds.connectAttr(f"{p2t_node}.{attr}", f"{file_node}.{attr}", force=True)
            cmds.connectAttr(f"{p2t_node}.outUV", f"{file_node}.uvCoord", force=True)
            cmds.connectAttr(f"{p2t_node}.outUvFilterSize", f"{file_node}.uvFilterSize", force=True)
            cmds.setAttr(f"{file_node}.fileTextureName", albedo_path, type="string")
            cmds.connectAttr(f"{file_node}.outColor", f"{shd}.baseColor", force=True)
            cmds.setAttr(f"{shd}.base", 1.0)
            cmds.setAttr(f"{shd}.specularRoughness", 0.4)

cmds.file(rename=MB_PATH)
try:
    cmds.file(save=True, type="mayaBinary")
    print(f"[Maya Loader] Successfully loaded CJ More Silom and saved {MB_PATH}!")
except Exception as e:
    print(f"[Maya Loader] Loaded CJ More Silom in Maya memory. Note: {e}")
