@tool
extends EditorScript
## Standalone VAT Baker for Crowd Characters (Male & Female Dance Variants).
## Open in Godot Script Editor and run via File -> Run (Ctrl+Shift+X).
## Does NOT modify any existing scenes or zombie assets.

const OUTPUT_DIR := "res://scenes/Crowds/VAT"
const BAKE_FPS := 24.0
const MAX_TEX_WIDTH := 2048

const MALE_CLIPS := [
	{"name": "Dance Animation Male/Dance 1", "alias": "dance_1", "loop": true},
	{"name": "Dance Animation Male/Dance 2", "alias": "dance_2", "loop": true},
	{"name": "Dance Animation Male/Dance Blue", "alias": "dance_blue", "loop": true},
	{"name": "Dance Animation Male/Dance orange", "alias": "dance_orange", "loop": true},
]

const FEMALE_CLIPS := [
	{"name": "F Dance 1", "alias": "dance_1", "loop": true},
	{"name": "F Dance 2", "alias": "dance_2", "loop": true},
	{"name": "F Dance 3", "alias": "dance_3", "loop": true},
	{"name": "F Dance Blue", "alias": "dance_blue", "loop": true},
	{"name": "F Dance orange", "alias": "dance_orange", "loop": true},
]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_bake_model("res://scenes/Crowds/crowd_male_model.tscn", "Body_001", "crowd_male", MALE_CLIPS)
	_bake_model("res://scenes/Crowds/crowd_female_model.tscn", "Body", "crowd_female", FEMALE_CLIPS)
	_bake_model("res://scenes/Crowds/crowd_female_model_nohat.tscn", "Body2", "crowd_female_nohat", FEMALE_CLIPS)
	EditorInterface.get_resource_filesystem().scan()


func _bake_model(scene_path: String, mesh_name: String, output_prefix: String, clips_cfg: Array) -> void:
	var packed := load(scene_path) as PackedScene
	if not packed:
		push_error("VATBaker: Failed to load scene: " + scene_path)
		return

	var root := packed.instantiate() as Node3D
	var tree_root := EditorInterface.get_base_control().get_tree().root
	tree_root.add_child(root)

	var anim_player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := root.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var mesh_inst := root.find_child(mesh_name, true, false) as MeshInstance3D

	if not anim_player or not skeleton or not mesh_inst or not mesh_inst.mesh:
		push_error("VATBaker: Missing AnimationPlayer, GeneralSkeleton, or %s in %s" % [mesh_name, scene_path])
		root.queue_free()
		return

	var src_mesh: Mesh = mesh_inst.mesh
	if src_mesh.get_surface_count() == 0:
		push_error("VATBaker: Source mesh has 0 surfaces in " + scene_path)
		root.queue_free()
		return

	var arrays := src_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var surface_format: int = src_mesh.surface_get_format(0)
	var bones_per_vertex: int = 8 if (surface_format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0 else 4

	var vertex_count := vertices.size()
	var tex_width := mini(vertex_count, MAX_TEX_WIDTH)
	var rows_per_frame := ceili(float(vertex_count) / float(tex_width))

	var valid_clips: Array[Dictionary] = []
	var total_frames := 0
	for clip_cfg in clips_cfg:
		var anim_name: String = clip_cfg["name"]
		if not anim_player.has_animation(anim_name):
			push_warning("VATBaker: Animation not found in %s, skipping: %s" % [output_prefix, anim_name])
			continue
		var anim: Animation = anim_player.get_animation(anim_name)
		var frame_count := maxi(2, ceili(anim.length * BAKE_FPS) + 1)
		valid_clips.append({
			"name": anim_name,
			"alias": clip_cfg["alias"],
			"loop": clip_cfg["loop"],
			"length": anim.length,
			"start_frame": total_frames,
			"frame_count": frame_count,
		})
		total_frames += frame_count

	if total_frames == 0:
		push_error("VATBaker: No valid animations found to bake for " + output_prefix)
		root.queue_free()
		return

	var tex_height := total_frames * rows_per_frame
	var pos_img := Image.create(tex_width, tex_height, false, Image.FORMAT_RGBAH)
	var nrm_img := Image.create(tex_width, tex_height, false, Image.FORMAT_RGBAH)

	var skin: Skin = mesh_inst.skin
	var bone_count := skeleton.get_bone_count()
	var bind_count := skin.get_bind_count() if skin else bone_count
	var bind_to_skel := PackedInt32Array()
	bind_to_skel.resize(bind_count)
	var bind_poses: Array[Transform3D] = []
	bind_poses.resize(bind_count)

	for i in range(bind_count):
		if skin:
			var skel_idx := skin.get_bind_bone(i)
			if skel_idx < 0:
				skel_idx = skeleton.find_bone(skin.get_bind_name(i))
			bind_to_skel[i] = skel_idx
			bind_poses[i] = skin.get_bind_pose(i)
		else:
			bind_to_skel[i] = i
			bind_poses[i] = skeleton.get_bone_global_rest(i).affine_inverse()

	var root_inv := root.global_transform.affine_inverse()
	var skel_to_root := root_inv * skeleton.global_transform
	var skel_to_root_nrm := skel_to_root.basis.inverse().transposed()

	var clips_meta := {}
	var bone_mats: Array[Transform3D] = []
	bone_mats.resize(bind_count)

	for clip in valid_clips:
		var anim_name: String = clip["name"]
		var alias: String = clip["alias"]
		var start_frame: int = clip["start_frame"]
		var frame_count: int = clip["frame_count"]
		var length: float = clip["length"]

		for f in range(frame_count):
			var t := 0.0
			if frame_count > 1:
				t = clampf((float(f) / float(frame_count - 1)) * length, 0.0, length)

			anim_player.assigned_animation = anim_name
			anim_player.seek(t, true)
			skeleton.advance(0.0)

			for i in range(bind_count):
				var skel_idx := bind_to_skel[i]
				if skel_idx >= 0 and skel_idx < bone_count:
					bone_mats[i] = skeleton.get_bone_global_pose(skel_idx) * bind_poses[i]
				else:
					bone_mats[i] = Transform3D.IDENTITY

			var base_row := (start_frame + f) * rows_per_frame
			for v_idx in range(vertex_count):
				var v_pos := vertices[v_idx]
				var v_nrm := normals[v_idx] if v_idx < normals.size() else Vector3.UP

				var skinned_pos := Vector3.ZERO
				var skinned_nrm := Vector3.ZERO
				var total_w := 0.0
				var base_b := v_idx * bones_per_vertex

				for k in range(bones_per_vertex):
					var w := weights[base_b + k]
					if w <= 0.0001:
						continue
					var b_idx := bones[base_b + k]
					if b_idx >= 0 and b_idx < bind_count:
						var m := bone_mats[b_idx]
						skinned_pos += (m * v_pos) * w
						skinned_nrm += (m.basis * v_nrm) * w
						total_w += w

				if total_w <= 0.0001:
					skinned_pos = v_pos
					skinned_nrm = v_nrm

				var final_pos := skel_to_root * skinned_pos
				var final_nrm := (skel_to_root_nrm * skinned_nrm).normalized()

				var col := v_idx % tex_width
				var row := base_row + (v_idx / tex_width)
				pos_img.set_pixel(col, row, Color(final_pos.x, final_pos.y, final_pos.z, 1.0))
				nrm_img.set_pixel(col, row, Color(final_nrm.x, final_nrm.y, final_nrm.z, 1.0))

		clips_meta[alias] = {
			"anim_name": anim_name,
			"start_frame": start_frame,
			"frame_count": frame_count,
			"duration": length,
			"loop": clip["loop"],
		}

	var pos_tex := ImageTexture.create_from_image(pos_img)
	var nrm_tex := ImageTexture.create_from_image(nrm_img)
	ResourceSaver.save(pos_tex, "%s/%s_vat_pos.res" % [OUTPUT_DIR, output_prefix])
	ResourceSaver.save(nrm_tex, "%s/%s_vat_nrm.res" % [OUTPUT_DIR, output_prefix])

	var vat_arrays := arrays.duplicate()
	vat_arrays[Mesh.ARRAY_BONES] = null
	vat_arrays[Mesh.ARRAY_WEIGHTS] = null

	var uv2 := PackedVector2Array()
	uv2.resize(vertex_count)
	for i in range(vertex_count):
		uv2[i] = Vector2(float(i), 0.0)
	vat_arrays[Mesh.ARRAY_TEX_UV2] = uv2

	var vat_mesh := ArrayMesh.new()
	vat_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, vat_arrays)
	vat_mesh.custom_aabb = AABB(Vector3(-1.5, -0.2, -1.5), Vector3(3.0, 2.5, 3.0))
	ResourceSaver.save(vat_mesh, "%s/%s_vat_mesh.tres" % [OUTPUT_DIR, output_prefix])

	var meta := {
		"vertex_count": vertex_count,
		"tex_width": tex_width,
		"tex_height": tex_height,
		"rows_per_frame": rows_per_frame,
		"total_frames": total_frames,
		"fps": BAKE_FPS,
		"clips": clips_meta,
	}
	var f := FileAccess.open("%s/%s_vat_meta.json" % [OUTPUT_DIR, output_prefix], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "\t"))
		f.close()

	root.queue_free()
	print("VATBaker: Baked %s — %d vertices, %d frames (%dx%d)" % [output_prefix, vertex_count, total_frames, tex_width, tex_height])
