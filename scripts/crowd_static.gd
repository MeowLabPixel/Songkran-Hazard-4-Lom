@tool
class_name CrowdStatic
extends Node3D

## Inner data class storing persistent base layout per crowd instance
class MemberInstanceData:
	var base_transform: Transform3D = Transform3D.IDENTITY
	var offset: float = 0.0
	var is_jumper: bool = false
	var is_gunner: bool = false
	var spin_mult: float = 0.0

# ─── Configuration & Toggles ──────────────────────────────────────────────────

@export_group("Crowd Layout")
@export var spawn_area_size: Vector3 = Vector3(24.0, 1.0, 8.0):
	set(val):
		spawn_area_size = val
		_on_config_changed()

@export_range(1, 10, 1) var row_count: int = 4:
	set(val):
		row_count = val
		_on_config_changed()

@export_range(1, 200, 1) var total_crowd_count: int = 60:
	set(val):
		total_crowd_count = val
		_on_config_changed()

@export var front_row_is_negative_z: bool = true:
	set(val):
		front_row_is_negative_z = val
		_on_config_changed()

@export var disallow_jumpers_in_front_row: bool = true:
	set(val):
		disallow_jumpers_in_front_row = val
		_on_config_changed()

@export_range(0.0, 180.0, 1.0) var facing_randomness_deg: float = 35.0:
	set(val):
		facing_randomness_deg = val
		_on_config_changed()

@export var base_facing_angle_deg: float = 0.0:
	set(val):
		base_facing_angle_deg = val
		_on_config_changed()

@export var custom_seed: int = 12345:
	set(val):
		custom_seed = val
		_on_config_changed()

@export_group("Model & Pose Baking")
@export var male_model_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model.tscn")
@export var crowd_static_material: Material = preload("res://scenes/Crowds/Crowd_Static_Material.tres")
@export var texture_blue: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Blue.png")
@export var texture_green: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Green.png")
@export var texture_pink: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Pink.png")
@export var uv_scale: Vector3 = Vector3(1.3, 1.3, 1.3):
	set(val):
		uv_scale = val
		_setup_materials()
		_on_config_changed()

@export_range(0.0, 1.0, 0.05) var anim_pose_percentage: float = 0.5:
	set(val):
		anim_pose_percentage = val
		_on_config_changed()

@export var pose_animations: Array[String] = [
	"Balloone Zombie Idle -loop",
	"Hit Leg act 1 Slipping",
	"Hit RightLeg act 1 Slipping",
	"Dance 1",
	"Dance 2",
	"Dance Blue",
	"Dance orange",
	"Range Zombie  ReloadLoop"
]

@export var anim_time_overrides: Dictionary = {
	"Dance 1": 0.01,
	"Dance 2": 2.78,
	"Dance Blue": 1.75,
	"Dance orange": 0.04,
	"Range Zombie  ReloadLoop": 0.3
}

@export var jumping_pose_keywords: Array[String] = [
	"Hit Leg act 1",
	"Hit RightLeg act 1"
]

@export var gun_pose_keyword: String = "ReloadLoop"

@export var enable_npc_guns: bool = true:
	set(val):
		enable_npc_guns = val
		_baked_meshes.clear()
		_on_config_changed()

@export var npc_gun_scene: PackedScene = preload("res://GunSystem/npc_gun_static_crowd.tscn"):
	set(val):
		npc_gun_scene = val
		_baked_meshes.clear()
		_on_config_changed()

@export var rebake_poses_now: bool = false:
	set(val):
		if val:
			rebake_poses_now = false
			_baked_meshes.clear()
			_gun_relative_transform = Transform3D.IDENTITY
			_bake_and_build_crowd()
			_setup_ambient_projectiles()

@export_group("Cheering & Animation")
@export var enable_cheering: bool = true:
	set(val):
		enable_cheering = val
		_update_process_state()

@export var preview_cheer_in_editor: bool = false:
	set(val):
		preview_cheer_in_editor = val
		_update_process_state()

@export var cheer_speed: float = 8.0
@export var cheer_height: float = 0.75
@export var wave_speed: float = 2.0
@export var wave_frequency: float = 0.4
@export var idle_bob_speed: float = 2.0
@export var idle_bob_height: float = 0.05
@export_range(0.0, 1.0, 0.05) var spin_chance: float = 0.15

@export_group("Ambient Projectiles")
@export var enable_ambient_projectiles: bool = true:
	set(val):
		enable_ambient_projectiles = val
		if not val:
			_cleanup_ambient_projectiles()
		else:
			if is_node_ready():
				_setup_ambient_projectiles()
		_update_process_state()

@export_range(1, 5, 1) var vfx_front_row_count: int = 1
@export var waterline_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterLine.tscn")
@export var water_balloon_scene: PackedScene = preload("res://scenes/items/water_balloon.tscn")
@export var waterline_interval_range: Vector2 = Vector2(0.8, 2.5)
@export var waterline_lifetime: float = 0.12
@export var water_balloon_interval_range: Vector2 = Vector2(2.0, 5.0)
@export var projectile_target_forward_distance: float = 12.0
@export var projectile_spread_x: float = 10.0

@export_group("Ground & Collision Snapping")
@export var enable_ground_snap: bool = true:
	set(val):
		enable_ground_snap = val
		_on_config_changed()

@export var ground_ray_height: float = 5.0
@export var ground_ray_depth: float = 5.0
@export_flags_3d_physics var ground_collision_mask: int = 1
@export_range(0.0, 1.0, 0.05) var min_ground_normal_y: float = 0.65
@export var skip_obstructed_members: bool = true
@export var obstacle_check_radius: float = 0.25

# ─── Internal State ──────────────────────────────────────────────────────────

var _pose_multimeshes: Array[MultiMeshInstance3D] = []
var _pose_members: Array[Array] = [] # Array of Array[MemberInstanceData]
var _baked_meshes: Dictionary = {} # anim_name -> ArrayMesh
var _materials: Array[StandardMaterial3D] = [] # [Blue, Green, Pink]
var _visibility_notifier: VisibleOnScreenNotifier3D = null
var _is_on_screen: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _change_pending: bool = false

var _guns_container: Node3D = null
var _gun_relative_transform: Transform3D = Transform3D.IDENTITY

var _projectiles_container: Node3D = null
var _waterline_pool: Array[Node3D] = []
var _balloon_pool: Array[Node3D] = []
var _waterline_timer: float = 0.0
var _balloon_timer: float = 0.0

# ─── Lifecycle ─────────────────────────────────────────────────────────────

func _enter_tree() -> void:
	_setup_materials()
	if Engine.is_editor_hint() and is_node_ready():
		if enable_ambient_projectiles and not is_instance_valid(_projectiles_container):
			_setup_ambient_projectiles()
		if _pose_multimeshes.is_empty():
			_bake_and_build_crowd()
		_update_process_state()

func _ready() -> void:
	_setup_materials()
	_setup_visibility_notifier()
	_setup_ambient_projectiles()

	if _pose_multimeshes.is_empty():
		_bake_and_build_crowd()

	_update_process_state()

func _exit_tree() -> void:
	_cleanup_ambient_projectiles()
	_clear_guns()

func _update_process_state() -> void:
	if Engine.is_editor_hint():
		set_process(preview_cheer_in_editor)
	else:
		set_process((enable_cheering or enable_ambient_projectiles) and _is_on_screen)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not preview_cheer_in_editor:
		return
	if not _is_on_screen and not Engine.is_editor_hint():
		return

	if enable_cheering:
		_process_cheering(delta)

	if enable_ambient_projectiles:
		_process_ambient_projectiles(delta)

func _process_cheering(_delta: float) -> void:
	var time: float = Time.get_ticks_msec() / 1000.0

	for p in range(_pose_multimeshes.size()):
		var mmi = _pose_multimeshes[p]
		if not is_instance_valid(mmi):
			continue
		var mm = mmi.multimesh
		if not mm:
			continue

		var members = _pose_members[p]
		for j in range(members.size()):
			var m: MemberInstanceData = members[j]
			var offset: float = m.offset

			var wave_time = time * wave_speed + offset
			var wave_envelope = (sin(wave_time) + 1.0) * 0.5
			var idle_y = sin(time * idle_bob_speed + offset * 5.0) * idle_bob_height

			var displacement: float = 0.0
			var tilt_angle: float = (sin(time * cheer_speed + offset) * 0.06) * wave_envelope
			var spin_angle: float = 0.0

			if m.is_jumper:
				var bounce = abs(sin(time * cheer_speed + offset * 2.0))
				var cheer_jump_y = bounce * cheer_height
				displacement = lerp(idle_y, cheer_jump_y, wave_envelope)
				if displacement < 0.0:
					displacement = lerp(displacement, 0.0, wave_envelope)
				if m.spin_mult != 0.0:
					spin_angle = bounce * PI * m.spin_mult * wave_envelope
			else:
				# Non-jumpers stay grounded, gentle wave bobbing
				displacement = idle_y * (1.0 + wave_envelope * 0.5)

			var t: Transform3D = m.base_transform
			t.origin.y += displacement
			if tilt_angle != 0.0:
				t.basis = t.basis.rotated(t.basis.z.normalized(), tilt_angle)
			if spin_angle != 0.0:
				t.basis = t.basis.rotated(Vector3.UP, spin_angle)

			mm.set_instance_transform(j, t)

# ─── Visibility Culling ────────────────────────────────────────────────────

func _setup_visibility_notifier() -> void:
	var existing = get_node_or_null("VisibilityNotifier") as VisibleOnScreenNotifier3D
	if existing:
		_visibility_notifier = existing
	else:
		_visibility_notifier = VisibleOnScreenNotifier3D.new()
		_visibility_notifier.name = "VisibilityNotifier"
		add_child(_visibility_notifier)

	_update_visibility_notifier_aabb()

	if not _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
		_visibility_notifier.screen_entered.connect(_on_screen_entered)
	if not _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
		_visibility_notifier.screen_exited.connect(_on_screen_exited)

func _update_visibility_notifier_aabb() -> void:
	if not _visibility_notifier:
		return
	var margin = Vector3(2.0, 1.5, 2.0)
	var size = spawn_area_size + margin * 2.0
	var center = Vector3(0.0, (spawn_area_size.y + cheer_height) * 0.5, 0.0)
	_visibility_notifier.aabb = AABB(center - size * 0.5, size)

func _on_screen_entered() -> void:
	_is_on_screen = true
	for mmi in _pose_multimeshes:
		if is_instance_valid(mmi):
			mmi.visible = true
	if is_instance_valid(_guns_container):
		_guns_container.visible = true
	if is_instance_valid(_projectiles_container):
		_projectiles_container.visible = true
	_update_process_state()

func _on_screen_exited() -> void:
	if Engine.is_editor_hint():
		return
	_is_on_screen = false
	for mmi in _pose_multimeshes:
		if is_instance_valid(mmi):
			mmi.visible = false
	if is_instance_valid(_guns_container):
		_guns_container.visible = false
	if is_instance_valid(_projectiles_container):
		_projectiles_container.visible = false
	_update_process_state()

# ─── Materials & Textures Setup ───────────────────────────────────────────

func _setup_materials() -> void:
	_materials.clear()
	var base_mat: StandardMaterial3D = crowd_static_material as StandardMaterial3D
	if not base_mat:
		base_mat = StandardMaterial3D.new()

	var textures: Array[Texture2D] = [texture_blue, texture_green, texture_pink]
	for tex in textures:
		var mat = base_mat.duplicate() as StandardMaterial3D
		if mat:
			if tex:
				mat.albedo_texture = tex
			mat.uv1_scale = uv_scale
			_materials.append(mat)
		else:
			_materials.append(base_mat)

# ─── Baking & MultiMesh Construction ───────────────────────────────────────

func _on_config_changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready():
		return
	if _change_pending:
		return
	_change_pending = true
	_apply_config_deferred.call_deferred()

func _apply_config_deferred() -> void:
	_change_pending = false
	if not Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready():
		return
	_bake_and_build_crowd()

func _clear_guns() -> void:
	if is_instance_valid(_guns_container):
		for child in _guns_container.get_children():
			child.queue_free()
		if _guns_container.get_parent() == self:
			remove_child(_guns_container)
		_guns_container.queue_free()
		_guns_container = null

	for child in get_children():
		if child.name == "NPCGuns":
			remove_child(child)
			child.queue_free()

func _clear_multimeshes() -> void:
	_clear_guns()

	for mmi in _pose_multimeshes:
		if is_instance_valid(mmi):
			if mmi.get_parent() == self:
				remove_child(mmi)
			mmi.queue_free()
	_pose_multimeshes.clear()
	_pose_members.clear()

	for child in get_children():
		if child is MultiMeshInstance3D:
			if child.get_parent() == self:
				remove_child(child)
			child.queue_free()

func _find_animation(anim_player: AnimationPlayer, target_name: String) -> String:
	if anim_player.has_animation(target_name):
		return target_name
	var target_clean = target_name.strip_edges()
	var all_anims = anim_player.get_animation_list()
	for a in all_anims:
		if a == target_clean:
			return a
		if a.ends_with("/" + target_clean):
			return a
		if a.to_lower() == target_clean.to_lower():
			return a
		if a.to_lower().ends_with("/" + target_clean.to_lower()):
			return a
	return ""

func _reset_skeleton_to_rest(skel: Skeleton3D) -> void:
	skel.clear_bones_global_pose_override()
	skel.reset_bone_poses()
	skel.force_update_all_bone_transforms()
	skel.notification(Node.NOTIFICATION_POST_ENTER_TREE)

func _apply_animation_to_skeleton(skel: Skeleton3D, anim: Animation, target_time: float) -> void:
	var track_count = anim.get_track_count()
	for t in range(track_count):
		var str_path: String = str(anim.track_get_path(t))
		var colon_idx: int = str_path.find(":")
		var bone_name: String = str_path.substr(colon_idx + 1) if colon_idx != -1 else str_path

		if bone_name == "":
			continue

		var bone_idx: int = skel.find_bone(bone_name)
		if bone_idx < 0:
			continue

		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				skel.set_bone_pose_position(bone_idx, anim.position_track_interpolate(t, target_time))
			Animation.TYPE_ROTATION_3D:
				skel.set_bone_pose_rotation(bone_idx, anim.rotation_track_interpolate(t, target_time))
			Animation.TYPE_SCALE_3D:
				skel.set_bone_pose_scale(bone_idx, anim.scale_track_interpolate(t, target_time))
			Animation.TYPE_VALUE:
				var val = anim.value_track_interpolate(t, target_time)
				if val is Quaternion:
					skel.set_bone_pose_rotation(bone_idx, val)
				elif val is Vector3:
					skel.set_bone_pose_position(bone_idx, val)

	skel.force_update_all_bone_transforms()
	skel.notification(Node.NOTIFICATION_POST_ENTER_TREE)

func _bake_pose_meshes() -> void:
	if pose_animations.is_empty() or not male_model_scene:
		return

	# Check if all target poses are already baked and gun transform is determined
	var all_present = true
	for anim_name in pose_animations:
		if not _baked_meshes.has(anim_name) or _baked_meshes[anim_name] == null:
			all_present = false
			break
	if all_present and not _baked_meshes.is_empty() and _gun_relative_transform != Transform3D.IDENTITY:
		return

	# Instantiate temporary model to sample bone poses
	var model = male_model_scene.instantiate() as Node3D
	if not model:
		return
	model.visible = false
	add_child(model)

	var anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skel = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var mesh_inst = model.find_child("Body_001", true, false) as MeshInstance3D
	if not mesh_inst:
		for child in model.find_children("*", "MeshInstance3D", true, false):
			mesh_inst = child as MeshInstance3D
			break

	if not anim_player or not skel or not mesh_inst:
		remove_child(model)
		model.queue_free()
		push_warning("[CrowdStatic] Missing AnimationPlayer, Skeleton, or MeshInstance3D in character model.")
		return

	for anim_name in pose_animations:
		if _baked_meshes.has(anim_name) and _baked_meshes[anim_name] != null:
			continue

		var resolved_name = _find_animation(anim_player, anim_name)
		if resolved_name != "":
			var anim = anim_player.get_animation(resolved_name)
			if anim:
				# Check for custom timestamp override or fallback to anim_pose_percentage
				var target_time: float = -1.0
				for k in anim_time_overrides.keys():
					var sk = str(k).strip_edges().to_lower()
					if sk == anim_name.strip_edges().to_lower() or sk == resolved_name.strip_edges().to_lower():
						target_time = float(anim_time_overrides[k])
						break
				if target_time < 0.0:
					var length = anim.length if anim.length > 0.0 else 1.0
					target_time = length * anim_pose_percentage

				_reset_skeleton_to_rest(skel)
				_apply_animation_to_skeleton(skel, anim, target_time)

				var baked: ArrayMesh = mesh_inst.bake_mesh_from_current_skeleton_pose()
				if baked:
					# When sampling gun pose, bake the water gun into the ArrayMesh surfaces
					if _is_gun_pose(anim_name) and enable_npc_guns and npc_gun_scene:
						var hand_idx = skel.find_bone("DEF-hand.R")
						if hand_idx >= 0:
							var gun_node = model.find_child("NPCGun", true, false) as Node3D
							var gun_local = gun_node.transform if gun_node else Transform3D(Vector3(-0.52649117, 0.31084087, 0.1512172), Vector3(0.23948482, -0.00089198886, 0.5168098), Vector3(0.39427686, 0.41561803, -0.11198624), Vector3(0.057711244, 0.10400703, 0.050934732))
							_gun_relative_transform = skel.get_bone_global_pose(hand_idx) * gun_local

							var gun_inst = npc_gun_scene.instantiate() as Node3D
							if gun_inst:
								_bake_gun_into_mesh(baked, gun_inst, _gun_relative_transform)
								gun_inst.queue_free()

					_baked_meshes[anim_name] = baked
		else:
			push_warning("[CrowdStatic] Animation '%s' not found on model." % anim_name)

	# Fallback if no animations matched
	if _baked_meshes.is_empty():
		var fallback_mesh = mesh_inst.bake_mesh_from_current_skeleton_pose()
		if fallback_mesh:
			_baked_meshes["Default"] = fallback_mesh

	# Destroy temporary model and all its skeletons completely
	remove_child(model)
	model.queue_free()

func _get_relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var curr: Node = node
	while curr and curr != ancestor and curr is Node3D:
		t = (curr as Node3D).transform * t
		curr = curr.get_parent()
	return t

func _bake_gun_into_mesh(target_mesh: ArrayMesh, gun_root: Node3D, gun_xform: Transform3D) -> void:
	var gun_st_map: Dictionary = {}
	var mat_list: Array[Material] = []

	for child in gun_root.find_children("*", "MeshInstance3D", true, false):
		var mi = child as MeshInstance3D
		if not mi or not mi.mesh:
			continue
		var child_rel_xform = _get_relative_transform(mi, gun_root)
		var total_xform = gun_xform * child_rel_xform

		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(s)
			if not mat:
				mat = mi.mesh.surface_get_material(s)
			if mat and mat.next_pass != null:
				mat = mat.duplicate()
				mat.next_pass = null
			if not gun_st_map.has(mat):
				var st = SurfaceTool.new()
				gun_st_map[mat] = st
				mat_list.append(mat)
			gun_st_map[mat].append_from(mi.mesh, s, total_xform)

	for mat in mat_list:
		var st: SurfaceTool = gun_st_map[mat]
		st.commit(target_mesh)
		var new_surf_idx = target_mesh.get_surface_count() - 1
		if mat:
			target_mesh.surface_set_material(new_surf_idx, mat)

func _is_jumper_pose(anim_name: String) -> bool:
	for kw in jumping_pose_keywords:
		if kw != "" and kw.to_lower() in anim_name.to_lower():
			return true
	return false

func _is_gun_pose(anim_name: String) -> bool:
	if gun_pose_keyword == "":
		return false
	return gun_pose_keyword.to_lower() in anim_name.to_lower()

func _snap_position_to_ground(local_x: float, local_z: float, space_state: PhysicsDirectSpaceState3D) -> Dictionary:
	# Returns { "valid": bool, "pos_y": float }
	if not space_state or not enable_ground_snap:
		return { "valid": true, "pos_y": 0.0 }

	var ray_start = to_global(Vector3(local_x, ground_ray_height, local_z))
	var ray_end = to_global(Vector3(local_x, -ground_ray_depth, local_z))

	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end, ground_collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit = space_state.intersect_ray(query)

	if hit.is_empty():
		return { "valid": true, "pos_y": 0.0 }

	var normal: Vector3 = hit.normal
	if normal.dot(Vector3.UP) < min_ground_normal_y:
		return { "valid": not skip_obstructed_members, "pos_y": to_local(hit.position).y }

	var snapped_y = to_local(hit.position).y

	if skip_obstructed_members and obstacle_check_radius > 0.0:
		var body_center = hit.position + Vector3(0, 0.8, 0)
		var shape_query = PhysicsShapeQueryParameters3D.new()
		var sphere = SphereShape3D.new()
		sphere.radius = obstacle_check_radius
		shape_query.shape = sphere
		shape_query.transform = Transform3D(Basis.IDENTITY, body_center)
		shape_query.collision_mask = ground_collision_mask
		shape_query.collide_with_areas = false
		shape_query.collide_with_bodies = true
		var overlaps = space_state.intersect_shape(shape_query, 1)
		if not overlaps.is_empty():
			return { "valid": false, "pos_y": snapped_y }

	return { "valid": true, "pos_y": snapped_y }

func _bake_and_build_crowd() -> void:
	_clear_multimeshes()
	_setup_materials()
	_bake_pose_meshes()
	_update_visibility_notifier_aabb()

	var active_keys: Array[String] = []
	for k in pose_animations:
		if _baked_meshes.has(k) and _baked_meshes[k] is Mesh:
			active_keys.append(k)

	# Also include any active fallback keys
	if active_keys.is_empty():
		for k in _baked_meshes.keys():
			if _baked_meshes[k] is Mesh:
				active_keys.append(k)

	if active_keys.is_empty():
		return

	_rng.seed = custom_seed

	var num_poses = active_keys.size()
	var num_mats = _materials.size() if not _materials.is_empty() else 1

	# Collect non-jumper pose indices for front row restriction
	var non_jumper_indices: Array[int] = []
	for i in range(num_poses):
		if not _is_jumper_pose(active_keys[i]):
			non_jumper_indices.append(i)

	if enable_ambient_projectiles and not is_instance_valid(_projectiles_container):
		_setup_ambient_projectiles()

	# Combination buckets: (pose_idx, mat_idx)
	var combo_buckets: Dictionary = {} # int (combo_id) -> Array[MemberInstanceData]

	var count = max(1, total_crowd_count)
	var rows = max(1, row_count)
	var per_row = int(ceil(float(count) / float(rows)))
	var half_w = spawn_area_size.x * 0.5
	var half_d = spawn_area_size.z * 0.5
	var spawned_count = 0

	var world_3d = get_world_3d() if is_inside_tree() else null
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state if world_3d else null

	for r in range(rows):
		var row_z_ratio = float(r) / float(max(1, rows - 1)) if rows > 1 else 0.5
		var row_z = lerp(-half_d, half_d, row_z_ratio) if front_row_is_negative_z else lerp(half_d, -half_d, row_z_ratio)
		var row_x_offset = (half_w / float(per_row)) * 0.5 if (r % 2 == 1) else 0.0

		for c in range(per_row):
			if spawned_count >= count:
				break

			var col_x_ratio = float(c) / float(max(1, per_row - 1)) if per_row > 1 else 0.5
			var pos_x = lerp(-half_w, half_w, col_x_ratio) + row_x_offset
			pos_x += _rng.randf_range(-0.35, 0.35)
			var pos_z = row_z + _rng.randf_range(-0.25, 0.25)

			var ground_snap = _snap_position_to_ground(pos_x, pos_z, space_state)
			if not ground_snap.valid:
				continue
			var pos_y = ground_snap.pos_y

			var base_rad = deg_to_rad(base_facing_angle_deg)
			var rand_rad = deg_to_rad(_rng.randf_range(-facing_randomness_deg, facing_randomness_deg))
			var rot_y = base_rad + rand_rad
			var scale_jitter = _rng.randf_range(0.96, 1.04)

			var xform = Transform3D()
			xform.basis = Basis(Vector3.UP, rot_y).scaled(Vector3.ONE * scale_jitter)
			xform.origin = Vector3(pos_x, pos_y, pos_z)

			# Interleaved distribution of poses and textures (jumpers disallowed on front row)
			var pose_idx: int
			if r == 0 and disallow_jumpers_in_front_row and not non_jumper_indices.is_empty():
				pose_idx = non_jumper_indices[c % non_jumper_indices.size()]
			else:
				pose_idx = spawned_count % num_poses
			var mat_idx = spawned_count % num_mats
			var anim_key = active_keys[pose_idx]

			var m_data = MemberInstanceData.new()
			m_data.base_transform = xform
			m_data.offset = pos_x * wave_frequency + pos_z * (wave_frequency * 0.5) + _rng.randf_range(0.0, TAU * 0.1)
			m_data.is_jumper = _is_jumper_pose(anim_key)
			m_data.is_gunner = _is_gun_pose(anim_key)

			var can_spin = (_rng.randf() < spin_chance) and not m_data.is_gunner
			m_data.spin_mult = (1.0 if _rng.randf() > 0.5 else -1.0) if can_spin else 0.0

			var combo_key = pose_idx * 100 + mat_idx
			if not combo_buckets.has(combo_key):
				combo_buckets[combo_key] = []
			combo_buckets[combo_key].append(m_data)

			spawned_count += 1

	# Create MultiMeshInstance3D for each active (pose, material) combination
	for combo_key in combo_buckets.keys():
		var bucket: Array = combo_buckets[combo_key]
		if bucket.is_empty():
			continue

		var pose_idx: int = combo_key / 100
		var mat_idx: int = combo_key % 100
		var anim_key = active_keys[pose_idx]

		var mmi = MultiMeshInstance3D.new()
		mmi.name = "MultiMesh_%s_Mat%d" % [anim_key.validate_node_name(), mat_idx]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var base_mesh: Mesh = _baked_meshes[anim_key]
		var char_mat: Material = _materials[mat_idx] if mat_idx < _materials.size() else (_materials[0] if not _materials.is_empty() else null)

		var final_mesh: Mesh = base_mesh
		if base_mesh and base_mesh.get_surface_count() > 1:
			# Multi-surface mesh (baked character + water gun).
			# Duplicate the mesh so each material variant sets its own Surface 0 material
			# without overriding the gun surfaces (Surfaces 1 & 2).
			var dup_mesh = base_mesh.duplicate() as ArrayMesh
			if char_mat:
				dup_mesh.surface_set_material(0, char_mat)
			final_mesh = dup_mesh
			mmi.material_override = null
		else:
			mmi.material_override = char_mat

		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.mesh = final_mesh
		mm.instance_count = bucket.size()

		for i in range(bucket.size()):
			var m_data: MemberInstanceData = bucket[i]
			mm.set_instance_transform(i, m_data.base_transform)

		mmi.multimesh = mm
		add_child(mmi)
		_pose_multimeshes.append(mmi)
		_pose_members.append(bucket)

# ─── Ambient Projectiles ───────────────────────────────────────────────────

func _cleanup_ambient_projectiles() -> void:
	_waterline_pool.clear()
	_balloon_pool.clear()
	if is_instance_valid(_projectiles_container):
		for child in _projectiles_container.get_children():
			child.queue_free()
		if _projectiles_container.get_parent() == self:
			remove_child(_projectiles_container)
		_projectiles_container.queue_free()
		_projectiles_container = null

	for child in get_children():
		if child.name == "AmbientProjectiles":
			remove_child(child)
			child.queue_free()

func _setup_ambient_projectiles() -> void:
	_cleanup_ambient_projectiles()
	if not enable_ambient_projectiles:
		return

	_projectiles_container = Node3D.new()
	_projectiles_container.name = "AmbientProjectiles"
	add_child(_projectiles_container)

	# Pre-allocate WaterLine pool
	if waterline_scene:
		for i in range(5):
			var line = waterline_scene.instantiate() as Node3D
			if line:
				line.visible = false
				_projectiles_container.add_child(line)
				_waterline_pool.append(line)

	# Pre-allocate WaterBalloon pool
	if water_balloon_scene:
		for i in range(4):
			var balloon = water_balloon_scene.instantiate() as Node3D
			if balloon:
				balloon.visible = false
				balloon.set("is_pooled", true)
				balloon.set("_active", false)
				for mesh in balloon.find_children("*", "GeometryInstance3D", true, false):
					var gi = mesh as GeometryInstance3D
					gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_projectiles_container.add_child(balloon)
				_balloon_pool.append(balloon)

	_reset_waterline_timer()
	_reset_balloon_timer()

func _reset_waterline_timer() -> void:
	_waterline_timer = _rng.randf_range(waterline_interval_range.x, waterline_interval_range.y)

func _reset_balloon_timer() -> void:
	_balloon_timer = _rng.randf_range(water_balloon_interval_range.x, water_balloon_interval_range.y)

func _process_ambient_projectiles(delta: float) -> void:
	if not is_inside_tree():
		return

	_waterline_timer -= delta
	if _waterline_timer <= 0.0:
		_fire_ambient_waterline()
		_reset_waterline_timer()

	_balloon_timer -= delta
	if _balloon_timer <= 0.0:
		_throw_ambient_water_balloon()
		_reset_balloon_timer()

func _get_random_crowd_spawn_pos() -> Vector3:
	var half_w = spawn_area_size.x * 0.5
	var half_d = spawn_area_size.z * 0.5
	var local_x = _rng.randf_range(-half_w, half_w)
	var local_y = _rng.randf_range(1.0, 1.4)

	# Constrain Z strictly to the front row(s)
	var max_row_idx = max(0, row_count - 1)
	var max_front_idx = min(max(0, vfx_front_row_count - 1), max_row_idx)
	var r_pick = _rng.randi_range(0, max_front_idx)
	var row_z_ratio = float(r_pick) / float(max(1, max_row_idx)) if max_row_idx > 0 else 0.5
	var row_z = lerp(-half_d, half_d, row_z_ratio) if front_row_is_negative_z else lerp(half_d, -half_d, row_z_ratio)
	var local_z = row_z + _rng.randf_range(-0.25, 0.25)

	# Adapt spawn height to ground elevation if ground snapping is enabled
	var world_3d = get_world_3d() if is_inside_tree() else null
	var space_state = world_3d.direct_space_state if world_3d else null
	if space_state and enable_ground_snap:
		var snap = _snap_position_to_ground(local_x, local_z, space_state)
		if snap.valid:
			local_y += snap.pos_y

	return to_global(Vector3(local_x, local_y, local_z))

func _get_random_target_pos(spawn_pos_global: Vector3) -> Vector3:
	var fwd_local = Vector3(0, 0, -1) if front_row_is_negative_z else Vector3(0, 0, 1)
	var base_rad = deg_to_rad(base_facing_angle_deg)
	var fwd_dir = (global_transform.basis * Basis(Vector3.UP, base_rad) * fwd_local).normalized()
	var right_dir = fwd_dir.cross(Vector3.UP).normalized()

	var forward_dist = projectile_target_forward_distance + _rng.randf_range(-2.0, 4.0)
	var spread_offset = right_dir * _rng.randf_range(-projectile_spread_x * 0.5, projectile_spread_x * 0.5)
	var target = spawn_pos_global + fwd_dir * forward_dist + spread_offset
	target.y = global_position.y + _rng.randf_range(0.0, 0.8)
	return target

func _apply_waterline_transform(line: Node3D, spawn_pos: Vector3, target_pos: Vector3, duration: float) -> void:
	var to_target = target_pos - spawn_pos
	var distance := to_target.length()
	if distance < 0.05:
		line.visible = false
		return

	line.global_position = spawn_pos
	var fwd = to_target.normalized()
	var up = Vector3.UP
	if abs(fwd.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	line.look_at(spawn_pos + fwd, up)

	var mesh_inst = line.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_inst:
		for child in line.find_children("*", "MeshInstance3D", true, false):
			mesh_inst = child as MeshInstance3D
			break
	if mesh_inst:
		mesh_inst.scale.z = distance
		mesh_inst.position = Vector3(0, 0, -distance * 0.5)

	line.visible = true
	var tree = get_tree()
	if tree:
		tree.create_timer(duration).timeout.connect(func():
			if is_instance_valid(line):
				line.visible = false
		)

func _fire_ambient_waterline() -> void:
	if _waterline_pool.is_empty():
		return
	var line: Node3D = null
	for inst in _waterline_pool:
		if is_instance_valid(inst) and not inst.visible:
			line = inst
			break
	if not line:
		line = _waterline_pool[0]

	if is_instance_valid(line):
		line.set("life_time", waterline_lifetime)
		var spawn_p = _get_random_crowd_spawn_pos()
		var target_p = _get_random_target_pos(spawn_p)
		var scr = line.get_script() as Script
		if (not Engine.is_editor_hint() or (scr and scr.is_tool())) and line.has_method("set_line"):
			line.call("set_line", spawn_p, target_p)
		else:
			_apply_waterline_transform(line, spawn_p, target_p, waterline_lifetime)

func _throw_ambient_water_balloon() -> void:
	if _balloon_pool.is_empty():
		return
	var balloon: Node3D = null
	for inst in _balloon_pool:
		if is_instance_valid(inst) and not inst.get("_active") and not inst.visible:
			balloon = inst
			break
	if not balloon:
		return

	if is_instance_valid(balloon):
		var spawn_p = _get_random_crowd_spawn_pos()
		var target_p = _get_random_target_pos(spawn_p)
		balloon.global_position = spawn_p
		var arc_h = _rng.randf_range(2.5, 4.5)
		var t_time = _rng.randf_range(1.0, 1.6)
		var scr = balloon.get_script() as Script
		if (not Engine.is_editor_hint() or (scr and scr.is_tool())) and balloon.has_method("launch_pooled"):
			balloon.call("launch_pooled", target_p, 0.0, 1.0, arc_h, t_time)
