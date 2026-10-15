import os
import numpy as np
import pygltflib
from pygltflib import (
    GLTF2, Scene, Node, Mesh, Primitive, Attributes, Buffer, BufferView,
    Accessor, Material, PbrMetallicRoughness, Texture, TextureInfo,
    Image as GLTFImage, Sampler
)

LANDMARK_DIR = "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Landmark"
OBJ_PATH = os.path.join(LANDMARK_DIR, "Landmark_BangkokBank_HeadOffice.obj")
GLB_PATH = os.path.join(LANDMARK_DIR, "Landmark_BangkokBank_HeadOffice.glb")

MAT_NAMES = ["Mat_BBL_Tower", "Mat_BBL_Podium", "Mat_BBL_Arcade"]

def convert_multi_material_obj_to_glb():
    print(f"Reading Multi-Material OBJ: {OBJ_PATH}")
    verts = []
    uvs = []
    normals = []
    
    # Store faces grouped by material
    faces_by_mat = {mat: [] for mat in MAT_NAMES}
    current_mat = MAT_NAMES[0]
    
    with open(OBJ_PATH) as f:
        for line in f:
            if line.startswith('v '):
                verts.append([float(x) for x in line.strip().split()[1:4]])
            elif line.startswith('vt '):
                uvs.append([float(x) for x in line.strip().split()[1:3]])
            elif line.startswith('vn '):
                normals.append([float(x) for x in line.strip().split()[1:4]])
            elif line.startswith('usemtl '):
                mat_name = line.strip().split()[1]
                if mat_name in faces_by_mat:
                    current_mat = mat_name
            elif line.startswith('f '):
                pts = line.strip().split()[1:]
                f_v = []
                f_uv = []
                f_vn = []
                for p in pts:
                    parts = p.split('/')
                    f_v.append(int(parts[0]) - 1)
                    f_uv.append(int(parts[1]) - 1)
                    if len(parts) >= 3 and parts[2]:
                        f_vn.append(int(parts[2]) - 1)
                faces_by_mat[current_mat].append((f_v, f_uv, f_vn))

    print(f"Total Vertices: {len(verts)}, UVs: {len(uvs)}, Normals: {len(normals)}")
    for mat in MAT_NAMES:
        print(f"  {mat}: {len(faces_by_mat[mat])} faces")

    # We will build unpacked vertex buffers per material primitive
    def pad(b):
        return b + b'\x00' * ((4 - len(b) % 4) % 4)

    binary_chunks = []
    gltf = GLTF2()
    
    # Sampler
    sampler = Sampler(magFilter=pygltflib.LINEAR, minFilter=pygltflib.LINEAR_MIPMAP_LINEAR)
    gltf.samplers.append(sampler)
    
    # Read all texture images
    img_filenames = {
        "Mat_BBL_Tower": ("BBL_Tower_BaseColor.png", "BBL_Tower_RoughnessMetallic.png", "BBL_Tower_Normal.png"),
        "Mat_BBL_Podium": ("BBL_Podium_BaseColor.png", "BBL_Podium_RoughnessMetallic.png", "BBL_Podium_Normal.png"),
        "Mat_BBL_Arcade": ("BBL_Arcade_BaseColor.png", "BBL_Arcade_RoughnessMetallic.png", "BBL_Arcade_Normal.png"),
    }
    
    mat_tex_indices = {}
    tex_counter = 0
    img_counter = 0
    
    # Add images and textures
    for mat in MAT_NAMES:
        albedo_fn, orm_fn, norm_fn = img_filenames[mat]
        with open(os.path.join(LANDMARK_DIR, albedo_fn), "rb") as f:
            albedo_data = pad(f.read())
        with open(os.path.join(LANDMARK_DIR, orm_fn), "rb") as f:
            orm_data = pad(f.read())
        with open(os.path.join(LANDMARK_DIR, norm_fn), "rb") as f:
            norm_data = pad(f.read())
            
        # BufferViews for images
        offset = sum(len(c) for c in binary_chunks)
        bv_albedo = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(albedo_data)))
        binary_chunks.append(albedo_data)
        
        offset = sum(len(c) for c in binary_chunks)
        bv_orm = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(orm_data)))
        binary_chunks.append(orm_data)
        
        offset = sum(len(c) for c in binary_chunks)
        bv_norm_img = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(norm_data)))
        binary_chunks.append(norm_data)
        
        # Images
        gltf.images.append(GLTFImage(bufferView=bv_albedo, mimeType="image/png"))
        gltf.images.append(GLTFImage(bufferView=bv_orm, mimeType="image/png"))
        gltf.images.append(GLTFImage(bufferView=bv_norm_img, mimeType="image/png"))
        
        # Textures
        idx_albedo = tex_counter; tex_counter += 1
        idx_orm = tex_counter; tex_counter += 1
        idx_norm = tex_counter; tex_counter += 1
        
        gltf.textures.append(Texture(sampler=0, source=img_counter))
        gltf.textures.append(Texture(sampler=0, source=img_counter + 1))
        gltf.textures.append(Texture(sampler=0, source=img_counter + 2))
        img_counter += 3
        
        mat_tex_indices[mat] = (idx_albedo, idx_orm, idx_norm)
        
        # Material with doubleSided = True!
        pbr = PbrMetallicRoughness(
            baseColorTexture=TextureInfo(index=idx_albedo),
            metallicRoughnessTexture=TextureInfo(index=idx_orm),
            metallicFactor=1.0,
            roughnessFactor=1.0
        )
        material = Material(
            name=mat,
            pbrMetallicRoughness=pbr,
            normalTexture=TextureInfo(index=idx_norm),
            doubleSided=True
        )
        gltf.materials.append(material)

    primitives = []
    
    # Now generate geometry buffers per primitive
    for mat_idx, mat in enumerate(MAT_NAMES):
        faces = faces_by_mat[mat]
        if not faces:
            continue
            
        unpacked_pos = []
        unpacked_uv = []
        unpacked_norm = []
        unpacked_indices = []
        
        for (f_v, f_uv, f_vn) in faces:
            if len(f_v) != 3: continue
            for i in range(3):
                vi = f_v[i]
                uvi = f_uv[i]
                vni = f_vn[i] if i < len(f_vn) else 0
                
                unpacked_indices.append(len(unpacked_pos))
                unpacked_pos.append(verts[vi])
                u, v = uvs[uvi]
                unpacked_uv.append([u, 1.0 - v])
                unpacked_norm.append(normals[vni] if vni < len(normals) else [0, 1, 0])
                
        pos_arr = np.array(unpacked_pos, dtype=np.float32)
        uv_arr = np.array(unpacked_uv, dtype=np.float32)
        norm_arr = np.array(unpacked_norm, dtype=np.float32)
        idx_arr = np.array(unpacked_indices, dtype=np.uint16)
        
        pos_bytes = pad(pos_arr.tobytes())
        uv_bytes = pad(uv_arr.tobytes())
        norm_bytes = pad(norm_arr.tobytes())
        idx_bytes = pad(idx_arr.tobytes())
        
        # Position BufferView & Accessor
        offset = sum(len(c) for c in binary_chunks)
        bv_pos = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(pos_bytes), target=pygltflib.ARRAY_BUFFER))
        binary_chunks.append(pos_bytes)
        
        acc_pos = len(gltf.accessors)
        gltf.accessors.append(Accessor(
            bufferView=bv_pos, byteOffset=0,
            componentType=pygltflib.FLOAT, count=len(pos_arr), type=pygltflib.VEC3,
            max=pos_arr.max(axis=0).tolist(), min=pos_arr.min(axis=0).tolist()
        ))
        
        # UV BufferView & Accessor
        offset = sum(len(c) for c in binary_chunks)
        bv_uv = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(uv_bytes), target=pygltflib.ARRAY_BUFFER))
        binary_chunks.append(uv_bytes)
        
        acc_uv = len(gltf.accessors)
        gltf.accessors.append(Accessor(
            bufferView=bv_uv, byteOffset=0,
            componentType=pygltflib.FLOAT, count=len(uv_arr), type=pygltflib.VEC2,
            max=uv_arr.max(axis=0).tolist(), min=uv_arr.min(axis=0).tolist()
        ))
        
        # Normal BufferView & Accessor
        offset = sum(len(c) for c in binary_chunks)
        bv_norm = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(norm_bytes), target=pygltflib.ARRAY_BUFFER))
        binary_chunks.append(norm_bytes)
        
        acc_norm = len(gltf.accessors)
        gltf.accessors.append(Accessor(
            bufferView=bv_norm, byteOffset=0,
            componentType=pygltflib.FLOAT, count=len(norm_arr), type=pygltflib.VEC3,
            max=norm_arr.max(axis=0).tolist(), min=norm_arr.min(axis=0).tolist()
        ))
        
        # Indices BufferView & Accessor
        offset = sum(len(c) for c in binary_chunks)
        bv_idx = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(idx_bytes), target=pygltflib.ELEMENT_ARRAY_BUFFER))
        binary_chunks.append(idx_bytes)
        
        acc_idx = len(gltf.accessors)
        gltf.accessors.append(Accessor(
            bufferView=bv_idx, byteOffset=0,
            componentType=pygltflib.UNSIGNED_SHORT, count=len(idx_arr), type=pygltflib.SCALAR,
            max=[int(idx_arr.max())], min=[int(idx_arr.min())]
        ))
        
        # Primitive
        prim = Primitive(
            attributes=Attributes(POSITION=acc_pos, TEXCOORD_0=acc_uv, NORMAL=acc_norm),
            indices=acc_idx,
            material=mat_idx
        )
        primitives.append(prim)

    mesh = Mesh(primitives=primitives)
    gltf.meshes.append(mesh)
    
    node = Node(mesh=0, name="Landmark_BangkokBank_HeadOffice")
    gltf.nodes.append(node)
    
    scene = Scene(nodes=[0])
    gltf.scenes.append(scene)
    gltf.scene = 0
    
    total_buffer = b"".join(binary_chunks)
    gltf.buffers.append(Buffer(byteLength=len(total_buffer)))
    gltf.set_binary_blob(total_buffer)
    gltf.save_binary(GLB_PATH)
    
    current_map_dest = "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Current Map/Landmark/Landmark_BangkokBank_HeadOffice.glb"
    import shutil
    shutil.copy2(GLB_PATH, current_map_dest)
    print(f"Successfully generated Multi-Material GLB: {GLB_PATH} ({os.path.getsize(GLB_PATH) / 1024:.1f} KB)")
    print(f"Synchronized to Current Map: {current_map_dest}")

if __name__ == "__main__":
    convert_multi_material_obj_to_glb()
