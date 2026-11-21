@tool
class_name CrowdVATSpawner
extends Node3D
## Full VAT Crowd Spawner:
## - Uses MultiMeshInstance3D (VAT) for Male, Female (Hat), and Female (No-Hat) dancers.
## - Runs Gunners (Body VAT + Paired Gun Prop VAT) and Ballooners (Body VAT + Hand-Tracked Balloon)
##   with 0 Skeleton3D nodes, smooth crossblends, target rotation, and exact projectile spawns.

signal projectile_spawn_requested(role: String, world_spawn_pos: Vector3, target_pos: Vector3, instance_idx: int)

const VATHitboxAreaScript := preload("res://scripts/vat/vat_hitbox_area.gd")
const VAT_SHADOW_SHADER := preload("res://shaders/crowd_vat_shadow.gdshader")

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
@export_file("*.json") var gun_vat_meta_path: String = "res://scenes/Crowds/VAT/crowd_gun_body_vat_meta.json":
	set(val):
		gun_vat_meta_path = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var gun_multimesh_node_path: NodePath = NodePath("MultiMeshInstance3D_Gun")
@export_file("*.tres") var gun_vat_mesh_path: String = "res://scenes/Crowds/VAT/crowd_gun_body_vat_mesh.tres"
@export_file("*.json") var gun_prop_vat_meta_path: String = "res://scenes/Crowds/VAT/crowd_gun_prop_vat_meta.json":
	set(val):
		gun_prop_vat_meta_path = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var gun_prop_multimesh_node_path: NodePath = NodePath("MultiMeshInstance3D_GunProp")
@export_file("*.tres") var gun_prop_vat_mesh_path: String = "res://scenes/Crowds/VAT/crowd_gun_prop_vat_mesh.tres"
@export_file("*.json") var balloon_vat_meta_path: String = "res://scenes/Crowds/VAT/crowd_balloon_vat_meta.json":
	set(val):
		balloon_vat_meta_path = val
		if is_inside_tree() and is_node_ready():
			_rebuild_crowd()
@export var balloon_multimesh_node_path: NodePath = NodePath("MultiMeshInstance3D_Balloon")
@export_file("*.tres") var balloon_vat_mesh_path: String = "res://scenes/Crowds/VAT/crowd_balloon_vat_mesh.tres"

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
@export_range(0.05, 0.5, 0.01) var vat_crossfade_duration: float = 0.18
@export_range(0.1, 1.5, 0.05) var vat_turn_duration: float = 0.4
@export var enable_hitboxes: bool = true:
	set(val):
		enable_hitboxes = val
		if is_inside_tree() and is_node_ready():
			_rebuild_hitboxes()
			_sync_vat_hitboxes()
@export var monitor_physics_projectiles: bool = false: ## Keep Area3D monitoring off unless physical bullet RigidBodies overlap crowd hitboxes (raycasts only need monitorable)
	set(val):
		monitor_physics_projectiles = val
		if is_inside_tree() and is_node_ready():
			_sync_vat_hitboxes()

@export_group("Performance & Distance LOD")
@export var enable_vat_shadows: bool = true: ## Toggle shadow casting on VAT crowd bodies (GunProp always stays shadow-off)
	set(val):
		enable_vat_shadows = val
		if is_inside_tree() and is_node_ready():
			call("_apply_vat_shadow_state")
@export_range(5.0, 150.0, 1.0) var specialist_active_distance: float = 35.0 ## Distance beyond which VAT Gunner/Ballooner turning & throwing actions pause
@export_range(5.0, 150.0, 1.0) var hitbox_active_distance: float = 35.0 ## Distance beyond which crowd hitboxes disable monitoring
@export_range(5.0, 150.0, 1.0) var shadow_active_distance: float = 30.0: ## Distance beyond which non-front-row crowd shadows finish fading out
	set(val):
		shadow_active_distance = val
		if is_inside_tree() and is_node_ready():
			call("_sync_lod_uniforms_only")
@export_range(1.0, 60.0, 0.5) var shadow_fade_distance: float = 10.0: ## Distance band over which shadows smoothly dither out before shadow_active_distance
	set(val):
		shadow_fade_distance = val
		if is_inside_tree() and is_node_ready():
			call("_sync_lod_uniforms_only")
@export_range(5.0, 150.0, 1.0) var outline_active_distance: float = 35.0: ## Distance beyond which non-front-row outlines finish fading out
	set(val):
		outline_active_distance = val
		if is_inside_tree() and is_node_ready():
			call("_sync_lod_uniforms_only")
@export_range(1.0, 60.0, 0.5) var outline_fade_distance: float = 10.0: ## Distance band over which outlines smoothly fade before outline_active_distance
	set(val):
		outline_fade_distance = val
		if is_inside_tree() and is_node_ready():
			call("_sync_lod_uniforms_only")
@export var keep_front_row_outline: bool = true: ## Keep outlines visible up to max_render_distance for the front row facing the camera
	set(val):
		keep_front_row_outline = val
		if is_inside_tree() and is_node_ready():
			call("_sync_lod_uniforms_only")
@export var keep_front_row_shadow: bool = true: ## Keep shadows enabled up to max_render_distance for the front row facing the camera
	set(val):
		keep_front_row_shadow = val
		if is_inside_tree() and is_node_ready():
			call("_sync_lod_uniforms_only")
@export_range(0.5, 8.0, 0.1) var front_row_depth: float = 1.8: ## Sightline depth behind the closest crowd member counted as front row
	set(val):
		front_row_depth = val
		_last_front_cam_pos = Vector3(1e9, 1e9, 1e9)
@export_range(10.0, 300.0, 1.0) var max_render_distance: float = 110.0: ## Distance beyond which crowd stops rendering and distant projectiles pause
	set(val):
		max_render_distance = val
		if is_inside_tree() and is_node_ready():
			_apply_render_distance()
			call("_sync_lod_uniforms_only")
@export_range(1.0, 60.0, 0.5) var max_render_fade_distance: float = 15.0: ## Distance band over which front-row outlines/shadows fade before max_render_distance
	set(val):
		max_render_fade_distance = val
		if is_inside_tree() and is_node_ready():
			call("_sync_lod_uniforms_only")

@export_group("Balloon Pop Animation")
@export var enable_balloon_pop_in: bool = true ## Pop crowd members in with a playful balloon inflation animation when entering max_render_distance
@export var enable_balloon_pop_out: bool = true: ## Pop crowd members out with a playful balloon deflation animation when leaving max_render_distance
	set(val):
		enable_balloon_pop_out = val
		if is_inside_tree() and is_node_ready():
			_apply_render_distance()
@export_range(0.1, 1.5, 0.05) var balloon_pop_duration: float = 0.45 ## Duration of the balloon pop-in squash & stretch animation
@export_range(0.1, 1.5, 0.05) var balloon_pop_out_duration: float = 0.35 ## Duration of the balloon pop-out deflation animation
@export_range(0.0, 0.2, 0.01) var balloon_pop_stagger: float = 0.04 ## Stagger delay between members entering/leaving in the same wave
@export_range(0.0, 15.0, 0.5) var balloon_pop_hysteresis: float = 3.0: ## Distance hysteresis past max_render_distance before popping out (prevents boundary flicker)
	set(val):
		balloon_pop_hysteresis = val
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

# VAT variants: 0 = Male, 1 = Female (Hat), 2 = Female (No Hat), 3 = VAT Gunner Body, 4 = VAT Ballooner
var _vat_variants: Array[Dictionary] = [{}, {}, {}, {}, {}]
var _gun_prop_variant: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _vat_clock: float = 0.0
var _active_vat_actions: Array[Dictionary] = []

var _shot_timer: float = 0.0
var _next_shot_time: float = 3.0
var _balloon_timer: float = 0.0
var _next_balloon_time: float = 4.5
var _lod_check_timer: float = 0.0
var _specialists_active: bool = true
var _hitboxes_within_dist: bool = true
var _shadows_active: bool = true
var _outlines_active: bool = true
var _within_render_dist: bool = true
var _cached_next_passes: Dictionary = {} # ShaderMaterial -> Material
var _shadow_proxy_container: Node3D = null
var _last_front_cam_pos: Vector3 = Vector3(1e9, 1e9, 1e9)
var _last_lod_ref_pos: Vector3 = Vector3.ZERO
var _crowd_local_center: Vector3 = Vector3.ZERO
var _crowd_bound_radius: float = 0.0

const _POP_HIDDEN: int = 0
const _POP_IN: int = 1
const _POP_VISIBLE: int = 2
const _POP_OUT: int = 3
var _pop_initialized: bool = false
var _last_pop_cam_pos: Vector3 = Vector3(1e9, 1e9, 1e9)
var _active_pop_count: int = 0

# Object pools
var _pool_container: Node3D = null
var _water_line_pool: Array[Node3D] = []
var _muzzle_vfx_pool: Array[Node3D] = []
var _hit_vfx_pool: Array[Node3D] = []
var _balloon_pool: Array[Node3D] = []
var _hand_balloon_pool: Array[Node3D] = []
var _water_line_idx: int = 0
var _muzzle_vfx_idx: int = 0
var _hit_vfx_idx: int = 0
var _balloon_idx: int = 0

# VAT Dancer state & pools
var _hitbox_container: Node3D = null
var _vat_hitbox_pool: Array[Area3D] = []


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
		for path in [
			multimesh_node_path,
			female_multimesh_node_path,
			female_nohat_multimesh_node_path,
			gun_multimesh_node_path,
			gun_prop_multimesh_node_path,
			balloon_multimesh_node_path,
		]:
			var mm_inst := get_node_or_null(path) as MultiMeshInstance3D
			if mm_inst:
				mm_inst.multimesh = null
		for v in _vat_variants:
			if not v.is_empty():
				var shadow_mm := v.get("shadow_mm_inst") as MultiMeshInstance3D
				if is_instance_valid(shadow_mm):
					shadow_mm.multimesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if preview_in_editor and is_inside_tree():
			call_deferred("_rebuild_crowd")


func _on_editor_child_entered(node: Node) -> void:
	if node is MultiMeshInstance3D and preview_in_editor:
		call_deferred("_rebuild_crowd")


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _vat_variants[0].is_empty():
		return

	_vat_clock += delta
	if _within_render_dist:
		_sync_specialist_vat_clocks()
	_update_hit_reactions(delta)
	_update_vat_actions(delta)
	_update_balloon_pops(delta)

	_lod_check_timer += delta
	if _lod_check_timer >= 0.15:
		_lod_check_timer = 0.0
		_update_specialist_lod()

	if not _within_render_dist:
		return

	if enable_gun_shooting and _has_active_vat_gunners() and (_specialists_active or allow_distant_projectiles):
		_shot_timer += delta
		if _shot_timer >= _next_shot_time:
			_shot_timer = 0.0
			_next_shot_time = _rng.randf_range(shot_interval_min, shot_interval_max)
			_trigger_vat_gun_shot()

	if enable_balloon_throwing and _has_active_vat_ballooners() and (_specialists_active or allow_distant_projectiles):
		_balloon_timer += delta
		if _balloon_timer >= _next_balloon_time:
			_balloon_timer = 0.0
			_next_balloon_time = _rng.randf_range(balloon_interval_min, balloon_interval_max)
			_trigger_vat_balloon_throw()


func _load_mesh_if_exists(path: String) -> Mesh:
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Mesh
	return null


func _all_vat_mm_instances() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for v in _vat_variants:
		if not v.is_empty() and v.get("mm_inst") is MultiMeshInstance3D:
			result.append(v["mm_inst"] as MultiMeshInstance3D)
	if not _gun_prop_variant.is_empty() and _gun_prop_variant.get("mm_inst") is MultiMeshInstance3D:
		result.append(_gun_prop_variant["mm_inst"] as MultiMeshInstance3D)
	return result


func _rebuild_crowd() -> void:
	var male_mm_inst := get_node_or_null(multimesh_node_path) as MultiMeshInstance3D
	if not male_mm_inst:
		return

	if Engine.is_editor_hint() and not preview_in_editor:
		_clear_preview()
		return

	_reset_active_vat_actions()

	var variant_configs := [
		{"mm_inst": male_mm_inst, "meta_path": vat_meta_path, "mesh": male_vat_mesh},
		{"mm_inst": get_node_or_null(female_multimesh_node_path) as MultiMeshInstance3D, "meta_path": female_vat_meta_path, "mesh": female_vat_mesh},
		{"mm_inst": get_node_or_null(female_nohat_multimesh_node_path) as MultiMeshInstance3D, "meta_path": female_nohat_vat_meta_path, "mesh": female_nohat_vat_mesh},
		{"mm_inst": get_node_or_null(gun_multimesh_node_path) as MultiMeshInstance3D, "meta_path": gun_vat_meta_path, "mesh": _load_mesh_if_exists(gun_vat_mesh_path)},
		{"mm_inst": get_node_or_null(balloon_multimesh_node_path) as MultiMeshInstance3D, "meta_path": balloon_vat_meta_path, "mesh": _load_mesh_if_exists(balloon_vat_mesh_path)},
	]
	for v_idx in range(5):
		var mm_inst: MultiMeshInstance3D = variant_configs[v_idx]["mm_inst"]
		var vat_mesh: Mesh = variant_configs[v_idx]["mesh"]
		if not vat_mesh and mm_inst and mm_inst.multimesh:
			vat_mesh = mm_inst.multimesh.mesh
		var meta := _load_json_dict(variant_configs[v_idx]["meta_path"]) if mm_inst else {}
		var clips: Dictionary = meta.get("clips", {}) if not meta.is_empty() else {}
		var empty_xforms: Array[Transform3D] = []
		var empty_idle: Array[Dictionary] = []
		var empty_pop_scales: Array[Vector3] = []
		_vat_variants[v_idx] = {
			"mm_inst": mm_inst,
			"shadow_mm_inst": null,
			"shadow_mat": null,
			"mm": null,
			"mesh": vat_mesh,
			"meta": meta,
			"clips": clips,
			"transforms": empty_xforms,
			"idle_states": empty_idle,
			"custom_base": PackedColorArray(),
			"front_flags": PackedByteArray(),
			"pop_states": PackedByteArray(),
			"pop_timers": PackedFloat32Array(),
			"pop_scales": empty_pop_scales,
			"hits": {},
			"active": mm_inst != null and vat_mesh != null and not clips.is_empty(),
		}

	var prop_mm_inst := get_node_or_null(gun_prop_multimesh_node_path) as MultiMeshInstance3D
	var prop_mesh := _load_mesh_if_exists(gun_prop_vat_mesh_path)
	if not prop_mesh and prop_mm_inst and prop_mm_inst.multimesh:
		prop_mesh = prop_mm_inst.multimesh.mesh
	var prop_meta := _load_json_dict(gun_prop_vat_meta_path) if prop_mm_inst else {}
	var prop_clips: Dictionary = prop_meta.get("clips", {}) if not prop_meta.is_empty() else {}
	_gun_prop_variant = {
		"mm_inst": prop_mm_inst,
		"mm": null,
		"mesh": prop_mesh,
		"meta": prop_meta,
		"clips": prop_clips,
		"custom_base": PackedColorArray(),
		"front_flags": PackedByteArray(),
		"active": prop_mm_inst != null and prop_mesh != null and not prop_clips.is_empty(),
	}

	if not _vat_variants[0]["active"]:
		return

	_sync_shader_params()

	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = custom_seed

	# 1. Generate non-overlapping slot transforms with O(1) spatial hash + Ground Snapping & Collision Check
	var placed_transforms: Array[Transform3D] = []
	var placed_positions: Array[Vector2] = []
	var placed_yaws: PackedFloat32Array = PackedFloat32Array()
	var placed_scales: PackedFloat32Array = PackedFloat32Array()
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
		var yaw_rad := deg_to_rad(base_facing_angle_deg + layout_rng.randf_range(-facing_randomness_deg, facing_randomness_deg))
		var s := 1.0 + layout_rng.randf_range(-scale_randomness, scale_randomness)
		var basis := Basis(Vector3.UP, yaw_rad).scaled(Vector3(s, s, s))
		placed_transforms.append(Transform3D(basis, Vector3(chosen_pos.x, chosen_y, chosen_pos.y)))
		placed_yaws.append(yaw_rad)
		placed_scales.append(s)

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

	var use_vat_gun := bool(_vat_variants[3]["active"])
	var use_vat_balloon := bool(_vat_variants[4]["active"])

	var used_slots := {}
	var gun_indices := _pick_spaced_role_indices(indices, used_slots, gun_count, placed_positions, min_gunner_spacing) if use_vat_gun else []
	var balloon_indices := _pick_spaced_role_indices(indices, used_slots, balloon_count, placed_positions, min_ballooner_spacing) if use_vat_balloon else []

	var placed_colors: Array[Dictionary] = []
	var gun_slots: Array[Dictionary] = []
	for idx in gun_indices:
		var c_idx := _pick_spaced_color(placed_positions[idx], placed_colors, layout_rng)
		gun_slots.append({"xform": placed_transforms[idx], "color": c_idx, "yaw": placed_yaws[idx], "scale": placed_scales[idx]})

	var balloon_slots: Array[Dictionary] = []
	for idx in balloon_indices:
		var c_idx := _pick_spaced_color(placed_positions[idx], placed_colors, layout_rng)
		balloon_slots.append({"xform": placed_transforms[idx], "color": c_idx, "yaw": placed_yaws[idx], "scale": placed_scales[idx]})

	var female_variants: Array[int] = []
	if _vat_variants[1]["active"]:
		female_variants.append(1)
	if _vat_variants[2]["active"]:
		female_variants.append(2)

	var variant_colors: Array[PackedInt32Array] = [
		PackedInt32Array(),
		PackedInt32Array(),
		PackedInt32Array(),
		PackedInt32Array(),
		PackedInt32Array(),
	]
	for idx in indices:
		if used_slots.has(idx):
			continue
		var chosen_v := 0
		if not female_variants.is_empty() and layout_rng.randf() < female_dancer_ratio:
			chosen_v = female_variants[layout_rng.randi_range(0, female_variants.size() - 1)]
		var c_idx := _pick_spaced_color(placed_positions[idx], placed_colors, layout_rng)
		(_vat_variants[chosen_v]["transforms"] as Array[Transform3D]).append(placed_transforms[idx])
		variant_colors[chosen_v].append(c_idx)

	if use_vat_gun:
		for s in gun_slots:
			(_vat_variants[3]["transforms"] as Array[Transform3D]).append(s["xform"])
			variant_colors[3].append(int(s["color"]))

	if use_vat_balloon:
		for s in balloon_slots:
			(_vat_variants[4]["transforms"] as Array[Transform3D]).append(s["xform"])
			variant_colors[4].append(int(s["color"]))

	# 3. Populate VAT MultiMeshes for dancers (0, 1, 2)
	for v_idx in range(3):
		var v: Dictionary = _vat_variants[v_idx]
		var mm_inst: MultiMeshInstance3D = v["mm_inst"]
		if v["active"]:
			_populate_dancer_multimesh(mm_inst, v["mesh"], v["transforms"], variant_colors[v_idx], v["clips"], layout_rng, v)
			v["mm"] = mm_inst.multimesh
		elif mm_inst:
			mm_inst.multimesh = null
			v["mm"] = null

	# 3b. Populate Full VAT Gunners (3 + paired Gun Prop) and Ballooners (4)
	if use_vat_gun:
		_populate_specialist_vat_multimesh(3, gun_slots, variant_colors[3], layout_rng, "gun_reload")
	else:
		if _vat_variants[3]["mm_inst"]:
			(_vat_variants[3]["mm_inst"] as MultiMeshInstance3D).multimesh = null
		_vat_variants[3]["mm"] = null
		if _gun_prop_variant.get("mm_inst"):
			(_gun_prop_variant["mm_inst"] as MultiMeshInstance3D).multimesh = null
		_gun_prop_variant["mm"] = null

	if use_vat_balloon:
		_populate_specialist_vat_multimesh(4, balloon_slots, variant_colors[4], layout_rng, "")
	else:
		if _vat_variants[4]["mm_inst"]:
			(_vat_variants[4]["mm_inst"] as MultiMeshInstance3D).multimesh = null
		_vat_variants[4]["mm"] = null

	_rebuild_hitboxes()
	_sync_invisible_wall()
	_sync_shadow_proxies()
	_apply_render_distance()
	_apply_vat_shadow_state()
	if not (_last_lod_ref_pos is Vector3):
		_last_lod_ref_pos = Vector3.ZERO
	_last_front_cam_pos = Vector3(1e9, 1e9, 1e9)
	_last_pop_cam_pos = Vector3(1e9, 1e9, 1e9)
	_pop_initialized = false
	_active_pop_count = 0
	_sync_shader_params()
	if not Engine.is_editor_hint() and get_viewport():
		_update_specialist_lod()


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


func _populate_dancer_multimesh(mm_inst: MultiMeshInstance3D, vat_mesh: Mesh, transforms: Array[Transform3D], colors: PackedInt32Array, clips: Dictionary, layout_rng: RandomNumberGenerator, v_dict: Dictionary = {}) -> void:
	var mm := MultiMesh.new()
	mm.mesh = vat_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = transforms.size()
	mm_inst.multimesh = mm

	var custom_base := PackedColorArray()
	custom_base.resize(transforms.size())
	var front_flags := PackedByteArray()
	front_flags.resize(transforms.size())
	front_flags.fill(0)

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
		var c := Color(0.0, 1.0, 0.0, float(tex_idx))
		if clips.has(clip_alias):
			var clip: Dictionary = clips[clip_alias]
			var start_f := float(clip.get("start_frame", 0))
			var count_f := float(clip.get("frame_count", 1))
			# 16 quantized phase buckets keep visual variety while letting GPU cache reuse VAT texel rows
			var phase := float(layout_rng.randi_range(0, 15)) * 0.25
			c = Color(start_f, count_f, phase, float(tex_idx))
		mm.set_instance_custom_data(i, c)
		custom_base[i] = c

	if not v_dict.is_empty():
		var pop_states := PackedByteArray()
		pop_states.resize(transforms.size())
		pop_states.fill(_POP_VISIBLE)
		var pop_timers := PackedFloat32Array()
		pop_timers.resize(transforms.size())
		pop_timers.fill(0.0)
		var pop_scales: Array[Vector3] = []
		pop_scales.resize(transforms.size())
		pop_scales.fill(Vector3.ONE)
		v_dict["custom_base"] = custom_base
		v_dict["front_flags"] = front_flags
		v_dict["pop_states"] = pop_states
		v_dict["pop_timers"] = pop_timers
		v_dict["pop_scales"] = pop_scales


func _populate_specialist_vat_multimesh(v_idx: int, slots: Array[Dictionary], colors: PackedInt32Array, layout_rng: RandomNumberGenerator, preferred_clip: String) -> void:
	var v: Dictionary = _vat_variants[v_idx]
	var mm_inst: MultiMeshInstance3D = v["mm_inst"]
	var clips: Dictionary = v["clips"]
	var mm := MultiMesh.new()
	mm.mesh = v["mesh"]
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = slots.size()
	mm_inst.multimesh = mm
	v["mm"] = mm

	var prop_mm: MultiMesh = null
	var prop_clips: Dictionary = {}
	if v_idx == 3 and _gun_prop_variant.get("active", false):
		var prop_inst: MultiMeshInstance3D = _gun_prop_variant["mm_inst"]
		prop_mm = MultiMesh.new()
		prop_mm.mesh = _gun_prop_variant["mesh"]
		prop_mm.transform_format = MultiMesh.TRANSFORM_3D
		prop_mm.use_colors = true
		prop_mm.use_custom_data = true
		prop_mm.instance_count = slots.size()
		prop_inst.multimesh = prop_mm
		prop_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gun_prop_variant["mm"] = prop_mm
		prop_clips = _gun_prop_variant["clips"]

	var idle_aliases: Array[String] = []
	if preferred_clip != "" and clips.has(preferred_clip):
		idle_aliases.append(preferred_clip)
	else:
		for alias in clips.keys():
			if str(alias).begins_with("dance"):
				idle_aliases.append(str(alias))
		if idle_aliases.is_empty() and clips.has("balloon_idle"):
			idle_aliases.append("balloon_idle")
		if idle_aliases.is_empty():
			for alias in clips.keys():
				idle_aliases.append(str(alias))

	var idle_states: Array[Dictionary] = v["idle_states"]
	idle_states.clear()

	var custom_base := PackedColorArray()
	custom_base.resize(slots.size())
	var front_flags := PackedByteArray()
	front_flags.resize(slots.size())
	front_flags.fill(0)

	var prop_custom_base := PackedColorArray()
	var prop_front_flags := PackedByteArray()
	if prop_mm:
		prop_custom_base.resize(slots.size())
		prop_front_flags.resize(slots.size())
		prop_front_flags.fill(0)

	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var xform: Transform3D = slot["xform"]
		var tex_idx := colors[i] if i < colors.size() else layout_rng.randi_range(0, 2)
		var clip_alias: String = idle_aliases[layout_rng.randi_range(0, idle_aliases.size() - 1)] if not idle_aliases.is_empty() else ""
		var clip: Dictionary = clips.get(clip_alias, {})
		var start_f := float(clip.get("start_frame", 0))
		var count_f := float(clip.get("frame_count", 1))
		var phase := float(layout_rng.randi_range(0, 15)) * 0.25

		var body_custom := Color(start_f, count_f, phase, float(tex_idx))
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, Color(0.0, 0.5, 0.5, 0.0))
		mm.set_instance_custom_data(i, body_custom)
		custom_base[i] = body_custom

		var prop_start_f := start_f
		var prop_count_f := count_f
		if prop_mm:
			var p_clip: Dictionary = prop_clips.get(clip_alias, {})
			if not p_clip.is_empty():
				prop_start_f = float(p_clip.get("start_frame", 0))
				prop_count_f = float(p_clip.get("frame_count", 1))
			var prop_custom := Color(prop_start_f, prop_count_f, phase, 0.0)
			prop_mm.set_instance_transform(i, xform)
			prop_mm.set_instance_color(i, Color(0.0, 0.5, 0.5, 0.0))
			prop_mm.set_instance_custom_data(i, prop_custom)
			prop_custom_base[i] = prop_custom

		idle_states.append({
			"clip": clip_alias,
			"start_frame": start_f,
			"frame_count": count_f,
			"prop_start_frame": prop_start_f,
			"prop_frame_count": prop_count_f,
			"phase": phase,
			"tex_idx": float(tex_idx),
			"is_front": false,
			"base_yaw": float(slot["yaw"]),
			"cur_yaw": float(slot["yaw"]),
			"scale": float(slot["scale"]),
			"origin": xform.origin,
			"busy": false,
		})

	var pop_states := PackedByteArray()
	pop_states.resize(slots.size())
	pop_states.fill(_POP_VISIBLE)
	var pop_timers := PackedFloat32Array()
	pop_timers.resize(slots.size())
	pop_timers.fill(0.0)
	var pop_scales: Array[Vector3] = []
	pop_scales.resize(slots.size())
	pop_scales.fill(Vector3.ONE)

	v["custom_base"] = custom_base
	v["front_flags"] = front_flags
	v["pop_states"] = pop_states
	v["pop_timers"] = pop_timers
	v["pop_scales"] = pop_scales
	if prop_mm:
		_gun_prop_variant["custom_base"] = prop_custom_base
		_gun_prop_variant["front_flags"] = prop_front_flags


func _clear_preview() -> void:
	_reset_active_vat_actions()
	_active_pop_count = 0
	_pop_initialized = false
	if is_instance_valid(_hitbox_container):
		_hitbox_container.queue_free()
		_hitbox_container = null
	for v in _vat_variants:
		if v.is_empty():
			continue
		(v["transforms"] as Array[Transform3D]).clear()
		if v.has("idle_states"):
			(v["idle_states"] as Array[Dictionary]).clear()
		if v.has("custom_base"):
			v["custom_base"] = PackedColorArray()
		if v.has("front_flags"):
			v["front_flags"] = PackedByteArray()
		if v.has("pop_states"):
			v["pop_states"] = PackedByteArray()
		if v.has("pop_timers"):
			v["pop_timers"] = PackedFloat32Array()
		if v.has("pop_scales"):
			(v["pop_scales"] as Array[Vector3]).clear()
		(v["hits"] as Dictionary).clear()
		var mm_inst: MultiMeshInstance3D = v.get("mm_inst")
		if mm_inst and mm_inst.multimesh:
			mm_inst.multimesh.instance_count = 0
		var shadow_mm: MultiMeshInstance3D = v.get("shadow_mm_inst")
		if is_instance_valid(shadow_mm):
			shadow_mm.multimesh = null
			shadow_mm.visible = false
	if not _gun_prop_variant.is_empty():
		_gun_prop_variant["custom_base"] = PackedColorArray()
		_gun_prop_variant["front_flags"] = PackedByteArray()
		var prop_inst: MultiMeshInstance3D = _gun_prop_variant.get("mm_inst")
		if prop_inst and prop_inst.multimesh:
			prop_inst.multimesh.instance_count = 0


func _sync_vat_hitboxes() -> void:
	var active := enable_hitboxes and _hitboxes_within_dist
	var monitor_overlap := active and monitor_physics_projectiles
	for hb in _vat_hitbox_pool:
		if is_instance_valid(hb):
			hb.monitoring = monitor_overlap
			hb.monitorable = active


func _find_internal_child(parent: Node, child_name: String) -> Node:
	if not is_instance_valid(parent):
		return null
	for c in parent.get_children(true):
		if c.name == child_name:
			return c
	return null


func _sync_shadow_proxies() -> void:
	var internal_mode := Node.INTERNAL_MODE_BACK if Engine.is_editor_hint() else Node.INTERNAL_MODE_DISABLED
	if not is_instance_valid(_shadow_proxy_container):
		_shadow_proxy_container = _find_internal_child(self, "_ShadowProxies") as Node3D
		if not is_instance_valid(_shadow_proxy_container):
			_shadow_proxy_container = Node3D.new()
			_shadow_proxy_container.name = "_ShadowProxies"
			add_child(_shadow_proxy_container, false, internal_mode)
			if not Engine.is_editor_hint():
				_shadow_proxy_container.owner = null

	var sum_origin := Vector3.ZERO
	var total_count := 0
	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty():
			continue
		var xforms: Array[Transform3D] = v.get("transforms", [])
		for xf in xforms:
			sum_origin += xf.origin
			total_count += 1
	_crowd_local_center = (sum_origin / float(total_count)) if total_count > 0 else Vector3.ZERO

	var max_dist_sq := 0.0
	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty():
			continue
		var xforms: Array[Transform3D] = v.get("transforms", [])
		for xf in xforms:
			var d_sq := xf.origin.distance_squared_to(_crowd_local_center)
			if d_sq > max_dist_sq:
				max_dist_sq = d_sq
	_crowd_bound_radius = sqrt(max_dist_sq) + 1.5

	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty():
			continue
		var proxy_name := "ShadowProxy_%d" % v_idx
		var shadow_mm := _find_internal_child(_shadow_proxy_container, proxy_name) as MultiMeshInstance3D
		var mm_inst := v.get("mm_inst") as MultiMeshInstance3D
		var mm := v.get("mm") as MultiMesh
		if bool(v.get("active", false)) and is_instance_valid(mm_inst) and mm != null and mm.instance_count > 0:
			if not is_instance_valid(shadow_mm):
				shadow_mm = MultiMeshInstance3D.new()
				shadow_mm.name = proxy_name
				_shadow_proxy_container.add_child(shadow_mm, false, internal_mode)
				if not Engine.is_editor_hint():
					shadow_mm.owner = null
			shadow_mm.transform = mm_inst.transform
			shadow_mm.multimesh = mm
			var shadow_mat := shadow_mm.material_override as ShaderMaterial
			if not shadow_mat or shadow_mat.shader != VAT_SHADOW_SHADER:
				shadow_mat = ShaderMaterial.new()
				shadow_mat.shader = VAT_SHADOW_SHADER
				shadow_mm.material_override = shadow_mat
			var src_mat := mm_inst.material_override as ShaderMaterial
			if src_mat:
				var pos_tex: Variant = src_mat.get_shader_parameter("vat_pos_tex")
				if pos_tex != null:
					shadow_mat.set_shader_parameter("vat_pos_tex", pos_tex)
			v["shadow_mm_inst"] = shadow_mm
			v["shadow_mat"] = shadow_mat
		else:
			if is_instance_valid(shadow_mm):
				shadow_mm.multimesh = null
				shadow_mm.visible = false
			v["shadow_mm_inst"] = null
			v["shadow_mat"] = null


func _apply_render_distance() -> void:
	var vis_end := max_render_distance + ((balloon_pop_hysteresis + 12.0) if (enable_balloon_pop_out and not Engine.is_editor_hint()) else 0.0)
	for mm_inst in _all_vat_mm_instances():
		mm_inst.visibility_range_end = vis_end
		mm_inst.visibility_range_end_margin = 5.0
	for v in _vat_variants:
		if not v.is_empty():
			var shadow_mm := v.get("shadow_mm_inst") as MultiMeshInstance3D
			if is_instance_valid(shadow_mm):
				shadow_mm.visibility_range_end = vis_end
				shadow_mm.visibility_range_end_margin = 5.0


func _apply_vat_shadow_state() -> void:
	var shadow_on := bool(enable_vat_shadows) and bool(_shadows_active)
	for v in _vat_variants:
		if v.is_empty():
			continue
		var mm_inst := v.get("mm_inst") as MultiMeshInstance3D
		var shadow_mm := v.get("shadow_mm_inst") as MultiMeshInstance3D
		if is_instance_valid(mm_inst):
			# Main opaque pass never casts shadows when the SHADOWS_ONLY proxy is present
			mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if is_instance_valid(shadow_mm):
			var has_mesh := shadow_mm.multimesh != null and shadow_mm.multimesh.instance_count > 0
			shadow_mm.visible = shadow_on and has_mesh
			shadow_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if (shadow_on and has_mesh) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep GunProp shadow-off (matches original NPC_Gun.tscn) to save 4 shadow cascade passes
	if not _gun_prop_variant.is_empty() and _gun_prop_variant.get("mm_inst") is MultiMeshInstance3D:
		(_gun_prop_variant["mm_inst"] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _sync_lod_uniforms_only() -> void:
	var ref_pos: Vector3 = _last_lod_ref_pos if (_last_lod_ref_pos is Vector3) else Vector3.ZERO
	_sync_lod_shader_uniforms(ref_pos)


func _sync_lod_shader_uniforms(lod_ref_world: Vector3) -> void:
	_last_lod_ref_pos = lod_ref_world
	var use_fade := not Engine.is_editor_hint()
	var o_end := maxf(outline_active_distance, 0.5)
	var o_start := clampf(o_end - maxf(outline_fade_distance, 0.1), 0.0, o_end - 0.01)
	var s_end := maxf(shadow_active_distance, 0.5)
	var s_start := clampf(s_end - maxf(shadow_fade_distance, 0.1), 0.0, s_end - 0.01)
	var m_end := maxf(max_render_distance, 1.0)
	var m_start := clampf(m_end - maxf(max_render_fade_distance, 0.1), 0.0, m_end - 0.01)

	for mm_inst in _all_vat_mm_instances():
		var mat := mm_inst.material_override as ShaderMaterial
		if not mat:
			continue
		var next_mat := mat.next_pass as ShaderMaterial
		if not next_mat and _cached_next_passes.has(mat):
			next_mat = _cached_next_passes[mat] as ShaderMaterial
		if next_mat:
			next_mat.set_shader_parameter("use_lod_fade", use_fade)
			next_mat.set_shader_parameter("keep_front_row_outline", keep_front_row_outline)
			next_mat.set_shader_parameter("lod_ref_pos", lod_ref_world)
			next_mat.set_shader_parameter("outline_fade_start", o_start)
			next_mat.set_shader_parameter("outline_fade_end", o_end)
			next_mat.set_shader_parameter("max_render_fade_start", m_start)
			next_mat.set_shader_parameter("max_render_fade_end", m_end)

	for v in _vat_variants:
		if v.is_empty():
			continue
		var shadow_mat := v.get("shadow_mat") as ShaderMaterial
		if shadow_mat:
			shadow_mat.set_shader_parameter("use_lod_fade", use_fade)
			shadow_mat.set_shader_parameter("keep_front_row_shadow", keep_front_row_shadow)
			shadow_mat.set_shader_parameter("lod_ref_pos", lod_ref_world)
			shadow_mat.set_shader_parameter("shadow_fade_start", s_start)
			shadow_mat.set_shader_parameter("shadow_fade_end", s_end)
			shadow_mat.set_shader_parameter("max_render_fade_start", m_start)
			shadow_mat.set_shader_parameter("max_render_fade_end", m_end)


func _update_front_row_mask(cam_world: Vector3) -> void:
	_last_front_cam_pos = cam_world
	var cam_local := to_local(cam_world)
	var cam_xz := Vector2(cam_local.x, cam_local.z)
	var center_xz := Vector2(_crowd_local_center.x, _crowd_local_center.z)
	var base_dir := center_xz - cam_xz
	if base_dir.length_squared() < 0.0001:
		base_dir = Vector2(0.0, -1.0)
	else:
		base_dir = base_dir.normalized()

	const BINS := 144
	const INF_DIST := 1e12
	var min_dists := PackedFloat32Array()
	min_dists.resize(BINS)
	min_dists.fill(INF_DIST)
	var inv_tau := float(BINS) / TAU

	var variant_count := _vat_variants.size()
	var cached_bins: Array[PackedInt32Array] = []
	var cached_dists: Array[PackedFloat32Array] = []
	cached_bins.resize(variant_count)
	cached_dists.resize(variant_count)

	for v_idx in range(variant_count):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty() or not bool(v.get("active", false)):
			continue
		var mm := v.get("mm") as MultiMesh
		if not mm or mm.instance_count <= 0:
			continue
		var xforms: Array[Transform3D] = v.get("transforms", [])
		var mm_inst := v.get("mm_inst") as MultiMeshInstance3D
		var mm_offset := mm_inst.transform if mm_inst else Transform3D.IDENTITY
		var count := mini(xforms.size(), mm.instance_count)
		var v_bins := PackedInt32Array()
		v_bins.resize(count)
		var v_dists := PackedFloat32Array()
		v_dists.resize(count)

		for i in range(count):
			var p := mm_offset * xforms[i].origin
			var dvec := Vector2(p.x, p.z) - cam_xz
			var dist := dvec.length()
			var b := 0
			if dist > 0.001:
				var rel := atan2(base_dir.x * dvec.y - base_dir.y * dvec.x, base_dir.dot(dvec))
				b = clampi(int(floorf((rel + PI) * inv_tau)), 0, BINS - 1)
			v_bins[i] = b
			v_dists[i] = dist
			if dist < min_dists[b]:
				min_dists[b] = dist

		cached_bins[v_idx] = v_bins
		cached_dists[v_idx] = v_dists

	var prop_mm := _gun_prop_variant.get("mm") as MultiMesh if not _gun_prop_variant.is_empty() else null
	var prop_custom_base: PackedColorArray = _gun_prop_variant.get("custom_base", PackedColorArray()) if prop_mm else PackedColorArray()

	for v_idx in range(variant_count):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty() or not bool(v.get("active", false)):
			continue
		var mm := v.get("mm") as MultiMesh
		if not mm or mm.instance_count <= 0:
			continue
		var v_bins := cached_bins[v_idx]
		var v_dists := cached_dists[v_idx]
		var count := v_bins.size()
		var front_flags: PackedByteArray = v.get("front_flags", PackedByteArray())
		if front_flags.size() != count:
			front_flags.resize(count)
			front_flags.fill(255)
			v["front_flags"] = front_flags
		var custom_base: PackedColorArray = v.get("custom_base", PackedColorArray())
		var idle_states: Array[Dictionary] = v.get("idle_states", [])
		var is_specialist := (v_idx >= 3)

		for i in range(count):
			var b := v_bins[i]
			var is_front := v_dists[i] <= (min_dists[b] + front_row_depth)
			var want: int = 1 if is_front else 0
			if front_flags[i] == want:
				continue
			front_flags[i] = want
			var front_offset := 10.0 if is_front else 0.0
			var busy := is_specialist and i < idle_states.size() and bool(idle_states[i].get("busy", false))
			if is_specialist and i < idle_states.size():
				idle_states[i]["is_front"] = is_front

			if busy:
				var cur := mm.get_instance_custom_data(i)
				var base_tex := float(idle_states[i]["tex_idx"])
				mm.set_instance_custom_data(i, Color(cur.r, cur.g, cur.b, base_tex + front_offset))
			elif i < custom_base.size():
				var base_c := custom_base[i]
				mm.set_instance_custom_data(i, Color(base_c.r, base_c.g, base_c.b, base_c.a + front_offset))

			if v_idx == 3 and prop_mm and i < prop_mm.instance_count:
				if busy:
					var pcur := prop_mm.get_instance_custom_data(i)
					prop_mm.set_instance_custom_data(i, Color(pcur.r, pcur.g, pcur.b, front_offset))
				elif i < prop_custom_base.size():
					var pbase := prop_custom_base[i]
					prop_mm.set_instance_custom_data(i, Color(pbase.r, pbase.g, pbase.b, front_offset))


func _eval_balloon_pop_scale(is_pop_in: bool, u: float) -> Vector3:
	if is_pop_in:
		if u < 0.65:
			var t := u / 0.65
			var e := 1.0 - (1.0 - t) * (1.0 - t)
			return Vector3(0.2, 0.02, 0.2).lerp(Vector3(0.85, 1.25, 0.85), e)
		var t2 := (u - 0.65) / 0.35
		var tm1 := t2 - 1.0
		const BACK_S := 1.70158
		var e2 := 1.0 + (BACK_S + 1.0) * tm1 * tm1 * tm1 + BACK_S * tm1 * tm1
		return Vector3(0.85, 1.25, 0.85).lerp(Vector3.ONE, e2)
	if u < 0.25:
		var t := u / 0.25
		var e := 1.0 - (1.0 - t) * (1.0 - t)
		return Vector3.ONE.lerp(Vector3(0.85, 1.25, 0.85), e)
	if u < 0.80:
		var t2 := (u - 0.25) / 0.55
		var e2 := t2 * t2
		return Vector3(0.85, 1.25, 0.85).lerp(Vector3(1.35, 0.03, 1.35), e2)
	var t3 := (u - 0.80) / 0.20
	var e3 := t3 * t3
	return Vector3(1.35, 0.03, 1.35).lerp(Vector3.ZERO, e3)


func _get_member_pop_scale(v: Dictionary, inst_idx: int) -> Vector3:
	var pop_scales: Array[Vector3] = v.get("pop_scales", [])
	if inst_idx >= 0 and inst_idx < pop_scales.size():
		return pop_scales[inst_idx]
	return Vector3.ONE


func _update_balloon_pop_triggers(cam_world: Vector3) -> void:
	_last_pop_cam_pos = cam_world
	var first_snap := not _pop_initialized
	_pop_initialized = true
	var enter_dist_sq := max_render_distance * max_render_distance
	var exit_dist := max_render_distance + maxf(balloon_pop_hysteresis, 0.0)
	var exit_dist_sq := exit_dist * exit_dist
	var prop_mm := _gun_prop_variant.get("mm") as MultiMesh if not _gun_prop_variant.is_empty() else null

	var wave_in_idx := 0
	var wave_out_idx := 0

	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty() or not bool(v.get("active", false)):
			continue
		var mm := v.get("mm") as MultiMesh
		if not mm or mm.instance_count <= 0:
			continue
		var xforms: Array[Transform3D] = v.get("transforms", [])
		var mm_inst := v.get("mm_inst") as MultiMeshInstance3D
		var mm_world_base := global_transform * (mm_inst.transform if mm_inst else Transform3D.IDENTITY)
		var count := mini(xforms.size(), mm.instance_count)
		var pop_states: PackedByteArray = v.get("pop_states", PackedByteArray())
		var pop_timers: PackedFloat32Array = v.get("pop_timers", PackedFloat32Array())
		var pop_scales: Array[Vector3] = v.get("pop_scales", [])
		if pop_states.size() != count:
			continue

		for i in range(count):
			var base_xf := xforms[i]
			var world_pos := mm_world_base * base_xf.origin
			var d_sq := world_pos.distance_squared_to(cam_world)
			var st := pop_states[i]

			if first_snap:
				if d_sq > enter_dist_sq:
					pop_states[i] = _POP_HIDDEN
					pop_timers[i] = 0.0
					pop_scales[i] = Vector3.ZERO
					var zero_xf := base_xf.scaled_local(Vector3.ZERO)
					mm.set_instance_transform(i, zero_xf)
					if v_idx == 3 and prop_mm and i < prop_mm.instance_count:
						prop_mm.set_instance_transform(i, zero_xf)
				else:
					pop_states[i] = _POP_VISIBLE
					pop_timers[i] = 0.0
					pop_scales[i] = Vector3.ONE
				continue

			if (st == _POP_HIDDEN or st == _POP_OUT) and d_sq <= enter_dist_sq:
				var was_active := (st == _POP_OUT)
				if enable_balloon_pop_in:
					var delay := 0.0 if was_active else minf(float(wave_in_idx) * balloon_pop_stagger, 0.55)
					wave_in_idx += 1
					pop_states[i] = _POP_IN
					pop_timers[i] = -delay
					if not was_active:
						_active_pop_count += 1
					if delay <= 0.0:
						var sc := Vector3(0.2, 0.02, 0.2)
						pop_scales[i] = sc
						var pop_xf := base_xf.scaled_local(sc)
						mm.set_instance_transform(i, pop_xf)
						if v_idx == 3 and prop_mm and i < prop_mm.instance_count:
							prop_mm.set_instance_transform(i, pop_xf)
				else:
					if was_active:
						_active_pop_count = maxi(_active_pop_count - 1, 0)
					pop_states[i] = _POP_VISIBLE
					pop_timers[i] = 0.0
					pop_scales[i] = Vector3.ONE
					mm.set_instance_transform(i, base_xf)
					if v_idx == 3 and prop_mm and i < prop_mm.instance_count:
						prop_mm.set_instance_transform(i, base_xf)
			elif (st == _POP_VISIBLE or st == _POP_IN) and d_sq > exit_dist_sq:
				var was_active := (st == _POP_IN)
				if enable_balloon_pop_out:
					var delay := 0.0 if was_active else minf(float(wave_out_idx) * balloon_pop_stagger, 0.55)
					wave_out_idx += 1
					pop_states[i] = _POP_OUT
					pop_timers[i] = -delay
					if not was_active:
						_active_pop_count += 1
				else:
					if was_active:
						_active_pop_count = maxi(_active_pop_count - 1, 0)
					pop_states[i] = _POP_HIDDEN
					pop_timers[i] = 0.0
					pop_scales[i] = Vector3.ZERO
					var zero_xf := base_xf.scaled_local(Vector3.ZERO)
					mm.set_instance_transform(i, zero_xf)
					if v_idx == 3 and prop_mm and i < prop_mm.instance_count:
						prop_mm.set_instance_transform(i, zero_xf)


func _update_balloon_pops(delta: float) -> void:
	if _active_pop_count <= 0:
		return
	var in_dur := maxf(balloon_pop_duration, 0.05)
	var out_dur := maxf(balloon_pop_out_duration, 0.05)
	var prop_mm := _gun_prop_variant.get("mm") as MultiMesh if not _gun_prop_variant.is_empty() else null

	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty() or not bool(v.get("active", false)):
			continue
		var mm := v.get("mm") as MultiMesh
		if not mm or mm.instance_count <= 0:
			continue
		var xforms: Array[Transform3D] = v.get("transforms", [])
		var count := mini(xforms.size(), mm.instance_count)
		var pop_states: PackedByteArray = v.get("pop_states", PackedByteArray())
		var pop_timers: PackedFloat32Array = v.get("pop_timers", PackedFloat32Array())
		var pop_scales: Array[Vector3] = v.get("pop_scales", [])
		if pop_states.size() != count:
			continue

		for i in range(count):
			var st := pop_states[i]
			if st != _POP_IN and st != _POP_OUT:
				continue
			var t := pop_timers[i] + delta
			pop_timers[i] = t
			if t < 0.0:
				continue
			var is_in := (st == _POP_IN)
			var dur := in_dur if is_in else out_dur
			var u := clampf(t / dur, 0.0, 1.0)
			var sc := Vector3.ONE if (is_in and u >= 1.0) else (Vector3.ZERO if (not is_in and u >= 1.0) else _eval_balloon_pop_scale(is_in, u))
			pop_scales[i] = sc
			var final_xf := xforms[i].scaled_local(sc)
			mm.set_instance_transform(i, final_xf)
			if v_idx == 3 and prop_mm and i < prop_mm.instance_count:
				prop_mm.set_instance_transform(i, final_xf)
			if u >= 1.0:
				pop_states[i] = _POP_VISIBLE if is_in else _POP_HIDDEN
				_active_pop_count = maxi(_active_pop_count - 1, 0)


func _update_specialist_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var cam_world := cam.global_position
	var crowd_world_center := global_transform * _crowd_local_center
	var dist := crowd_world_center.distance_to(cam_world)
	var dist_to_edge := maxf(dist - _crowd_bound_radius, 0.0)

	if not _pop_initialized or not (_last_pop_cam_pos is Vector3) or cam_world.distance_squared_to(_last_pop_cam_pos) > 0.25:
		_update_balloon_pop_triggers(cam_world)

	var render_exit_cutoff := max_render_distance + (maxf(balloon_pop_hysteresis, 0.0) if enable_balloon_pop_out else 0.0)
	_within_render_dist = (dist_to_edge <= max_render_distance) if not _within_render_dist else (dist_to_edge <= render_exit_cutoff)
	_specialists_active = dist_to_edge <= specialist_active_distance

	var new_hitboxes := dist_to_edge <= hitbox_active_distance
	if new_hitboxes != _hitboxes_within_dist:
		_hitboxes_within_dist = new_hitboxes
		_sync_vat_hitboxes()

	var shadow_cutoff := max_render_distance if keep_front_row_shadow else shadow_active_distance
	var new_shadows := dist_to_edge <= (shadow_cutoff + 2.0)
	if new_shadows != _shadows_active:
		_shadows_active = new_shadows
		_apply_vat_shadow_state()

	var outline_cutoff := max_render_distance if keep_front_row_outline else outline_active_distance
	var new_outlines := dist_to_edge <= (outline_cutoff + 2.0)
	if new_outlines != _outlines_active:
		_outlines_active = new_outlines
		for mm_inst in _all_vat_mm_instances():
			if mm_inst.material_override is ShaderMaterial:
				var mat := mm_inst.material_override as ShaderMaterial
				if new_outlines and _cached_next_passes.has(mat):
					mat.next_pass = _cached_next_passes[mat]
				elif not new_outlines and mat.next_pass != null:
					_cached_next_passes[mat] = mat.next_pass
					mat.next_pass = null

	if not (_last_lod_ref_pos is Vector3) or cam_world.distance_squared_to(_last_lod_ref_pos) > 0.0025:
		_sync_lod_shader_uniforms(cam_world)

	if (keep_front_row_outline or keep_front_row_shadow) and (not (_last_front_cam_pos is Vector3) or cam_world.distance_squared_to(_last_front_cam_pos) > 0.25):
		_update_front_row_mask(cam_world)


func _sync_specialist_vat_clocks() -> void:
	for mm_inst in [
		_vat_variants[3].get("mm_inst") if _vat_variants.size() > 3 else null,
		_gun_prop_variant.get("mm_inst"),
		_vat_variants[4].get("mm_inst") if _vat_variants.size() > 4 else null,
	]:
		if not (mm_inst is MultiMeshInstance3D):
			continue
		var mat := (mm_inst as MultiMeshInstance3D).material_override as ShaderMaterial
		if not mat:
			continue
		mat.set_shader_parameter("vat_time_override", _vat_clock)
		var next_mat := mat.next_pass as ShaderMaterial
		if next_mat:
			next_mat.set_shader_parameter("vat_time_override", _vat_clock)
	for v_idx in [3, 4]:
		if _vat_variants.size() > v_idx and not _vat_variants[v_idx].is_empty():
			var shadow_mat := _vat_variants[v_idx].get("shadow_mat") as ShaderMaterial
			if shadow_mat:
				shadow_mat.set_shader_parameter("vat_time_override", _vat_clock)


func _has_active_vat_gunners() -> bool:
	return _vat_variants.size() > 3 and not _vat_variants[3].is_empty() and bool(_vat_variants[3].get("active", false)) and not (_vat_variants[3]["transforms"] as Array).is_empty()


func _has_active_vat_ballooners() -> bool:
	return _vat_variants.size() > 4 and not _vat_variants[4].is_empty() and bool(_vat_variants[4].get("active", false)) and not (_vat_variants[4]["transforms"] as Array).is_empty()


func _reset_active_vat_actions() -> void:
	for act in _active_vat_actions:
		var hb: Node3D = act.get("hand_balloon")
		if is_instance_valid(hb):
			hb.visible = false
	_active_vat_actions.clear()
	for hb in _hand_balloon_pool:
		if is_instance_valid(hb):
			hb.visible = false


func _vec3_from_json(arr: Variant, fallback: Vector3) -> Vector3:
	if arr is Array and (arr as Array).size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback


func _quat_from_json(arr: Variant, fallback: Quaternion) -> Quaternion:
	if arr is Array and (arr as Array).size() >= 4:
		return Quaternion(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3])).normalized()
	return fallback


func _compute_target_local_yaw(inst_local_origin: Vector3, world_target_pos: Vector3, fallback_yaw: float) -> float:
	var world_pos := global_transform * inst_local_origin
	var world_dir := world_target_pos - world_pos
	world_dir.y = 0.0
	var local_dir := global_transform.basis.inverse() * world_dir
	local_dir.y = 0.0
	if local_dir.length_squared() < 0.001:
		return fallback_yaw
	return Basis.looking_at(local_dir.normalized(), Vector3.UP).get_euler().y


func _trigger_vat_gun_shot() -> void:
	var v: Dictionary = _vat_variants[3]
	var idle_states: Array[Dictionary] = v["idle_states"]
	var transforms: Array[Transform3D] = v["transforms"]
	var candidates: Array[int] = []
	for i in range(idle_states.size()):
		if not _specialists_active or not bool(idle_states[i]["busy"]):
			candidates.append(i)
	if candidates.is_empty():
		return

	var inst_idx := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var world_pos := (global_transform * transforms[inst_idx]).origin
	var target_pos := _pick_random_crowd_target(world_pos, 3, inst_idx)

	var clips: Dictionary = v["clips"]
	var shot_clip: Dictionary = clips.get("gun_shot", {})
	if not _specialists_active or shot_clip.is_empty():
		var muzzle_pos := world_pos + Vector3(0.0, 1.25, 0.0)
		projectile_spawn_requested.emit("gun", muzzle_pos, target_pos, inst_idx)
		var aim_dir := target_pos - muzzle_pos
		var muzzle_xf := Transform3D(Basis.looking_at(aim_dir.normalized(), Vector3.UP) if aim_dir.length_squared() > 0.001 else Basis.IDENTITY, muzzle_pos)
		_spawn_water_gun_vfx_world(muzzle_xf, muzzle_pos, target_pos)
		return

	var prop_clips: Dictionary = _gun_prop_variant.get("clips", {})
	var prop_shot_clip: Dictionary = prop_clips.get("gun_shot", shot_clip)
	var state: Dictionary = idle_states[inst_idx]
	state["busy"] = true

	var fps := float((v["meta"] as Dictionary).get("fps", 24.0))
	var idle_local := fposmod((_vat_clock + float(state["phase"])) * fps, maxf(float(state["frame_count"]), 1.0))
	var snap_body := float(state["start_frame"]) + clampf(idle_local, 0.0, maxf(float(state["frame_count"]) - 1.001, 0.0))
	var snap_prop := float(state["prop_start_frame"]) + clampf(idle_local, 0.0, maxf(float(state["prop_frame_count"]) - 1.001, 0.0))

	var duration := maxf(float(shot_clip.get("duration", 4.0)), 0.15)
	var crossfade := minf(vat_crossfade_duration, duration * 0.25)
	var start_yaw := float(state["cur_yaw"])
	var target_yaw := _compute_target_local_yaw(state["origin"] as Vector3, target_pos, start_yaw)

	var spawn_event: Dictionary = shot_clip.get("spawn_event", {})
	var fire_time := clampf(float(spawn_event.get("time", 3.44)), 0.05, duration)
	var local_muzzle_pos := _vec3_from_json(spawn_event.get("pos"), Vector3(0.0, 1.25, -0.5))
	var bx := _vec3_from_json(spawn_event.get("basis_x"), Vector3.RIGHT)
	var by := _vec3_from_json(spawn_event.get("basis_y"), Vector3.UP)
	var bz := _vec3_from_json(spawn_event.get("basis_z"), Vector3.BACK)
	var local_muzzle_basis := Basis(bx, by, bz).orthonormalized()

	_active_vat_actions.append({
		"type": "gun",
		"variant_id": 3,
		"inst_idx": inst_idx,
		"elapsed": 0.0,
		"duration": duration,
		"total_time": duration,
		"crossfade": crossfade,
		"fps": fps,
		"action_start": float(shot_clip.get("start_frame", 0)),
		"action_count": maxf(float(shot_clip.get("frame_count", 2)), 2.0),
		"prop_action_start": float(prop_shot_clip.get("start_frame", 0)),
		"prop_action_count": maxf(float(prop_shot_clip.get("frame_count", 2)), 2.0),
		"snap_body": snap_body,
		"snap_prop": snap_prop,
		"start_yaw": start_yaw,
		"target_yaw": target_yaw,
		"return_yaw": target_yaw,
		"return_start_time": duration + 1.0,
		"turn_duration": maxf(vat_turn_duration, 0.05),
		"fire_time": fire_time,
		"fired": false,
		"anim_handed_back": false,
		"target_pos": target_pos,
		"local_muzzle_pos": local_muzzle_pos,
		"local_muzzle_basis": local_muzzle_basis,
	})


func _trigger_vat_balloon_throw() -> void:
	var v: Dictionary = _vat_variants[4]
	var idle_states: Array[Dictionary] = v["idle_states"]
	var transforms: Array[Transform3D] = v["transforms"]
	var candidates: Array[int] = []
	for i in range(idle_states.size()):
		if not _specialists_active or not bool(idle_states[i]["busy"]):
			candidates.append(i)
	if candidates.is_empty():
		return

	var inst_idx := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var world_pos := (global_transform * transforms[inst_idx]).origin
	var target_pos := _pick_random_crowd_target(world_pos, 4, inst_idx)

	if not _specialists_active:
		var throw_pos := world_pos + Vector3(0.0, 1.35, 0.0)
		projectile_spawn_requested.emit("balloon", throw_pos, target_pos, inst_idx)
		_spawn_balloon_projectile(throw_pos, target_pos)
		return

	var clips: Dictionary = v["clips"]
	var throw_clip: Dictionary = clips.get("balloon_throw", {})
	if throw_clip.is_empty():
		var throw_pos := world_pos + Vector3(0.0, 1.35, 0.0)
		projectile_spawn_requested.emit("balloon", throw_pos, target_pos, inst_idx)
		_spawn_balloon_projectile(throw_pos, target_pos)
		return

	var state: Dictionary = idle_states[inst_idx]
	state["busy"] = true

	var fps := float((v["meta"] as Dictionary).get("fps", 24.0))
	var idle_local := fposmod((_vat_clock + float(state["phase"])) * fps, maxf(float(state["frame_count"]), 1.0))
	var snap_body := float(state["start_frame"]) + clampf(idle_local, 0.0, maxf(float(state["frame_count"]) - 1.001, 0.0))

	var duration := maxf(float(throw_clip.get("duration", 2.5)), 0.15)
	var crossfade := minf(vat_crossfade_duration, duration * 0.25)
	var turn_dur := maxf(vat_turn_duration, 0.05)
	var start_yaw := float(state["cur_yaw"])
	var base_yaw := float(state["base_yaw"])
	var target_yaw := _compute_target_local_yaw(state["origin"] as Vector3, target_pos, start_yaw)

	var release_time := clampf(float(throw_clip.get("release_time", 1.80)), 0.05, duration)
	var local_release_pos := _vec3_from_json(throw_clip.get("release_pos"), Vector3(0.0, 1.45, -0.35))
	var hand_positions_raw: Array = throw_clip.get("hand_positions", [])
	var hand_positions: PackedVector3Array = PackedVector3Array()
	for entry in hand_positions_raw:
		hand_positions.append(_vec3_from_json(entry, local_release_pos))
	var hand_rotations_raw: Array = throw_clip.get("hand_rotations", [])
	var hand_rotations: Array[Quaternion] = []
	for entry in hand_rotations_raw:
		hand_rotations.append(_quat_from_json(entry, Quaternion.IDENTITY))
	var hand_scale := _vec3_from_json(throw_clip.get("hand_scale"), Vector3.ONE)

	var balloon_idle_clip: Dictionary = clips.get("balloon_idle", {})
	var has_balloon_idle := not balloon_idle_clip.is_empty()
	var b_idle_start := float(balloon_idle_clip.get("start_frame", state["start_frame"]))
	var b_idle_count := maxf(float(balloon_idle_clip.get("frame_count", state["frame_count"])), 1.0)
	var hand_balloon := _acquire_hand_balloon()

	_active_vat_actions.append({
		"type": "balloon",
		"phase": "throw",
		"variant_id": 4,
		"inst_idx": inst_idx,
		"elapsed": 0.0,
		"wait_elapsed": 0.0,
		"return_elapsed": 0.0,
		"duration": duration,
		"total_time": duration,
		"crossfade": crossfade,
		"fps": fps,
		"action_start": float(throw_clip.get("start_frame", 0)),
		"action_count": maxf(float(throw_clip.get("frame_count", 2)), 2.0),
		"b_idle_start": b_idle_start,
		"b_idle_count": b_idle_count,
		"has_balloon_idle": has_balloon_idle,
		"b_idle_phase": 0.0,
		"snap_body": snap_body,
		"snap_wait": b_idle_start,
		"start_yaw": start_yaw,
		"target_yaw": target_yaw,
		"return_yaw": base_yaw,
		"turn_duration": turn_dur,
		"release_time": release_time,
		"released": false,
		"exploded": false,
		"anim_handed_back": false,
		"target_pos": target_pos,
		"local_release_pos": local_release_pos,
		"hand_positions": hand_positions,
		"hand_rotations": hand_rotations,
		"hand_scale": hand_scale,
		"hand_balloon": hand_balloon,
	})


func _update_vat_actions(delta: float) -> void:
	if _active_vat_actions.is_empty():
		return

	var prop_mm: MultiMesh = _gun_prop_variant.get("mm") if _gun_prop_variant.get("active", false) else null
	var i := _active_vat_actions.size() - 1
	while i >= 0:
		var act: Dictionary = _active_vat_actions[i]
		var v_idx: int = act["variant_id"]
		var inst_idx: int = act["inst_idx"]
		var v: Dictionary = _vat_variants[v_idx]
		var mm: MultiMesh = v.get("mm")
		var idle_states: Array[Dictionary] = v.get("idle_states", [])
		var transforms: Array[Transform3D] = v.get("transforms", [])

		if not mm or inst_idx < 0 or inst_idx >= idle_states.size():
			var orphan_hb: Node3D = act.get("hand_balloon")
			if is_instance_valid(orphan_hb):
				orphan_hb.visible = false
			_active_vat_actions.remove_at(i)
			i -= 1
			continue

		var state: Dictionary = idle_states[inst_idx]
		var elapsed: float = float(act["elapsed"]) + delta
		act["elapsed"] = elapsed

		var duration: float = act["duration"]
		var crossfade: float = act["crossfade"]
		var turn_dur: float = act["turn_duration"]
		var is_gun: bool = (act["type"] == "gun")
		var fps: float = act["fps"]
		var is_front: bool = bool(state.get("is_front", false))
		var front_offset: float = 10.0 if is_front else 0.0
		var tex_idx: float = float(state["tex_idx"]) + front_offset
		var idle_start: float = float(state["start_frame"])
		var idle_count: float = maxf(float(state["frame_count"]), 1.0)
		var inst_scale := float(state["scale"])

		if is_gun:
			var cur_yaw: float = float(act["target_yaw"])
			if elapsed < turn_dur:
				var t := sin(clampf(elapsed / turn_dur, 0.0, 1.0) * PI * 0.5)
				var diff := wrapf(float(act["target_yaw"]) - float(act["start_yaw"]), -PI, PI)
				cur_yaw = float(act["start_yaw"]) + diff * t

			state["cur_yaw"] = cur_yaw
			var new_xform := Transform3D(Basis(Vector3.UP, cur_yaw).scaled(Vector3(inst_scale, inst_scale, inst_scale)), state["origin"] as Vector3)
			transforms[inst_idx] = new_xform
			var popped_xform := new_xform.scaled_local(_get_member_pop_scale(v, inst_idx))
			mm.set_instance_transform(inst_idx, popped_xform)
			if prop_mm:
				prop_mm.set_instance_transform(inst_idx, popped_xform)

			var prop_idle_start: float = float(state.get("prop_start_frame", idle_start))
			var prop_idle_count: float = maxf(float(state.get("prop_frame_count", idle_count)), 1.0)

			if elapsed < duration:
				var norm_t := clampf(elapsed / duration, 0.0, 1.0)
				var action_count: float = act["action_count"]
				var body_action_f: float = float(act["action_start"]) + clampf(norm_t * (action_count - 1.0), 0.0, maxf(action_count - 1.001, 0.0))
				var prop_action_f := 0.0
				if prop_mm:
					var prop_action_count: float = act["prop_action_count"]
					prop_action_f = float(act["prop_action_start"]) + clampf(norm_t * (prop_action_count - 1.0), 0.0, maxf(prop_action_count - 1.001, 0.0))

				if elapsed < crossfade:
					var w := clampf(elapsed / maxf(crossfade, 0.001), 0.0, 1.0)
					mm.set_instance_custom_data(inst_idx, Color(body_action_f, -(float(act["snap_body"]) + 1.0), w, tex_idx))
					if prop_mm:
						prop_mm.set_instance_custom_data(inst_idx, Color(prop_action_f, -(float(act["snap_prop"]) + 1.0), w, front_offset))
				elif elapsed >= duration - crossfade:
					var out_elapsed := elapsed - (duration - crossfade)
					var out_w := clampf(out_elapsed / maxf(crossfade, 0.001), 0.0, 1.0)
					var idle_out_local := fposmod(out_elapsed * fps, idle_count)
					var body_idle_f := idle_start + clampf(idle_out_local, 0.0, maxf(idle_count - 1.001, 0.0))
					mm.set_instance_custom_data(inst_idx, Color(body_idle_f, -(body_action_f + 1.0), out_w, tex_idx))
					if prop_mm:
						var prop_idle_local := fposmod(out_elapsed * fps, prop_idle_count)
						var prop_idle_f := prop_idle_start + clampf(prop_idle_local, 0.0, maxf(prop_idle_count - 1.001, 0.0))
						prop_mm.set_instance_custom_data(inst_idx, Color(prop_idle_f, -(prop_action_f + 1.0), out_w, front_offset))
				else:
					mm.set_instance_custom_data(inst_idx, Color(body_action_f, -1.0, 1.0, tex_idx))
					if prop_mm:
						prop_mm.set_instance_custom_data(inst_idx, Color(prop_action_f, -1.0, 1.0, front_offset))

			if not bool(act["fired"]) and elapsed >= float(act["fire_time"]):
				act["fired"] = true
				var inst_world := global_transform * new_xform
				var world_muzzle_pos := inst_world * (act["local_muzzle_pos"] as Vector3)
				var world_muzzle_basis := (inst_world.basis * (act["local_muzzle_basis"] as Basis)).orthonormalized()
				var target_pos: Vector3 = act["target_pos"]
				projectile_spawn_requested.emit("gun", world_muzzle_pos, target_pos, inst_idx)
				_spawn_water_gun_vfx_world(Transform3D(world_muzzle_basis, world_muzzle_pos), world_muzzle_pos, target_pos)

			if elapsed >= duration:
				var new_phase := crossfade - _vat_clock
				state["phase"] = new_phase
				mm.set_instance_custom_data(inst_idx, Color(idle_start, idle_count, new_phase, tex_idx))
				if prop_mm:
					prop_mm.set_instance_custom_data(inst_idx, Color(prop_idle_start, prop_idle_count, new_phase, front_offset))
				state["cur_yaw"] = wrapf(float(act["target_yaw"]), -PI, PI)
				state["busy"] = false
				_active_vat_actions.remove_at(i)
		else:
			# Ballooner 3-stage flow: "throw" -> "wait_explosion" (Balloone Zombie Idle -loop) -> "return_to_dance"
			var phase_name: String = act["phase"]
			var cur_yaw: float = float(act["target_yaw"])
			if phase_name == "throw" and elapsed < turn_dur:
				var t := sin(clampf(elapsed / turn_dur, 0.0, 1.0) * PI * 0.5)
				var diff := wrapf(float(act["target_yaw"]) - float(act["start_yaw"]), -PI, PI)
				cur_yaw = float(act["start_yaw"]) + diff * t
			elif phase_name == "return_to_dance":
				var r_elapsed: float = float(act["return_elapsed"]) + delta
				act["return_elapsed"] = r_elapsed
				var bt := sin(clampf(r_elapsed / turn_dur, 0.0, 1.0) * PI * 0.5)
				var bdiff := wrapf(float(act["return_yaw"]) - float(act["target_yaw"]), -PI, PI)
				cur_yaw = float(act["target_yaw"]) + bdiff * bt

			state["cur_yaw"] = cur_yaw
			var new_xform := Transform3D(Basis(Vector3.UP, cur_yaw).scaled(Vector3(inst_scale, inst_scale, inst_scale)), state["origin"] as Vector3)
			transforms[inst_idx] = new_xform
			mm.set_instance_transform(inst_idx, new_xform.scaled_local(_get_member_pop_scale(v, inst_idx)))

			var b_idle_start: float = act["b_idle_start"]
			var b_idle_count: float = act["b_idle_count"]
			var has_b_idle: bool = act["has_balloon_idle"]

			if phase_name == "throw":
				var norm_t := clampf(elapsed / duration, 0.0, 1.0)
				var action_count: float = act["action_count"]
				var body_action_f: float = float(act["action_start"]) + clampf(norm_t * (action_count - 1.0), 0.0, maxf(action_count - 1.001, 0.0))

				if elapsed < crossfade:
					var w := clampf(elapsed / maxf(crossfade, 0.001), 0.0, 1.0)
					mm.set_instance_custom_data(inst_idx, Color(body_action_f, -(float(act["snap_body"]) + 1.0), w, tex_idx))
				elif elapsed >= duration - crossfade and has_b_idle:
					var out_elapsed := elapsed - (duration - crossfade)
					var out_w := clampf(out_elapsed / maxf(crossfade, 0.001), 0.0, 1.0)
					var wait_local := fposmod(out_elapsed * fps, b_idle_count)
					var wait_f := b_idle_start + clampf(wait_local, 0.0, maxf(b_idle_count - 1.001, 0.0))
					mm.set_instance_custom_data(inst_idx, Color(wait_f, -(body_action_f + 1.0), out_w, tex_idx))
				else:
					mm.set_instance_custom_data(inst_idx, Color(body_action_f, -1.0, 1.0, tex_idx))

				var hb: Node3D = act.get("hand_balloon")
				if not bool(act["released"]):
					if elapsed >= float(act["release_time"]):
						act["released"] = true
						if is_instance_valid(hb):
							hb.visible = false
						act["hand_balloon"] = null
						var world_release_pos := (global_transform * new_xform) * (act["local_release_pos"] as Vector3)
						var target_pos: Vector3 = act["target_pos"]
						projectile_spawn_requested.emit("balloon", world_release_pos, target_pos, inst_idx)
						_spawn_balloon_projectile(world_release_pos, target_pos, func():
							act["exploded"] = true
						)
					elif is_instance_valid(hb):
						if elapsed < crossfade * 0.5:
							hb.visible = false
						else:
							var hp: PackedVector3Array = act["hand_positions"]
							var hr: Array[Quaternion] = act["hand_rotations"]
							var h_scale: Vector3 = act["hand_scale"]
							var local_hand := act["local_release_pos"] as Vector3
							var local_rot := Quaternion.IDENTITY
							if not hp.is_empty():
								var f_float := norm_t * float(hp.size() - 1)
								var f0 := clampi(int(floorf(f_float)), 0, hp.size() - 1)
								var f1 := mini(f0 + 1, hp.size() - 1)
								var frac: float = f_float - floorf(f_float)
								local_hand = hp[f0].lerp(hp[f1], frac)
								if f1 < hr.size():
									local_rot = hr[f0].slerp(hr[f1], frac)
							hb.global_transform = (global_transform * new_xform) * Transform3D(Basis(local_rot).scaled(h_scale), local_hand)
							hb.visible = true

				if elapsed >= duration:
					if bool(act["exploded"]) or not has_b_idle:
						act["phase"] = "return_to_dance"
						act["return_elapsed"] = 0.0
						act["snap_wait"] = b_idle_start if has_b_idle else (float(act["action_start"]) + maxf(action_count - 1.001, 0.0))
					else:
						act["phase"] = "wait_explosion"
						act["wait_elapsed"] = 0.0
						var b_phase := crossfade - _vat_clock
						act["b_idle_phase"] = b_phase
						mm.set_instance_custom_data(inst_idx, Color(b_idle_start, b_idle_count, b_phase, tex_idx))
			elif phase_name == "wait_explosion":
				var wait_elapsed: float = float(act["wait_elapsed"]) + delta
				act["wait_elapsed"] = wait_elapsed
				# Transition back to dance only after balloon explodes (or safety timeout)
				if bool(act["exploded"]) or wait_elapsed >= 10.0:
					var b_local := fposmod((_vat_clock + float(act["b_idle_phase"])) * fps, b_idle_count)
					act["snap_wait"] = b_idle_start + clampf(b_local, 0.0, maxf(b_idle_count - 1.001, 0.0))
					act["phase"] = "return_to_dance"
					act["return_elapsed"] = 0.0
			else:
				# "return_to_dance"
				var r_elapsed: float = float(act["return_elapsed"])
				var finish_dur := maxf(crossfade, turn_dur)
				if r_elapsed <= crossfade:
					var w := clampf(r_elapsed / maxf(crossfade, 0.001), 0.0, 1.0)
					var d_local := fposmod(r_elapsed * fps, idle_count)
					var d_f := idle_start + clampf(d_local, 0.0, maxf(idle_count - 1.001, 0.0))
					mm.set_instance_custom_data(inst_idx, Color(d_f, -(float(act["snap_wait"]) + 1.0), w, tex_idx))
				elif not bool(act["anim_handed_back"]):
					act["anim_handed_back"] = true
					var new_phase := crossfade - _vat_clock
					state["phase"] = new_phase
					mm.set_instance_custom_data(inst_idx, Color(idle_start, idle_count, new_phase, tex_idx))

				if r_elapsed >= finish_dur:
					if not bool(act["anim_handed_back"]):
						var new_phase := crossfade - _vat_clock
						state["phase"] = new_phase
						mm.set_instance_custom_data(inst_idx, Color(idle_start, idle_count, new_phase, tex_idx))
					state["cur_yaw"] = wrapf(float(act["return_yaw"]), -PI, PI)
					state["busy"] = false
					_active_vat_actions.remove_at(i)

		i -= 1


func _spawn_water_gun_vfx_world(muzzle_world_xform: Transform3D, muzzle_pos: Vector3, target_pos: Vector3) -> void:
	var cur_muzzle_scale := Vector3(0.2, 0.2, 0.2)
	var cur_impact_scale := Vector3(0.4, 0.4, 0.4)

	var muzzle_vfx := _get_pooled_node(_muzzle_vfx_pool, "_muzzle_vfx_idx")
	if muzzle_vfx:
		muzzle_vfx.global_transform = muzzle_world_xform
		muzzle_vfx.scale = cur_muzzle_scale
		muzzle_vfx.visible = true
		_trigger_vfx_node(muzzle_vfx, "Muzzle")
		_hide_after_delay(muzzle_vfx, 1.2)

	var line := _get_pooled_node(_water_line_pool, "_water_line_idx")
	if line and line.has_method("set_line"):
		line.visible = true
		line.set_line(muzzle_pos, target_pos)

	var hit_vfx := _get_pooled_node(_hit_vfx_pool, "_hit_vfx_idx")
	if hit_vfx:
		_place_hit_vfx(hit_vfx, muzzle_pos, target_pos, cur_impact_scale)
		_trigger_vfx_node(hit_vfx, "Muzzle")
		_hide_after_delay(hit_vfx, 1.2)

	_apply_splash_hits_to_dancers(target_pos, 1.2)


func _place_hit_vfx(hit_vfx: Node3D, muzzle_pos: Vector3, target_pos: Vector3, impact_scale: Vector3) -> void:
	var shot_normal := muzzle_pos - target_pos
	shot_normal.y = 0.0
	shot_normal = shot_normal.normalized() if shot_normal.length_squared() > 0.001 else Vector3.BACK
	hit_vfx.global_position = target_pos + shot_normal * 0.25
	var up_dir := Vector3.UP if absf(shot_normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	hit_vfx.look_at(hit_vfx.global_position + shot_normal, up_dir)
	hit_vfx.scale = impact_scale
	hit_vfx.visible = true


func _spawn_balloon_projectile(throw_pos: Vector3, target_pos: Vector3, on_exploded: Callable = Callable()) -> void:
	var balloon := _get_pooled_balloon()
	if not balloon:
		if on_exploded.is_valid():
			on_exploded.call()
		return
	balloon.global_position = throw_pos
	if balloon.has_method("launch_pooled"):
		balloon.launch_pooled(target_pos, 0.0, 2.0, 2.5, 1.2, func(splash_pos: Vector3):
			_apply_splash_hits_to_dancers(splash_pos, 2.2)
			if on_exploded.is_valid():
				on_exploded.call()
		)
	elif on_exploded.is_valid():
		on_exploded.call()


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
	_init_hand_balloon_pool()


func _init_hand_balloon_pool() -> void:
	if not balloon_scene:
		return
	for _i in range(balloon_pool_size):
		var inst := balloon_scene.instantiate() as Node3D
		if not inst:
			continue
		inst.visible = false
		if inst is RigidBody3D:
			var rb := inst as RigidBody3D
			rb.freeze = true
			rb.collision_layer = 0
			rb.collision_mask = 0
		if "trail_particles" in inst:
			inst.trail_particles = null
		if "splash_particles" in inst:
			inst.splash_particles = null
		for child in inst.find_children("*", "GPUParticles3D", true, false):
			child.queue_free()
		for col in inst.find_children("*", "CollisionShape3D", true, false):
			col.queue_free()
		_pool_container.add_child(inst)
		inst.owner = null
		inst.set_process(false)
		inst.set_physics_process(false)
		_hand_balloon_pool.append(inst)


func _acquire_hand_balloon() -> Node3D:
	for b in _hand_balloon_pool:
		if is_instance_valid(b) and not b.visible:
			return b
	return null


func _populate_pool(scene: PackedScene, count: int, out_pool: Array[Node3D]) -> void:
	if not scene:
		return
	for _i in range(count):
		var inst := scene.instantiate() as Node3D
		if not inst:
			continue
		if "auto_free_on_play" in inst:
			inst.set("auto_free_on_play", false)
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
	if not tree or not is_instance_valid(node):
		return
	var serial := int(node.get_meta("_hide_serial", 0)) + 1
	node.set_meta("_hide_serial", serial)
	tree.create_timer(delay).timeout.connect(func():
		if is_instance_valid(node) and int(node.get_meta("_hide_serial", 0)) == serial:
			node.visible = false
	)


func _pick_random_crowd_target(from_pos: Vector3, exclude_variant: int = -1, exclude_inst: int = -1) -> Vector3:
	var candidates: Array[Vector3] = []
	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if v.is_empty() or not v.get("active", false):
			continue
		var transforms: Array[Transform3D] = v["transforms"]
		for i in range(transforms.size()):
			if v_idx == exclude_variant and i == exclude_inst:
				continue
			var world_pos := (global_transform * transforms[i]).origin
			var dx := world_pos.x - from_pos.x
			var dz := world_pos.z - from_pos.z
			if dx * dx + dz * dz < 0.25:
				continue
			candidates.append(world_pos + Vector3(0.0, 1.0, 0.0))
	if not candidates.is_empty():
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
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
	var hit_col := Color(new_decay, angle_norm, y_norm, x_norm)
	mm.set_instance_color(instance_idx, hit_col)
	if variant_id == 3 and _gun_prop_variant.get("active", false):
		var prop_mm: MultiMesh = _gun_prop_variant.get("mm")
		if prop_mm and instance_idx < prop_mm.instance_count:
			prop_mm.set_instance_color(instance_idx, hit_col)


func _step_vat_hit_dict(hits_dict: Dictionary, mm: MultiMesh, step: float, mirror_mm: MultiMesh = null) -> void:
	if hits_dict.is_empty() or not mm:
		return
	var finished: Array[int] = []
	for idx in hits_dict.keys():
		var h: Dictionary = hits_dict[idx]
		h["decay"] = maxf(0.0, h["decay"] - step)
		var col := Color(h["decay"], h["angle"], h["y_norm"], h["x_norm"])
		mm.set_instance_color(idx, col)
		if mirror_mm and idx < mirror_mm.instance_count:
			mirror_mm.set_instance_color(idx, col)
		if h["decay"] <= 0.0:
			finished.append(idx)
	for idx in finished:
		hits_dict.erase(idx)


func _update_hit_reactions(delta: float) -> void:
	var step := delta / maxf(hit_reaction_duration, 0.05)
	var prop_mm: MultiMesh = _gun_prop_variant.get("mm") if _gun_prop_variant.get("active", false) else null
	for v_idx in range(_vat_variants.size()):
		var v: Dictionary = _vat_variants[v_idx]
		if not v.is_empty():
			_step_vat_hit_dict(v["hits"], v["mm"], step, prop_mm if v_idx == 3 else null)


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
	area.monitoring = monitor_physics_projectiles
	area.monitorable = true


func _sync_invisible_wall() -> void:
	var internal_mode := Node.INTERNAL_MODE_BACK if Engine.is_editor_hint() else Node.INTERNAL_MODE_DISABLED
	var wall := _find_internal_child(self, "InvisibleWall") as StaticBody3D
	if not enable_invisible_wall:
		if is_instance_valid(wall):
			var existing_col := _find_internal_child(wall, "CollisionShape3D") as CollisionShape3D
			if existing_col:
				existing_col.disabled = true
		return

	if not is_instance_valid(wall):
		wall = StaticBody3D.new()
		wall.name = "InvisibleWall"
		add_child(wall, false, internal_mode)
		if not Engine.is_editor_hint():
			wall.owner = null

	wall.collision_layer = invisible_wall_layer
	wall.collision_mask = 0
	wall.position = Vector3(0.0, invisible_wall_height * 0.5, 0.0)

	var col := _find_internal_child(wall, "CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		col = _find_internal_child(wall, "InvisibleWall") as CollisionShape3D
	if not is_instance_valid(col):
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		wall.add_child(col, false, internal_mode)
		if not Engine.is_editor_hint():
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
			_sync_vat_material_meta(v.get("mm_inst"), v.get("meta", {}), v.get("shadow_mat"))
	if not _gun_prop_variant.is_empty():
		_sync_vat_material_meta(_gun_prop_variant.get("mm_inst"), _gun_prop_variant.get("meta", {}))
	_sync_hit_reaction_params()
	_sync_lod_uniforms_only()


func _sync_vat_material_meta(mm_inst: MultiMeshInstance3D, meta: Dictionary, shadow_mat: ShaderMaterial = null) -> void:
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
	if Engine.is_editor_hint():
		mat.set_shader_parameter("vat_time_override", -1.0)
	var next_mat := mat.next_pass as ShaderMaterial
	if not next_mat and _cached_next_passes.has(mat):
		next_mat = _cached_next_passes[mat] as ShaderMaterial
	if next_mat:
		_cached_next_passes[mat] = next_mat
		next_mat.set_shader_parameter("vat_tex_width", tex_w)
		next_mat.set_shader_parameter("vat_rows_per_frame", rows)
		next_mat.set_shader_parameter("vat_fps", fps)
		if Engine.is_editor_hint():
			next_mat.set_shader_parameter("vat_time_override", -1.0)
	if shadow_mat:
		var pos_tex: Variant = mat.get_shader_parameter("vat_pos_tex")
		if pos_tex != null:
			shadow_mat.set_shader_parameter("vat_pos_tex", pos_tex)
		shadow_mat.set_shader_parameter("vat_tex_width", tex_w)
		shadow_mat.set_shader_parameter("vat_rows_per_frame", rows)
		shadow_mat.set_shader_parameter("vat_fps", fps)
		if Engine.is_editor_hint():
			shadow_mat.set_shader_parameter("vat_time_override", -1.0)


func _sync_hit_reaction_params() -> void:
	for mm_inst in _all_vat_mm_instances():
		var mat := mm_inst.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
			mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
			mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
			var next_mat := mat.next_pass as ShaderMaterial
			if not next_mat and _cached_next_passes.has(mat):
				next_mat = _cached_next_passes[mat] as ShaderMaterial
			if next_mat:
				next_mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
				next_mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
				next_mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
	for v in _vat_variants:
		if not v.is_empty():
			var shadow_mat := v.get("shadow_mat") as ShaderMaterial
			if shadow_mat:
				shadow_mat.set_shader_parameter("hit_bend_strength", hit_bend_strength)
				shadow_mat.set_shader_parameter("hit_zone_radius", hit_zone_radius)
				shadow_mat.set_shader_parameter("hit_oscillation_freq", hit_oscillation_freq)
