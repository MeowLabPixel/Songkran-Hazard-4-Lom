import os, math
import numpy as np
from PIL import Image

LANDMARK_DIR = "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Landmark"
ARTIFACTS_DIR = "C:/Users/creep/.gemini/antigravity/brain/b0cac446-45b6-4b6b-bcae-2bd8e6a4bdf9"
OBJ_PATH = os.path.join(LANDMARK_DIR, "Landmark_BangkokBank_HeadOffice.obj")

# Preload the 3 textures
tex_tower = Image.open(os.path.join(LANDMARK_DIR, "BBL_Tower_BaseColor.png")).convert('RGB')
tex_podium = Image.open(os.path.join(LANDMARK_DIR, "BBL_Podium_BaseColor.png")).convert('RGB')
tex_arcade = Image.open(os.path.join(LANDMARK_DIR, "BBL_Arcade_BaseColor.png")).convert('RGB')

textures = {
    "Mat_BBL_Tower": (tex_tower, tex_tower.size[0], tex_tower.size[1], tex_tower.load()),
    "Mat_BBL_Podium": (tex_podium, tex_podium.size[0], tex_podium.size[1], tex_podium.load()),
    "Mat_BBL_Arcade": (tex_arcade, tex_arcade.size[0], tex_arcade.size[1], tex_arcade.load())
}

def render_multi_material_obj(obj_path, out_path, cam_pos, cam_target, fov=45, w=1280, h=720, light_dir=(0.4, 0.7, 0.6)):
    verts = []
    uvs = []
    triangles_by_mat = {}
    current_mat = "Mat_BBL_Tower"
    
    with open(obj_path) as f:
        for line in f:
            if line.startswith('v '):
                verts.append([float(p) for p in line.strip().split()[1:4]])
            elif line.startswith('vt '):
                uvs.append([float(p) for p in line.strip().split()[1:3]])
            elif line.startswith('usemtl '):
                current_mat = line.strip().split()[1]
                if current_mat not in triangles_by_mat:
                    triangles_by_mat[current_mat] = []
            elif line.startswith('f '):
                p = line.strip().split()[1:]
                f_v = []
                f_uv = []
                for item in p:
                    spl = item.split('/')
                    f_v.append(int(spl[0]) - 1)
                    f_uv.append(int(spl[1]) - 1)
                if len(f_v) == 3:
                    triangles_by_mat.setdefault(current_mat, []).append((f_v, f_uv))
                elif len(f_v) == 4:
                    triangles_by_mat.setdefault(current_mat, []).append(([f_v[0], f_v[1], f_v[2]], [f_uv[0], f_uv[1], f_uv[2]]))
                    triangles_by_mat.setdefault(current_mat, []).append(([f_v[0], f_v[2], f_v[3]], [f_uv[0], f_uv[2], f_uv[3]]))

    cx, cy, cz = cam_pos
    tx, ty, tz = cam_target
    fx, fy, fz = tx - cx, ty - cy, tz - cz
    fl = math.sqrt(fx*fx + fy*fy + fz*fz)
    fx, fy, fz = fx/fl, fy/fl, fz/fl
    
    # Camera right and up
    rx = fy*0 - fz*1; ry = fz*0 - fx*0; rz = fx*1 - fy*0
    rl = math.sqrt(rx*rx + ry*ry + rz*rz)
    if rl < 1e-6:
        # Looking straight up or down
        rx, ry, rz = 1, 0, 0
    else:
        rx, ry, rz = rx/rl, ry/rl, rz/rl
    ux = ry*fz - rz*fy; uy = rz*fx - rx*fz; uz = rx*fy - ry*fx
    
    aspect = w / h
    tan_fov = math.tan(math.radians(fov / 2.0))
    
    view_verts = []
    for vx, vy, vz in verts:
        dx, dy, dz = vx - cx, vy - cy, vz - cz
        cam_x = dx*rx + dy*ry + dz*rz
        cam_y = dx*ux + dy*uy + dz*uz
        cam_z = dx*fx + dy*fy + dz*fz
        view_verts.append((cam_x, cam_y, cam_z))
        
    lx, ly, lz = light_dir
    ll = math.sqrt(lx*lx + ly*ly + lz*lz)
    lx, ly, lz = lx/ll, ly/ll, lz/ll
    
    # Create stylish sky gradient background (Songkran sunny sky)
    out_img = Image.new("RGB", (w, h))
    for y in range(h):
        fac = y / h
        # Top: bright cyan/azure (135, 206, 250), Bottom: pastel warm horizon (220, 240, 255)
        r = int(135 * (1 - fac) + 220 * fac)
        g = int(206 * (1 - fac) + 240 * fac)
        b = int(250 * (1 - fac) + 255 * fac)
        for x in range(w):
            out_img.putpixel((x, y), (r, g, b))
            
    out_pix = out_img.load()
    zbuf = [float('inf')] * (w * h)
    
    for mat_name, tri_list in triangles_by_mat.items():
        tex, tw, th, tex_pix = textures.get(mat_name, textures["Mat_BBL_Tower"])
        
        for v_idx, uv_idx in tri_list:
            p0 = view_verts[v_idx[0]]
            p1 = view_verts[v_idx[1]]
            p2 = view_verts[v_idx[2]]
            
            if p0[2] <= 0.1 or p1[2] <= 0.1 or p2[2] <= 0.1:
                continue
                
            s0x = (p0[0] / (p0[2] * tan_fov * aspect) + 1.0) * 0.5 * w
            s0y = (1.0 - (p0[1] / (p0[2] * tan_fov))) * 0.5 * h
            s1x = (p1[0] / (p1[2] * tan_fov * aspect) + 1.0) * 0.5 * w
            s1y = (1.0 - (p1[1] / (p1[2] * tan_fov))) * 0.5 * h
            s2x = (p2[0] / (p2[2] * tan_fov * aspect) + 1.0) * 0.5 * w
            s2y = (1.0 - (p2[1] / (p2[2] * tan_fov))) * 0.5 * h
            
            cp = (s1x - s0x) * (s2y - s0y) - (s1y - s0y) * (s2x - s0x)
            # Double-sided rendering: don't cull cp >= 0!
            # If back-facing, we can still render it with double-sided support!
            is_backfacing = (cp >= 0)
            if abs(cp) < 1e-5:
                continue
                
            ax = verts[v_idx[1]][0] - verts[v_idx[0]][0]
            ay = verts[v_idx[1]][1] - verts[v_idx[0]][1]
            az = verts[v_idx[1]][2] - verts[v_idx[0]][2]
            bx = verts[v_idx[2]][0] - verts[v_idx[0]][0]
            by = verts[v_idx[2]][1] - verts[v_idx[0]][1]
            bz = verts[v_idx[2]][2] - verts[v_idx[0]][2]
            nx = ay*bz - az*by; ny = az*bx - ax*bz; nz = ax*by - ay*bx
            nl = math.sqrt(nx*nx + ny*ny + nz*nz)
            if nl > 1e-6:
                nx, ny, nz = nx/nl, ny/nl, nz/nl
                if is_backfacing:
                    nx, ny, nz = -nx, -ny, -nz
                dot = max(0.0, nx*lx + ny*ly + nz*lz)
                # Vibrant PS1 arcade shading: 0.55 ambient + 0.45 directional
                shade = 0.55 + 0.45 * dot
            else:
                shade = 1.0
                
            u0, v0 = uvs[uv_idx[0]]
            u1, v1 = uvs[uv_idx[1]]
            u2, v2 = uvs[uv_idx[2]]
            
            min_x = max(0, int(min(s0x, s1x, s2x)))
            max_x = min(w - 1, int(max(s0x, s1x, s2x)))
            min_y = max(0, int(min(s0y, s1y, s2y)))
            max_y = min(h - 1, int(max(s0y, s1y, s2y)))
            if min_x > max_x or min_y > max_y:
                continue
                
            inv_denom = 1.0 / cp
            iz0, iz1, iz2 = 1.0 / p0[2], 1.0 / p1[2], 1.0 / p2[2]
            u0_z, v0_z = u0 * iz0, v0 * iz0
            u1_z, v1_z = u1 * iz1, v1 * iz1
            u2_z, v2_z = u2 * iz2, v2 * iz2
            
            for py in range(min_y, max_y + 1):
                for px in range(min_x, max_x + 1):
                    w0 = ((s1x - px)*(s2y - py) - (s1y - py)*(s2x - px)) * inv_denom
                    w1 = ((s2x - px)*(s0y - py) - (s2y - py)*(s0x - px)) * inv_denom
                    w2 = 1.0 - w0 - w1
                    if (cp < 0 and w0 >= -1e-4 and w1 >= -1e-4 and w2 >= -1e-4) or (cp > 0 and w0 <= 1e-4 and w1 <= 1e-4 and w2 <= 1e-4):
                        if cp > 0:
                            w0, w1, w2 = -w0, -w1, -w2
                        pz_inv = w0 * iz0 + w1 * iz1 + w2 * iz2
                        if pz_inv <= 0: continue
                        pz = 1.0 / pz_inv
                        idx = py * w + px
                        if pz < zbuf[idx]:
                            zbuf[idx] = pz
                            tu = (w0 * u0_z + w1 * u1_z + w2 * u2_z) * pz
                            tv = (w0 * v0_z + w1 * v1_z + w2 * v2_z) * pz
                            
                            tx_pix = int((tu % 1.0) * tw)
                            ty_pix = int(((1.0 - tv) % 1.0) * th)
                            r, g, b = tex_pix[tx_pix, ty_pix][:3]
                            out_pix[px, py] = (
                                min(255, int(r * shade)),
                                min(255, int(g * shade)),
                                min(255, int(b * shade))
                            )
                            
    out_img.save(out_path)
    print(f"Rendered: {out_path}")

views = [
    ("bbl_ho_hero_aerial.png", (45.0, 38.0, 56.0), (0.0, 26.0, 0.0), 52),
    ("bbl_ho_street_hero.png", (0.0, 2.0, 36.0), (0.0, 24.0, 5.0), 56),
    ("bbl_ho_arcade_straight.png", (0.0, 3.2, 20.0), (0.0, 3.2, 4.5), 48),
    ("bbl_ho_entrance_doors.png", (0.0, 2.8, 12.0), (0.0, 2.8, 4.5), 42),
    ("bbl_ho_atm_booth.png", (-9.0, 2.8, 12.0), (-9.0, 2.8, 4.5), 42),
    ("bbl_ho_canted_podium.png", (0.0, 11.5, 23.0), (0.0, 10.5, 10.0), 44),
    ("bbl_ho_roof_garden.png", (-14.0, 19.0, 20.0), (0.0, 14.5, 8.0), 46),
    ("bbl_ho_helical_ramp.png", (18.0, 22.0, -1.0), (12.0, 14.0, -9.0), 44),
    ("bbl_ho_helipad_topdown.png", (0.0, 74.0, -1.0), (0.0, 56.0, -1.0), 40),
    ("bbl_ho_arcade_ceiling_soffit.png", (0.0, 1.2, 8.0), (0.0, 5.5, 6.5), 60),
    ("bbl_ho_rear_cavity_check.png", (22.0, 32.0, -30.0), (0.0, 16.0, -6.0), 50),
    ("bbl_ho_front_terrace_gap_check.png", (-14.0, 20.0, 20.0), (0.0, 16.0, 4.5), 48),
    ("bbl_ho_ground_flank_left.png", (-22.0, 3.5, 9.0), (-16.0, 3.5, 6.0), 50),
    ("bbl_ho_colonnade_doors_atm.png", (0.0, 3.2, 17.0), (0.0, 3.0, 4.5), 48),
    ("bbl_ho_garuda_true_1to1.png", (0.0, 11.0, 21.0), (0.0, 10.5, 10.0), 42),
    ("bbl_ho_podium_return_cap.png", (-22.0, 10.0, 8.0), (-17.0, 10.0, 8.0), 46),
]

if __name__ == "__main__":
    for fname, pos, tgt, fov in views:
        out_dst = os.path.join(LANDMARK_DIR, fname)
        render_multi_material_obj(OBJ_PATH, out_dst, pos, tgt, fov=fov)
        out_art = os.path.join(ARTIFACTS_DIR, fname)
        render_multi_material_obj(OBJ_PATH, out_art, pos, tgt, fov=fov)
    print("All 10 Bangkok Bank Head Office (Silom) verification views rendered successfully!")
