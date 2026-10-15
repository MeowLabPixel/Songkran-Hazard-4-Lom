import os, math, sys
from PIL import Image

OUT_DIR = "d:/3D Stuff/GAMEJAM 2026/SONGRANG/BTS Train"

def render_obj(obj_path, tex_path, out_path, cam_pos, cam_target, fov=45, w=1280, h=720, light_dir=(0.5, 0.8, 0.3)):
    tex = Image.open(tex_path).convert('RGB')
    tw, th = tex.size
    tex_pix = tex.load()
    
    verts = []
    uvs = []
    faces = []
    with open(obj_path) as f:
        for line in f:
            if line.startswith('v '):
                verts.append([float(p) for p in line.strip().split()[1:4]])
            elif line.startswith('vt '):
                uvs.append([float(p) for p in line.strip().split()[1:3]])
            elif line.startswith('f '):
                p = line.strip().split()[1:]
                f_v = []
                f_uv = []
                for item in p:
                    spl = item.split('/')
                    f_v.append(int(spl[0]) - 1)
                    f_uv.append(int(spl[1]) - 1)
                faces.append((f_v, f_uv))
                
    cx, cy, cz = cam_pos
    tx, ty, tz = cam_target
    fx, fy, fz = tx - cx, ty - cy, tz - cz
    fl = math.sqrt(fx*fx + fy*fy + fz*fz)
    fx, fy, fz = fx/fl, fy/fl, fz/fl
    
    rx = fy*0 - fz*1; ry = fz*0 - fx*0; rz = fx*1 - fy*0
    rl = math.sqrt(rx*rx + ry*ry + rz*rz)
    if rl < 1e-6: rx, ry, rz = 1, 0, 0
    else: rx, ry, rz = rx/rl, ry/rl, rz/rl
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
    
    out_img = Image.new('RGB', (w, h), (255, 255, 255))
    out_pix = out_img.load()
    zbuf = [float('inf')] * (w * h)
    
    half_w, half_h = w * 0.5, h * 0.5
    
    for (v_idx, uv_idx) in faces:
        if len(v_idx) != 3: continue
        p0 = view_verts[v_idx[0]]
        p1 = view_verts[v_idx[1]]
        p2 = view_verts[v_idx[2]]
        
        if p0[2] < 0.1 or p1[2] < 0.1 or p2[2] < 0.1: continue
            
        s0x = half_w + (p0[0] / (p0[2] * tan_fov * aspect)) * half_w
        s0y = half_h - (p0[1] / (p0[2] * tan_fov)) * half_h
        s1x = half_w + (p1[0] / (p1[2] * tan_fov * aspect)) * half_w
        s1y = half_h - (p1[1] / (p1[2] * tan_fov)) * half_h
        s2x = half_w + (p2[0] / (p2[2] * tan_fov * aspect)) * half_w
        s2y = half_h - (p2[1] / (p2[2] * tan_fov)) * half_h
        
        cp = (s1x - s0x) * (s2y - s0y) - (s1y - s0y) * (s2x - s0x)
        if cp >= 0: continue
            
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
            dot = max(0.0, nx*lx + ny*ly + nz*lz)
            shade = 0.50 + 0.50 * dot
        else:
            shade = 1.0
            
        u0, v0 = uvs[uv_idx[0]]
        u1, v1 = uvs[uv_idx[1]]
        u2, v2 = uvs[uv_idx[2]]
        
        min_x = max(0, int(min(s0x, s1x, s2x)))
        max_x = min(w - 1, int(max(s0x, s1x, s2x)))
        min_y = max(0, int(min(s0y, s1y, s2y)))
        max_y = min(h - 1, int(max(s0y, s1y, s2y)))
        if min_x > max_x or min_y > max_y: continue
            
        inv_denom = 1.0 / cp
        iz0, iz1, iz2 = 1.0 / p0[2], 1.0 / p1[2], 1.0 / p2[2]
        u0_z, v0_z = u0 * iz0, v0 * iz0
        u1_z, v1_z = u1 * iz1, v1 * iz1
        u2_z, v2_z = u2 * iz2, v2 * iz2
        
        for py in range(min_y, max_y + 1):
            row_idx = py * w
            for px in range(min_x, max_x + 1):
                w0 = (s1x - px) * (s2y - py) - (s1y - py) * (s2x - px)
                if w0 > 0: continue
                w1 = (s2x - px) * (s0y - py) - (s2y - py) * (s0x - px)
                if w1 > 0: continue
                w2 = (s0x - px) * (s1y - py) - (s0y - py) * (s1x - px)
                if w2 > 0: continue
                
                b0 = w0 * inv_denom
                b1 = w1 * inv_denom
                b2 = w2 * inv_denom
                
                iz = b0 * iz0 + b1 * iz1 + b2 * iz2
                z = 1.0 / iz
                
                if z < zbuf[row_idx + px]:
                    zbuf[row_idx + px] = z
                    u = (b0 * u0_z + b1 * u1_z + b2 * u2_z) * z
                    v = (b0 * v0_z + b1 * v1_z + b2 * v2_z) * z
                    
                    tx = int(u * (tw - 1)) % tw
                    ty = int((1.0 - v) * (th - 1)) % th
                    
                    c = tex_pix[tx, ty]
                    r = min(255, int(c[0] * shade))
                    g = min(255, int(c[1] * shade))
                    b_col = min(255, int(c[2] * shade))
                    out_pix[px, py] = (r, g, b_col)
                    
    out_img.save(out_path)
    print('Rendered:', out_path)

if __name__ == '__main__':
    cab_obj = os.path.join(OUT_DIR, 'BTS_Train_Cab.obj')
    consist_obj = os.path.join(OUT_DIR, 'BTS_Train_FullConsist.obj')
    tex_png = os.path.join(OUT_DIR, 'BTS_Train_BaseColor.png')

    render_obj(cab_obj, tex_png, os.path.join(OUT_DIR, 'rev10_front_hero_check.png'), 
               cam_pos=(3.8, 2.9, 15.0), cam_target=(0.0, 2.1, 11.2), fov=34, w=1280, h=720, light_dir=(0.4, 0.8, 0.4))

    render_obj(cab_obj, tex_png, os.path.join(OUT_DIR, 'rev10_front_close.png'), 
               cam_pos=(1.8, 2.5, 14.5), cam_target=(0.0, 2.2, 11.2), fov=28, w=1280, h=720, light_dir=(0.3, 0.8, 0.5))

    render_obj(cab_obj, tex_png, os.path.join(OUT_DIR, 'rev10_side_swoop_check.png'), 
               cam_pos=(14.5, 2.4, 7.5), cam_target=(1.56, 2.2, 7.5), fov=45, w=1280, h=720, light_dir=(0.5, 0.8, 0.3))

    render_obj(consist_obj, tex_png, os.path.join(OUT_DIR, 'rev10_consist_hero.png'), 
               cam_pos=(16.0, 6.5, 42.0), cam_target=(0.0, 2.2, 16.0), fov=36, w=1280, h=720, light_dir=(0.5, 0.8, 0.3))