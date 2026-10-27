# ================================================================================
# AUTODESK MAYA LOADER: LANDMARK 1 (ITF TOWER - SILOM ROAD)
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
        if os.path.exists(os.path.join(d, "Landmark1.obj")):
            return d

    # 2. Check current working directory
    cwd = os.getcwd().replace('\\', '/')
    if os.path.exists(os.path.join(cwd, "Landmark1.obj")):
        return cwd

    # 3. Check Maya current project directory
    try:
        ws = cmds.workspace(q=True, rootDirectory=True)
        if ws:
            ws = ws.replace('\\', '/')
            if os.path.exists(os.path.join(ws, "Landmark1.obj")):
                return ws
    except Exception:
        pass

    # 4. Fallback: prompt user to select the OBJ file
    print("[Maya Loader] Prompting for Landmark1.obj location...")
    res = cmds.fileDialog2(fileMode=1, caption="Locate Landmark1.obj", fileFilter="OBJ Files (*.obj)")
    if res and len(res) > 0:
        return os.path.dirname(res[0]).replace('\\', '/')

    # 5. Last resort fallback
    return "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Landmark"

SCRIPT_DIR = find_asset_dir()
OBJ_PATH = os.path.join(SCRIPT_DIR, "Landmark1.obj").replace("\\", "/")
MB_PATH = os.path.join(SCRIPT_DIR, "landmark1.mb").replace("\\", "/")
ALBEDO_PATH = os.path.join(SCRIPT_DIR, "ITF_BaseColor.png").replace("\\", "/")
NORM_PATH = os.path.join(SCRIPT_DIR, "ITF_Normal.png").replace("\\", "/")
ORM_PATH = os.path.join(SCRIPT_DIR, "ITF_RoughnessMetallic.png").replace("\\", "/")

print(f"[Maya Loader] Loading Landmark 1 (ITF Tower) from: {SCRIPT_DIR}")

cmds.file(new=True, force=True)
cmds.file(OBJ_PATH, i=True, type="OBJ", ignoreVersion=True, ra=True, mergeNamespacesOnClash=False, options="mo=1")

mat_name = "M_ITF_Tower"
if not cmds.objExists(mat_name):
    shd = cmds.shadingNode("standardSurface", asShader=True, name=mat_name)
    sg = cmds.sets(renderable=True, noSurfaceShader=True, empty=True, name=f"{mat_name}SG")
    cmds.connectAttr(f"{shd}.outColor", f"{sg}.surfaceShader", force=True)

    # 1. Base Color Texture
    if os.path.exists(ALBEDO_PATH):
        file_albedo = cmds.shadingNode("file", asTexture=True, name="file_ITF_BaseColor")
        p2t_albedo = cmds.shadingNode("place2dTexture", asUtility=True, name="place2d_ITF_albedo")
        for attr in ['coverage', 'translateFrame', 'rotateFrame', 'mirrorU', 'mirrorV', 'stagger', 'wrapU', 'wrapV', 'repeatUV', 'offset', 'rotateUV']:
            cmds.connectAttr(f"{p2t_albedo}.{attr}", f"{file_albedo}.{attr}", force=True)
        cmds.connectAttr(f"{p2t_albedo}.outUV", f"{file_albedo}.uvCoord", force=True)
        cmds.connectAttr(f"{p2t_albedo}.outUvFilterSize", f"{file_albedo}.uvFilterSize", force=True)
        cmds.setAttr(f"{file_albedo}.fileTextureName", ALBEDO_PATH, type="string")
        cmds.connectAttr(f"{file_albedo}.outColor", f"{shd}.baseColor", force=True)
        cmds.setAttr(f"{shd}.base", 1.0)

    # 2. Roughness & Metallic
    if os.path.exists(ORM_PATH):
        file_orm = cmds.shadingNode("file", asTexture=True, name="file_ITF_ORM")
        p2t_orm = cmds.shadingNode("place2dTexture", asUtility=True, name="place2d_ITF_orm")
        for attr in ['coverage', 'translateFrame', 'rotateFrame', 'mirrorU', 'mirrorV', 'stagger', 'wrapU', 'wrapV', 'repeatUV', 'offset', 'rotateUV']:
            cmds.connectAttr(f"{p2t_orm}.{attr}", f"{file_orm}.{attr}", force=True)
        cmds.connectAttr(f"{p2t_orm}.outUV", f"{file_orm}.uvCoord", force=True)
        cmds.connectAttr(f"{p2t_orm}.outUvFilterSize", f"{file_orm}.uvFilterSize", force=True)
        cmds.setAttr(f"{file_orm}.fileTextureName", ORM_PATH, type="string")
        cmds.setAttr(f"{file_orm}.colorSpace", "Raw", type="string")
        cmds.connectAttr(f"{file_orm}.outColorG", f"{shd}.specularRoughness", force=True)
        cmds.connectAttr(f"{file_orm}.outColorB", f"{shd}.metalness", force=True)
    else:
        cmds.setAttr(f"{shd}.specularRoughness", 0.35)

    # 3. Normal Map
    if os.path.exists(NORM_PATH):
        file_norm = cmds.shadingNode("file", asTexture=True, name="file_ITF_Normal")
        p2t_norm = cmds.shadingNode("place2dTexture", asUtility=True, name="place2d_ITF_norm")
        for attr in ['coverage', 'translateFrame', 'rotateFrame', 'mirrorU', 'mirrorV', 'stagger', 'wrapU', 'wrapV', 'repeatUV', 'offset', 'rotateUV']:
            cmds.connectAttr(f"{p2t_norm}.{attr}", f"{file_norm}.{attr}", force=True)
        cmds.connectAttr(f"{p2t_norm}.outUV", f"{file_norm}.uvCoord", force=True)
        cmds.connectAttr(f"{p2t_norm}.outUvFilterSize", f"{file_norm}.uvFilterSize", force=True)
        cmds.setAttr(f"{file_norm}.fileTextureName", NORM_PATH, type="string")
        cmds.setAttr(f"{file_norm}.colorSpace", "Raw", type="string")
        bump_node = cmds.shadingNode("bump2d", asUtility=True, name="bump_ITF")
        cmds.setAttr(f"{bump_node}.bump2d", 1)  # Tangent space normals
        cmds.connectAttr(f"{file_norm}.outAlpha", f"{bump_node}.bumpValue", force=True)
        cmds.connectAttr(f"{bump_node}.outNormal", f"{shd}.normalCamera", force=True)

    meshes = cmds.ls(type="mesh")
    for m in meshes:
        cmds.sets(m, edit=True, forceElement=sg)

cmds.file(rename=MB_PATH)
try:
    cmds.file(save=True, type="mayaBinary")
    print(f"[Maya Loader] Successfully loaded Landmark 1 (ITF Tower) and saved {MB_PATH}!")
except Exception as e:
    print(f"[Maya Loader] Loaded Landmark 1 (ITF Tower) in Maya memory. Note: {e}")
