import os
import math
import struct
import json

OUT_DIR = r"d:\3D Stuff\GAMEJAM 2026\SONGRANG\BTS Train"
os.makedirs(OUT_DIR, exist_ok=True)

class MeshBuilder:
    def __init__(self, name="Mesh"):
        self.name = name
        self.vertices = []      # (x, y, z)
        self.normals = []       # (nx, ny, nz)
        self.uvs = []           # (u, v)
        self.indices = []       # int indices

    def add_quad_oriented(self, v0, v1, v2, v3, uv0, uv1, uv2, uv3, expected_outward_dir):
        ax, ay, az = v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]
        bx, by, bz = v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]
        nx = ay * bz - az * by
        ny = az * bx - ax * bz
        nz = ax * by - ay * bx
        dot = nx * expected_outward_dir[0] + ny * expected_outward_dir[1] + nz * expected_outward_dir[2]
        if dot < 0:
            v0, v1, v2, v3 = v0, v3, v2, v1
            uv0, uv1, uv2, uv3 = uv0, uv3, uv2, uv1
            nx, ny, nz = -nx, -ny, -nz

        length = math.sqrt(nx*nx + ny*ny + nz*nz) or 1.0
        normal = (nx/length, ny/length, nz/length)

        base_idx = len(self.vertices)
        for v, uv in [(v0, uv0), (v1, uv1), (v2, uv2), (v3, uv3)]:
            self.vertices.append(v)
            self.normals.append(normal)
            self.uvs.append(uv)

        self.indices.extend([base_idx, base_idx + 1, base_idx + 2, base_idx, base_idx + 2, base_idx + 3])

    def add_tri_oriented(self, v0, v1, v2, uv0, uv1, uv2, expected_outward_dir):
        ax, ay, az = v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]
        bx, by, bz = v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]
        nx = ay * bz - az * by
        ny = az * bx - ax * bz
        nz = ax * by - ay * bx
        dot = nx * expected_outward_dir[0] + ny * expected_outward_dir[1] + nz * expected_outward_dir[2]
        if dot < 0:
            v0, v1 = v1, v0
            uv0, uv1 = uv1, uv0
            nx, ny, nz = -nx, -ny, -nz

        length = math.sqrt(nx*nx + ny*ny + nz*nz) or 1.0
        normal = (nx/length, ny/length, nz/length)

        base_idx = len(self.vertices)
        for v, uv in [(v0, uv0), (v1, uv1), (v2, uv2)]:
            self.vertices.append(v)
            self.normals.append(normal)
            self.uvs.append(uv)

        self.indices.extend([base_idx, base_idx + 1, base_idx + 2])

    def add_box_specific_uv(self, min_pt, max_pt, top_uv, side_uv, end_uv, bot_uv):
        """Adds a box with distinct dedicated UV rectangles for top, sides, ends, and bottom."""
        x0, y0, z0 = min_pt
        x1, y1, z1 = max_pt

        # Top (+Y)
        u0, v0, u1, v1 = top_uv
        self.add_quad_oriented((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0),
                               (u0, v0), (u1, v0), (u1, v1), (u0, v1), (0, 1, 0))
        # Bottom (-Y)
        u0, v0, u1, v1 = bot_uv
        self.add_quad_oriented((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
                               (u0, v0), (u1, v0), (u1, v1), (u0, v1), (0, -1, 0))
        # Right Side (+X)
        u0, v0, u1, v1 = side_uv
        self.add_quad_oriented((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1),
                               (u0, v0), (u1, v0), (u1, v1), (u0, v1), (1, 0, 0))
        # Left Side (-X)
        self.add_quad_oriented((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0),
                               (u1, v0), (u0, v0), (u0, v1), (u1, v1), (-1, 0, 0))
        # Front End (+Z)
        u0, v0, u1, v1 = end_uv
        self.add_quad_oriented((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
                               (u0, v0), (u1, v0), (u1, v1), (u0, v1), (0, 0, 1))
        # Back End (-Z)
        self.add_quad_oriented((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0),
                               (u0, v0), (u1, v0), (u1, v1), (u0, v1), (0, 0, -1))

    def add_cylinder_8sided(self, center, radius, length, axis='x',
                            tread_uv=(0.895, 0.398, 0.995, 0.495),
                            cap_center_uv=(0.83984, 0.44824),
                            cap_radius_uv=0.04639):
        cx, cy, cz = center
        angles = [i * (2 * math.pi / 8) for i in range(8)]
        half_l = length / 2.0
        u0, v0, u1, v1 = tread_uv

        ring0, ring1 = [], []
        for a in angles:
            cos_a, sin_a = math.cos(a), math.sin(a)
            if axis == 'x':
                p0 = (cx - half_l, cy + radius * cos_a, cz + radius * sin_a)
                p1 = (cx + half_l, cy + radius * cos_a, cz + radius * sin_a)
            elif axis == 'z':
                p0 = (cx + radius * cos_a, cy + radius * sin_a, cz - half_l)
                p1 = (cx + radius * cos_a, cy + radius * sin_a, cz + half_l)
            else:
                p0 = (cx + radius * cos_a, cy - half_l, cz + radius * sin_a)
                p1 = (cx + radius * cos_a, cy + half_l, cz + radius * sin_a)
            ring0.append(p0)
            ring1.append(p1)

        # 1. Cylindrical rolling tread around barrel
        for i in range(8):
            next_i = (i + 1) % 8
            u_step0 = u0 + (u1 - u0) * (i / 8.0)
            u_step1 = u0 + (u1 - u0) * ((i + 1) / 8.0)
            mid_p = ((ring0[i][0] + ring1[next_i][0])/2.0 - cx,
                     (ring0[i][1] + ring1[next_i][1])/2.0 - cy,
                     (ring0[i][2] + ring1[next_i][2])/2.0 - cz)
            self.add_quad_oriented(ring0[i], ring1[i], ring1[next_i], ring0[next_i],
                                   (u_step0, v0), (u_step0, v1), (u_step1, v1), (u_step1, v0),
                                   expected_outward_dir=mid_p)

        # 2. Circular Radial UV Projection for Disc Caps (Zero fan/pinwheel distortion!)
        cap0_center = (cx - half_l, cy, cz) if axis == 'x' else ((cx, cy, cz - half_l) if axis == 'z' else (cx, cy - half_l, cz))
        cap1_center = (cx + half_l, cy, cz) if axis == 'x' else ((cx, cy, cz + half_l) if axis == 'z' else (cx, cy + half_l, cz))
        uc, vc = cap_center_uv
        ru = cap_radius_uv
        uv_c = (uc, vc)

        for i in range(8):
            next_i = (i + 1) % 8
            a0 = angles[i]
            a1 = angles[next_i]
            if axis == 'x':
                # Looking from -X towards +X: Y is Up, +Z is Right
                uv0 = (uc + ru * math.sin(a0), vc + ru * math.cos(a0))
                uv1 = (uc + ru * math.sin(a1), vc + ru * math.cos(a1))
                self.add_tri_oriented(cap0_center, ring0[next_i], ring0[i], uv_c, uv1, uv0, (-1, 0, 0))
                # Looking from +X towards -X: Y is Up, -Z is Right
                uv0_r = (uc - ru * math.sin(a0), vc + ru * math.cos(a0))
                uv1_r = (uc - ru * math.sin(a1), vc + ru * math.cos(a1))
                self.add_tri_oriented(cap1_center, ring1[i], ring1[next_i], uv_c, uv0_r, uv1_r, (1, 0, 0))

    def write_obj(self, filepath, mtl_name="BTS_Train.mtl"):
        with open(filepath, 'w') as f:
            f.write(f"# Wavefront OBJ: {self.name}\n")
            f.write(f"mtllib {mtl_name}\n")
            f.write(f"o {self.name}\n")
            for v in self.vertices:
                f.write(f"v {v[0]:.4f} {v[1]:.4f} {v[2]:.4f}\n")
            for uv in self.uvs:
                f.write(f"vt {uv[0]:.4f} {uv[1]:.4f}\n")
            for n in self.normals:
                f.write(f"vn {n[0]:.4f} {n[1]:.4f} {n[2]:.4f}\n")
            f.write("usemtl M_BTS_Train\n")
            f.write("s 1\n")
            for i in range(0, len(self.indices), 3):
                i0 = self.indices[i] + 1
                i1 = self.indices[i+1] + 1
                i2 = self.indices[i+2] + 1
                f.write(f"f {i0}/{i0}/{i0} {i1}/{i1}/{i1} {i2}/{i2}/{i2}\n")
        print("Exported OBJ:", filepath)

    def write_glb(self, filepath, texture_png_path=None):
        num_v = len(self.vertices)
        pos_bytes = bytearray()
        norm_bytes = bytearray()
        uv_bytes = bytearray()

        min_pos = [float('inf')]*3
        max_pos = [float('-inf')]*3

        for v in self.vertices:
            pos_bytes.extend(struct.pack('<fff', v[0], v[1], v[2]))
            for k in range(3):
                min_pos[k] = min(min_pos[k], v[k])
                max_pos[k] = max(max_pos[k], v[k])
        for n in self.normals:
            norm_bytes.extend(struct.pack('<fff', n[0], n[1], n[2]))
        for uv in self.uvs:
            uv_bytes.extend(struct.pack('<ff', uv[0], 1.0 - uv[1]))

        use_uint32 = num_v > 65535
        idx_bytes = bytearray()
        if use_uint32:
            for idx in self.indices:
                idx_bytes.extend(struct.pack('<I', idx))
        else:
            for idx in self.indices:
                idx_bytes.extend(struct.pack('<H', idx))

        def pad4_bytes(b):
            rem = len(b) % 4
            if rem > 0:
                b.extend(b'\x00' * (4 - rem))
            return b

        def pad4_json(b):
            rem = len(b) % 4
            if rem > 0:
                b.extend(b' ' * (4 - rem))
            return b

        pos_bytes = pad4_bytes(pos_bytes)
        norm_bytes = pad4_bytes(norm_bytes)
        uv_bytes = pad4_bytes(uv_bytes)
        idx_bytes = pad4_bytes(idx_bytes)

        img_bytes = b""
        if texture_png_path and os.path.exists(texture_png_path):
            with open(texture_png_path, 'rb') as img_f:
                img_bytes = img_f.read()

        bin_buffer = bytearray()
        offset_pos = len(bin_buffer); bin_buffer.extend(pos_bytes)
        offset_norm = len(bin_buffer); bin_buffer.extend(norm_bytes)
        offset_uv = len(bin_buffer); bin_buffer.extend(uv_bytes)
        offset_idx = len(bin_buffer); bin_buffer.extend(idx_bytes)
        offset_img = len(bin_buffer)
        if img_bytes:
            bin_buffer.extend(img_bytes)
            bin_buffer = pad4_bytes(bin_buffer)

        buffer_views = [
            {"buffer": 0, "byteOffset": offset_pos, "byteLength": len(pos_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offset_norm, "byteLength": len(norm_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offset_uv, "byteLength": len(uv_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offset_idx, "byteLength": len(idx_bytes), "target": 34963}
        ]
        accessors = [
            {"bufferView": 0, "byteOffset": 0, "componentType": 5126, "count": num_v, "type": "VEC3", "min": min_pos, "max": max_pos},
            {"bufferView": 1, "byteOffset": 0, "componentType": 5126, "count": num_v, "type": "VEC3"},
            {"bufferView": 2, "byteOffset": 0, "componentType": 5126, "count": num_v, "type": "VEC2"},
            {"bufferView": 3, "byteOffset": 0, "componentType": 5125 if use_uint32 else 5123, "count": len(self.indices), "type": "SCALAR", "min": [0], "max": [num_v - 1]}
        ]

        materials = [{
            "name": "M_BTS_Train",
            "doubleSided": True,
            "pbrMetallicRoughness": {
                "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                "metallicFactor": 0.4,
                "roughnessFactor": 0.4
            }
        }]

        textures = []
        images = []
        samplers = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]

        if img_bytes:
            buffer_views.append({"buffer": 0, "byteOffset": offset_img, "byteLength": len(img_bytes)})
            images.append({"bufferView": 4, "mimeType": "image/png"})
            textures.append({"sampler": 0, "source": 0})
            materials[0]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}

        meshes = [{
            "name": self.name,
            "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                "indices": 3,
                "material": 0
            }]
        }]

        nodes = [{"name": self.name, "mesh": 0}]
        scenes = [{"name": "DefaultScene", "nodes": [0]}]

        gltf_dict = {
            "asset": {"version": "2.0", "generator": "SongkranHazard_AssetPipeline"},
            "scene": 0,
            "scenes": scenes,
            "nodes": nodes,
            "meshes": meshes,
            "materials": materials,
            "textures": textures,
            "images": images,
            "samplers": samplers,
            "accessors": accessors,
            "bufferViews": buffer_views,
            "buffers": [{"byteLength": len(bin_buffer)}]
        }

        json_bytes = json.dumps(gltf_dict).encode('utf-8')
        json_bytes = pad4_json(bytearray(json_bytes))

        total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_buffer)
        header = struct.pack('<III', 0x46546C67, 2, total_len)
        chunk0_hdr = struct.pack('<II', len(json_bytes), 0x4E4F534A)
        chunk1_hdr = struct.pack('<II', len(bin_buffer), 0x004E4942)

        with open(filepath, 'wb') as f:
            f.write(header)
            f.write(chunk0_hdr)
            f.write(json_bytes)
            f.write(chunk1_hdr)
            f.write(bin_buffer)
        print("Exported GLB:", filepath)


def build_bogie(builder, center_z):
    wheel_r = 0.40
    gauge = 1.435
    axle_dist = 1.15
    y_wheel = wheel_r

    wheel_tread_uv = (0.895, 0.398, 0.995, 0.495)
    wheel_cap_center = (0.83984, 0.44824)
    wheel_cap_radius = 0.04639
    axle_tread_uv = (0.895, 0.400, 0.940, 0.440)

    for dz in [-axle_dist, axle_dist]:
        # Left wheel (+X side, cap1 faces outwards)
        builder.add_cylinder_8sided((gauge / 2.0, y_wheel, center_z + dz), wheel_r, 0.14, axis='x',
                                   tread_uv=wheel_tread_uv, cap_center_uv=wheel_cap_center, cap_radius_uv=wheel_cap_radius)
        # Right wheel (-X side, cap0 faces outwards)
        builder.add_cylinder_8sided((-gauge / 2.0, y_wheel, center_z + dz), wheel_r, 0.14, axis='x',
                                   tread_uv=wheel_tread_uv, cap_center_uv=wheel_cap_center, cap_radius_uv=wheel_cap_radius)
        # Center axle shaft
        builder.add_cylinder_8sided((0, y_wheel, center_z + dz), 0.07, gauge - 0.2, axis='x',
                                   tread_uv=axle_tread_uv, cap_center_uv=(0.910, 0.420), cap_radius_uv=0.005)

    # Bogie H-frame chassis (heavy cast dark steel, no hazard tape!)
    y_frame_bot = 0.44
    y_frame_top = 0.58
    frame_uv = (0.795, 0.240, 0.995, 0.390)
    builder.add_box_specific_uv((1.05, y_frame_bot, center_z - 1.55),
                               (1.25, y_frame_top, center_z + 1.55),
                               frame_uv, frame_uv, frame_uv, frame_uv)
    builder.add_box_specific_uv((-1.25, y_frame_bot, center_z - 1.55),
                               (-1.05, y_frame_top, center_z + 1.55),
                               frame_uv, frame_uv, frame_uv, frame_uv)
    builder.add_box_specific_uv((-1.10, y_frame_bot + 0.02, center_z - 0.35),
                               (1.10, y_frame_top + 0.04, center_z + 0.35),
                               frame_uv, frame_uv, frame_uv, frame_uv)



def build_hvac_pod(builder, center_z):
    """
    Rooftop HVAC pod:
    - TOP FACE has dual circular cooling fans.
    - SIDE FACES (+X, -X) and END FACES (+Z, -Z) have CLEAN HORIZONTAL VENTILATION LOUVERS.
    """
    w = 2.10
    l = 3.60
    h = 0.36
    y_base = 3.80

    top_uv = (0.300, 0.260, 0.495, 0.495)
    side_uv = (0.300, 0.145, 0.495, 0.252)
    end_uv  = (0.300, 0.145, 0.495, 0.252)
    bot_uv  = (0.010, 0.010, 0.280, 0.495)

    # Pod body
    builder.add_box_specific_uv((-w/2.0, y_base, center_z - l/2.0),
                               (w/2.0, y_base + h, center_z + l/2.0),
                               top_uv, side_uv, end_uv, bot_uv)

    # Top face rim bevel
    builder.add_box_specific_uv((-w/2.0 + 0.08, y_base + h, center_z - l/2.0 + 0.15),
                               (w/2.0 - 0.08, y_base + h + 0.03, center_z + l/2.0 - 0.15),
                               top_uv, side_uv, end_uv, bot_uv)


# =========================================================================
# GEOMETRIC & UV BAND CONSTANTS (STRICT HORIZONTAL ALIGNMENT)
# =========================================================================
# Every face around the perimeter (Side, Cheek, Nose) uses these exact Y levels
# and corresponding V texture coordinates:
Y_SKIRT_BOT = 0.72   # V = 0.500 (Skirt bottom / Floor level)
Y_SKIRT_TOP = 0.86   # V = 0.580 (Skirt top / Lower body bottom)
Y_STRIPE_BOT = 1.35  # V = 0.670 (Lower body top / Coral Red stripe bottom)
Y_STRIPE_TOP = 2.05  # V = 0.760 (Tropical Blue stripe top / Window sill)
Y_WIN_TOP    = 3.35  # V = 0.920 (Window top / Cantrail bottom)
Y_ROOF_EDGE  = 3.65  # V = 0.961 (Roof cantrail top / Roof chamfer base)
Y_ROOF_CROWN = 3.78  # V = 1.000 (Roof crown center)

V_SKIRT_BOT  = 0.500
V_SKIRT_TOP  = 0.580
V_STRIPE_BOT = 0.670
V_STRIPE_TOP = 0.760
V_WIN_TOP    = 0.920
V_ROOF_EDGE  = 0.961
V_ROOF_CROWN = 1.000

# Dedicated Non-Overlapping Sub-Regions for Lower Half:
ROOF_UV      = (0.010, 0.010, 0.280, 0.495)
HVAC_TOP_UV  = (0.300, 0.260, 0.495, 0.495)
HVAC_SIDE_UV = (0.300, 0.145, 0.495, 0.252)
BELLOWS_UV   = (0.300, 0.005, 0.495, 0.138)
BULKHEAD_UV  = (0.505, 0.005, 0.625, 0.495)
UNDER_UV     = (0.630, 0.005, 0.780, 0.495)
EQUIPMENT_UV = (0.865, 0.005, 0.995, 0.230)


def build_cab_car():
    b = MeshBuilder("BTS_Train_Cab")

    half_w = 1.56
    z_rear = -9.80
    z_cab_start = 9.50
    w_nose = 1.15
    z_nose_corner = 11.45
    z_nose_center = 11.65

    u_side_start = 0.000
    u_side_end   = 0.585
    u_chk_start  = 0.585
    u_chk_end    = 0.805
    u_nose_start = 0.805
    u_nose_end   = 1.000

    # ---------------------------------------------------------------------
    # 1. MAIN PASSENGER SIDE WALLS (z: z_rear .. z_cab_start)
    # ---------------------------------------------------------------------
    # Left Side Wall (+X = 1.56)
    # Band 0: Skirt
    b.add_quad_oriented((half_w, Y_SKIRT_BOT, z_rear), (half_w, Y_SKIRT_BOT, z_cab_start),
                        (half_w, Y_SKIRT_TOP, z_cab_start), (half_w, Y_SKIRT_TOP, z_rear),
                        (u_side_start, V_SKIRT_BOT), (u_side_end, V_SKIRT_BOT),
                        (u_side_end, V_SKIRT_TOP), (u_side_start, V_SKIRT_TOP), (1, 0, 0))
    # Band 1: Lower Cream Body Fluting
    b.add_quad_oriented((half_w, Y_SKIRT_TOP, z_rear), (half_w, Y_SKIRT_TOP, z_cab_start),
                        (half_w, Y_STRIPE_BOT, z_cab_start), (half_w, Y_STRIPE_BOT, z_rear),
                        (u_side_start, V_SKIRT_TOP), (u_side_end, V_SKIRT_TOP),
                        (u_side_end, V_STRIPE_BOT), (u_side_start, V_STRIPE_BOT), (1, 0, 0))
    # Band 2: Speed Stripes (Red, White, Blue)
    b.add_quad_oriented((half_w, Y_STRIPE_BOT, z_rear), (half_w, Y_STRIPE_BOT, z_cab_start),
                        (half_w, Y_STRIPE_TOP, z_cab_start), (half_w, Y_STRIPE_TOP, z_rear),
                        (u_side_start, V_STRIPE_BOT), (u_side_end, V_STRIPE_BOT),
                        (u_side_end, V_STRIPE_TOP), (u_side_start, V_STRIPE_TOP), (1, 0, 0))
    # Band 3: Passenger Windows & Doors
    b.add_quad_oriented((half_w, Y_STRIPE_TOP, z_rear), (half_w, Y_STRIPE_TOP, z_cab_start),
                        (half_w, Y_WIN_TOP, z_cab_start), (half_w, Y_WIN_TOP, z_rear),
                        (u_side_start, V_STRIPE_TOP), (u_side_end, V_STRIPE_TOP),
                        (u_side_end, V_WIN_TOP), (u_side_start, V_WIN_TOP), (1, 0, 0))
    # Band 4: Upper Cantrail
    b.add_quad_oriented((half_w, Y_WIN_TOP, z_rear), (half_w, Y_WIN_TOP, z_cab_start),
                        (half_w, Y_ROOF_EDGE, z_cab_start), (half_w, Y_ROOF_EDGE, z_rear),
                        (u_side_start, V_WIN_TOP), (u_side_end, V_WIN_TOP),
                        (u_side_end, V_ROOF_EDGE), (u_side_start, V_ROOF_EDGE), (1, 0, 0))
    # Band 5: Roof Chamfer
    b.add_quad_oriented((half_w, Y_ROOF_EDGE, z_rear), (half_w, Y_ROOF_EDGE, z_cab_start),
                        (half_w - 0.22, Y_ROOF_CROWN, z_cab_start), (half_w - 0.22, Y_ROOF_CROWN, z_rear),
                        (u_side_start, V_ROOF_EDGE), (u_side_end, V_ROOF_EDGE),
                        (u_side_end, V_ROOF_CROWN), (u_side_start, V_ROOF_CROWN), (0.5, 0.86, 0))

    # Right Side Wall (-X = -1.56)
    # Band 0: Skirt
    b.add_quad_oriented((-half_w, Y_SKIRT_BOT, z_cab_start), (-half_w, Y_SKIRT_BOT, z_rear),
                        (-half_w, Y_SKIRT_TOP, z_rear), (-half_w, Y_SKIRT_TOP, z_cab_start),
                        (u_side_end, V_SKIRT_BOT), (u_side_start, V_SKIRT_BOT),
                        (u_side_start, V_SKIRT_TOP), (u_side_end, V_SKIRT_TOP), (-1, 0, 0))
    # Band 1: Lower Cream Body Fluting
    b.add_quad_oriented((-half_w, Y_SKIRT_TOP, z_cab_start), (-half_w, Y_SKIRT_TOP, z_rear),
                        (-half_w, Y_STRIPE_BOT, z_rear), (-half_w, Y_STRIPE_BOT, z_cab_start),
                        (u_side_end, V_SKIRT_TOP), (u_side_start, V_SKIRT_TOP),
                        (u_side_start, V_STRIPE_BOT), (u_side_end, V_STRIPE_BOT), (-1, 0, 0))
    # Band 2: Speed Stripes
    b.add_quad_oriented((-half_w, Y_STRIPE_BOT, z_cab_start), (-half_w, Y_STRIPE_BOT, z_rear),
                        (-half_w, Y_STRIPE_TOP, z_rear), (-half_w, Y_STRIPE_TOP, z_cab_start),
                        (u_side_end, V_STRIPE_BOT), (u_side_start, V_STRIPE_BOT),
                        (u_side_start, V_STRIPE_TOP), (u_side_end, V_STRIPE_TOP), (-1, 0, 0))
    # Band 3: Windows
    b.add_quad_oriented((-half_w, Y_STRIPE_TOP, z_cab_start), (-half_w, Y_STRIPE_TOP, z_rear),
                        (-half_w, Y_WIN_TOP, z_rear), (-half_w, Y_WIN_TOP, z_cab_start),
                        (u_side_end, V_STRIPE_TOP), (u_side_start, V_STRIPE_TOP),
                        (u_side_start, V_WIN_TOP), (u_side_end, V_WIN_TOP), (-1, 0, 0))
    # Band 4: Cantrail
    b.add_quad_oriented((-half_w, Y_WIN_TOP, z_cab_start), (-half_w, Y_WIN_TOP, z_rear),
                        (-half_w, Y_ROOF_EDGE, z_rear), (-half_w, Y_ROOF_EDGE, z_cab_start),
                        (u_side_end, V_WIN_TOP), (u_side_start, V_WIN_TOP),
                        (u_side_start, V_ROOF_EDGE), (u_side_end, V_ROOF_EDGE), (-1, 0, 0))
    # Band 5: Roof Chamfer
    b.add_quad_oriented((-half_w, Y_ROOF_EDGE, z_cab_start), (-half_w, Y_ROOF_EDGE, z_rear),
                        (-half_w + 0.22, Y_ROOF_CROWN, z_rear), (-half_w + 0.22, Y_ROOF_CROWN, z_cab_start),
                        (u_side_end, V_ROOF_EDGE), (u_side_start, V_ROOF_EDGE),
                        (u_side_start, V_ROOF_CROWN), (u_side_end, V_ROOF_CROWN), (-0.5, 0.86, 0))

    # Clean Corrugated Roof Center (z: z_rear .. z_cab_start)
    b.add_quad_oriented((-half_w + 0.22, Y_ROOF_CROWN, z_cab_start), (half_w - 0.22, Y_ROOF_CROWN, z_cab_start),
                        (half_w - 0.22, Y_ROOF_CROWN, z_rear), (-half_w + 0.22, Y_ROOF_CROWN, z_rear),
                        (ROOF_UV[0], ROOF_UV[1]), (ROOF_UV[2], ROOF_UV[1]),
                        (ROOF_UV[2], ROOF_UV[3]), (ROOF_UV[0], ROOF_UV[3]), (0, 1, 0))

    # ---------------------------------------------------------------------
    # 2. CAB CHEEKS (100% MATHEMATICAL SEAMLESS STRIPES & WINDOWS!)
    # ---------------------------------------------------------------------
    # Left Cheek (+X side):
    # Band 0: Skirt (Y: 0.72 .. 0.86)
    b.add_quad_oriented((half_w, Y_SKIRT_BOT, z_cab_start), (w_nose * 0.92, Y_SKIRT_BOT, z_nose_corner),
                        (w_nose, Y_SKIRT_TOP, z_nose_center), (half_w, Y_SKIRT_TOP, z_cab_start),
                        (u_chk_start, V_SKIRT_BOT), (u_chk_end, V_SKIRT_BOT),
                        (u_chk_end, V_SKIRT_TOP), (u_chk_start, V_SKIRT_TOP), (1, 0, 0.35))
    # Band 1: Lower Cream Body (Y: 0.86 .. 1.35)
    b.add_quad_oriented((half_w, Y_SKIRT_TOP, z_cab_start), (w_nose, Y_SKIRT_TOP, z_nose_center),
                        (w_nose, Y_STRIPE_BOT, z_nose_center), (half_w, Y_STRIPE_BOT, z_cab_start),
                        (u_chk_start, V_SKIRT_TOP), (u_chk_end, V_SKIRT_TOP),
                        (u_chk_end, V_STRIPE_BOT), (u_chk_start, V_STRIPE_BOT), (1, 0, 0.35))
    # Band 2: Speed Stripes (Y: 1.35 .. 2.05) - PERFECTLY CONNECTED ON BOTH ENDS!
    b.add_quad_oriented((half_w, Y_STRIPE_BOT, z_cab_start), (w_nose, Y_STRIPE_BOT, z_nose_center),
                        (w_nose, Y_STRIPE_TOP, z_nose_corner), (half_w, Y_STRIPE_TOP, z_cab_start),
                        (u_chk_start, V_STRIPE_BOT), (u_chk_end, V_STRIPE_BOT),
                        (u_chk_end, V_STRIPE_TOP), (u_chk_start, V_STRIPE_TOP), (1, 0, 0.35))
    # Band 3: Driver's Cab Side Window (Y: 2.05 .. 3.35)
    b.add_quad_oriented((half_w, Y_STRIPE_TOP, z_cab_start), (w_nose, Y_STRIPE_TOP, z_nose_corner),
                        (w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55), (half_w, Y_WIN_TOP, z_cab_start),
                        (u_chk_start, V_STRIPE_TOP), (u_chk_end, V_STRIPE_TOP),
                        (u_chk_end, V_WIN_TOP), (u_chk_start, V_WIN_TOP), (1, 0.1, 0.35))
    # Band 4: Cantrail Upper Panel (Y: 3.35 .. 3.65)
    b.add_quad_oriented((half_w, Y_WIN_TOP, z_cab_start), (w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55),
                        (w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85), (half_w, Y_ROOF_EDGE, z_cab_start),
                        (u_chk_start, V_WIN_TOP), (u_chk_end, V_WIN_TOP),
                        (u_chk_end, V_ROOF_EDGE), (u_chk_start, V_ROOF_EDGE), (1, 0.2, 0.35))
    # Band 5: Roof Chamfer Transition (clean triangle)
    b.add_tri_oriented((half_w, Y_ROOF_EDGE, z_cab_start),
                       (w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85),
                       (half_w - 0.22, Y_ROOF_CROWN, z_cab_start),
                       (u_chk_start, V_ROOF_EDGE), (u_chk_end, V_ROOF_EDGE),
                       (u_chk_start, V_ROOF_CROWN), (0.7, 0.7, 0.2))

    # Right Cheek (-X side):
    # Band 0: Skirt
    b.add_quad_oriented((-w_nose * 0.92, Y_SKIRT_BOT, z_nose_corner), (-half_w, Y_SKIRT_BOT, z_cab_start),
                        (-half_w, Y_SKIRT_TOP, z_cab_start), (-w_nose, Y_SKIRT_TOP, z_nose_center),
                        (u_chk_end, V_SKIRT_BOT), (u_chk_start, V_SKIRT_BOT),
                        (u_chk_start, V_SKIRT_TOP), (u_chk_end, V_SKIRT_TOP), (-1, 0, 0.35))
    # Band 1: Lower Cream Body
    b.add_quad_oriented((-w_nose, Y_SKIRT_TOP, z_nose_center), (-half_w, Y_SKIRT_TOP, z_cab_start),
                        (-half_w, Y_STRIPE_BOT, z_cab_start), (-w_nose, Y_STRIPE_BOT, z_nose_center),
                        (u_chk_end, V_SKIRT_TOP), (u_chk_start, V_SKIRT_TOP),
                        (u_chk_start, V_STRIPE_BOT), (u_chk_end, V_STRIPE_BOT), (-1, 0, 0.35))
    # Band 2: Speed Stripes
    b.add_quad_oriented((-w_nose, Y_STRIPE_BOT, z_nose_center), (-half_w, Y_STRIPE_BOT, z_cab_start),
                        (-half_w, Y_STRIPE_TOP, z_cab_start), (-w_nose, Y_STRIPE_TOP, z_nose_corner),
                        (u_chk_end, V_STRIPE_BOT), (u_chk_start, V_STRIPE_BOT),
                        (u_chk_start, V_STRIPE_TOP), (u_chk_end, V_STRIPE_TOP), (-1, 0, 0.35))
    # Band 3: Driver's Cab Window
    b.add_quad_oriented((-w_nose, Y_STRIPE_TOP, z_nose_corner), (-half_w, Y_STRIPE_TOP, z_cab_start),
                        (-half_w, Y_WIN_TOP, z_cab_start), (-w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55),
                        (u_chk_end, V_STRIPE_TOP), (u_chk_start, V_STRIPE_TOP),
                        (u_chk_start, V_WIN_TOP), (u_chk_end, V_WIN_TOP), (-1, 0.1, 0.35))
    # Band 4: Cantrail Upper Panel
    b.add_quad_oriented((-w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55), (-half_w, Y_WIN_TOP, z_cab_start),
                        (-half_w, Y_ROOF_EDGE, z_cab_start), (-w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85),
                        (u_chk_end, V_WIN_TOP), (u_chk_start, V_WIN_TOP),
                        (u_chk_start, V_ROOF_EDGE), (u_chk_end, V_ROOF_EDGE), (-1, 0.2, 0.35))
    # Band 5: Roof Chamfer Transition (clean triangle)
    b.add_tri_oriented((-w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85),
                       (-half_w, Y_ROOF_EDGE, z_cab_start),
                       (-half_w + 0.22, Y_ROOF_CROWN, z_cab_start),
                       (u_chk_end, V_ROOF_EDGE), (u_chk_start, V_ROOF_EDGE),
                       (u_chk_start, V_ROOF_CROWN), (-0.7, 0.7, 0.2))

    # ---------------------------------------------------------------------
    # 3. FRONT NOSE (SEAMLESS CONTINUATION ACROSS ENTIRE FRONT FACIA!)
    # ---------------------------------------------------------------------
    # Front Panoramic Windshield (Y: 2.05 .. 3.35)
    b.add_quad_oriented((-w_nose, Y_STRIPE_TOP, z_nose_corner), (w_nose, Y_STRIPE_TOP, z_nose_corner),
                        (w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55), (-w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55),
                        (u_nose_start, V_STRIPE_TOP), (u_nose_end, V_STRIPE_TOP),
                        (u_nose_end, V_WIN_TOP), (u_nose_start, V_WIN_TOP), (0, 0.40, 0.91))

    # Destination Marquee ("SILOM 4LOM") (Y: 3.35 .. 3.65)
    b.add_quad_oriented((-w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55), (w_nose * 0.96, Y_WIN_TOP, z_nose_corner - 0.55),
                        (w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85), (-w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85),
                        (u_nose_start, V_WIN_TOP), (u_nose_end, V_WIN_TOP),
                        (u_nose_end, V_ROOF_EDGE), (u_nose_start, V_ROOF_EDGE), (0, 0.50, 0.86))

    # Cab Roof Center Transition Face (above marquee to roof crown)
    b.add_quad_oriented((-w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85), (w_nose * 0.92, Y_ROOF_EDGE, z_nose_corner - 0.85),
                        (half_w - 0.22, Y_ROOF_CROWN, z_cab_start), (-half_w + 0.22, Y_ROOF_CROWN, z_cab_start),
                        (ROOF_UV[0], ROOF_UV[1] + 0.1), (ROOF_UV[2], ROOF_UV[1] + 0.1),
                        (ROOF_UV[2], ROOF_UV[3]), (ROOF_UV[0], ROOF_UV[3]), (0, 0.70, 0.70))

    # Front Lower Nose Speed Stripes (Y: 1.35 .. 2.05) - Seamless with cheek!
    b.add_quad_oriented((-w_nose, Y_STRIPE_BOT, z_nose_center), (w_nose, Y_STRIPE_BOT, z_nose_center),
                        (w_nose, Y_STRIPE_TOP, z_nose_corner), (-w_nose, Y_STRIPE_TOP, z_nose_corner),
                        (u_nose_start, V_STRIPE_BOT), (u_nose_end, V_STRIPE_BOT),
                        (u_nose_end, V_STRIPE_TOP), (u_nose_start, V_STRIPE_TOP), (0, 0.25, 0.96))

    # Front Lower Chin / Headlights (Y: 0.86 .. 1.35)
    b.add_quad_oriented((-w_nose, Y_SKIRT_TOP, z_nose_center), (w_nose, Y_SKIRT_TOP, z_nose_center),
                        (w_nose, Y_STRIPE_BOT, z_nose_center), (-w_nose, Y_STRIPE_BOT, z_nose_center),
                        (u_nose_start, V_SKIRT_TOP), (u_nose_end, V_SKIRT_TOP),
                        (u_nose_end, V_STRIPE_BOT), (u_nose_start, V_STRIPE_BOT), (0, 0.10, 0.99))

    # Front Cowcatcher Wedge Face (Y: 0.72 .. 0.86)
    b.add_quad_oriented((-w_nose * 0.92, Y_SKIRT_BOT, z_nose_corner), (w_nose * 0.92, Y_SKIRT_BOT, z_nose_corner),
                        (w_nose, Y_SKIRT_TOP, z_nose_center), (-w_nose, Y_SKIRT_TOP, z_nose_center),
                        (u_nose_start, V_SKIRT_BOT), (u_nose_end, V_SKIRT_BOT),
                        (u_nose_end, V_SKIRT_TOP), (u_nose_start, V_SKIRT_TOP), (0, -0.45, 0.89))


    # ---------------------------------------------------------------------
    # 4. SOLID UNDERBELLY FLOOR PLATES (NO BACKFACE / NO HOLES ANYWHERE!)
    # ---------------------------------------------------------------------
    u0, v0, u1, v1 = UNDER_UV

    # A. Main Cabin Floor Plate (z: z_rear .. z_cab_start, Y: 0.72m)
    b.add_quad_oriented((-half_w, Y_SKIRT_BOT, z_rear), (half_w, Y_SKIRT_BOT, z_rear),
                        (half_w, Y_SKIRT_BOT, z_cab_start), (-half_w, Y_SKIRT_BOT, z_cab_start),
                        (u0, v0), (u1, v0), (u1, v1), (u0, v1), (0, -1, 0))

    # B. Front Under-Cab Floor Plate (z: z_cab_start .. z_nose_corner, Y: 0.72m)
    b.add_quad_oriented((-half_w, Y_SKIRT_BOT, z_cab_start), (half_w, Y_SKIRT_BOT, z_cab_start),
                        (w_nose * 0.92, Y_SKIRT_BOT, z_nose_corner), (-w_nose * 0.92, Y_SKIRT_BOT, z_nose_corner),
                        (u0, v0), (u1, v0), (u1, v1), (u0, v1), (0, -1, 0))

    # ---------------------------------------------------------------------
    # 5. REAR BULKHEAD WALL & INTER-CAR GANGWAY
    # ---------------------------------------------------------------------
    b.add_quad_oriented((half_w, Y_SKIRT_BOT, z_rear), (-half_w, Y_SKIRT_BOT, z_rear),
                        (-half_w, Y_ROOF_EDGE, z_rear), (half_w, Y_ROOF_EDGE, z_rear),
                        (BULKHEAD_UV[0], BULKHEAD_UV[1]), (BULKHEAD_UV[2], BULKHEAD_UV[1]),
                        (BULKHEAD_UV[2], BULKHEAD_UV[3]), (BULKHEAD_UV[0], BULKHEAD_UV[3]), (0, 0, -1))
    b.add_quad_oriented((half_w, Y_ROOF_EDGE, z_rear), (-half_w, Y_ROOF_EDGE, z_rear),
                        (-half_w + 0.22, Y_ROOF_CROWN, z_rear), (half_w - 0.22, Y_ROOF_CROWN, z_rear),
                        (BULKHEAD_UV[0], BULKHEAD_UV[3] - 0.04), (BULKHEAD_UV[2], BULKHEAD_UV[3] - 0.04),
                        (BULKHEAD_UV[2], BULKHEAD_UV[3]), (BULKHEAD_UV[0], BULKHEAD_UV[3]), (0, 0, -1))

    gw_w = 0.95
    gw_h_top = 3.10
    gw_h_bot = 0.92
    z_gw_end = z_rear - 0.55
    b.add_box_specific_uv((-gw_w, gw_h_bot, z_gw_end), (gw_w, gw_h_top, z_rear),
                          BELLOWS_UV, BELLOWS_UV, BELLOWS_UV, BELLOWS_UV)
    b.add_box_specific_uv((-gw_w * 0.75, gw_h_bot - 0.04, z_gw_end - 0.10),
                          (gw_w * 0.75, gw_h_bot + 0.04, z_rear),
                          BELLOWS_UV, BELLOWS_UV, BELLOWS_UV, BELLOWS_UV)

    # ---------------------------------------------------------------------
    # 6. UNDERFLOOR EQUIPMENT BOXES (DEEP 3D PROTRUDING BOXES, NOT FLATTENED!)
    # ---------------------------------------------------------------------
    b.add_box_specific_uv((-1.15, 0.48, -4.0), (1.15, 0.72, 4.0),
                          EQUIPMENT_UV, EQUIPMENT_UV, EQUIPMENT_UV, EQUIPMENT_UV)

    # ---------------------------------------------------------------------
    # 7. BOGIES & ROOFTOP HVAC
    # ---------------------------------------------------------------------
    build_bogie(b, center_z = 6.60)
    build_bogie(b, center_z = -6.60)

    build_hvac_pod(b, center_z = 4.80)
    build_hvac_pod(b, center_z = -4.80)

    return b


def build_middle_car():
    b = MeshBuilder("BTS_Train_Middle")

    half_w = 1.56
    z_rear = -10.90
    z_front = 10.90

    u_start = 0.000
    u_end   = 0.585

    # ---------------------------------------------------------------------
    # 1. SIDE WALLS (IDENTICAL HORIZONTAL BANDS)
    # ---------------------------------------------------------------------
    # Left Side Wall (+X = 1.56)
    # Band 0: Skirt
    b.add_quad_oriented((half_w, Y_SKIRT_BOT, z_rear), (half_w, Y_SKIRT_BOT, z_front),
                        (half_w, Y_SKIRT_TOP, z_front), (half_w, Y_SKIRT_TOP, z_rear),
                        (u_start, V_SKIRT_BOT), (u_end, V_SKIRT_BOT),
                        (u_end, V_SKIRT_TOP), (u_start, V_SKIRT_TOP), (1, 0, 0))
    # Band 1: Lower Cream Body Fluting
    b.add_quad_oriented((half_w, Y_SKIRT_TOP, z_rear), (half_w, Y_SKIRT_TOP, z_front),
                        (half_w, Y_STRIPE_BOT, z_front), (half_w, Y_STRIPE_BOT, z_rear),
                        (u_start, V_SKIRT_TOP), (u_end, V_SKIRT_TOP),
                        (u_end, V_STRIPE_BOT), (u_start, V_STRIPE_BOT), (1, 0, 0))
    # Band 2: Speed Stripes (Red, White, Blue)
    b.add_quad_oriented((half_w, Y_STRIPE_BOT, z_rear), (half_w, Y_STRIPE_BOT, z_front),
                        (half_w, Y_STRIPE_TOP, z_front), (half_w, Y_STRIPE_TOP, z_rear),
                        (u_start, V_STRIPE_BOT), (u_end, V_STRIPE_BOT),
                        (u_end, V_STRIPE_TOP), (u_start, V_STRIPE_TOP), (1, 0, 0))
    # Band 3: Passenger Windows & Doors
    b.add_quad_oriented((half_w, Y_STRIPE_TOP, z_rear), (half_w, Y_STRIPE_TOP, z_front),
                        (half_w, Y_WIN_TOP, z_front), (half_w, Y_WIN_TOP, z_rear),
                        (u_start, V_STRIPE_TOP), (u_end, V_STRIPE_TOP),
                        (u_end, V_WIN_TOP), (u_start, V_WIN_TOP), (1, 0, 0))
    # Band 4: Upper Cantrail
    b.add_quad_oriented((half_w, Y_WIN_TOP, z_rear), (half_w, Y_WIN_TOP, z_front),
                        (half_w, Y_ROOF_EDGE, z_front), (half_w, Y_ROOF_EDGE, z_rear),
                        (u_start, V_WIN_TOP), (u_end, V_WIN_TOP),
                        (u_end, V_ROOF_EDGE), (u_start, V_ROOF_EDGE), (1, 0, 0))
    # Band 5: Roof Chamfer
    b.add_quad_oriented((half_w, Y_ROOF_EDGE, z_rear), (half_w, Y_ROOF_EDGE, z_front),
                        (half_w - 0.22, Y_ROOF_CROWN, z_front), (half_w - 0.22, Y_ROOF_CROWN, z_rear),
                        (u_start, V_ROOF_EDGE), (u_end, V_ROOF_EDGE),
                        (u_end, V_ROOF_CROWN), (u_start, V_ROOF_CROWN), (0.5, 0.86, 0))

    # Right Side Wall (-X = -1.56)
    b.add_quad_oriented((-half_w, Y_SKIRT_BOT, z_front), (-half_w, Y_SKIRT_BOT, z_rear),
                        (-half_w, Y_SKIRT_TOP, z_rear), (-half_w, Y_SKIRT_TOP, z_front),
                        (u_end, V_SKIRT_BOT), (u_start, V_SKIRT_BOT),
                        (u_start, V_SKIRT_TOP), (u_end, V_SKIRT_TOP), (-1, 0, 0))
    b.add_quad_oriented((-half_w, Y_SKIRT_TOP, z_front), (-half_w, Y_SKIRT_TOP, z_rear),
                        (-half_w, Y_STRIPE_BOT, z_rear), (-half_w, Y_STRIPE_BOT, z_front),
                        (u_end, V_SKIRT_TOP), (u_start, V_SKIRT_TOP),
                        (u_start, V_STRIPE_BOT), (u_end, V_STRIPE_BOT), (-1, 0, 0))
    b.add_quad_oriented((-half_w, Y_STRIPE_BOT, z_front), (-half_w, Y_STRIPE_BOT, z_rear),
                        (-half_w, Y_STRIPE_TOP, z_rear), (-half_w, Y_STRIPE_TOP, z_front),
                        (u_end, V_STRIPE_BOT), (u_start, V_STRIPE_BOT),
                        (u_start, V_STRIPE_TOP), (u_end, V_STRIPE_TOP), (-1, 0, 0))
    b.add_quad_oriented((-half_w, Y_STRIPE_TOP, z_front), (-half_w, Y_STRIPE_TOP, z_rear),
                        (-half_w, Y_WIN_TOP, z_rear), (-half_w, Y_WIN_TOP, z_front),
                        (u_end, V_STRIPE_TOP), (u_start, V_STRIPE_TOP),
                        (u_start, V_WIN_TOP), (u_end, V_WIN_TOP), (-1, 0, 0))
    b.add_quad_oriented((-half_w, Y_WIN_TOP, z_front), (-half_w, Y_WIN_TOP, z_rear),
                        (-half_w, Y_ROOF_EDGE, z_rear), (-half_w, Y_ROOF_EDGE, z_front),
                        (u_end, V_WIN_TOP), (u_start, V_WIN_TOP),
                        (u_start, V_ROOF_EDGE), (u_end, V_ROOF_EDGE), (-1, 0, 0))
    b.add_quad_oriented((-half_w, Y_ROOF_EDGE, z_front), (-half_w, Y_ROOF_EDGE, z_rear),
                        (-half_w + 0.22, Y_ROOF_CROWN, z_rear), (-half_w + 0.22, Y_ROOF_CROWN, z_front),
                        (u_end, V_ROOF_EDGE), (u_start, V_ROOF_EDGE),
                        (u_start, V_ROOF_CROWN), (u_end, V_ROOF_CROWN), (-0.5, 0.86, 0))

    # Clean Corrugated Roof Center
    b.add_quad_oriented((-half_w + 0.22, Y_ROOF_CROWN, z_front), (half_w - 0.22, Y_ROOF_CROWN, z_front),
                        (half_w - 0.22, Y_ROOF_CROWN, z_rear), (-half_w + 0.22, Y_ROOF_CROWN, z_rear),
                        (ROOF_UV[0], ROOF_UV[1]), (ROOF_UV[2], ROOF_UV[1]),
                        (ROOF_UV[2], ROOF_UV[3]), (ROOF_UV[0], ROOF_UV[3]), (0, 1, 0))

    # Solid Underbelly Floor Plate (Y: 0.72m)
    u0, v0, u1, v1 = UNDER_UV
    b.add_quad_oriented((-half_w, Y_SKIRT_BOT, z_rear), (half_w, Y_SKIRT_BOT, z_rear),
                        (half_w, Y_SKIRT_BOT, z_front), (-half_w, Y_SKIRT_BOT, z_front),
                        (u0, v0), (u1, v0), (u1, v1), (u0, v1), (0, -1, 0))

    # ---------------------------------------------------------------------
    # 2. GANGWAY BELLOWS & BULKHEAD END WALLS FRONT & REAR
    # ---------------------------------------------------------------------
    gw_w = 0.95
    gw_h_top = 3.10
    gw_h_bot = 0.92

    # Front End Bulkhead Wall & Bellows
    b.add_quad_oriented((-half_w, Y_SKIRT_BOT, z_front), (half_w, Y_SKIRT_BOT, z_front),
                        (half_w, Y_ROOF_EDGE, z_front), (-half_w, Y_ROOF_EDGE, z_front),
                        (BULKHEAD_UV[0], BULKHEAD_UV[1]), (BULKHEAD_UV[2], BULKHEAD_UV[1]),
                        (BULKHEAD_UV[2], BULKHEAD_UV[3]), (BULKHEAD_UV[0], BULKHEAD_UV[3]), (0, 0, 1))
    b.add_quad_oriented((-half_w, Y_ROOF_EDGE, z_front), (half_w, Y_ROOF_EDGE, z_front),
                        (half_w - 0.22, Y_ROOF_CROWN, z_front), (-half_w + 0.22, Y_ROOF_CROWN, z_front),
                        (BULKHEAD_UV[0], BULKHEAD_UV[3] - 0.04), (BULKHEAD_UV[2], BULKHEAD_UV[3] - 0.04),
                        (BULKHEAD_UV[2], BULKHEAD_UV[3]), (BULKHEAD_UV[0], BULKHEAD_UV[3]), (0, 0, 1))
    b.add_box_specific_uv((-gw_w, gw_h_bot, z_front), (gw_w, gw_h_top, z_front + 0.55),
                          BELLOWS_UV, BELLOWS_UV, BELLOWS_UV, BELLOWS_UV)
    b.add_box_specific_uv((-gw_w * 0.75, gw_h_bot - 0.04, z_front),
                          (gw_w * 0.75, gw_h_bot + 0.04, z_front + 0.65),
                          BELLOWS_UV, BELLOWS_UV, BELLOWS_UV, BELLOWS_UV)

    # Rear End Bulkhead Wall & Bellows
    b.add_quad_oriented((half_w, Y_SKIRT_BOT, z_rear), (-half_w, Y_SKIRT_BOT, z_rear),
                        (-half_w, Y_ROOF_EDGE, z_rear), (half_w, Y_ROOF_EDGE, z_rear),
                        (BULKHEAD_UV[0], BULKHEAD_UV[1]), (BULKHEAD_UV[2], BULKHEAD_UV[1]),
                        (BULKHEAD_UV[2], BULKHEAD_UV[3]), (BULKHEAD_UV[0], BULKHEAD_UV[3]), (0, 0, -1))
    b.add_quad_oriented((half_w, Y_ROOF_EDGE, z_rear), (-half_w, Y_ROOF_EDGE, z_rear),
                        (-half_w + 0.22, Y_ROOF_CROWN, z_rear), (half_w - 0.22, Y_ROOF_CROWN, z_rear),
                        (BULKHEAD_UV[0], BULKHEAD_UV[3] - 0.04), (BULKHEAD_UV[2], BULKHEAD_UV[3] - 0.04),
                        (BULKHEAD_UV[2], BULKHEAD_UV[3]), (BULKHEAD_UV[0], BULKHEAD_UV[3]), (0, 0, -1))
    b.add_box_specific_uv((-gw_w, gw_h_bot, z_rear - 0.55), (gw_w, gw_h_top, z_rear),
                          BELLOWS_UV, BELLOWS_UV, BELLOWS_UV, BELLOWS_UV)
    b.add_box_specific_uv((-gw_w * 0.75, gw_h_bot - 0.04, z_rear - 0.65),
                          (gw_w * 0.75, gw_h_bot + 0.04, z_rear),
                          BELLOWS_UV, BELLOWS_UV, BELLOWS_UV, BELLOWS_UV)

    # ---------------------------------------------------------------------
    # 3. UNDERFLOOR EQUIPMENT BOXES (DEEP 3D PROTRUDING BOXES)
    # ---------------------------------------------------------------------
    b.add_box_specific_uv((-1.15, 0.48, -4.5), (1.15, 0.72, 4.5),
                          EQUIPMENT_UV, EQUIPMENT_UV, EQUIPMENT_UV, EQUIPMENT_UV)

    # 4. Bogies & Rooftop HVAC
    build_bogie(b, center_z = 7.50)
    build_bogie(b, center_z = -7.50)

    build_hvac_pod(b, center_z = 5.20)
    build_hvac_pod(b, center_z = -5.20)

    return b


def build_full_consist():
    consist = MeshBuilder("BTS_Train_3Car_Consist")

    cab_lead = build_cab_car()
    mid = build_middle_car()

    # Spacing: Gangways meet seamlessly at Z = ±11.45m!
    offset_lead = 21.80
    for v in cab_lead.vertices:
        consist.vertices.append((v[0], v[1], v[2] + offset_lead))
    consist.normals.extend(cab_lead.normals)
    consist.uvs.extend(cab_lead.uvs)
    consist.indices.extend(cab_lead.indices)

    base_idx_mid = len(consist.vertices)
    consist.vertices.extend(mid.vertices)
    consist.normals.extend(mid.normals)
    consist.uvs.extend(mid.uvs)
    consist.indices.extend([i + base_idx_mid for i in mid.indices])

    base_idx_rear = len(consist.vertices)
    offset_rear = -21.80
    for v in cab_lead.vertices:
        consist.vertices.append((-v[0], v[1], -v[2] + offset_rear))
    for n in cab_lead.normals:
        consist.normals.append((-n[0], n[1], -n[2]))
    consist.uvs.extend(cab_lead.uvs)
    # 180° rotation around Y is a proper rotation (det=+1), so winding order is PRESERVED!
    for i in range(0, len(cab_lead.indices), 3):
        consist.indices.extend([base_idx_rear + cab_lead.indices[i],
                                base_idx_rear + cab_lead.indices[i+1],
                                base_idx_rear + cab_lead.indices[i+2]])

    return consist


tex_png = os.path.join(OUT_DIR, "BTS_Train_BaseColor.png")

# 1. Lead Cab Car
cab_mesh = build_cab_car()
cab_obj = os.path.join(OUT_DIR, "BTS_Train_Cab.obj")
cab_glb = os.path.join(OUT_DIR, "BTS_Train_Cab.glb")
cab_mesh.write_obj(cab_obj)
cab_mesh.write_glb(cab_glb, texture_png_path=tex_png)
print(f"Revision 4 Cab Car: {len(cab_mesh.vertices)} vertices, {len(cab_mesh.indices)//3} triangles.")

# 2. Middle Car
mid_mesh = build_middle_car()
mid_obj = os.path.join(OUT_DIR, "BTS_Train_Middle.obj")
mid_glb = os.path.join(OUT_DIR, "BTS_Train_Middle.glb")
mid_mesh.write_obj(mid_obj)
mid_mesh.write_glb(mid_glb, texture_png_path=tex_png)
print(f"Revision 4 Middle Car: {len(mid_mesh.vertices)} vertices, {len(mid_mesh.indices)//3} triangles.")

# 3. Full 3-Car Consist
consist_mesh = build_full_consist()
consist_glb = os.path.join(OUT_DIR, "BTS_Train_FullConsist.glb")
consist_obj = os.path.join(OUT_DIR, "BTS_Train_FullConsist.obj")
consist_mesh.write_obj(consist_obj)
consist_mesh.write_glb(consist_glb, texture_png_path=tex_png)
print(f"Revision 7 3-Car Consist: {len(consist_mesh.vertices)} vertices, {len(consist_mesh.indices)//3} triangles.")

# 4. Update MTL
mtl_path = os.path.join(OUT_DIR, "BTS_Train.mtl")
with open(mtl_path, 'w') as f:
    f.write("""newmtl M_BTS_Train
Ka 1.0 1.0 1.0
Kd 1.0 1.0 1.0
Ks 0.4 0.4 0.4
Ns 30.0
d 1.0
illum 2
map_Kd BTS_Train_BaseColor.png
""")
print("Updated MTL file:", mtl_path)
