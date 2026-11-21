@tool
class_name CrowdVATSpawner
extends Node3D
## Hybrid VAT Crowd Spawner:
## - Uses a single MultiMeshInstance3D (VAT) for all dancing crowd members.
## - Uses the existing non-VAT rigged scenes (crowd_male_model_Gun / crowd_male_model_Balloon)
##   for Gun and Balloon crowd members so their hand attachments, projectiles, and animations work natively.
## - Enforces minimum XZ spacing so crowd members do not spawn overlapping each other.

signal projectile_spawn_requested(role: String, world_spawn_pos: Vector3, target_pos: Vector3, instance_idx: int)

const VATHitboxAreaScript := preload("res://scripts/vat/vat_hitbox_area.gd")
const SPECIALIST_HIT_SHADER := preload("res://shaders/crowd_specialist_hit.gdshader")
const SPECIALIST_HIT_OUTLINE_SHADER := preload("res://shaders/crowd_specialist_hit_outline.gdshader")

@export_group("Editor Preview")
@export_tool_button("Rebuild Crowd") var rebuild_crowd_button := _rebuild_crowd
@export var preview_in_editor: bool = true:
	set(val):
		if preview_in_editor == val:
			return
		preview_in_editor = val
		if Engine.is_editor_hint() and is_inside_tree() and is_node_ready():
			if preview_in_editor:
				_rebuild_crowd()
			else:
				_clear_preview()
@export var preview_specialists_in_editor: bool = false: ## Off by default so Editor keeps 0 skeleton/node overhead (Gun/Balloon slots preview as VAT dancers in Editor)
	set(val):
		if preview_specialists_in_editor == val:
			return
		preview_specialists_in_editor = val
		if Engine.is_editor_hint() and is_inside_tree() and is_node_ready() and preview_in_editor:
			_rebuild_crowd()

@export_group("VAT Assets")
@export_file("*.json") var vat_meta_path: String = "res://scenes/Crowds/VAT/crowd_male_vat_meta.json":
	set(val):
		vat_meta_path = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var multimesh_node_path: NodePath = NodePath("MultiMeshInstance3D")
@export var male_vat_mesh: Mesh = preload("res://scenes/Crowds/VAT/crowd_male_vat_mesh.tres")
@export_file("*.json") var female_vat_meta_path: String = "res://scenes/Crowds/VAT/crowd_female_vat_meta.json":
	set(val):
		female_vat_meta_path = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var female_multimesh_node_path: NodePath = NodePath("MultiMeshInstance3D_Female")
@export var female_vat_mesh: Mesh = preload("res://scenes/Crowds/VAT/crowd_female_vat_mesh.tres")
@export_file("*.json") var female_nohat_vat_meta_path: String = "res://scenes/Crowds/VAT/crowd_female_nohat_vat_meta.json":
	set(val):
		female_nohat_vat_meta_path = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var female_nohat_multimesh_node_path: NodePath = NodePath("MultiMeshInstance3D_Female_NoHat")
@export var female_nohat_vat_mesh: Mesh = preload("res://scenes/Crowds/VAT/crowd_female_nohat_vat_mesh.tres")

@export_group("Non-VAT Specialist Scenes")
@export var gun_member_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model_Gun.tscn"):
	set(val):
		gun_member_scene = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var balloon_member_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model_Balloon.tscn"):
	set(val):
		balloon_member_scene = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var base_crowd_material: Material = preload("res://scenes/Crowds/Crowd_Material.tres")
@export var texture_blue: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Blue.png")
@export var texture_green: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Green.png")
@export var texture_pink: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Pink.png")

@export_group("Crowd Layout")
@export var spawn_area_size: Vector3 = Vector3(20.0, 1.0, 10.0):
	set(val):
		spawn_area_size = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(1, 10, 1) var row_count: int = 3:
	set(val):
		row_count = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var organic_scatter: bool = true:
	set(val):
		organic_scatter = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 0.2, 0.01) var scale_randomness: float = 0.03:
	set(val):
		scale_randomness = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(1, 600, 1) var total_crowd_count: int = 100:
	set(val):
		total_crowd_count = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.3, 10.0, 0.05) var min_member_spacing: float = 1.0:
	set(val):
		min_member_spacing = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 10.0, 0.1) var min_same_color_spacing: float = 1.5:
	set(val):
		min_same_color_spacing = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 180.0, 1.0) var facing_randomness_deg: float = 180.0:
	set(val):
		facing_randomness_deg = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var base_facing_angle_deg: float = 0.0:
	set(val):
		base_facing_angle_deg = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var custom_seed: int = 12345:
	set(val):
		custom_seed = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()

@export_group("Collision & Ground Snapping")
@export var enable_collision_check: bool = true:
	set(val):
		enable_collision_check = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var enable_ground_snapping: bool = true:
	set(val):
		enable_ground_snapping = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_flags_3d_physics var collision_mask_world: int = 1
@export var ground_snap_height: float = 0.2:
	set(val):
		ground_snap_height = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var ground_snap_depth: float = 10.0:
	set(val):
		ground_snap_depth = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 1.0, 0.05) var ground_snap_min_normal_y: float = 0.5:
	set(val):
		ground_snap_min_normal_y = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()

@export_group("Role Ratios")
@export_range(0.0, 1.0, 0.05) var gunner_ratio: float = 0.1:
	set(val):
		gunner_ratio = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 1.0, 0.05) var ballooner_ratio: float = 0.1:
	set(val):
		ballooner_ratio = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 1.0, 0.05) var female_dancer_ratio: float = 0.5:
	set(val):
		female_dancer_ratio = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 15.0, 0.1) var min_gunner_spacing: float = 2.0:
	set(val):
		min_gunner_spacing = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export_range(0.0, 15.0, 0.1) var min_ballooner_spacing: float = 2.0:
	set(val):
		min_ballooner_spacing = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()

@export_group("Combat & Projectiles")
@export var enable_gun_shooting: bool = true
@export var enable_balloon_throwing: bool = true
@export var allow_distant_projectiles: bool = true ## Keep emitting pooled WaterLine & WaterBalloon projectiles when far away with skeletons paused
@export var shot_interval_min: float = 2.5
@export var shot_interval_max: float = 5.5
@export var balloon_interval_min: float = 3.5
@export var balloon_interval_max: float = 7.5
@export var enable_hitboxes: bool = true:
	set(val):
		enable_hitboxes = val
		if is_inside_tree() and is_node_ready():
			_rebuild_hitboxes()
			_sync_specialist_hitboxes()

@export_group("Performance & Distance LOD")
@export_range(5.0, 100.0, 1.0) var specialist_half_rate_distance: float = 15.0 ## Distance beyond which Gun/Balloon skeletons step at 1/2 rate (30 FPS)
@export_range(5.0, 120.0, 1.0) var specialist_quarter_rate_distance: float = 25.0 ## Distance beyond which Gun/Balloon skeletons step at 1/4 rate (15 FPS)
@export_range(5.0, 150.0, 1.0) var specialist_active_distance: float = 35.0 ## Distance beyond which Gun/Balloon skeletons pause completely
@export_range(5.0, 150.0, 1.0) var hitbox_active_distance: float = 35.0 ## Distance beyond which crowd hitboxes disable monitoring
@export_range(5.0, 150.0, 1.0) var shadow_active_distance: float = 30.0 ## Distance beyond which crowd shadows turn off
@export_range(5.0, 150.0, 1.0) var outline_active_distance: float = 35.0 ## Distance beyond which VAT outline next_pass detaches
@export_range(10.0, 300.0, 1.0) var max_render_distance: float = 110.0: ## Distance beyond which crowd stops rendering and distant projectiles pause
	set(val):
		max_render_distance = val
		if is_inside_tree() and is_node_ready():
			_apply_render_distance()

@export_group("Hit Reaction")
@export_range(0.05, 2.0, 0.05) var hit_reaction_duration: float = 0.25
@export_range(0.0, 1.5, 0.01) var hit_bend_strength: float = 0.5:
	set(val):
		hit_bend_strength = val
		if is_inside_tree() and is_node_ready():
			_sync_hit_reaction_params()
@export_range(0.05, 1.5, 0.01) var hit_zone_radius: float = 0.3:
	set(val):
		hit_zone_radius = val
		if is_inside_tree() and is_node_ready():
			_sync_hit_reaction_params()
@export_range(1.0, 60.0, 0.5) var hit_oscillation_freq: float = 10.0:
	set(val):
		hit_oscillation_freq = val
		if is_inside_tree() and is_node_ready():
			_sync_hit_reaction_params()

@export_group("Invisible Wall")
@export var enable_invisible_wall: bool = true:
	set(val):
		enable_invisible_wall = val
		if is_inside_tree() and is_node_ready():
			_sync_invisible_wall()
@export_flags_3d_physics var invisible_wall_layer: int = 8:
	set(val):
		invisible_wall_layer = val
		if is_inside_tree() and is_node_ready():
			_sync_invisible_wall()
@export_range(0.5, 10.0, 0.1) var invisible_wall_height: float = 2.5:
	set(val):
		invisible_wall_height = val
		if is_inside_tree() and is_node_ready():
			_sync_invisible_wall()
@export var invisible_wall_padding: Vector3 = Vector3(0.5, 0.0, 0.5):
	set(val):
		invisible_wall_padding = val
		if is_inside_tree() and is_node_ready():
			_sync_invisible_wall()

@export_group("Pooling & VFX")
@export var water_line_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterLine.tscn")
@export var muzzle_vfx_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterMuzzle.tscn")
@export var hit_vfx_scene: PackedScene = preload("res://Jomp_Folder/VFX_Water/VFX2/vfx_water_splatter.tscn")
@export var balloon_scene: PackedScene = preload("res://scenes/items/water_balloon.tscn")
@export_range(1, 20, 1) var water_line_pool_size: int = 6
@export_range(1, 20, 1) var vfx_pool_size: int = 4
@export_range(1, 20, 1) var balloon_pool_size: int = 4

# VAT Dancer variants: 0 = Male, 1 = Female (Hat), 2 = Female (No Hat)
var _vat_variants: Array[Dictionary] = [{}, {}, {}]
var _rng := RandomNumberGenerator.new()

var _shot_timer: float = 0.0
var _next_shot_time: float = 3.0
var _balloon_timer: float = 0.0
var _next_balloon_time: float = 4.5
var _lod_check_timer: float = 0.0
var _specialists_active: bool = true
var _specialist_step_interval: int = 1
var _hitboxes_within_dist: bool = true
var _shadows_active: bool = true
var _outlines_active: bool = true
var _within_render_dist: bool = true
var _cached_next_passes: Dictionary = {} # ShaderMaterial -> Material
var _specialist_meshes: Array[MeshInstance3D] = []

# Object pools
var _pool_container: Node3D = null
var _water_line_pool: Array[Node3D] = []
var _muzzle_vfx_pool: Array[Node3D] = []
var _hit_vfx_pool: Array[Node3D] = []
var _balloon_pool: Array[Node3D] = []
var _water_line_idx: int = 0
var _muzzle_vfx_idx: int = 0
var _hit_vfx_idx: int = 0
var _balloon_idx: int = 0

# VAT Dancer state & pools
var _hitbox_container: Node3D = null
var _vat_hitbox_pool: Array[Area3D] = []

# Non-VAT Rigged Gun & Balloon CrowdMembers & pools
var _specialists_container: Node3D = null
var _gun_members: Array[CrowdMember] = []
var _balloon_members: Array[CrowdMember] = []
var _gun_member_pool: Array[CrowdMember] = []
var _balloon_member_pool: Array[CrowdMember] = []
var _variant_materials: Array[Material] = []
var _active_specialist_hits: Dictionary = {} # MeshInstance3D -> {decay, angle, y_norm, x_norm}


func _ready() -> void:
	_rebuild_crowd()
	if Engine.is_editor_hint():
		if not child_entered_tree.is_connected(_on_editor_child_entered):
			child_entered_tree.connect(_on_editor_child_entered)
	else:
		_init_pools()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		for path in [multimesh_node_path, female_multimesh_node_path, female_nohat_multimesh_node_path]:
			var mm_inst := get_node_or_null(path) as MultiMeshInstance3D
			if mm_inst:
				mm_inst.multimesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if preview_in_editor and is_inside_tree():
			call_deferred("_rebuild_crowd")


func _on_editor_child_entered(node: Node) -> void:
	if node is MultiMeshInstance3D and preview_in_editor:
		call_deferred("_rebuild_crowd")


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _vat_variants[0].is_empty():
		return

	_update_hit_reactions(delta)

	_lod_check_timer += delta
	if _lod_check_timer >= 0.25:
		_lod_check_timer = 0.0
		_update_specialist_lod()

	if not _within_render_dist:
		return

	if enable_gun_shooting and not _gun_members.is_empty() and (_specialists_active or allow_distant_projectiles):
		_shot_timer += delta
		if _shot_timer >= _next_shot_time:
			_shot_timer = 0.0
			_next_shot_time = _rng.randf_range(shot_interval_min, shot_interval_max)
			_trigger_random_gun_shot()

	if enable_balloon_throwing and not _balloon_members.is_empty() and (_specialists_active or allow_distant_projectiles):
		_balloon_timer += delta
		if _balloon_timer >= _next_balloon_time:
			_balloon_timer = 0.0
			_next_balloon_time = _rng.randf_range(balloon_interval_min, balloon_interval_max)
			_trigger_random_balloon_throw()


func _rebuild_crowd() -> void:
	var male_mm_inst := get_node_or_null(multimesh_node_path) as MultiMeshInstance3D
	if not male_mm_inst:
		return

	if Engine.is_editor_hint() and not preview_in_editor:
		_clear_preview()
		return

	var variant_configs := [
		{"mm_inst": male_mm_inst, "meta_path": vat_meta_path, "mesh": male_vat_mesh},
		{"mm_inst": get_node_or_null(female_multimesh_node_path) as MultiMeshInstance3D, "meta_path": female_vat_meta_path, "mesh": female_vat_mesh},
		{"mm_inst": get_node_or_null(female_nohat_multimesh_node_path) as MultiMeshInstance3D, "meta_path": female_nohat_vat_meta_path, "mesh": female_nohat_vat_mesh},
	]
	for v_idx in range(3):
		var mm_inst: MultiMeshInstance3D = variant_configs[v_idx]["mm_inst"]
		var vat_mesh: Mesh = variant_configs[v_idx]["mesh"]
		if not vat_mesh and mm_inst and mm_inst.multimesh:
			vat_mesh = mm_inst.multimesh.mesh
		var meta := _load_json_dict(variant_configs[v_idx]["meta_path"]) if mm_inst else {}
		var clips: Dictionary = meta.get("clips", {}) if not meta.is_empty() else {}
		var empty_xforms: Array[Transform3D] = []
		_vat_variants[v_idx] = {
			"mm_inst": mm_inst,
			"mm": null,
			"mesh": vat_mesh,
			"meta": meta,
			"clips": clips,
			"transforms": empty_xforms,
			"hits": {},
			"active": mm_inst != null and vat_mesh != null and not clips.is_empty(),
		}

	if not _vat_variants[0]["active"]:
		return

	_sync_shader_params()
	_build_variant_materials()
	_clear_specialists()

	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = custom_seed

	# 1. Generate non-overlapping slot transforms with O(1) spatial hash + Ground Snapping & Collision Check
	var placed_transforms: Array[Transform3D] = []
	var placed_positions: Array[Vector2] = []
	var cell_size := maxf(min_member_spacing, 0.25)
	var pos_grid: Dictionary = {} # Vector2i -> Array[Vector2]
	var min_dist_sq := min_member_spacing * min_member_spacing
	var half_x := spawn_area_size.x * 0.5
	var half_z := spawn_area_size.z * 0.5
	var row_jitter_z := minf(0.25, (spawn_area_size.z / maxf(float(row_count), 1.0)) * 0.35)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if (get_world_3d() and (enable_ground_snapping or enable_collision_check)) else null
	var exclude_rids: Array[RID] = _collect_self_physics_rids()
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.collision_mask = collision_mask_world
	ray_query.exclude = exclude_rids

	var check_shape := CapsuleShape3D.new()
	check_shape.radius = 0.35
	check_shape.height = 1.6
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = check_shape
	shape_query.collision_mask = collision_mask_world
	shape_query.exclude = exclude_rids

	for i in range(total_crowd_count):
		var chosen_pos := Vector2.ZERO
		var chosen_y := 0.0
		var found := false
		for _attempt in range(30):
			var px := layout_rng.randf_range(-half_x, half_x)
			var pz := 0.0
			if organic_scatter:
				pz = layout_rng.randf_range(-half_z, half_z)
			else:
				var row_idx := i % row_count
				var row_t := 0.5 if row_count == 1 else float(row_idx) / float(row_count - 1)
				var base_z := lerpf(-half_z, half_z, row_t)
				pz = base_z + layout_rng.randf_range(-row_jitter_z, row_jitter_z)

			var candidate := Vector2(px, pz)
			var cx := floori(px / cell_size)
			var cz := floori(pz / cell_size)
			var too_close := false
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var key := Vector2i(cx + dx, cz + dz)
					if not pos_grid.has(key):
						continue
					for existing in (pos_grid[key] as Array):
						if candidate.distance_squared_to(existing) < min_dist_sq:
							too_close = true
							break
					if too_close:
						break
				if too_close:
					break
			if too_close:
				continue

			var local_y := 0.0
			if space_state and enable_ground_snapping:
				var start_world := global_transform * Vector3(px, spawn_area_size.y * 0.5 + ground_snap_height, pz)
				var end_world := global_transform * Vector3(px, -ground_snap_depth, pz)
				ray_query.from = start_world
				ray_query.to = end_world
				var hit := space_state.intersect_ray(ray_query)
				if not hit.is_empty():
					if (hit["normal"] as Vector3).y < ground_snap_min_normal_y:
						continue
					local_y = (global_transform.affine_inverse() * (hit["position"] as Vector3)).y

			if space_state and enable_collision_check:
				var world_check := global_transform * Vector3(px, local_y + 0.9, pz)
				shape_query.transform = Transform3D(Basis.IDENTITY, world_check)
				if not space_state.intersect_shape(shape_query, 1).is_empty():
					continue

			chosen_pos = candidate
			chosen_y = local_y
			found = true
			break

		if not found:
			continue

		placed_positions.append(chosen_pos)
		var g_key := Vector2i(floori(chosen_pos.x / cell_size), floori(chosen_pos.y / cell_size))
		if not pos_grid.has(g_key):
			pos_grid[g_key] = []
		(pos_grid[g_key] as Array).append(chosen_pos)
		var yaw_deg := base_facing_angle_deg + layout_rng.randf_range(-facing_randomness_deg, facing_randomness_deg)
		var s := 1.0 + layout_rng.randf_range(-scale_randomness, scale_randomness)
		var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3(s, s, s))
		placed_transforms.append(Transform3D(basis, Vector3(chosen_pos.x, chosen_y, chosen_pos.y)))

	# 2. Partition slots with Gunner, Ballooner, and Same-Color spacing
	var actual_count := placed_transforms.size()
	var gun_count := clampi(roundi(float(actual_count) * gunner_ratio), 0, actual_count)
	var balloon_count := clampi(roundi(float(actual_count) * ballooner_ratio), 0, actual_count - gun_count)

	var indices: Array[int] = []
	indices.resize(actual_count)
	for i in range(actual_count):
		indices[i] = i
	for i in range(actual_count - 1, 0, -1):
		var j := layout_rng.randi_range(0, i)
		var tmp := indices[i]
		indices[i] = indices[j]
		indices[j] = tmp

	var used_slots := {}
	var gun_indices := _pick_spaced_role_indices(indices, used_slots, gun_count, placed_positions, min_gunner_spacing) if gun_member_scene else []
	var balloon_indices := _pick_spaced_role_indices(indices, used_slots, balloon_count, placed_positions, min_ballooner_spacing) if balloon_member_scene else []

	var placed_colors: Array[Dictionary] = []
	var gun_slots: Array[Dictionary] = []
	for idx in gun_indices:
		var c_idx := _pick_spaced_color(placed_positions[idx], placed_colors, layout_rng)
		gun_slots.append({"xform": placed_transforms[idx], "color": c_idx})

	var balloon_slots: Array[Dictionary] = []
	for idx in balloon_indices:
		var c_idx := _pick_spaced_color(placed_positions[idx], placed_colors, layout_rng)
		balloon_slots.append({"xform": placed_transforms[idx], "color": c_idx})

	var female_variants: Array[int] = []
	if _vat_variants[1]["active"]:
		female_variants.append(1)
	if _vat_variants[2]["active"]:
		female_variants.append(2)

	var variant_colors: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for idx in indices:
		if used_slots.has(idx):
			continue
		var chosen_v := 0
		if not female_variants.is_empty() and layout_rng.randf() < female_dancer_ratio:
			chosen_v = female_variants[layout_rng.randi_range(0, female_variants.size() - 1)]
		var c_idx := _pick_spaced_color(placed_positions[idx], placed_colors, layout_rng)
		(_vat_variants[chosen_v]["transforms"] as Array[Transform3D]).append(placed_transforms[idx])
		variant_colors[chosen_v].append(c_idx)

	var spawn_rigged_specialists := (not Engine.is_editor_hint()) or preview_specialists_in_editor
	if not spawn_rigged_specialists:
		for s in gun_slots:
			(_vat_variants[0]["transforms"] as Array[Transform3D]).append(s["xform"])
			variant_colors[0].append(int(s["color"]))
		for s in balloon_slots:
			(_vat_variants[0]["transforms"] as Array[Transform3D]).append(s["xform"])
			variant_colors[0].append(int(s["color"]))

	# 3. Populate VAT MultiMeshes for all active variants
	for v_idx in range(3):
		var v: Dictionary = _vat_variants[v_idx]
		var mm_inst: MultiMeshInstance3D = v["mm_inst"]
		if v["active"]:
			_populate_dancer_multimesh(mm_inst, v["mesh"], v["transforms"], variant_colors[v_idx], v["clips"], layout_rng)
			v["mm"] = mm_inst.multimesh
		elif mm_inst:
			mm_inst.multimesh = null
			v["mm"] = null

	# 4. Spawn/reuse pooled Gun & Balloon CrowdMembers (runtime, or Editor if preview_specialists_in_editor)
	if spawn_rigged_specialists:
		_spawn_specialists(gun_slots, balloon_slots)
	elif is_instance_valid(_specialists_container):
		if _specialists_container.get_parent() == self:
			remove_child(_specialists_container)
		_specialists_container.queue_free()
		_specialists_container = null
		_gun_member_pool.clear()
		_balloon_member_pool.clear()
	_rebuild_hitboxes()
	_sync_invisible_wall()
	_apply_render_distance()


func _collect_self_physics_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for child in find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			rids.append((child as CollisionObject3D).get_rid())
	return rids


func _pick_spaced_role_indices(shuffled: Array[int], used: Dictionary, target_count: int, positions: Array[Vector2], min_spacing: float) -> Array[int]:
	var picked: Array[int] = []
	if target_count <= 0:
		return picked
	var min_sq := min_spacing * min_spacing
	for idx in shuffled:
		if picked.size() >= target_count:
			break
		if used.has(idx):
			continue
		var pos := positions[idx]
		var ok := true
		for p_idx in picked:
			if pos.distance_squared_to(positions[p_idx]) < min_sq:
				ok = false
				break
		if ok:
			picked.append(idx)
			used[idx] = true
	if picked.size() < target_count:
		for idx in shuffled:
			if picked.size() >= target_count:
				break
			if not used.has(idx):
				picked.append(idx)
				used[idx] = true
	return picked


func _pick_spaced_color(pos: Vector2, placed_colors: Array[Dictionary], layout_rng: RandomNumberGenerator) -> int:
	var min_sq := min_same_color_spacing * min_same_color_spacing
	var allowed: Array[int] = []
	for c in range(3):
		var conflict := false
		if min_sq > 0.0:
			for entry in placed_colors:
				if int(entry["color"]) == c and pos.distance_squared_to(entry["pos"]) < min_sq:
					conflict = true
					break
		if not conflict:
			allowed.append(c)
	var chosen := allowed[layout_rng.randi_range(0, allowed.size() - 1)] if not allowed.is_empty() else layout_rng.randi_range(0, 2)
	placed_colors.append({"pos": pos, "color": chosen})
	return chosen


func _populate_dancer_multimesh(mm_inst: MultiMeshInstance3D, vat_mesh: Mesh, transforms: Array[Transform3D], colors: PackedInt32Array, clips: Dictionary, layout_rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.mesh = vat_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = transforms.size()
	mm_inst.multimesh = mm

	var dance_aliases: Array[String] = []
	for alias in clips.keys():
		if str(alias).begins_with("dance"):
			dance_aliases.append(str(alias))
	if dance_aliases.is_empty():
		for alias in clips.keys():
			dance_aliases.append(str(alias))

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, Color(0.0, 0.5, 0.5, 0.0))
		var tex_idx := colors[i] if i < colors.size() else layout_rng.randi_range(0, 2)
		var clip_alias: String = dance_aliases[layout_rng.randi_range(0, dance_aliases.size() - 1)] if not dance_aliases.is_empty() else ""
		if clips.has(clip_alias):
			var clip: Dictionary = clips[clip_alias]
			var start_f := float(clip.get("start_frame", 0))
			var count_f := float(clip.get("frame_count", 1))
			mm.set_instance_custom_data(i, Color(start_f, count_f, layout_rng.randf_range(0.0, 4.0), float(tex_idx)))


func _clear_preview() -> void:
	_clear_specialists()
	if is_instance_valid(_hitbox_container):
		_hitbox_container.queue_free()
		_hitbox_container = null
	for v in _vat_variants:
		if v.is_empty():
			continue
		(v["transforms"] as Array[Transform3D]).clear()
		(v["hits"] as Dictionary).clear()
		var mm_inst: MultiMeshInstance3D = v.get("mm_inst")
		if mm_inst and mm_inst.multimesh:
			mm_inst.multimesh.instance_count = 0


func _clear_specialists() -> void:
	_gun_members.clear()
	_balloon_members.clear()
	_specialist_meshes.clear()
	for m in _gun_member_pool:
		if is_instance_valid(m):
			m.visible = false
			m.set_row_active(false)
			var hb := m.get_node_or_null("SpecialistHitbox") as Area3D
			if hb:
				hb.monitoring = false
				hb.monitorable = false
	for m in _balloon_member_pool:
		if is_instance_valid(m):
			m.visible = false
			m.set_row_active(false)
			var hb := m.get_node_or_null("SpecialistHitbox") as Area3D
			if hb:
				hb.monitoring = false
				hb.monitorable = false


func _spawn_specialists(gun_slots: Array[Dictionary], balloon_slots: Array[Dictionary]) -> void:
	if gun_slots.is_empty() and balloon_slots.is_empty():
		return

	if not is_instance_valid(_specialists_container):
		_specialists_container = Node3D.new()
		_specialists_container.name = "RiggedSpecialists"
		add_child(_specialists_container)
		_specialists_container.owner = null

	var member_idx := 0
	for i in range(gun_slots.size()):
		var slot: Dictionary = gun_slots[i]
		var member := _acquire_pooled_specialist(_gun_member_pool, gun_member_scene, i)
		if not member:
			continue
		member.transform = slot["xform"]
		member.visible = true
		member.member_index = member_idx
		member.anim_step_interval = _specialist_step_interval
		member_idx += 1
		var mat := _variant_materials[int(slot["color"])] if not _variant_materials.is_empty() else null
		member.setup_member(true, mat, {"enable_hitbox": enable_hitboxes}, false)
		member.set_row_active(_specialists_active)
		_attach_specialist_hitbox(member)
		_cache_specialist_meshes(member)
		_gun_members.append(member)

	for i in range(balloon_slots.size()):
		var slot: Dictionary = balloon_slots[i]
		var member := _acquire_pooled_specialist(_balloon_member_pool, balloon_member_scene, i)
		if not member:
			continue
		member.transform = slot["xform"]
		member.visible = true
		member.member_index = member_idx
		member.anim_step_interval = _specialist_step_interval
		member_idx += 1
		var mat := _variant_materials[int(slot["color"])] if not _variant_materials.is_empty() else null
		member.setup_member(false, mat, {"enable_hitbox": enable_hitboxes}, true)
		member.set_row_active(_specialists_active)
		_attach_specialist_hitbox(member)
		_cache_specialist_meshes(member)
		_balloon_members.append(member)


func _cache_specialist_meshes(member: CrowdMember) -> void:
	var shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows_active else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in member.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			mi.cast_shadow = shadow_mode
			_specialist_meshes.append(mi)


func _acquire_pooled_specialist(pool: Array[CrowdMember], scene: PackedScene, pool_idx: int) -> CrowdMember:
	if pool_idx < pool.size() and is_instance_valid(pool[pool_idx]):
		return pool[pool_idx]
	if not scene:
		return null
	var member := scene.instantiate() as CrowdMember
	if not member:
		return null
	_specialists_container.add_child(member)
	member.owner = null
	if pool_idx < pool.size():
		pool[pool_idx] = member
	else:
		pool.append(member)
	return member


func _build_variant_materials() -> void:
	if not _variant_materials.is_empty():
		return
	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = SPECIALIST_HIT_OUTLINE_SHADER
	outline_mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
	outline_mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
	outline_mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)

	var textures := [texture_blue, texture_green, texture_pink]
	for tex in textures:
		var mat := ShaderMaterial.new()
		mat.shader = SPECIALIST_HIT_SHADER
		mat.next_pass = outline_mat
		if tex:
			mat.set_shader_parameter("albedo_texture", tex)
		mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
		mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
		mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
		_variant_materials.append(mat)


func _attach_specialist_hitbox(member: CrowdMember) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(member):
		return
	var existing := member.get_node_or_null("SpecialistHitbox") as Area3D
	if existing:
		existing.set_deferred("monitoring", enable_hitboxes and _hitboxes_within_dist)
		existing.set_deferred("monitorable", enable_hitboxes and _hitboxes_within_dist)
		return
	var area: Area3D = VATHitboxAreaScript.new()
	area.name = "SpecialistHitbox"
	area.set("spawner", self)
	area.set("target_member", member)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.9
	col.shape = shape
	col.position = Vector3(0.0, 0.92, 0.0)
	area.add_child(col)
	member.add_child(area)
	area.owner = null
	area.set_deferred("monitoring", enable_hitboxes and _hitboxes_within_dist)
	area.set_deferred("monitorable", enable_hitboxes and _hitboxes_within_dist)


func _sync_specialist_hitboxes() -> void:
	var active := enable_hitboxes and _hitboxes_within_dist
	for m in _gun_members:
		if is_instance_valid(m):
			m.enable_hitbox = active
			var hb := m.get_node_or_null("SpecialistHitbox") as Area3D
			if hb:
				hb.monitoring = active
				hb.monitorable = active
	for m in _balloon_members:
		if is_instance_valid(m):
			m.enable_hitbox = active
			var hb := m.get_node_or_null("SpecialistHitbox") as Area3D
			if hb:
				hb.monitoring = active
				hb.monitorable = active
	for hb in _vat_hitbox_pool:
		if is_instance_valid(hb):
			hb.monitoring = active
			hb.monitorable = active


func _apply_render_distance() -> void:
	for v in _vat_variants:
		if v.is_empty():
			continue
		var mm_inst: MultiMeshInstance3D = v.get("mm_inst")
		if mm_inst:
			mm_inst.visibility_range_end = max_render_distance
			mm_inst.visibility_range_end_margin = 5.0


func _update_specialist_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var dist := global_position.distance_to(cam.global_position)

	var in_render := dist <= max_render_distance
	if in_render != _within_render_dist:
		_within_render_dist = in_render
		if is_instance_valid(_specialists_container):
			_specialists_container.visible = in_render

	var should_be_active := dist <= specialist_active_distance
	var new_step := 1
	if dist > specialist_quarter_rate_distance:
		new_step = 4
	elif dist > specialist_half_rate_distance:
		new_step = 2

	if should_be_active != _specialists_active or new_step != _specialist_step_interval:
		_specialists_active = should_be_active
		_specialist_step_interval = new_step
		for m in _gun_members:
			if is_instance_valid(m):
				m.anim_step_interval = new_step
				m.set_row_active(should_be_active)
		for m in _balloon_members:
			if is_instance_valid(m):
				m.anim_step_interval = new_step
				m.set_row_active(should_be_active)

	var new_hitboxes := dist <= hitbox_active_distance
	if new_hitboxes != _hitboxes_within_dist:
		_hitboxes_within_dist = new_hitboxes
		_sync_specialist_hitboxes()

	var new_shadows := dist <= shadow_active_distance
	if new_shadows != _shadows_active:
		_shadows_active = new_shadows
		var shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if new_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for v in _vat_variants:
			if not v.is_empty() and v.get("mm_inst") is MultiMeshInstance3D:
				(v["mm_inst"] as MultiMeshInstance3D).cast_shadow = shadow_mode
		for mi in _specialist_meshes:
			if is_instance_valid(mi):
				mi.cast_shadow = shadow_mode

	var new_outlines := dist <= outline_active_distance
	if new_outlines != _outlines_active:
		_outlines_active = new_outlines
		for v in _vat_variants:
			if v.is_empty():
				continue
			var mm_inst: MultiMeshInstance3D = v.get("mm_inst")
			if mm_inst and mm_inst.material_override is ShaderMaterial:
				var mat := mm_inst.material_override as ShaderMaterial
				if new_outlines and _cached_next_passes.has(mat):
					mat.next_pass = _cached_next_passes[mat]
				elif not new_outlines and mat.next_pass != null:
					_cached_next_passes[mat] = mat.next_pass
					mat.next_pass = null


func _trigger_random_gun_shot() -> void:
	var candidates: Array[CrowdMember] = []
	for m in _gun_members:
		if is_instance_valid(m) and (not _specialists_active or not m.is_performing_action):
			candidates.append(m)
	if candidates.is_empty():
		return

	var shooter := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var target_pos := _pick_random_crowd_target(shooter.global_position)

	if not _specialists_active:
		var muzzle_pos := shooter.global_position + Vector3(0.0, 1.25, 0.0)
		projectile_spawn_requested.emit("gun", muzzle_pos, target_pos, shooter.get_index())
		_spawn_water_gun_vfx(shooter, muzzle_pos, target_pos)
		return

	shooter.shoot_at(target_pos, func(member: Node3D, muzzle_pos: Vector3, aim_pos: Vector3):
		projectile_spawn_requested.emit("gun", muzzle_pos, aim_pos, member.get_index())
		_spawn_water_gun_vfx(member, muzzle_pos, aim_pos)
	)


func _trigger_random_balloon_throw() -> void:
	var candidates: Array[CrowdMember] = []
	for m in _balloon_members:
		if is_instance_valid(m) and (not _specialists_active or not m.is_performing_action):
			candidates.append(m)
	if candidates.is_empty():
		return

	var thrower := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var target_pos := _pick_random_crowd_target(thrower.global_position)

	if not _specialists_active:
		var throw_pos := thrower.global_position + Vector3(0.0, 1.35, 0.0)
		projectile_spawn_requested.emit("balloon", throw_pos, target_pos, thrower.get_index())
		_spawn_balloon_projectile(throw_pos, target_pos)
		return

	thrower.throw_balloon_at(target_pos, func(member: Node3D, throw_pos: Vector3, aim_pos: Vector3):
		projectile_spawn_requested.emit("balloon", throw_pos, aim_pos, member.get_index())
		_spawn_balloon_projectile(throw_pos, aim_pos)
	)


func _spawn_water_gun_vfx(shooter: Node3D, muzzle_pos: Vector3, target_pos: Vector3) -> void:
	var cur_muzzle_scale := Vector3(0.2, 0.2, 0.2)
	var cur_muzzle_offset := Vector3.ZERO
	var cur_impact_scale := Vector3(0.4, 0.4, 0.4)
	var cur_muzzle_anim := "Muzzle"
	var cur_impact_anim := "Muzzle"

	var cm := shooter as CrowdMember
	var spawn_node: Node3D = cm.gun_spawn_point if (cm and is_instance_valid(cm.gun_spawn_point)) else null
	if cm and is_instance_valid(cm.npc_gun):
		var gun := cm.npc_gun
		if "muzzle_scale" in gun:
			cur_muzzle_scale = gun.muzzle_scale
		if "muzzle_offset" in gun:
			cur_muzzle_offset = gun.muzzle_offset
		if "impact_scale" in gun:
			cur_impact_scale = gun.impact_scale
		if "muzzle_animation_name" in gun:
			cur_muzzle_anim = gun.muzzle_animation_name
		if "impact_animation_name" in gun:
			cur_impact_anim = gun.impact_animation_name

	var muzzle_vfx := _get_pooled_node(_muzzle_vfx_pool, "_muzzle_vfx_idx")
	if muzzle_vfx:
		if spawn_node and _specialists_active:
			muzzle_vfx.global_transform = spawn_node.global_transform
			muzzle_vfx.position += spawn_node.global_transform.basis * cur_muzzle_offset
		else:
			muzzle_vfx.global_position = muzzle_pos
			if target_pos.distance_squared_to(muzzle_pos) > 0.001:
				muzzle_vfx.look_at(target_pos, Vector3.UP)
		muzzle_vfx.scale = cur_muzzle_scale
		muzzle_vfx.visible = true
		_trigger_vfx_node(muzzle_vfx, cur_muzzle_anim)
		_hide_after_delay(muzzle_vfx, 1.2)

	var line := _get_pooled_node(_water_line_pool, "_water_line_idx")
	if line and line.has_method("set_line"):
		line.visible = true
		line.set_line(muzzle_pos, target_pos)

	var hit_vfx := _get_pooled_node(_hit_vfx_pool, "_hit_vfx_idx")
	if hit_vfx:
		hit_vfx.global_position = target_pos
		hit_vfx.scale = cur_impact_scale
		hit_vfx.visible = true
		_trigger_vfx_node(hit_vfx, cur_impact_anim)
		_hide_after_delay(hit_vfx, 1.2)

	_apply_splash_hits_to_dancers(target_pos, 1.2)


func _spawn_balloon_projectile(throw_pos: Vector3, target_pos: Vector3) -> void:
	var balloon := _get_pooled_balloon()
	if not balloon:
		return
	balloon.global_position = throw_pos
	if balloon.has_method("launch_pooled"):
		balloon.launch_pooled(target_pos, 0.0, 2.0, 2.5, 1.2, func(splash_pos: Vector3):
			_apply_splash_hits_to_dancers(splash_pos, 2.2)
		)


func _apply_splash_hits_to_dancers(splash_pos: Vector3, radius: float) -> void:
	var radius_sq := radius * radius
	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty() or not v.get("active", false):
			continue
		var transforms: Array[Transform3D] = v["transforms"]
		for i in range(transforms.size()):
			var world_pos := (global_transform * transforms[i]).origin
			var delta := world_pos - splash_pos
			delta.y = 0.0
			if delta.length_squared() <= radius_sq:
				trigger_hit(i, delta.normalized() if delta.length_squared() > 0.001 else Vector3.BACK, Vector3(0.0, 1.0, 0.0), v_idx)


func _init_pools() -> void:
	if is_instance_valid(_pool_container):
		return
	_pool_container = Node3D.new()
	_pool_container.name = "VATProjectilesPool"
	add_child(_pool_container)
	_pool_container.owner = null

	_populate_pool(water_line_scene, water_line_pool_size, _water_line_pool)
	_populate_pool(muzzle_vfx_scene, vfx_pool_size, _muzzle_vfx_pool)
	_populate_pool(hit_vfx_scene, vfx_pool_size, _hit_vfx_pool)
	_populate_pool(balloon_scene, balloon_pool_size, _balloon_pool)


func _populate_pool(scene: PackedScene, count: int, out_pool: Array[Node3D]) -> void:
	if not scene:
		return
	for _i in range(count):
		var inst := scene.instantiate() as Node3D
		if not inst:
			continue
		inst.visible = false
		_pool_container.add_child(inst)
		inst.owner = null
		out_pool.append(inst)


func _get_pooled_node(pool: Array[Node3D], idx_prop: String) -> Node3D:
	if pool.is_empty():
		return null
	for n in pool:
		if is_instance_valid(n) and not n.visible:
			return n
	var cur := int(get(idx_prop))
	cur = (cur + 1) % pool.size()
	set(idx_prop, cur)
	return pool[cur] if is_instance_valid(pool[cur]) else null


func _get_pooled_balloon() -> Node3D:
	if _balloon_pool.is_empty():
		return null
	for b in _balloon_pool:
		if is_instance_valid(b) and not b.visible and not b.get("_active"):
			return b
	_balloon_idx = (_balloon_idx + 1) % _balloon_pool.size()
	return _balloon_pool[_balloon_idx] if is_instance_valid(_balloon_pool[_balloon_idx]) else null


func _trigger_vfx_node(vfx_node: Node, anim_name: String = "") -> void:
	if not vfx_node:
		return
	if vfx_node.has_method("play"):
		vfx_node.play(false, false, false)
		return

	var cached_particles = vfx_node.get_meta("_vfx_particles") if vfx_node.has_meta("_vfx_particles") else null
	if cached_particles == null:
		cached_particles = []
		if vfx_node is GPUParticles3D:
			cached_particles.append(vfx_node)
		for p in vfx_node.find_children("*", "GPUParticles3D", true, false):
			if p is GPUParticles3D:
				cached_particles.append(p)
		vfx_node.set_meta("_vfx_particles", cached_particles)

	for p in cached_particles:
		if is_instance_valid(p):
			p.visible = true
			p.restart()
			p.emitting = true

	var cached_anim_players = vfx_node.get_meta("_vfx_anim_players") if vfx_node.has_meta("_vfx_anim_players") else null
	if cached_anim_players == null:
		cached_anim_players = []
		if vfx_node is AnimationPlayer:
			cached_anim_players.append(vfx_node)
		for ap in vfx_node.find_children("*", "AnimationPlayer", true, false):
			if ap is AnimationPlayer:
				cached_anim_players.append(ap)
		vfx_node.set_meta("_vfx_anim_players", cached_anim_players)

	for ap in cached_anim_players:
		if is_instance_valid(ap):
			if anim_name != "" and ap.has_animation(anim_name):
				ap.stop()
				ap.play(anim_name)


func _hide_after_delay(node: Node3D, delay: float) -> void:
	var tree := get_tree()
	if not tree:
		return
	tree.create_timer(delay).timeout.connect(func():
		if is_instance_valid(node):
			node.visible = false
	)


func _pick_random_crowd_target(from_pos: Vector3) -> Vector3:
	var all_xforms: Array[Transform3D] = []
	for v in _vat_variants:
		if not v.is_empty() and v.get("active", false):
			all_xforms.append_array(v["transforms"])
	if not all_xforms.is_empty():
		var t := all_xforms[_rng.randi_range(0, all_xforms.size() - 1)]
		return (global_transform * t).origin + Vector3(0.0, 1.0, 0.0)
	return from_pos + Vector3(0.0, 1.0, -5.0)


## Triggers a position-based motion-only vertex hit reaction on a specific VAT dancer instance (no color flash).
func trigger_hit(instance_idx: int, world_hit_dir: Vector3, local_hit_pos: Vector3 = Vector3(0.0, 1.0, 0.0), variant_id: int = 0) -> void:
	if variant_id < 0 or variant_id >= _vat_variants.size() or _vat_variants[variant_id].is_empty():
		return
	var v: Dictionary = _vat_variants[variant_id]
	var transforms: Array[Transform3D] = v["transforms"]
	var mm: MultiMesh = v["mm"]
	var hits_dict: Dictionary = v["hits"]
	if not mm or instance_idx < 0 or instance_idx >= transforms.size():
		return
	var local_dir := (transforms[instance_idx].basis.inverse() * global_transform.basis.inverse() * world_hit_dir)
	var xz := Vector2(local_dir.x, local_dir.z)
	if xz.length_squared() > 0.0001:
		xz = xz.normalized()
	else:
		xz = Vector2(0.0, 1.0)

	var angle_norm := wrapf(atan2(xz.y, xz.x), 0.0, TAU) / TAU
	var y_norm := clampf(local_hit_pos.y / 1.8, 0.0, 1.0)
	var x_norm := clampf(local_hit_pos.x * 0.5 + 0.5, 0.0, 1.0)
	var new_decay := 1.0

	if hits_dict.has(instance_idx):
		var prev: Dictionary = hits_dict[instance_idx]
		if float(prev["decay"]) > 0.05:
			new_decay = minf(float(prev["decay"]) + 0.35, 2.5)
			y_norm = lerpf(float(prev["y_norm"]), y_norm, 0.35)
			x_norm = lerpf(float(prev["x_norm"]), x_norm, 0.35)

	hits_dict[instance_idx] = {
		"decay": new_decay,
		"angle": angle_norm,
		"y_norm": y_norm,
		"x_norm": x_norm,
	}
	mm.set_instance_color(instance_idx, Color(new_decay, angle_norm, y_norm, x_norm))


func trigger_specialist_hit(member: CrowdMember, world_hit_dir: Vector3, world_hit_pos: Vector3) -> void:
	if not is_instance_valid(member):
		return
	var body_mesh := member.find_child("Body_001", true, false) as MeshInstance3D
	if not body_mesh:
		return

	var mesh_inv := body_mesh.global_transform.affine_inverse()
	var local_dir := mesh_inv.basis * world_hit_dir
	var xz := Vector2(local_dir.x, local_dir.z)
	if xz.length_squared() > 0.0001:
		xz = xz.normalized()
	else:
		xz = Vector2(0.0, 1.0)

	var local_pos := mesh_inv * world_hit_pos
	var angle_norm := wrapf(atan2(xz.y, xz.x), 0.0, TAU) / TAU
	var y_norm := clampf(local_pos.y / 1.8, 0.0, 1.0)
	var x_norm := clampf(local_pos.x * 0.5 + 0.5, 0.0, 1.0)
	var new_decay := 1.0

	if _active_specialist_hits.has(body_mesh):
		var prev: Dictionary = _active_specialist_hits[body_mesh]
		if float(prev["decay"]) > 0.05:
			new_decay = minf(float(prev["decay"]) + 0.35, 2.5)
			y_norm = lerpf(float(prev["y_norm"]), y_norm, 0.35)
			x_norm = lerpf(float(prev["x_norm"]), x_norm, 0.35)

	_active_specialist_hits[body_mesh] = {
		"decay": new_decay,
		"angle": angle_norm,
		"y_norm": y_norm,
		"x_norm": x_norm,
	}
	body_mesh.set_instance_shader_parameter("hit_data", Vector4(new_decay, angle_norm, y_norm, x_norm))


func _step_vat_hit_dict(hits_dict: Dictionary, mm: MultiMesh, step: float) -> void:
	if hits_dict.is_empty() or not mm:
		return
	var finished: Array[int] = []
	for idx in hits_dict.keys():
		var h: Dictionary = hits_dict[idx]
		h["decay"] = maxf(0.0, h["decay"] - step)
		mm.set_instance_color(idx, Color(h["decay"], h["angle"], h["y_norm"], h["x_norm"]))
		if h["decay"] <= 0.0:
			finished.append(idx)
	for idx in finished:
		hits_dict.erase(idx)


func _update_hit_reactions(delta: float) -> void:
	var step := delta / maxf(hit_reaction_duration, 0.05)
	for v in _vat_variants:
		if not v.is_empty():
			_step_vat_hit_dict(v["hits"], v["mm"], step)

	if not _active_specialist_hits.is_empty():
		var finished_meshes: Array = []
		for mesh_inst in _active_specialist_hits.keys():
			if not is_instance_valid(mesh_inst):
				finished_meshes.append(mesh_inst)
				continue
			var h: Dictionary = _active_specialist_hits[mesh_inst]
			h["decay"] = maxf(0.0, h["decay"] - step)
			mesh_inst.set_instance_shader_parameter("hit_data", Vector4(h["decay"], h["angle"], h["y_norm"], h["x_norm"]))
			if h["decay"] <= 0.0:
				finished_meshes.append(mesh_inst)
		for mesh_inst in finished_meshes:
			_active_specialist_hits.erase(mesh_inst)


func _rebuild_hitboxes() -> void:
	if not enable_hitboxes or not _hitboxes_within_dist or Engine.is_editor_hint():
		for hb in _vat_hitbox_pool:
			if is_instance_valid(hb):
				hb.monitoring = false
				hb.monitorable = false
		return

	if not is_instance_valid(_hitbox_container):
		_hitbox_container = Node3D.new()
		_hitbox_container.name = "VATHitboxes"
		add_child(_hitbox_container)
		_hitbox_container.owner = null

	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.9

	var used_count := 0
	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty() or not v.get("active", false):
			continue
		var transforms: Array[Transform3D] = v["transforms"]
		for i in range(transforms.size()):
			_acquire_vat_hitbox(used_count, i, transforms[i], shape, v_idx)
			used_count += 1

	for k in range(used_count, _vat_hitbox_pool.size()):
		var hb := _vat_hitbox_pool[k]
		if is_instance_valid(hb):
			hb.monitoring = false
			hb.monitorable = false


func _acquire_vat_hitbox(pool_idx: int, instance_idx: int, xform: Transform3D, shape: CapsuleShape3D, variant_id: int) -> void:
	var area: Area3D = null
	if pool_idx < _vat_hitbox_pool.size() and is_instance_valid(_vat_hitbox_pool[pool_idx]):
		area = _vat_hitbox_pool[pool_idx]
	else:
		area = VATHitboxAreaScript.new()
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(0.0, 0.92, 0.0)
		area.add_child(col)
		_hitbox_container.add_child(area)
		area.owner = null
		if pool_idx < _vat_hitbox_pool.size():
			_vat_hitbox_pool[pool_idx] = area
		else:
			_vat_hitbox_pool.append(area)

	area.set("spawner", self)
	area.set("instance_idx", instance_idx)
	area.set("variant_id", variant_id)
	area.transform = xform
	area.monitoring = true
	area.monitorable = true


func _sync_invisible_wall() -> void:
	var wall := get_node_or_null("InvisibleWall") as StaticBody3D
	if not enable_invisible_wall:
		if is_instance_valid(wall):
			var existing_col := wall.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if existing_col:
				existing_col.disabled = true
		return

	if not is_instance_valid(wall):
		wall = StaticBody3D.new()
		wall.name = "InvisibleWall"
		add_child(wall)
		wall.owner = null

	wall.collision_layer = invisible_wall_layer
	wall.collision_mask = 0
	wall.position = Vector3(0.0, invisible_wall_height * 0.5, 0.0)

	var col := wall.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		col = wall.get_node_or_null("InvisibleWall") as CollisionShape3D
	if not is_instance_valid(col):
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		wall.add_child(col)
		col.owner = null

	var box := col.shape as BoxShape3D
	if not box:
		box = BoxShape3D.new()
		col.shape = box
	box.size = Vector3(
		maxf(0.2, spawn_area_size.x + invisible_wall_padding.x),
		maxf(0.5, invisible_wall_height + invisible_wall_padding.y),
		maxf(0.2, spawn_area_size.z + invisible_wall_padding.z)
	)
	col.disabled = false


func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _sync_shader_params() -> void:
	for v in _vat_variants:
		if not v.is_empty():
			_sync_vat_material_meta(v.get("mm_inst"), v.get("meta", {}))
	_sync_hit_reaction_params()


func _sync_vat_material_meta(mm_inst: MultiMeshInstance3D, meta: Dictionary) -> void:
	if not mm_inst or meta.is_empty():
		return
	var mat := mm_inst.material_override as ShaderMaterial
	if not mat:
		return
	var tex_w := int(meta.get("tex_width", 1024))
	var rows := int(meta.get("rows_per_frame", 1))
	var fps := float(meta.get("fps", 24.0))
	mat.set_shader_parameter("vat_tex_width", tex_w)
	mat.set_shader_parameter("vat_rows_per_frame", rows)
	mat.set_shader_parameter("vat_fps", fps)
	var next_mat := mat.next_pass as ShaderMaterial
	if next_mat:
		_cached_next_passes[mat] = next_mat
		next_mat.set_shader_parameter("vat_tex_width", tex_w)
		next_mat.set_shader_parameter("vat_rows_per_frame", rows)
		next_mat.set_shader_parameter("vat_fps", fps)


func _sync_hit_reaction_params() -> void:
	for v in _vat_variants:
		if v.is_empty():
			continue
		var mm_inst: MultiMeshInstance3D = v.get("mm_inst")
		if not mm_inst:
			continue
		var mat := mm_inst.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
			mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
			mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
			var next_mat := mat.next_pass as ShaderMaterial
			if next_mat:
				next_mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
				next_mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
				next_mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
	for v_mat in _variant_materials:
		if v_mat is ShaderMaterial:
			v_mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
			v_mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
			v_mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
			var v_next := v_mat.next_pass as ShaderMaterial
			if v_next:
				v_next.set_shader_parameter("hit_bend_strength", hit_bend_strength)
				v_next.set_shader_parameter("hit_zone_radius", hit_zone_radius)
				v_next.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
