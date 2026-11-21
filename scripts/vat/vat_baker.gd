@tool
extends EditorScript
## Standalone VAT Baker for Full VAT Crowd:
## - Male Dancers, Female (Hat) Dancers, Female (No-Hat) Dancers
## - Male Gunner Body + Paired Animated Gun Prop (all 6 NPCGun sub-meshes)
## - Male Ballooner Body + Per-Frame Hand Balloon Transforms
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

const GUN_CLIPS := [
	{"name": "Range Zombie  ReloadLoop", "alias": "gun_reload", "loop": true, "ping_pong": true, "fire_time": -1.0},
	{"name": "Range Zombie  shot", "alias": "gun_shot", "loop": false, "fire_time": 3.44},
]

const BALLOON_CLIPS := [
	{"name": "Dance Animation Male/Dance 1", "alias": "dance_1", "loop": true, "release_time": -1.0},
	{"name": "Dance Animation Male/Dance 2", "alias": "dance_2", "loop": true, "release_time": -1.0},
	{"name": "Dance Animation Male/Dance Blue", "alias": "dance_blue", "loop": true, "release_time": -1.0},
	{"name": "Dance Animation Male/Dance orange", "alias": "dance_orange", "loop": true, "release_time": -1.0},
	{"name": "Balloone Zombie/Balloone Zombie Idle -loop", "alias": "balloon_idle", "loop": true, "release_time": -1.0},
	{"name": "Balloone Zombie/Balloone Zombie equip and throw", "alias": "balloon_throw", "loop": false, "release_time": 1.80},
]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_bake_model("res://scenes/Crowds/crowd_male_model.tscn", "Body_001", "crowd_male", MALE_CLIPS)
	_bake_model("res://scenes/Crowds/crowd_female_model.tscn", "Body", "crowd_female", FEMALE_CLIPS)
	_bake_model("res://scenes/Crowds/crowd_female_model_nohat.tscn", "Body2", "crowd_female_nohat", FEMALE_CLIPS)
	_bake_gun_pair("res://scenes/Crowds/crowd_male_model_Gun.tscn", "Body_001", GUN_CLIPS)
	_bake_balloon_model("res://scenes/Crowds/crowd_male_model_Balloon.tscn", "Body_001", BALLOON_CLIPS)
	EditorInterface.get_resource_filesystem().scan()
	print("VATBaker: All Full VAT crowd assets baked to " + OUTPUT_DIR)


func _sync_bone_attachments(root: Node3D, skeleton: Skeleton3D) -> void:
	for child in skeleton.get_children():
		if child is BoneAttachment3D:
			var ba := child as BoneAttachment3D
			var b_idx := skeleton.find_bone(ba.bone_name) if ba.bone_name != "" else ba.bone_idx
			if b_idx < 0:
				b_idx = ba.bone_idx
			if b_idx >= 0 and b_idx < skeleton.get_bone_count():
				ba.transform = skeleton.get_bone_global_pose(b_idx)
	# Also ensure any nested BoneAttachment3D inside root updates
	if root:
		pass


func _build_clip_sample_times(length: float, base_frames: int, ping_pong: bool) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	for f in range(base_frames):
		var t := clampf((float(f) / float(base_frames - 1)) * length, 0.0, length) if base_frames > 1 else 0.0
		times.append(t)
	if ping_pong and base_frames > 2:
		for f in range(base_frames - 2, 0, -1):
			var t := clampf((float(f) / float(base_frames - 1)) * length, 0.0, length)
			times.append(t)
	return times


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

	_bake_skinned_mesh_internal(root, anim_player, skeleton, mesh_inst, output_prefix, clips_cfg, {})
	root.queue_free()


func _bake_gun_pair(scene_path: String, body_mesh_name: String, clips_cfg: Array) -> void:
	var packed := load(scene_path) as PackedScene
	if not packed:
		push_error("VATBaker: Failed to load gun scene: " + scene_path)
		return

	var root := packed.instantiate() as Node3D
	var tree_root := EditorInterface.get_base_control().get_tree().root
	tree_root.add_child(root)

	var anim_player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := root.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var body_mesh := root.find_child(body_mesh_name, true, false) as MeshInstance3D
	var npc_gun := root.find_child("NPCGun", true, false) as Node3D
	var gun_spawn := root.find_child("GunSpawnPoint", true, false) as Node3D

	if not anim_player or not skeleton or not body_mesh or not body_mesh.mesh:
		push_error("VATBaker: Missing nodes in " + scene_path)
		root.queue_free()
		return

	# 1. Bake Gunner Body + record GunSpawnPoint transform at fire_time
	var extra_meta := {}
	if gun_spawn:
		for clip_cfg in clips_cfg:
			var fire_time: float = float(clip_cfg.get("fire_time", -1.0))
			var anim_name: String = clip_cfg["name"]
			if fire_time >= 0.0 and anim_player.has_animation(anim_name):
				var anim: Animation = anim_player.get_animation(anim_name)
				anim_player.assigned_animation = anim_name
				anim_player.seek(clampf(fire_time, 0.0, anim.length), true)
				skeleton.advance(0.0)
				_sync_bone_attachments(root, skeleton)
				var rel := root.global_transform.affine_inverse() * gun_spawn.global_transform
				extra_meta[clip_cfg["alias"]] = {
					"spawn_event": {
						"time": fire_time,
						"pos": [rel.origin.x, rel.origin.y, rel.origin.z],
						"forward": [-rel.basis.z.x, -rel.basis.z.y, -rel.basis.z.z],
						"basis_x": [rel.basis.x.x, rel.basis.x.y, rel.basis.x.z],
						"basis_y": [rel.basis.y.x, rel.basis.y.y, rel.basis.y.z],
						"basis_z": [rel.basis.z.x, rel.basis.z.y, rel.basis.z.z],
					}
				}

	_bake_skinned_mesh_internal(root, anim_player, skeleton, body_mesh, "crowd_gun_body", clips_cfg, extra_meta)

	# 2. Bake Paired Gun Prop (all MeshInstance3D sub-meshes combined into 1 single-surface VAT)
	if npc_gun:
		_bake_prop_hierarchy(root, anim_player, skeleton, npc_gun, "crowd_gun_prop", clips_cfg)
	else:
		push_warning("VATBaker: NPCGun node not found in " + scene_path)

	root.queue_free()


func _bake_balloon_model(scene_path: String, body_mesh_name: String, clips_cfg: Array) -> void:
	var packed := load(scene_path) as PackedScene
	if not packed:
		push_error("VATBaker: Failed to load balloon scene: " + scene_path)
		return

	var root := packed.instantiate() as Node3D
	var tree_root := EditorInterface.get_base_control().get_tree().root
	tree_root.add_child(root)

	var anim_player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := root.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var body_mesh := root.find_child(body_mesh_name, true, false) as MeshInstance3D
	var balloon_node := root.find_child("WaterBalloon", true, false) as Node3D

	if not anim_player or not skeleton or not body_mesh or not body_mesh.mesh:
		push_error("VATBaker: Missing nodes in " + scene_path)
		root.queue_free()
		return

	# Record per-frame WaterBalloon hand positions, rotations, and scale during balloon_throw
	var extra_meta := {}
	if balloon_node:
		for clip_cfg in clips_cfg:
			var release_time: float = float(clip_cfg.get("release_time", -1.0))
			var anim_name: String = clip_cfg["name"]
			if release_time >= 0.0 and anim_player.has_animation(anim_name):
				var anim: Animation = anim_player.get_animation(anim_name)
				var frame_count := maxi(2, ceili(anim.length * BAKE_FPS) + 1)
				var hand_positions: Array = []
				var hand_rotations: Array = []
				var hand_scale := [1.0, 1.0, 1.0]
				var root_inv := root.global_transform.affine_inverse()
				for f in range(frame_count):
					var t := clampf((float(f) / float(frame_count - 1)) * anim.length, 0.0, anim.length)
					anim_player.assigned_animation = anim_name
					anim_player.seek(t, true)
					skeleton.advance(0.0)
					_sync_bone_attachments(root, skeleton)
					var rel := root_inv * balloon_node.global_transform
					var q := rel.basis.orthonormalized().get_rotation_quaternion()
					if f == 0:
						var s := rel.basis.get_scale()
						hand_scale = [s.x, s.y, s.z]
					hand_positions.append([rel.origin.x, rel.origin.y, rel.origin.z])
					hand_rotations.append([q.x, q.y, q.z, q.w])

				anim_player.assigned_animation = anim_name
				anim_player.seek(clampf(release_time, 0.0, anim.length), true)
				skeleton.advance(0.0)
				_sync_bone_attachments(root, skeleton)
				var rel_release := root_inv * balloon_node.global_transform
				var rel_q := rel_release.basis.orthonormalized().get_rotation_quaternion()

				extra_meta[clip_cfg["alias"]] = {
					"release_time": release_time,
					"release_pos": [rel_release.origin.x, rel_release.origin.y, rel_release.origin.z],
					"release_rot": [rel_q.x, rel_q.y, rel_q.z, rel_q.w],
					"hand_scale": hand_scale,
					"hand_positions": hand_positions,
					"hand_rotations": hand_rotations,
				}

	_bake_skinned_mesh_internal(root, anim_player, skeleton, body_mesh, "crowd_balloon", clips_cfg, extra_meta)
	root.queue_free()


func _bake_skinned_mesh_internal(
	root: Node3D,
	anim_player: AnimationPlayer,
	skeleton: Skeleton3D,
	mesh_inst: MeshInstance3D,
	output_prefix: String,
	clips_cfg: Array,
	extra_clip_meta: Dictionary
) -> void:
	var src_mesh: Mesh = mesh_inst.mesh
	if src_mesh.get_surface_count() == 0:
		push_error("VATBaker: Source mesh has 0 surfaces for " + output_prefix)
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
		var base_frames := maxi(2, ceili(anim.length * BAKE_FPS) + 1)
		var ping_pong := bool(clip_cfg.get("ping_pong", false))
		var sample_times := _build_clip_sample_times(anim.length, base_frames, ping_pong)
		var frame_count := sample_times.size()
		valid_clips.append({
			"name": anim_name,
			"alias": clip_cfg["alias"],
			"loop": clip_cfg["loop"],
			"ping_pong": ping_pong,
			"length": anim.length * 2.0 if ping_pong else anim.length,
			"start_frame": total_frames,
			"frame_count": frame_count,
			"sample_times": sample_times,
		})
		total_frames += frame_count

	if total_frames == 0:
		push_error("VATBaker: No valid animations found to bake for " + output_prefix)
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
		var sample_times: PackedFloat32Array = clip["sample_times"]

		for f in range(frame_count):
			var t := sample_times[f]
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

		var clip_entry := {
			"anim_name": anim_name,
			"start_frame": start_frame,
			"frame_count": frame_count,
			"duration": length,
			"loop": clip["loop"],
			"ping_pong": clip["ping_pong"],
		}
		if extra_clip_meta.has(alias):
			for k in (extra_clip_meta[alias] as Dictionary).keys():
				clip_entry[k] = extra_clip_meta[alias][k]
		clips_meta[alias] = clip_entry

	ResourceSaver.save(ImageTexture.create_from_image(pos_img), "%s/%s_vat_pos.res" % [OUTPUT_DIR, output_prefix])
	ResourceSaver.save(ImageTexture.create_from_image(nrm_img), "%s/%s_vat_nrm.res" % [OUTPUT_DIR, output_prefix])

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

	print("VATBaker: Baked %s — %d vertices, %d frames (%dx%d)" % [output_prefix, vertex_count, total_frames, tex_width, tex_height])


func _bake_prop_hierarchy(
	root: Node3D,
	anim_player: AnimationPlayer,
	skeleton: Skeleton3D,
	prop_root: Node3D,
	output_prefix: String,
	clips_cfg: Array
) -> void:
	# Gather all MeshInstance3D sub-meshes inside prop_root
	var sub_entries: Array[Dictionary] = []
	var palette_colors: Array[Color] = []

	for child in prop_root.find_children("*", "MeshInstance3D", true, false):
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		if not mi.mesh:
			continue
		for surf_idx in range(mi.mesh.get_surface_count()):
			var surf_arrays := mi.mesh.surface_get_arrays(surf_idx)
			var verts: PackedVector3Array = surf_arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var nrms: PackedVector3Array = surf_arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = surf_arrays[Mesh.ARRAY_INDEX] if surf_arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

			var mat: Material = mi.get_surface_override_material(surf_idx)
			if not mat:
				mat = mi.material_override
			if not mat:
				mat = mi.mesh.surface_get_material(surf_idx)
			var albedo_col := Color.WHITE
			if mat is StandardMaterial3D:
				albedo_col = (mat as StandardMaterial3D).albedo_color

			var color_idx := palette_colors.size()
			palette_colors.append(albedo_col)
			sub_entries.append({
				"node": mi,
				"verts": verts,
				"nrms": nrms,
				"indices": indices,
				"color_idx": color_idx,
			})

	if sub_entries.is_empty():
		push_warning("VATBaker: No sub-meshes found in prop " + prop_root.name)
		return

	# Combine into one static ArrayMesh with UV pointing into palette & UV2 holding vertex index
	var combined_verts := PackedVector3Array()
	var combined_nrms := PackedVector3Array()
	var combined_uv := PackedVector2Array()
	var combined_uv2 := PackedVector2Array()
	var combined_indices := PackedInt32Array()
	var palette_count := maxi(palette_colors.size(), 1)

	for entry in sub_entries:
		var base_v := combined_verts.size()
		var verts: PackedVector3Array = entry["verts"]
		var nrms: PackedVector3Array = entry["nrms"]
		var idxs: PackedInt32Array = entry["indices"]
		var u := (float(entry["color_idx"]) + 0.5) / float(palette_count)

		for i in range(verts.size()):
			combined_verts.append(verts[i])
			combined_nrms.append(nrms[i] if i < nrms.size() else Vector3.UP)
			combined_uv.append(Vector2(u, 0.5))
			combined_uv2.append(Vector2(float(base_v + i), 0.0))

		if idxs.is_empty():
			for i in range(verts.size()):
				combined_indices.append(base_v + i)
		else:
			for idx in idxs:
				combined_indices.append(base_v + idx)

	var vertex_count := combined_verts.size()
	var tex_width := mini(vertex_count, MAX_TEX_WIDTH)
	var rows_per_frame := ceili(float(vertex_count) / float(tex_width))

	var valid_clips: Array[Dictionary] = []
	var total_frames := 0
	for clip_cfg in clips_cfg:
		var anim_name: String = clip_cfg["name"]
		if not anim_player.has_animation(anim_name):
			continue
		var anim: Animation = anim_player.get_animation(anim_name)
		var base_frames := maxi(2, ceili(anim.length * BAKE_FPS) + 1)
		var ping_pong := bool(clip_cfg.get("ping_pong", false))
		var sample_times := _build_clip_sample_times(anim.length, base_frames, ping_pong)
		var frame_count := sample_times.size()
		valid_clips.append({
			"name": anim_name,
			"alias": clip_cfg["alias"],
			"loop": clip_cfg["loop"],
			"ping_pong": ping_pong,
			"length": anim.length * 2.0 if ping_pong else anim.length,
			"start_frame": total_frames,
			"frame_count": frame_count,
			"sample_times": sample_times,
		})
		total_frames += frame_count

	if total_frames == 0:
		return

	var tex_height := total_frames * rows_per_frame
	var pos_img := Image.create(tex_width, tex_height, false, Image.FORMAT_RGBAH)
	var nrm_img := Image.create(tex_width, tex_height, false, Image.FORMAT_RGBAH)
	var root_inv := root.global_transform.affine_inverse()
	var clips_meta := {}

	for clip in valid_clips:
		var anim_name: String = clip["name"]
		var alias: String = clip["alias"]
		var start_frame: int = clip["start_frame"]
		var frame_count: int = clip["frame_count"]
		var length: float = clip["length"]
		var sample_times: PackedFloat32Array = clip["sample_times"]

		for f in range(frame_count):
			var t := sample_times[f]
			anim_player.assigned_animation = anim_name
			anim_player.seek(t, true)
			skeleton.advance(0.0)
			_sync_bone_attachments(root, skeleton)

			var base_row := (start_frame + f) * rows_per_frame
			var cursor := 0
			for entry in sub_entries:
				var mi: MeshInstance3D = entry["node"]
				var verts: PackedVector3Array = entry["verts"]
				var nrms: PackedVector3Array = entry["nrms"]
				var to_root := root_inv * mi.global_transform
				var nrm_basis := to_root.basis.inverse().transposed()

				for i in range(verts.size()):
					var final_pos := to_root * verts[i]
					var raw_nrm := nrms[i] if i < nrms.size() else Vector3.UP
					var final_nrm := (nrm_basis * raw_nrm).normalized()
					var v_idx := cursor + i
					var col := v_idx % tex_width
					var row := base_row + (v_idx / tex_width)
					pos_img.set_pixel(col, row, Color(final_pos.x, final_pos.y, final_pos.z, 1.0))
					nrm_img.set_pixel(col, row, Color(final_nrm.x, final_nrm.y, final_nrm.z, 1.0))
				cursor += verts.size()

		clips_meta[alias] = {
			"anim_name": anim_name,
			"start_frame": start_frame,
			"frame_count": frame_count,
			"duration": length,
			"loop": clip["loop"],
			"ping_pong": clip["ping_pong"],
		}

	# Save palette texture
	var pal_img := Image.create(palette_count, 1, false, Image.FORMAT_RGBA8)
	for i in range(palette_colors.size()):
		pal_img.set_pixel(i, 0, palette_colors[i])
	ResourceSaver.save(ImageTexture.create_from_image(pal_img), "%s/%s_palette.res" % [OUTPUT_DIR, output_prefix])

	ResourceSaver.save(ImageTexture.create_from_image(pos_img), "%s/%s_vat_pos.res" % [OUTPUT_DIR, output_prefix])
	ResourceSaver.save(ImageTexture.create_from_image(nrm_img), "%s/%s_vat_nrm.res" % [OUTPUT_DIR, output_prefix])

	var mesh_arrays := []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = combined_verts
	mesh_arrays[Mesh.ARRAY_NORMAL] = combined_nrms
	mesh_arrays[Mesh.ARRAY_TEX_UV] = combined_uv
	mesh_arrays[Mesh.ARRAY_TEX_UV2] = combined_uv2
	mesh_arrays[Mesh.ARRAY_INDEX] = combined_indices

	var prop_mesh := ArrayMesh.new()
	prop_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	prop_mesh.custom_aabb = AABB(Vector3(-1.5, -0.2, -1.5), Vector3(3.0, 2.5, 3.0))
	ResourceSaver.save(prop_mesh, "%s/%s_vat_mesh.tres" % [OUTPUT_DIR, output_prefix])

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

	print("VATBaker: Baked prop %s — %d vertices, %d parts, %d frames (%dx%d)" % [output_prefix, vertex_count, sub_entries.size(), total_frames, tex_width, tex_height])
