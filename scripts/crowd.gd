@tool
extends Node3D

enum CrowdRow { FRONT = 0, MIDDLE = 1, BACK = 2 }

# ─── Exported Properties & Toggles ──────────────────────────────────────────

@export_group("Editor Preview")
@export var preview_in_editor: bool = true: ## Toggle to show or hide the live crowd preview in the Godot 3D editor
	set(val):
		if preview_in_editor == val:
			return
		preview_in_editor = val
		if Engine.is_editor_hint() and is_inside_tree() and is_node_ready():
			if preview_in_editor:
				_setup_crowd()
				_apply_editor_performance_mode()
			else:
				_clear_preview_crowd()
@export var editor_performance_mode: bool = true: ## In-editor only performance mode: freezes preview animations at 50% and turns off cast shadows to eliminate editor lag. Does not affect running game!
	set(val):
		editor_performance_mode = val
		if is_inside_tree() and is_node_ready():
			_apply_editor_performance_mode()

@export_group("Crowd Spawning")
@export var spawn_area_size: Vector3 = Vector3(10, 2, 3): ## Size of the spawn area box (X: Width, Y: Height, Z: Depth). Automatically updates the shape in the editor!
	set(val):
		if spawn_area_size == val:
			return
		spawn_area_size = val
		if is_inside_tree() and is_node_ready():
			_update_spawn_shapes()
			_on_setting_changed()
@export var sync_invisible_wall: bool = true: ## Automatically sync InvisibleWall shape size with spawn_area_size
	set(val):
		sync_invisible_wall = val
		if val and is_inside_tree() and is_node_ready():
			_update_spawn_shapes()
@export var enable_spawning: bool = true:
	set(val):
		enable_spawning = val
		_on_setting_changed()
@export var use_density_mode: bool = true: ## When true, crowd count is calculated from Area3D footprint * crowd_density
	set(val):
		use_density_mode = val
		_on_setting_changed()
@export_range(0.01, 1.0, 0.01) var crowd_density: float = 0.4: ## Crowd density (members per m² of the Area3D box footprint)
	set(val):
		crowd_density = val
		_on_setting_changed()
@export_range(1, 40, 1) var max_crowd_members: int = 25: ## Hard safety cap on total crowd members spawned
	set(val):
		max_crowd_members = val
		_on_setting_changed()
@export_range(1, 150, 1) var crowd_count: int = 12: ## Fallback fixed count when use_density_mode is false
	set(val):
		crowd_count = val
		_on_setting_changed()
@export var min_member_spacing: float = 1.2:
	set(val):
		min_member_spacing = val
		_on_setting_changed()
@export var male_model_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model.tscn")
@export var female_model_scene: PackedScene = null  # Coming soon!
@export var enable_male_crowd: bool = true:
	set(val):
		enable_male_crowd = val
		_on_setting_changed()
@export var enable_female_crowd: bool = true:
	set(val):
		enable_female_crowd = val
		_on_setting_changed()

@export_group("Collision & Ground Snapping")
@export var enable_collision_check: bool = true:
	set(val):
		enable_collision_check = val
		_on_setting_changed()
@export var collision_mask_world: int = 1
@export var ground_snap_height: float = 0.2: ## Headroom buffer above spawn area ceiling to cast downward ray (keep small to avoid roofs)
	set(val):
		ground_snap_height = val
		_on_setting_changed()
@export var ground_snap_depth: float = 10.0: ## Depth below spawn area to search downward for ground
	set(val):
		ground_snap_depth = val
		_on_setting_changed()
@export_range(0.0, 1.0, 0.05) var ground_snap_min_normal_y: float = 0.5: ## Minimum upward normal Y to consider ground walkable
	set(val):
		ground_snap_min_normal_y = val
		_on_setting_changed()

@export_group("Performance & Culling")
@export var max_render_distance: float = 100.0: ## Distance beyond which crowd members are hidden / not rendered
	set(val):
		max_render_distance = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export var enable_occlusion_culling: bool = false ## Raycast line-of-sight occlusion test against walls/buildings
@export var enable_shadow_optimization: bool = true: ## Disable shadows on micro-meshes (fingers, flipflops, nose, etc.)
	set(val):
		enable_shadow_optimization = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export var culling_check_interval: float = 0.1 ## Interval in seconds for CPU occlusion & camera distance culling checks
@export var start_from_30_fps: bool = true ## When true, crowd members at close range animate at 30 FPS (staggered alternating frames) instead of 60 FPS, halving CPU bone calculations
@export var anim_full_fps_distance: float = 7.0: ## Distance from camera within which crowd members animate at 100% full framerate (or 30 FPS if start_from_30_fps is enabled)
	set(val):
		anim_full_fps_distance = val
@export var anim_half_fps_distance: float = 15.0: ## Distance from camera within which crowd members step at medium range (always 30 FPS)
	set(val):
		anim_half_fps_distance = val
@export var anim_far_fps_distance: float = 30.0: ## Distance up to which far-range crowd members animate (15 FPS). Beyond 30m, animations pause completely (no movement, 0 CPU cost).
	set(val):
		anim_far_fps_distance = val

@export_group("Row & Distance Architecture")
@export var enable_row_architecture: bool = true: ## Spawns crowd in 3 depth rows (front, middle, back) with row-staggered culling
	set(val):
		enable_row_architecture = val
		_on_setting_changed()
@export var front_row_max_distance: float = 80.0: ## Max render distance for front row (up to 100m)
	set(val):
		front_row_max_distance = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export var front_row_distant_visibility: bool = true: ## If true, front row remains visible beyond front_row_max_distance with animations/shadows/combat disabled
	set(val):
		front_row_distant_visibility = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export var front_row_distant_max_distance: float = 140.0: ## Distance where front row finally dither-fades out when front_row_distant_visibility is enabled
	set(val):
		front_row_distant_max_distance = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export var dither_fade_margin: float = 8.0: ## Distance margin in meters for smooth shader dithering fade-in/out
	set(val):
		dither_fade_margin = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export_range(0.1, 3.0, 0.05) var dither_fade_duration: float = 1.0: ## Time in seconds for a row to smoothly dither from 0% invisible to 100% solid opaque once triggered
	set(val):
		dither_fade_duration = val
@export var middle_row_max_distance: float = 60.0: ## Max render distance for middle row (up to 50m)
	set(val):
		middle_row_max_distance = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export var back_row_max_distance: float = 30.0: ## Max render distance for back row (up to 25m)
	set(val):
		back_row_max_distance = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export var max_front_row_members: int = 10: ## Front row cap (user limit: max 8 crowd)
	set(val):
		max_front_row_members = val
		_on_setting_changed()
@export var front_row_is_negative_z: bool = true: ## If true, front row is along -Z (Godot forward); if false, along +Z
	set(val):
		front_row_is_negative_z = val
		_on_setting_changed()
@export var enable_shader_dithering: bool = false: ## Use GPU dither fade per row (VISIBILITY_RANGE_FADE_SELF)
	set(val):
		enable_shader_dithering = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export_range(0.1, 1.0, 0.05) var activity_distance_ratio: float = 0.35 ## Fraction of row distance beyond which animation/combat pauses (35%)

@export_group("Balloon Pop Animation")
@export var enable_balloon_pop_in: bool = true ## Pop revealed crowd rows in with an elastic balloon inflation animation
@export var enable_balloon_pop_out: bool = true ## Pop hidden crowd rows out with a playful balloon deflation animation when walking away
@export var pop_distance: float = 60.0: ## Distance in meters where the crowd pops in / pops out
	set(val):
		pop_distance = val
		if is_inside_tree() and is_node_ready():
			_update_render_distances()
@export_range(0.1, 1.5, 0.05) var balloon_pop_duration: float = 0.45 ## Duration of the pop-in squash & stretch animation
@export_range(0.1, 1.5, 0.05) var balloon_pop_out_duration: float = 0.35 ## Duration of the pop-out deflation animation
@export_range(0.0, 0.2, 0.01) var balloon_pop_stagger: float = 0.04 ## Delay between each member in the row popping up/down
@export var enable_distance_density_scaling: bool = true: ## Dynamically scale crowd density from min_distance_density to max_distance_density based on distance (100m to 25m)
	set(val):
		enable_distance_density_scaling = val
		_on_setting_changed()
@export var min_distance_density: float = 0.2: ## Density at 100m distance
	set(val):
		min_distance_density = val
		_on_setting_changed()
@export var max_distance_density: float = 0.5: ## Density at 25m distance
	set(val):
		max_distance_density = val
		_on_setting_changed()
@export var enable_row_shadows: bool = true: ## Each row enables its own shadow independently based on its render distance
	set(val):
		enable_row_shadows = val
		if is_inside_tree() and is_node_ready():
			_update_shadow_state()

@export_group("Appearance & Animation")
@export var enable_random_textures: bool = true:
	set(val):
		enable_random_textures = val
		_on_setting_changed()
@export var min_same_color_distance: float = 2.5: ## Minimum distance between crowd members sharing the same shirt color
	set(val):
		min_same_color_distance = val
		_on_setting_changed()
@export var material_uv1_scale: Vector3 = Vector3(1, 1, 1):
	set(val):
		material_uv1_scale = val
		if is_inside_tree() and is_node_ready():
			_setup_materials()
@export var material_uv1_offset: Vector3 = Vector3.ZERO:
	set(val):
		material_uv1_offset = val
		if is_inside_tree() and is_node_ready():
			_setup_materials()
@export var enable_triplanar: bool = false:
	set(val):
		enable_triplanar = val
		if is_inside_tree() and is_node_ready():
			_setup_materials()
@export_range(0.1, 3.0, 0.05) var dance_animation_speed: float = 1.25: ## Speed slider for dance animations
	set(val):
		dance_animation_speed = val
		_on_setting_changed()
@export_range(0.1, 3.0, 0.05) var range_animation_speed: float = 1.75: ## Speed slider for ranged water gun reload and shot animations
	set(val):
		range_animation_speed = val
		_on_setting_changed()
@export var enable_dance_animation: bool = true:
	set(val):
		enable_dance_animation = val
		_on_setting_changed()
@export var enable_water_gun_spawn: bool = true:
	set(val):
		enable_water_gun_spawn = val
		_on_setting_changed()
@export_range(0.0, 1.0) var gun_spawn_chance: float = 0.35:
	set(val):
		gun_spawn_chance = val
		_on_setting_changed()
@export var min_gun_spacing: float = 6.0: ## Minimum distance between crowd members equipped with water guns
	set(val):
		min_gun_spacing = val
		_on_setting_changed()

@export_group("Seed & Randomization")
@export var use_custom_seed: bool = false: ## If true, crowd layout, characters, guns, and colors are 100% deterministic
	set(val):
		use_custom_seed = val
		_on_setting_changed()
@export var custom_seed: int = 0: ## Specific integer seed. Set any number to lock in a layout
	set(val):
		custom_seed = val
		_on_setting_changed()
@export var reroll_seed: bool = false: ## Toggle in the Inspector to roll a new seed and refresh the crowd
	set(value):
		if value and is_inside_tree() and is_node_ready():
			reroll()

@export_group("Layout Persistence")
@export var lock_editor_positions: bool = true: ## When true, exact positions and rotations from the editor preview are saved and restored identically in game
	set(val):
		lock_editor_positions = val
		if not val:
			saved_crowd_data.clear()
		elif saved_crowd_data.is_empty() and Engine.is_editor_hint() and is_inside_tree():
			regenerate_crowd()
@export var rebake_positions: bool = false: ## Toggle in Inspector to re-generate and bake a fresh layout from current settings
	set(val):
		if val:
			rebake()
@export_storage var saved_crowd_data: Array[Dictionary] = []

@export_group("Combat & Interaction")
@export var enable_water_gun_shooting: bool = true
@export var enable_balloon_throwing: bool = true
@export var shot_interval_min: float = 2.0
@export var shot_interval_max: float = 5.0
@export var balloon_throw_interval_min: float = 3.5
@export var balloon_throw_interval_max: float = 8.0
@export var balloon_damage: float = 0.0

@export_group("Hit Reactions")
@export var enable_hit_reaction: bool = true
@export var enable_hit_animation: bool = false
@export var enable_hit_from_player: bool = true
@export var enable_hit_from_crowd: bool = true

@export_group("Audio Settings")
@export var enable_audio: bool = true: ## Master audio toggle. If false, completely disables all sound from crowd shooting, VFX, and animations
	set(val):
		enable_audio = val
		_update_audio_settings()
@export var enable_vfx_sounds: bool = true: ## Toggle sound effects from water gun shots, beam VFX, and hit splatter
	set(val):
		enable_vfx_sounds = val
		_update_audio_settings()
@export var enable_animation_sounds: bool = true: ## Toggle sounds triggered by or associated with animations (footsteps, voice, audio tracks)
	set(val):
		enable_animation_sounds = val
		_update_audio_settings()

@export_group("Gun VFX & Customization")
@export var shot_vfx_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterLine.tscn")
@export var muzzle_vfx_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterMuzzle.tscn")
@export var hit_vfx_scene: PackedScene = preload("res://Jomp_Folder/VFX_Water/VFX2/vfx_water_splatter.tscn")
@export var muzzle_scale: Vector3 = Vector3(0.2, 0.2, 0.2)
@export var muzzle_offset: Vector3 = Vector3.ZERO
@export var impact_scale: Vector3 = Vector3(0.4, 0.4, 0.4)
@export var impact_offset: Vector3 = Vector3.ZERO
@export var muzzle_animation_name: String = "Muzzle"
@export var impact_animation_name: String = "Muzzle"

@export_group("Pooling")
@export var water_line_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterLine.tscn")
@export var balloon_scene: PackedScene = preload("res://scenes/items/water_balloon.tscn")
@export var water_line_pool_size: int = 6
@export var balloon_pool_size: int = 4

# ─── Shared Materials Cache (3 shared instances, 0 per-NPC duplicates) ─────

const MAT_BLUE: Material = preload("res://scenes/Crowds/Crowd_Material.tres")
const TEX_GREEN: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Green.png")
const TEX_PINK: Texture2D = preload("res://scenes/Crowds/Crowd_Texture_Pink.png")

static var _shared_materials: Array[Material] = []

static func get_shared_materials() -> Array[Material]:
	if _shared_materials.is_empty():
		var mat_blue = MAT_BLUE
		var mat_green = mat_blue.duplicate() as StandardMaterial3D
		mat_green.albedo_texture = TEX_GREEN
		var mat_pink = mat_blue.duplicate() as StandardMaterial3D
		mat_pink.albedo_texture = TEX_PINK
		_shared_materials = [mat_blue, mat_green, mat_pink]
	return _shared_materials

static func get_random_crowd_material() -> Material:
	var mats = get_shared_materials()
	return mats.pick_random() if mats.size() > 0 else MAT_BLUE

# ─── Runtime State ──────────────────────────────────────────────────────────

var active_members: Array[Node3D] = []
var _water_line_pool: Array[Node3D] = []
var _balloon_pool: Array[Node3D] = []
var _muzzle_vfx_pool: Array[Node3D] = []
var _hit_vfx_pool: Array[Node3D] = []
var _water_line_index: int = 0
var _balloon_index: int = 0
var _muzzle_vfx_index: int = 0
var _hit_vfx_index: int = 0
const VFX_POOL_SIZE: int = 4

var _materials_dither_active: bool = false
var _occlusion_ray_query: PhysicsRayQueryParameters3D = null
var _cached_spawn_bounds: AABB = AABB()
var _has_cached_spawn_bounds: bool = false

var _candidate_shooters: Array[CrowdMember] = []
var _candidate_targets: Array[CrowdMember] = []

var shot_timer: float = 0.0
var next_shot_time: float = 2.0
var balloon_timer: float = 0.0
var next_balloon_time: float = 4.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _visibility_notifier: VisibleOnScreenNotifier3D = null
var _culling_timer: float = 0.0
var _is_on_screen: bool = true
var _is_rendered: bool = true
var _is_occluded: bool = false
var _member_occlusion_cursor: int = 0
const MEMBER_OCCLUSION_BATCH_SIZE: int = 8
var _crowd_rids: Array[RID] = []
var _all_rows_present: bool = false
var _front_row_revealed: bool = false
var _mid_row_revealed: bool = false
var _back_row_revealed: bool = false
var _front_row_fade: float = 1.0
var _mid_row_fade: float = 1.0
var _back_row_fade: float = 1.0
var _is_beyond_front_max: bool = false
var _is_validating_physics: bool = false
var _initial_culling_done: bool = false

func are_all_rows_present() -> bool:
	return _all_rows_present

func get_row_local_z_range(row: CrowdRow) -> Vector2:
	var depth = spawn_area_size.z
	var half_d = depth * 0.5
	if front_row_is_negative_z:
		match row:
			CrowdRow.FRONT:
				return Vector2(-half_d, -half_d + depth * 0.35)
			CrowdRow.MIDDLE:
				return Vector2(-half_d + depth * 0.35, -half_d + depth * 0.70)
			CrowdRow.BACK:
				return Vector2(-half_d + depth * 0.70, half_d)
			_:
				return Vector2(-half_d, half_d)
	else:
		match row:
			CrowdRow.FRONT:
				return Vector2(half_d - depth * 0.35, half_d)
			CrowdRow.MIDDLE:
				return Vector2(half_d - depth * 0.70, half_d - depth * 0.35)
			CrowdRow.BACK:
				return Vector2(-half_d, half_d - depth * 0.70)
			_:
				return Vector2(-half_d, half_d)

func _update_spawn_shapes() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var area = get_node_or_null("CrowdSpawnArea")
	if area:
		var col_shape = area.get_node_or_null("CrowdSpawnArea") as CollisionShape3D
		if col_shape:
			if not (col_shape.shape is BoxShape3D):
				col_shape.shape = BoxShape3D.new()
			elif col_shape.shape.resource_path != "":
				col_shape.shape = col_shape.shape.duplicate()
			var box = col_shape.shape as BoxShape3D
			box.size = spawn_area_size

	if sync_invisible_wall:
		var wall = get_node_or_null("InvisibleWall")
		if wall:
			var col_wall = wall.get_node_or_null("InvisibleWall") as CollisionShape3D
			if col_wall:
				if not (col_wall.shape is BoxShape3D):
					col_wall.shape = BoxShape3D.new()
				elif col_wall.shape.resource_path != "":
					col_wall.shape = col_wall.shape.duplicate()
				var box = col_wall.shape as BoxShape3D
				box.size = spawn_area_size

func _sync_spawn_size_from_shape() -> void:
	var area = get_node_or_null("CrowdSpawnArea")
	if area:
		var col_shape = area.get_node_or_null("CrowdSpawnArea") as CollisionShape3D
		if col_shape and col_shape.shape is BoxShape3D:
			var box = col_shape.shape as BoxShape3D
			# If the child shape was edited directly in the scene (e.g. via Editable Children),
			# preserve that shape and sync spawn_area_size to it!
			if box.size != Vector3(10, 2, 3) and spawn_area_size == Vector3(10, 2, 3):
				spawn_area_size = box.size
			elif spawn_area_size != Vector3(10, 2, 3) and box.size == Vector3(10, 2, 3):
				box.size = spawn_area_size
			else:
				spawn_area_size = box.size

			if sync_invisible_wall:
				var wall = get_node_or_null("InvisibleWall")
				if wall:
					var col_wall = wall.get_node_or_null("InvisibleWall") as CollisionShape3D
					if col_wall and col_wall.shape is BoxShape3D:
						(col_wall.shape as BoxShape3D).size = box.size
	_has_cached_spawn_bounds = false

var _setting_change_pending: bool = false

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_sync_spawn_size_from_shape()
		_setup_materials()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		_clear_preview_crowd()

func _on_setting_changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready():
		return
	if _setting_change_pending:
		return
	_setting_change_pending = true
	_apply_setting_change_deferred.call_deferred()

func _apply_setting_change_deferred() -> void:
	_setting_change_pending = false
	if not Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready():
		return
	saved_crowd_data.clear()
	if preview_in_editor:
		regenerate_crowd()
	else:
		regenerate_crowd()
		_clear_preview_crowd()

func _update_audio_settings() -> void:
	for member in active_members:
		if is_instance_valid(member):
			if "enable_audio" in member:
				member.enable_audio = enable_audio
			if "enable_animation_sounds" in member:
				member.enable_animation_sounds = enable_animation_sounds

func _silence_audio_nodes(node: Node) -> void:
	if not node or not is_instance_valid(node):
		return
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.volume_db = -80.0
		node.stop()
	for child in node.find_children("*", "AudioStreamPlayer", true, false):
		if child is AudioStreamPlayer:
			child.volume_db = -80.0
			child.stop()
	for child in node.find_children("*", "AudioStreamPlayer3D", true, false):
		if child is AudioStreamPlayer3D:
			child.volume_db = -80.0
			child.stop()

func reroll() -> void:
	saved_crowd_data.clear()
	custom_seed = randi() % 1000000 + 1
	use_custom_seed = true
	reroll_seed = false
	notify_property_list_changed()
	print("[Crowd] Rerolled seed: %d" % custom_seed)
	if is_inside_tree():
		regenerate_crowd()

func rebake() -> void:
	saved_crowd_data.clear()
	rebake_positions = false
	notify_property_list_changed()
	print("[Crowd] Rebaking crowd positions...")
	if is_inside_tree():
		regenerate_crowd()

func _clear_preview_crowd() -> void:
	if not is_inside_tree():
		return
	var existing_male = get_node_or_null("CrowdMaleModel") as Node3D
	for child in get_children():
		if child != existing_male and (child is CrowdMember or child.has_meta("is_crowd_preview")):
			if child.get_parent() == self:
				remove_child(child)
			child.queue_free()
	active_members.clear()
	_crowd_rids.clear()
	if existing_male:
		existing_male.visible = not Engine.is_editor_hint() or preview_in_editor

func regenerate_crowd() -> void:
	_clear_preview_crowd()
	_setup_crowd()

func _apply_editor_performance_mode() -> void:
	if not Engine.is_editor_hint():
		return
	for member in active_members:
		if not is_instance_valid(member):
			continue
		if member.has_method("apply_editor_performance_mode"):
			member.apply_editor_performance_mode(editor_performance_mode)
		_apply_culling_settings_to_member(member)

func _setup_materials() -> void:
	var mats = get_shared_materials()
	for mat in mats:
		if mat is StandardMaterial3D:
			mat.uv1_scale = material_uv1_scale
			mat.uv1_offset = material_uv1_offset
			mat.uv1_triplanar = enable_triplanar
			mat.uv1_world_triplanar = enable_triplanar
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_materials_dither_active = false

func _update_materials_transparency_mode() -> void:
	# Materials remain permanently at TRANSPARENCY_DISABLED to prevent Vulkan pipeline rebuild hitches
	pass

# ─── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_sync_spawn_size_from_shape()
	_setup_materials()
	if Engine.is_editor_hint():
		if preview_in_editor:
			_setup_crowd()
			_apply_editor_performance_mode()
			_deferred_physics_validation()
		else:
			if saved_crowd_data.is_empty():
				regenerate_crowd()
			_clear_preview_crowd()
		return

	# Enforce runtime safety clamps on LOD stepping distances so scene inspector overrides (.tscn)
	# cannot inadvertently lock members to 60 FPS beyond close range:
	anim_full_fps_distance = minf(anim_full_fps_distance, 7.0)
	anim_half_fps_distance = minf(anim_half_fps_distance, 15.0)
	anim_far_fps_distance = maxf(anim_far_fps_distance, 30.0)
	enable_shader_dithering = false
	if pop_distance > 0.0:
		front_row_max_distance = maxf(front_row_max_distance, pop_distance)
		max_render_distance = maxf(max_render_distance, pop_distance + 15.0)

	_init_pools()
	_setup_visibility_notifier()
	_setup_crowd()
	_deferred_physics_validation()

	next_shot_time = _rng.randf_range(shot_interval_min, shot_interval_max)
	next_balloon_time = _rng.randf_range(balloon_throw_interval_min, balloon_throw_interval_max)
	_culling_timer = _rng.randf_range(0.0, culling_check_interval)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not _initial_culling_done:
		var vp = get_viewport()
		var cam = vp.get_camera_3d() if vp else null
		if cam:
			_initial_culling_done = true
			_check_culling(true)

	# Low-frequency culling & occlusion checks
	_culling_timer += delta
	if _culling_timer >= culling_check_interval:
		_culling_timer = 0.0
		_check_culling()

	if not _is_rendered or _is_occluded or _is_beyond_front_max:
		return

	if active_members.size() < 2:
		return

	# Handle shooting timer
	if enable_water_gun_shooting:
		shot_timer += delta
		if shot_timer >= next_shot_time:
			shot_timer = 0.0
			next_shot_time = randf_range(shot_interval_min, shot_interval_max)
			_trigger_random_shot()

	# Handle balloon throwing timer
	if enable_balloon_throwing:
		balloon_timer += delta
		if balloon_timer >= next_balloon_time:
			balloon_timer = 0.0
			next_balloon_time = randf_range(balloon_throw_interval_min, balloon_throw_interval_max)
			_trigger_random_balloon()

# ─── Visibility & Culling Optimization ─────────────────────────────────────

func _update_render_distances() -> void:
	for member in active_members:
		_apply_culling_settings_to_member(member)

func _apply_culling_settings_to_member(member: Node3D) -> void:
	if not is_instance_valid(member):
		return

	var row = member.crowd_row if ("crowd_row" in member) else CrowdRow.FRONT
	var row_dist = front_row_max_distance
	if enable_row_architecture:
		match row:
			CrowdRow.FRONT:
				row_dist = front_row_distant_max_distance if front_row_distant_visibility else front_row_max_distance
			CrowdRow.MIDDLE:
				row_dist = middle_row_max_distance
			CrowdRow.BACK:
				row_dist = back_row_max_distance
	else:
		row_dist = max_render_distance

	var in_editor_perf = Engine.is_editor_hint() and editor_performance_mode
	var meshes = member.cached_meshes if ("cached_meshes" in member and not member.cached_meshes.is_empty()) else member.find_children("*", "MeshInstance3D", true, false)
	for child in meshes:
		if not is_instance_valid(child):
			continue
		var mesh_inst = child as MeshInstance3D
		if mesh_inst:
			mesh_inst.transparency = 0.0
			mesh_inst.visibility_range_end = 0.0
			mesh_inst.visibility_range_end_margin = 0.0
			mesh_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if in_editor_perf:
				mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif not enable_row_shadows:
				mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif enable_shadow_optimization:
				var m_name = mesh_inst.name.to_lower()
				if ("flipflop" in m_name) or ("nose" in m_name) or ("foot" in m_name) or ("hand" in m_name) or ("neck" in m_name):
					mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				else:
					mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _update_row_fade(_row: CrowdRow, _progress: float, _cam: Camera3D = null) -> void:
	# Dither fading is handled natively on GPU via GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	pass

func _pop_in_row(row: CrowdRow) -> void:
	var stagger_idx: int = 0
	for member in active_members:
		if not is_instance_valid(member):
			continue
		var r = member.crowd_row if ("crowd_row" in member) else CrowdRow.FRONT
		if r == row and member.has_method("play_balloon_pop_in"):
			var delay = stagger_idx * balloon_pop_stagger
			member.play_balloon_pop_in(delay, balloon_pop_duration)
			stagger_idx += 1

func _pop_out_row(row: CrowdRow) -> void:
	var stagger_idx: int = 0
	for member in active_members:
		if not is_instance_valid(member):
			continue
		var r = member.crowd_row if ("crowd_row" in member) else CrowdRow.FRONT
		if r == row and member.has_method("play_balloon_pop_out"):
			var delay = stagger_idx * balloon_pop_stagger
			member.play_balloon_pop_out(delay, balloon_pop_out_duration)
			stagger_idx += 1

func _update_row_mesh_culling(target_row: CrowdRow) -> void:
	for member in active_members:
		if not is_instance_valid(member):
			continue
		var r = member.crowd_row if ("crowd_row" in member) else CrowdRow.FRONT
		if r == target_row:
			_apply_culling_settings_to_member(member)

func _update_shadow_state(_cam_dist: float = -1.0) -> void:
	# Shadows are configured once per member in _apply_culling_settings_to_member
	# to avoid periodic shadow atlas invalidation and micro-stutter.
	pass

func _setup_visibility_notifier() -> void:
	if _visibility_notifier and is_instance_valid(_visibility_notifier):
		_visibility_notifier.queue_free()
		_visibility_notifier = null

	var bounds = get_spawn_bounds()
	_visibility_notifier = VisibleOnScreenNotifier3D.new()
	_visibility_notifier.name = "CrowdVisibilityNotifier"
	
	var local_center = to_local(bounds.position + bounds.size * 0.5)
	var margin = Vector3(2.0, 1.5, 2.0)
	var local_size = bounds.size + margin * 2.0
	_visibility_notifier.aabb = AABB(local_center - local_size * 0.5, local_size)

	_visibility_notifier.screen_entered.connect(_on_crowd_screen_entered)
	_visibility_notifier.screen_exited.connect(_on_crowd_screen_exited)
	add_child(_visibility_notifier)

func _on_crowd_screen_entered() -> void:
	_is_on_screen = true
	if not Engine.is_editor_hint():
		set_process(true)
	_check_culling(true)

func _on_crowd_screen_exited() -> void:
	_is_on_screen = false
	_is_occluded = false
	_set_crowd_rendered(false)

	# When camera doesn't show the crowd, reset rows that are beyond their trigger distance
	var vp = get_viewport()
	var cam = vp.get_camera_3d() if vp else null
	if cam:
		var bounds = get_spawn_bounds()
		var center = bounds.position + bounds.size * 0.5
		var cam_dist = cam.global_position.distance_to(center)
		var effective_front_dist = pop_distance if pop_distance > 0.0 else ((front_row_distant_max_distance if front_row_distant_visibility else front_row_max_distance) if enable_row_architecture else max_render_distance)
		var mid_dist = (pop_distance * 0.75 if pop_distance > 0.0 else middle_row_max_distance)
		var back_dist = (pop_distance * 0.50 if pop_distance > 0.0 else back_row_max_distance)
		if _front_row_revealed and cam_dist > effective_front_dist:
			_front_row_revealed = false
			_front_row_fade = 0.0
		if _back_row_revealed and cam_dist > back_dist:
			_back_row_revealed = false
			_back_row_fade = 0.0
		if _mid_row_revealed and cam_dist > mid_dist:
			_mid_row_revealed = false
			_mid_row_fade = 0.0
	_update_materials_transparency_mode()
	if not Engine.is_editor_hint():
		set_process(false)

func _is_point_occluded(space_state: PhysicsDirectSpaceState3D, cam_pos: Vector3, target_pos: Vector3, base_exclude: Array[RID], clearance_margin: float = 1.8) -> bool:
	if not _occlusion_ray_query:
		_occlusion_ray_query = PhysicsRayQueryParameters3D.new()
		_occlusion_ray_query.collision_mask = collision_mask_world
		_occlusion_ray_query.collide_with_areas = false
		_occlusion_ray_query.collide_with_bodies = true

	_occlusion_ray_query.from = cam_pos
	_occlusion_ray_query.to = target_pos
	_occlusion_ray_query.exclude = base_exclude

	var current_exclude: Array[RID] = []
	var has_custom_exclude: bool = false

	# Loop up to 4 times to pass through dynamic CharacterBody3D (player, enemies, NPCs)
	for _attempt in range(4):
		var res = space_state.intersect_ray(_occlusion_ray_query)
		if res.is_empty():
			return false # Line of sight is clear
		var collider = res.collider
		if is_instance_valid(collider) and collider is CharacterBody3D:
			if not has_custom_exclude:
				current_exclude = base_exclude.duplicate()
				has_custom_exclude = true
			current_exclude.append(collider.get_rid())
			_occlusion_ray_query.exclude = current_exclude
			continue
		# It hit world geometry. If the hit is very close to the target point, consider it clear (ground slope/props)
		var hit_dist_to_target = res.position.distance_to(target_pos)
		if hit_dist_to_target <= clearance_margin:
			return false
		return true # Blocked by static world geometry
	return false

func _set_crowd_rendered(rendered: bool) -> void:
	if _is_rendered == rendered:
		return
	_is_rendered = rendered

	for member in active_members:
		if not is_instance_valid(member):
			continue
		if "is_occluded" in member:
			member.is_occluded = false
		var is_row_revealed = true
		if enable_row_architecture:
			var r = member.crowd_row if ("crowd_row" in member) else CrowdRow.FRONT
			match r:
				CrowdRow.FRONT:
					is_row_revealed = _front_row_revealed
				CrowdRow.MIDDLE:
					is_row_revealed = _mid_row_revealed
				CrowdRow.BACK:
					is_row_revealed = _back_row_revealed
		else:
			is_row_revealed = _front_row_revealed

		member.visible = rendered and is_row_revealed
		member.process_mode = Node.PROCESS_MODE_INHERIT if rendered else Node.PROCESS_MODE_DISABLED
		if not rendered and member.has_method("set_row_active"):
			member.set_row_active(false)

	_update_shadow_state()
	_update_materials_transparency_mode()

func _check_culling(_force_check: bool = false) -> void:
	if not _is_on_screen:
		_set_crowd_rendered(false)
		return

	var vp = get_viewport()
	if not vp:
		return
	var cam = vp.get_camera_3d()
	if not cam:
		return
	_initial_culling_done = true

	var bounds = get_spawn_bounds()
	var center = bounds.position + bounds.size * 0.5
	var cam_pos = cam.global_position
	var dist_sq = cam_pos.distance_squared_to(center + Vector3(0.0, 1.0, 0.0))
	var effective_max_dist = maxf(
		(front_row_distant_max_distance if front_row_distant_visibility else front_row_max_distance) if enable_row_architecture else max_render_distance,
		(pop_distance + 6.0) if pop_distance > 0.0 else 0.0
	)
	var max_dist_sq = effective_max_dist * effective_max_dist

	# Distance culling (out of max distance)
	if dist_sq > max_dist_sq:
		_set_crowd_rendered(false)
		_front_row_revealed = false
		_mid_row_revealed = false
		_back_row_revealed = false
		_front_row_fade = 0.0
		_mid_row_fade = 0.0
		_back_row_fade = 0.0
		return

	# Frustum / behind-camera view plane culling:
	# If the entire bounding sphere of the crowd is strictly behind the camera forward plane, cull immediately.
	var cam_forward: Vector3 = -cam.global_transform.basis.z.normalized()
	var to_crowd: Vector3 = center - cam_pos
	var forward_proj: float = to_crowd.dot(cam_forward)
	var crowd_radius: float = bounds.size.length() * 0.5
	if forward_proj < -crowd_radius:
		_set_crowd_rendered(false)
		return

	_set_crowd_rendered(true)

	var space_state = get_world_3d().direct_space_state if enable_occlusion_culling else null

	# 1. Group-level multi-point occlusion check (Option A: Zero-Pop Pause)
	var group_occluded = false
	if enable_occlusion_culling and space_state:
		var half_size = bounds.size * 0.5
		var dx = half_size.x * 0.85
		var dz = half_size.z * 0.85
		var head_y = center.y + 1.8
		var chest_y = center.y + 1.0

		var test_pts = [
			Vector3(center.x, head_y, center.z),
			Vector3(center.x - dx, head_y, center.z - dz),
			Vector3(center.x + dx, head_y, center.z + dz),
			Vector3(center.x - dx, head_y, center.z + dz),
			Vector3(center.x + dx, head_y, center.z - dz),
			Vector3(center.x - dx, chest_y, center.z - dz),
			Vector3(center.x + dx, chest_y, center.z + dz),
			Vector3(center.x - dx, chest_y, center.z + dz),
			Vector3(center.x + dx, chest_y, center.z - dz),
		]

		group_occluded = true
		for pt in test_pts:
			if not _is_point_occluded(space_state, cam_pos, pt, _crowd_rids, 1.8):
				group_occluded = false
				break # Early out: visible!

	var was_group_occluded = _is_occluded
	_is_occluded = group_occluded

	# 2. Per-Member Occlusion Check (Zero-Pop Mode)
	# When on-screen, member.visible remains true so the hardware GPU Early-Z depth buffer
	# rejects hidden pixels with 0 ms latency on the exact frame the camera moves.
	# Occlusion status strictly drives CPU skeleton/animation pausing and shadow casting.
	if enable_occlusion_culling and space_state and not active_members.is_empty():
		var total_members = active_members.size()
		var batch_count = total_members if group_occluded else mini(MEMBER_OCCLUSION_BATCH_SIZE, total_members)
		for _step in range(batch_count):
			if _member_occlusion_cursor >= total_members:
				_member_occlusion_cursor = 0
			var member = active_members[_member_occlusion_cursor]
			_member_occlusion_cursor += 1

			if not is_instance_valid(member):
				continue

			var m_pos = member.global_position
			var head_pt = m_pos + Vector3(0.0, 1.9, 0.0)
			var chest_pt = m_pos + Vector3(0.0, 1.1, 0.0)

			var mem_occluded = false
			if group_occluded:
				mem_occluded = true
			elif _is_point_occluded(space_state, cam_pos, head_pt, _crowd_rids, 1.8):
				if _is_point_occluded(space_state, cam_pos, chest_pt, _crowd_rids, 1.8):
					mem_occluded = true

			if "is_occluded" in member:
				member.is_occluded = mem_occluded
	elif not enable_occlusion_culling or not space_state:
		if was_group_occluded:
			for member in active_members:
				if is_instance_valid(member) and "is_occluded" in member:
					member.is_occluded = false

	if was_group_occluded and not _is_occluded:
		for member in active_members:
			if is_instance_valid(member) and "is_occluded" in member:
				member.is_occluded = false

	var cam_dist = sqrt(dist_sq)
	_is_beyond_front_max = enable_row_architecture and (cam_dist > front_row_max_distance)

	# Trigger row reveal & time-based dither fade-in
	const POP_HYSTERESIS: float = 3.0
	if enable_row_architecture:
		var target_pop_dist = pop_distance if pop_distance > 0.0 else front_row_max_distance
		var front_dist = target_pop_dist
		var mid_dist = target_pop_dist * 0.75 if pop_distance > 0.0 else middle_row_max_distance
		var back_dist = target_pop_dist * 0.50 if pop_distance > 0.0 else back_row_max_distance

		# Front Row Pop-In / Pop-Out:
		if not _front_row_revealed and cam_dist <= front_dist:
			_front_row_revealed = true
			_front_row_fade = 1.0 if (_force_check or not enable_shader_dithering) else 0.0
			_update_row_fade(CrowdRow.FRONT, _front_row_fade, cam)
			if not _force_check and enable_balloon_pop_in:
				_pop_in_row(CrowdRow.FRONT)
		elif _front_row_revealed and cam_dist > (front_dist + POP_HYSTERESIS):
			_front_row_revealed = false
			_front_row_fade = 0.0
			_update_row_fade(CrowdRow.FRONT, 0.0, cam)
			if not _force_check and enable_balloon_pop_out:
				_pop_out_row(CrowdRow.FRONT)
			else:
				_update_row_mesh_culling(CrowdRow.FRONT)

		# Middle Row Pop-In / Pop-Out:
		if not _mid_row_revealed and cam_dist <= mid_dist:
			_mid_row_revealed = true
			_mid_row_fade = 1.0 if (_force_check or not enable_shader_dithering) else 0.0
			_update_row_fade(CrowdRow.MIDDLE, _mid_row_fade, cam)
			if not _force_check and enable_balloon_pop_in:
				_pop_in_row(CrowdRow.MIDDLE)
		elif _mid_row_revealed and cam_dist > (mid_dist + POP_HYSTERESIS):
			_mid_row_revealed = false
			_mid_row_fade = 0.0
			_update_row_fade(CrowdRow.MIDDLE, 0.0, cam)
			if not _force_check and enable_balloon_pop_out:
				_pop_out_row(CrowdRow.MIDDLE)
			else:
				_update_row_mesh_culling(CrowdRow.MIDDLE)

		# Back Row Pop-In / Pop-Out:
		if not _back_row_revealed and cam_dist <= back_dist:
			_back_row_revealed = true
			_back_row_fade = 1.0 if (_force_check or not enable_shader_dithering) else 0.0
			_update_row_fade(CrowdRow.BACK, _back_row_fade, cam)
			if not _force_check and enable_balloon_pop_in:
				_pop_in_row(CrowdRow.BACK)
		elif _back_row_revealed and cam_dist > (back_dist + POP_HYSTERESIS):
			_back_row_revealed = false
			_back_row_fade = 0.0
			_update_row_fade(CrowdRow.BACK, 0.0, cam)
			if not _force_check and enable_balloon_pop_out:
				_pop_out_row(CrowdRow.BACK)
			else:
				_update_row_mesh_culling(CrowdRow.BACK)
	else:
		var target_dist = pop_distance if pop_distance > 0.0 else max_render_distance
		if not _front_row_revealed and cam_dist <= target_dist:
			_front_row_revealed = true
			_front_row_fade = 1.0 if (_force_check or not enable_shader_dithering) else 0.0
			_update_row_fade(CrowdRow.FRONT, _front_row_fade, cam)
			if not _force_check and enable_balloon_pop_in:
				_pop_in_row(CrowdRow.FRONT)
		elif _front_row_revealed and cam_dist > (target_dist + POP_HYSTERESIS):
			_front_row_revealed = false
			_front_row_fade = 0.0
			_update_row_fade(CrowdRow.FRONT, 0.0, cam)
			if not _force_check and enable_balloon_pop_out:
				_pop_out_row(CrowdRow.FRONT)
			else:
				_update_row_mesh_culling(CrowdRow.FRONT)

	# Animations start as soon as dither alpha > 0 (or while revealed)
	var has_back_row = false
	var has_mid_row = false
	var full_fps_dist_sq = anim_full_fps_distance * anim_full_fps_distance
	var half_fps_dist_sq = anim_half_fps_distance * anim_half_fps_distance
	var far_fps_dist_sq = anim_far_fps_distance * anim_far_fps_distance

	for member in active_members:
		if not is_instance_valid(member):
			continue
		var r = member.crowd_row if ("crowd_row" in member) else CrowdRow.FRONT
		if r == CrowdRow.BACK:
			has_back_row = true
		elif r == CrowdRow.MIDDLE:
			has_mid_row = true

		var is_row_revealed = true
		if enable_row_architecture:
			match r:
				CrowdRow.FRONT:
					is_row_revealed = _front_row_revealed
				CrowdRow.MIDDLE:
					is_row_revealed = _mid_row_revealed
				CrowdRow.BACK:
					is_row_revealed = _back_row_revealed
		else:
			is_row_revealed = _front_row_revealed

		var is_popping_out = member.is_popping_out if ("is_popping_out" in member) else false
		if is_popping_out:
			member.visible = true
		else:
			member.visible = is_row_revealed

		var mem_occluded = member.is_occluded if ("is_occluded" in member) else false

		# Distance from camera to this specific crowd member
		var m_dist_sq = cam_pos.distance_squared_to(member.global_position)
		var is_within_motion_range = (m_dist_sq <= far_fps_dist_sq)

		# Active if: row is revealed, not occluded, AND within 30m motion range
		var is_active = is_row_revealed and not _is_occluded and not mem_occluded and is_within_motion_range

		if member.has_method("set_row_active"):
			member.set_row_active(is_active)

		# Omni-directional distance-based animation stepping LOD:
		if "anim_step_interval" in member:
			if is_active:
				if m_dist_sq <= full_fps_dist_sq:
					member.anim_step_interval = 2 if start_from_30_fps else 1
				elif m_dist_sq <= half_fps_dist_sq:
					member.anim_step_interval = 2 # Medium range: always 30 FPS!
				else:
					member.anim_step_interval = 4 # Far range (up to 30m): 15 FPS!
			else:
				member.anim_step_interval = 4

	# Hit reactions only work when ALL crowd rows are present and front row is active
	if not enable_row_architecture:
		_all_rows_present = true
	elif _is_beyond_front_max:
		_all_rows_present = false
	elif has_back_row:
		_all_rows_present = _back_row_revealed or (cam_dist <= back_row_max_distance)
	elif has_mid_row:
		_all_rows_present = _mid_row_revealed or (cam_dist <= middle_row_max_distance)
	else:
		_all_rows_present = (cam_dist <= front_row_max_distance)

	_update_shadow_state(cam_dist)

# ─── Object & VFX Pooling ──────────────────────────────────────────────────

func _init_pools() -> void:
	var active_shot_scene = shot_vfx_scene if shot_vfx_scene else water_line_scene
	if active_shot_scene:
		for i in range(water_line_pool_size):
			var line = active_shot_scene.instantiate() as Node3D
			line.top_level = true
			line.visible = false
			add_child(line)
			_water_line_pool.append(line)

	if balloon_scene:
		for i in range(balloon_pool_size):
			var balloon = balloon_scene.instantiate() as Node3D
			balloon.top_level = true
			balloon.visible = false
			add_child(balloon)
			_balloon_pool.append(balloon)

	if muzzle_vfx_scene:
		for i in range(VFX_POOL_SIZE):
			var vfx = muzzle_vfx_scene.instantiate() as Node3D
			vfx.top_level = true
			vfx.visible = false
			if not (enable_audio and enable_vfx_sounds):
				_silence_audio_nodes(vfx)
			add_child(vfx)
			_muzzle_vfx_pool.append(vfx)

	if hit_vfx_scene:
		for i in range(VFX_POOL_SIZE):
			var vfx = hit_vfx_scene.instantiate() as Node3D
			vfx.top_level = true
			vfx.visible = false
			if not (enable_audio and enable_vfx_sounds):
				_silence_audio_nodes(vfx)
			add_child(vfx)
			_hit_vfx_pool.append(vfx)

func get_pooled_water_line() -> Node3D:
	if _water_line_pool.is_empty():
		return null
	for line in _water_line_pool:
		if is_instance_valid(line) and not line.visible:
			return line
	_water_line_index = (_water_line_index + 1) % _water_line_pool.size()
	var fallback = _water_line_pool[_water_line_index]
	return fallback if is_instance_valid(fallback) else null

func get_pooled_balloon() -> Node3D:
	if _balloon_pool.is_empty():
		return null
	for b in _balloon_pool:
		if is_instance_valid(b) and not b.visible and not b.get("_active"):
			return b
	_balloon_index = (_balloon_index + 1) % _balloon_pool.size()
	var fallback = _balloon_pool[_balloon_index]
	return fallback if is_instance_valid(fallback) else null

func get_pooled_muzzle_vfx() -> Node3D:
	if _muzzle_vfx_pool.is_empty():
		return null
	for vfx in _muzzle_vfx_pool:
		if is_instance_valid(vfx) and not vfx.visible:
			return vfx
	_muzzle_vfx_index = (_muzzle_vfx_index + 1) % _muzzle_vfx_pool.size()
	return _muzzle_vfx_pool[_muzzle_vfx_index] if is_instance_valid(_muzzle_vfx_pool[_muzzle_vfx_index]) else null

func get_pooled_hit_vfx() -> Node3D:
	if _hit_vfx_pool.is_empty():
		return null
	for vfx in _hit_vfx_pool:
		if is_instance_valid(vfx) and not vfx.visible:
			return vfx
	_hit_vfx_index = (_hit_vfx_index + 1) % _hit_vfx_pool.size()
	return _hit_vfx_pool[_hit_vfx_index] if is_instance_valid(_hit_vfx_pool[_hit_vfx_index]) else null

func _trigger_vfx_node(vfx_node: Node, anim_name: String = "") -> void:
	if not vfx_node:
		return

	if vfx_node.has_method("play"):
		vfx_node.play(false, false, false)
		return

	var cached_particles = vfx_node.get_meta("_vfx_particles") if vfx_node.has_meta("_vfx_particles") else null
	if cached_particles == null:
		cached_particles = []
		var sub_emitters: Array = []
		if vfx_node is GPUParticles3D and vfx_node.sub_emitter != ^"":
			var target = vfx_node.get_node_or_null(vfx_node.sub_emitter)
			if target: sub_emitters.append(target)
		for p in vfx_node.find_children("*", "GPUParticles3D", true, false):
			if p is GPUParticles3D and p.sub_emitter != ^"":
				var target = p.get_node_or_null(p.sub_emitter)
				if target: sub_emitters.append(target)

		if vfx_node is GPUParticles3D and not sub_emitters.has(vfx_node):
			cached_particles.append(vfx_node)
		for child in vfx_node.find_children("*", "GPUParticles3D", true, false):
			if child is GPUParticles3D and not sub_emitters.has(child):
				cached_particles.append(child)
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
		for child in vfx_node.find_children("*", "AnimationPlayer", true, false):
			if child is AnimationPlayer:
				cached_anim_players.append(child)
		vfx_node.set_meta("_vfx_anim_players", cached_anim_players)

	for ap in cached_anim_players:
		if is_instance_valid(ap):
			if anim_name != "" and ap.has_animation(anim_name):
				ap.play(anim_name)

# ─── Spawn Area & Collision Detection ──────────────────────────────────────

func get_spawn_bounds() -> AABB:
	if _has_cached_spawn_bounds and not Engine.is_editor_hint():
		return _cached_spawn_bounds
	var area = get_node_or_null("CrowdSpawnArea")
	if area:
		var col_shape = area.get_node_or_null("CrowdSpawnArea") as CollisionShape3D
		if col_shape and col_shape.shape is BoxShape3D:
			var box = col_shape.shape as BoxShape3D
			var scale_factor = col_shape.global_transform.basis.get_scale().abs()
			var size = box.size * scale_factor
			var center = col_shape.global_position
			_cached_spawn_bounds = AABB(center - size * 0.5, size)
			_has_cached_spawn_bounds = true
			return _cached_spawn_bounds
	_cached_spawn_bounds = AABB(global_position - Vector3(spawn_area_size.x * 0.5, 0, spawn_area_size.z * 0.5), spawn_area_size)
	_has_cached_spawn_bounds = true
	return _cached_spawn_bounds

func _snap_point_to_ground(space_state: PhysicsDirectSpaceState3D, pos: Vector3, bounds: AABB, placed_rids: Array[RID] = []) -> Dictionary:
	if not space_state:
		return { "valid": true, "position": pos }
	var ray_top = bounds.end.y + ground_snap_height
	var ray_bottom = bounds.position.y - ground_snap_depth
	var ray_query = PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, ray_top, pos.z),
		Vector3(pos.x, ray_bottom, pos.z)
	)
	ray_query.collision_mask = collision_mask_world
	ray_query.collide_with_areas = false
	ray_query.collide_with_bodies = true
	var current_exclude = placed_rids.duplicate()
	for _att in range(3):
		ray_query.exclude = current_exclude
		var res = space_state.intersect_ray(ray_query)
		if res.is_empty():
			break
		var collider = res.collider
		if is_instance_valid(collider) and collider is CharacterBody3D:
			current_exclude.append(collider.get_rid())
			continue
		var hit_norm = res.normal
		var hit_y = res.position.y
		if hit_y <= (bounds.end.y + 0.1) and hit_y >= ray_bottom and hit_norm.y >= ground_snap_min_normal_y:
			return { "valid": true, "position": Vector3(pos.x, hit_y, pos.z) }
		break
	return { "valid": false, "position": pos }

func find_valid_spawn_position(bounds: AABB, placed_positions: Array[Vector3], placed_rids: Array[RID] = [], rng: RandomNumberGenerator = null, max_attempts: int = 80, target_row: int = -1) -> Dictionary:
	var active_rng = rng if rng else _rng
	var space_state = get_world_3d().direct_space_state
	var min_spacing_sq = min_member_spacing * min_member_spacing

	# Strict ceiling: top of the user's defined spawn box plus small buffer
	var ray_top = bounds.end.y + ground_snap_height
	var ray_bottom = bounds.position.y - ground_snap_depth

	# Reusable query instances outside loop (zero heap allocations inside loop)
	var ray_query: PhysicsRayQueryParameters3D = null
	var shape_query: PhysicsShapeQueryParameters3D = null
	var test_shape: CapsuleShape3D = null

	if enable_collision_check and space_state:
		ray_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
		ray_query.collision_mask = collision_mask_world
		ray_query.collide_with_areas = false
		ray_query.collide_with_bodies = true
		ray_query.exclude = placed_rids

		shape_query = PhysicsShapeQueryParameters3D.new()
		test_shape = CapsuleShape3D.new()
		test_shape.radius = 0.35
		test_shape.height = 1.75
		shape_query.shape = test_shape
		shape_query.collision_mask = collision_mask_world
		shape_query.collide_with_areas = false
		shape_query.collide_with_bodies = true

	var best_valid_pos = Vector3.ZERO
	var best_valid_dist_sq: float = -1.0
	var found = false

	for attempt in range(max_attempts):
		var rx: float = 0.0
		var rz: float = 0.0

		if target_row >= 0 and enable_row_architecture:
			var z_range = get_row_local_z_range(target_row as CrowdRow)
			var local_x = active_rng.randf_range(-spawn_area_size.x * 0.5, spawn_area_size.x * 0.5)
			var local_z = active_rng.randf_range(z_range.x, z_range.y)
			var world_cand = to_global(Vector3(local_x, 0.0, local_z))
			rx = world_cand.x
			rz = world_cand.z
		else:
			rx = active_rng.randf_range(bounds.position.x, bounds.end.x)
			rz = active_rng.randf_range(bounds.position.z, bounds.end.z)

		# 1. Fast 2D horizontal distance check FIRST (zero physics cost)
		var closest_dist_sq = INF
		for p in placed_positions:
			var dx = rx - p.x
			var dz = rz - p.z
			var d2 = dx * dx + dz * dz
			if d2 < closest_dist_sq:
				closest_dist_sq = d2

		var satisfies_spacing = placed_positions.is_empty() or (closest_dist_sq >= min_spacing_sq)

		# Skip early if spacing fails AND this candidate is closer than our current best fallback
		if not satisfies_spacing and closest_dist_sq <= best_valid_dist_sq:
			continue

		# 2. Physics & world collision check (if enabled)
		var hit_ground_y = bounds.position.y

		if enable_collision_check and space_state:
			ray_query.from = Vector3(rx, ray_top, rz)
			ray_query.to = Vector3(rx, ray_bottom, rz)
			var ray_result = space_state.intersect_ray(ray_query)

			if ray_result.is_empty():
				continue

			var hit_norm = ray_result.normal
			var hit_y = ray_result.position.y

			# Strictly reject roofs/ceilings above the box top, deep pits, or steep walls
			if hit_y > (bounds.end.y + 0.1) or hit_y < ray_bottom or hit_norm.y < ground_snap_min_normal_y:
				continue

			hit_ground_y = hit_y

			# 3. Headroom / clearance check (1.75m capsule standing on ground)
			shape_query.transform = Transform3D(Basis.IDENTITY, Vector3(rx, hit_ground_y + 0.9, rz))
			var shape_exclude = placed_rids.duplicate()
			if ray_result.has("collider") and ray_result.collider is CollisionObject3D:
				shape_exclude.append(ray_result.collider.get_rid())
			shape_query.exclude = shape_exclude

			var hits = space_state.intersect_shape(shape_query, 1)
			if not hits.is_empty():
				continue # Headroom blocked (low ceiling / tiny gap or obstacle)

		var candidate_pos = Vector3(rx, hit_ground_y, rz)

		if satisfies_spacing:
			best_valid_pos = candidate_pos
			found = true
			break
		elif closest_dist_sq > best_valid_dist_sq:
			best_valid_dist_sq = closest_dist_sq
			best_valid_pos = candidate_pos

	if found:
		return { "found": true, "position": best_valid_pos }
	elif best_valid_dist_sq > 0.0:
		return { "found": true, "position": best_valid_pos }
	else:
		return { "found": false, "position": Vector3.ZERO }

func _deferred_physics_validation() -> void:
	if not is_inside_tree() or _is_validating_physics:
		return
	_is_validating_physics = true
	# Wait 2 physics frames so StaticBody3D, CSG shapes, and terrain colliders are fully registered in PhysicsServer3D
	await get_tree().physics_frame
	await get_tree().physics_frame
	_is_validating_physics = false
	if not is_inside_tree():
		return
	_validate_and_snap_members()
	if not Engine.is_editor_hint():
		_check_culling(true)

func _validate_and_snap_members() -> void:
	if not is_inside_tree():
		return
	var world_3d = get_world_3d()
	if not world_3d:
		return
	var space_state = world_3d.direct_space_state
	if not space_state or not enable_collision_check:
		return

	var bounds = get_spawn_bounds()
	var ray_top = bounds.end.y + ground_snap_height
	var ray_bottom = bounds.position.y - ground_snap_depth

	var ray_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	ray_query.collision_mask = collision_mask_world
	ray_query.collide_with_areas = false
	ray_query.collide_with_bodies = true

	var shape_query = PhysicsShapeQueryParameters3D.new()
	var test_shape = CapsuleShape3D.new()
	test_shape.radius = 0.35
	test_shape.height = 1.75
	shape_query.shape = test_shape
	shape_query.collision_mask = collision_mask_world
	shape_query.collide_with_areas = false
	shape_query.collide_with_bodies = true

	var placed_positions: Array[Vector3] = []
	for member in active_members:
		if is_instance_valid(member):
			placed_positions.append(member.global_position)

	var needs_saved_data_update = false

	for i in range(active_members.size()):
		var member = active_members[i]
		if not is_instance_valid(member):
			continue

		var pos = member.global_position
		placed_positions[i] = Vector3(999999, 999999, 999999)

		var current_exclude = _crowd_rids.duplicate()
		var ray_res: Dictionary = {}

		# 1. Ground Raycast (passing through any dynamic CharacterBody3D)
		for _att in range(3):
			ray_query.exclude = current_exclude
			ray_query.from = Vector3(pos.x, ray_top, pos.z)
			ray_query.to = Vector3(pos.x, ray_bottom, pos.z)
			ray_res = space_state.intersect_ray(ray_query)
			if ray_res.is_empty():
				break
			var col = ray_res.collider
			if is_instance_valid(col) and col is CharacterBody3D:
				current_exclude.append(col.get_rid())
				continue
			break

		var is_ground_valid = false
		var hit_ground_y = pos.y

		if not ray_res.is_empty():
			var hit_norm = ray_res.normal
			var hit_y = ray_res.position.y
			if hit_y <= (bounds.end.y + 0.1) and hit_y >= ray_bottom and hit_norm.y >= ground_snap_min_normal_y:
				is_ground_valid = true
				hit_ground_y = hit_y

		# 2. Wall / Obstacle Headroom Check
		var is_clear = false
		if is_ground_valid:
			shape_query.transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, hit_ground_y + 0.9, pos.z))
			var shape_exclude = current_exclude.duplicate()
			if ray_res.has("collider") and ray_res.collider is CollisionObject3D:
				shape_exclude.append(ray_res.collider.get_rid())
			shape_query.exclude = shape_exclude

			var hits = space_state.intersect_shape(shape_query, 4)
			var blocked = false
			for h in hits:
				var c = h.collider
				if is_instance_valid(c) and not (c is CharacterBody3D):
					blocked = true
					break
			if not blocked:
				is_clear = true

		if is_ground_valid and is_clear:
			# Snap feet flush to ground
			member.global_position.y = hit_ground_y
			placed_positions[i] = member.global_position
			if i < saved_crowd_data.size() and lock_editor_positions:
				saved_crowd_data[i]["local_pos"] = to_local(member.global_position)
				needs_saved_data_update = true
		else:
			# Relocate member away from wall or out-of-bounds terrain
			var target_row = member.crowd_row if ("crowd_row" in member) else CrowdRow.FRONT
			var spawn_info = find_valid_spawn_position(bounds, placed_positions, _crowd_rids, _rng, 80, target_row)
			if spawn_info.found:
				member.global_position = spawn_info.position
				placed_positions[i] = spawn_info.position
				if i < saved_crowd_data.size() and lock_editor_positions:
					saved_crowd_data[i]["local_pos"] = to_local(spawn_info.position)
					needs_saved_data_update = true
			else:
				placed_positions[i] = member.global_position

	if needs_saved_data_update and Engine.is_editor_hint():
		notify_property_list_changed()

# ─── Crowd Initialization & Member Setup ───────────────────────────────────

func _get_member_config() -> Dictionary:
	return {
		"enable_dance_animation": enable_dance_animation,
		"enable_water_gun": enable_water_gun_spawn,
		"enable_hit_reaction": enable_hit_reaction,
		"enable_hit_animation": enable_hit_animation,
		"enable_hit_from_player": enable_hit_from_player,
		"enable_hit_from_crowd": enable_hit_from_crowd,
		"enable_audio": enable_audio,
		"enable_animation_sounds": enable_animation_sounds,
		"dance_animation_speed": dance_animation_speed,
		"range_animation_speed": range_animation_speed,
		"editor_performance_mode": editor_performance_mode if Engine.is_editor_hint() else false,
	}

func _setup_crowd() -> void:
	_clear_preview_crowd()

	# If layout locking is active and positions are already saved, restore them identically
	if lock_editor_positions and not saved_crowd_data.is_empty():
		_spawn_from_saved_layout()
		_deferred_physics_validation()
		return

	saved_crowd_data.clear()

	# Initialize deterministic or random seed
	if use_custom_seed:
		_rng.seed = custom_seed
	else:
		_rng.randomize()

	var member_config = _get_member_config()
	var bounds = get_spawn_bounds()
	var placed_positions: Array[Vector3] = []
	var placed_colors: Array[int] = []
	var armed_positions: Array[Vector3] = []
	var placed_rids: Array[RID] = []

	var existing_male = get_node_or_null("CrowdMaleModel") as Node3D

	# Calculate spawn count via density slider or fixed crowd_count
	var target_count = crowd_count
	if use_density_mode and bounds.size.x > 0.0 and bounds.size.z > 0.0:
		var area_m2 = bounds.size.x * bounds.size.z
		var active_density = crowd_density
		if enable_distance_density_scaling:
			active_density = clampf(crowd_density, min_distance_density, max_distance_density)
		target_count = max(1, int(round(area_m2 * active_density)))

	target_count = clampi(target_count, 1, max_crowd_members)

	if not enable_spawning:
		target_count = 1 if existing_male else 0

	# 3-Row Distribution: Front gets ~50% (capped at max_front_row_members), Mid ~30%, Back ~20%
	var row_plan: Array[CrowdRow] = []
	if enable_row_architecture and target_count >= 3:
		var front_count = clampi(int(ceil(target_count * 0.5)), 1, max_front_row_members)
		var remaining = target_count - front_count
		var mid_count = int(round(remaining * 0.6))
		var back_count = remaining - mid_count
		for r in range(front_count):
			row_plan.append(CrowdRow.FRONT)
		for r in range(mid_count):
			row_plan.append(CrowdRow.MIDDLE)
		for r in range(back_count):
			row_plan.append(CrowdRow.BACK)
	elif enable_row_architecture and target_count == 2:
		row_plan.append(CrowdRow.FRONT)
		row_plan.append(CrowdRow.MIDDLE)
	elif enable_row_architecture and target_count == 1:
		row_plan.append(CrowdRow.FRONT)
	else:
		for r in range(target_count):
			row_plan.append(CrowdRow.FRONT)

	for i in range(target_count):
		var row = row_plan[i] if i < row_plan.size() else CrowdRow.FRONT
		# 1. Determine valid ground position FIRST
		var spawn_info = find_valid_spawn_position(bounds, placed_positions, placed_rids, _rng, 80, row)
		if not spawn_info.found:
			if i == 0 and existing_male:
				var snap_res = _snap_point_to_ground(get_world_3d().direct_space_state, existing_male.global_position, bounds, placed_rids)
				if snap_res.valid:
					existing_male.global_position = snap_res.position
			break

		var spawn_pos: Vector3 = spawn_info.position
		var member: Node3D = null
		var chosen_model_type: int = 0

		if i == 0 and existing_male:
			member = existing_male
			member.visible = true
			chosen_model_type = 0
		else:
			var candidate_scenes: Array[PackedScene] = []
			if enable_male_crowd and male_model_scene:
				candidate_scenes.append(male_model_scene)
			if enable_female_crowd and female_model_scene:
				candidate_scenes.append(female_model_scene)

			if candidate_scenes.is_empty():
				if male_model_scene:
					candidate_scenes.append(male_model_scene)
				else:
					break

			var scene_to_use = candidate_scenes[_rng.randi_range(0, candidate_scenes.size() - 1)]
			if female_model_scene and scene_to_use == female_model_scene:
				chosen_model_type = 1
			member = scene_to_use.instantiate() as Node3D
			member.name = "CrowdMember_%d" % i
			member.set_meta("is_crowd_preview", true)
			if not (member is CrowdMember):
				var crowd_member_script = preload("res://scripts/crowd_member.gd")
				member.set_script(crowd_member_script)
			add_child(member)

		placed_positions.append(spawn_pos)
		member.global_position = spawn_pos
		member.rotation.y = _rng.randf_range(0.0, TAU)

		# Collect RIDs from placed member to exclude from future spawn raycasts/shapes
		if member is CollisionObject3D:
			placed_rids.append(member.get_rid())

		# 1. Armed spacing check: crowd members with guns should not be near each other
		var can_have_gun = enable_water_gun_spawn
		if can_have_gun:
			for armed_pos in armed_positions:
				if spawn_pos.distance_to(armed_pos) < min_gun_spacing:
					can_have_gun = false
					break

		var has_gun = can_have_gun and (_rng.randf() < gun_spawn_chance)
		if has_gun:
			armed_positions.append(spawn_pos)

		# 2. Material/Color selection: crowd members should not share the same color when near each other
		var shared_mats = get_shared_materials()
		var mat: Material = MAT_BLUE
		var chosen_color_idx: int = 0
		if enable_random_textures and shared_mats.size() > 0:
			var available_colors = [0, 1, 2] # 0: Blue, 1: Green, 2: Pink
			var neighbor_colors: Array[int] = []
			var min_dist_per_color = {0: INF, 1: INF, 2: INF}

			for j in range(placed_colors.size()):
				var dist = placed_positions[j].distance_to(spawn_pos)
				var c_idx = placed_colors[j]
				if dist < min_dist_per_color[c_idx]:
					min_dist_per_color[c_idx] = dist
				if dist < min_same_color_distance:
					if not neighbor_colors.has(c_idx):
						neighbor_colors.append(c_idx)

			# Prioritize colors not present in the immediate neighborhood
			var candidate_colors: Array[int] = []
			for c in available_colors:
				if not neighbor_colors.has(c):
					candidate_colors.append(c)

			if not candidate_colors.is_empty():
				chosen_color_idx = candidate_colors[_rng.randi_range(0, candidate_colors.size() - 1)]
			else:
				# If all 3 colors exist within the neighborhood, pick the color furthest away
				var best_dist = -1.0
				for c in available_colors:
					if min_dist_per_color[c] > best_dist:
						best_dist = min_dist_per_color[c]
						chosen_color_idx = c

			placed_colors.append(chosen_color_idx)
			mat = shared_mats[chosen_color_idx]
		else:
			placed_colors.append(0)
			chosen_color_idx = 0

		if "crowd_row" in member:
			member.crowd_row = row
		if "crowd_manager" in member:
			member.crowd_manager = self
		if "member_index" in member:
			member.member_index = i

		if member.has_method("setup_member"):
			member.setup_member(has_gun, mat, member_config)

		active_members.append(member)
		_apply_culling_settings_to_member(member)

		if Engine.is_editor_hint() or lock_editor_positions:
			saved_crowd_data.append({
				"local_pos": to_local(spawn_pos),
				"rot_y": member.rotation.y,
				"row": row,
				"has_gun": has_gun,
				"color_idx": chosen_color_idx,
				"model_type": chosen_model_type,
			})

	_crowd_rids = placed_rids.duplicate()
	if Engine.is_editor_hint() and not saved_crowd_data.is_empty():
		print("[Crowd] Baked %d crowd positions to layout. Save scene (Ctrl+S) to persist." % saved_crowd_data.size())
	if not Engine.is_editor_hint():
		_check_culling(true)
	_deferred_physics_validation()

func _spawn_from_saved_layout() -> void:
	var existing_male = get_node_or_null("CrowdMaleModel") as Node3D
	var shared_mats = get_shared_materials()
	var placed_rids: Array[RID] = []
	var member_config = _get_member_config()

	for i in range(saved_crowd_data.size()):
		var data: Dictionary = saved_crowd_data[i]
		var local_pos: Vector3 = data.get("local_pos", Vector3.ZERO)
		var rot_y: float = data.get("rot_y", 0.0)
		var row: CrowdRow = data.get("row", CrowdRow.FRONT) as CrowdRow
		var has_gun: bool = bool(data.get("has_gun", false)) and enable_water_gun_spawn
		var color_idx: int = int(data.get("color_idx", 0))
		var model_type: int = int(data.get("model_type", 0))

		var member: Node3D = null
		if i == 0 and existing_male:
			member = existing_male
			member.visible = true
		else:
			var scene_to_use: PackedScene = male_model_scene
			if model_type == 1 and female_model_scene and enable_female_crowd:
				scene_to_use = female_model_scene
			elif not enable_male_crowd and female_model_scene:
				scene_to_use = female_model_scene

			if not scene_to_use:
				if male_model_scene:
					scene_to_use = male_model_scene
				elif female_model_scene:
					scene_to_use = female_model_scene
				else:
					continue

			member = scene_to_use.instantiate() as Node3D
			member.name = "CrowdMember_%d" % i
			member.set_meta("is_crowd_preview", true)
			if not (member is CrowdMember):
				var crowd_member_script = preload("res://scripts/crowd_member.gd")
				member.set_script(crowd_member_script)
			add_child(member)

		member.position = local_pos
		member.rotation.y = rot_y

		# Collect RIDs
		if member is CollisionObject3D:
			placed_rids.append(member.get_rid())

		var mat: Material = MAT_BLUE
		if enable_random_textures and shared_mats.size() > 0:
			var safe_idx = clampi(color_idx, 0, shared_mats.size() - 1)
			mat = shared_mats[safe_idx]

		if "crowd_row" in member:
			member.crowd_row = row
		if "crowd_manager" in member:
			member.crowd_manager = self
		if "member_index" in member:
			member.member_index = i

		if member.has_method("setup_member"):
			member.setup_member(has_gun, mat, member_config)

		active_members.append(member)
		_apply_culling_settings_to_member(member)

	_crowd_rids = placed_rids.duplicate()
	if not Engine.is_editor_hint():
		_check_culling(true)
	_deferred_physics_validation()

# ─── Random Actions (Shooting & Balloon Throwing) ───────────────────────────

func _trigger_random_shot() -> void:
	_candidate_shooters.clear()
	for m in active_members:
		if m is CrowdMember and m.is_armed and m.is_row_active and not m.is_performing_action:
			_candidate_shooters.append(m)
	if _candidate_shooters.is_empty() or active_members.size() < 2:
		return

	var shooter = _candidate_shooters.pick_random() as CrowdMember
	_candidate_targets.clear()
	for m in active_members:
		if m is CrowdMember and m != shooter and m.is_row_active:
			_candidate_targets.append(m)
	if _candidate_targets.is_empty():
		return
	var target = _candidate_targets.pick_random()
	if target.has_method("ensure_chest_hitbox_active"):
		target.ensure_chest_hitbox_active()

	var target_aim = target.global_position + Vector3(
		randf_range(-0.15, 0.15),
		randf_range(0.8, 1.4),
		randf_range(-0.15, 0.15)
	)

	shooter.shoot_at(target_aim, _on_water_gun_fired)

func _on_water_gun_fired(shooter: Node3D, muzzle_pos: Vector3, target_pos: Vector3) -> void:
	var cur_muzzle_vfx_scene = muzzle_vfx_scene
	var cur_hit_vfx_scene = hit_vfx_scene
	var cur_muzzle_scale = muzzle_scale
	var cur_muzzle_offset = muzzle_offset
	var cur_impact_scale = impact_scale
	var cur_impact_offset = impact_offset
	var cur_muzzle_anim = muzzle_animation_name
	var cur_impact_anim = impact_animation_name

	if shooter is CrowdMember and shooter.npc_gun:
		var gun = shooter.npc_gun
		if "muzzle_vfx_scene" in gun and gun.muzzle_vfx_scene != null:
			cur_muzzle_vfx_scene = gun.muzzle_vfx_scene
		if "hit_vfx_scene" in gun and gun.hit_vfx_scene != null:
			cur_hit_vfx_scene = gun.hit_vfx_scene
		if "muzzle_scale" in gun:
			cur_muzzle_scale = gun.muzzle_scale
		if "muzzle_offset" in gun:
			cur_muzzle_offset = gun.muzzle_offset
		if "impact_scale" in gun:
			cur_impact_scale = gun.impact_scale
		if "impact_offset" in gun:
			cur_impact_offset = gun.impact_offset
		if "muzzle_animation_name" in gun:
			cur_muzzle_anim = gun.muzzle_animation_name
		if "impact_animation_name" in gun:
			cur_impact_anim = gun.impact_animation_name

	# 1. Muzzle VFX
	if cur_muzzle_vfx_scene:
		var muzzle_vfx: Node3D = null
		var is_pooled = (cur_muzzle_vfx_scene == muzzle_vfx_scene)
		if is_pooled:
			muzzle_vfx = get_pooled_muzzle_vfx()
		else:
			muzzle_vfx = cur_muzzle_vfx_scene.instantiate() as Node3D
			var tree = get_tree()
			var container = tree.current_scene if (tree and tree.current_scene) else self
			container.add_child(muzzle_vfx)

		if muzzle_vfx:
			var spawn_node: Node3D = null
			if shooter is CrowdMember and shooter.gun_spawn_point:
				spawn_node = shooter.gun_spawn_point
			else:
				spawn_node = shooter

			if spawn_node:
				muzzle_vfx.global_transform = spawn_node.global_transform
				muzzle_vfx.position += spawn_node.global_transform.basis * cur_muzzle_offset
			else:
				muzzle_vfx.global_position = muzzle_pos

			muzzle_vfx.scale = cur_muzzle_scale
			if not (enable_audio and enable_vfx_sounds):
				_silence_audio_nodes(muzzle_vfx)
			muzzle_vfx.visible = true
			_trigger_vfx_node(muzzle_vfx, cur_muzzle_anim)

			var tree = get_tree()
			if tree:
				tree.create_timer(1.2).timeout.connect(func():
					if is_instance_valid(muzzle_vfx):
						if is_pooled:
							muzzle_vfx.visible = false
						else:
							muzzle_vfx.queue_free()
				)
			elif not is_pooled:
				muzzle_vfx.queue_free()

	# 2. Physics Raycast for surface detection and normal
	var actual_hit_pos: Vector3 = target_pos
	var hit_normal: Vector3 = (muzzle_pos - target_pos).normalized()
	if hit_normal.length_squared() < 0.01:
		hit_normal = Vector3.UP

	var space_state = get_world_3d().direct_space_state
	var dir = (target_pos - muzzle_pos).normalized()
	var ray_end = muzzle_pos + dir * 50.0

	var exclude: Array[RID] = shooter.cached_rids if ("cached_rids" in shooter and not shooter.cached_rids.is_empty()) else []
	if exclude.is_empty():
		if shooter is CollisionObject3D:
			exclude.append(shooter.get_rid())
		for c in shooter.find_children("*", "CollisionObject3D", true, false):
			if c is CollisionObject3D:
				exclude.append(c.get_rid())

	var query = PhysicsRayQueryParameters3D.create(muzzle_pos, ray_end)
	query.exclude = exclude
	var result = space_state.intersect_ray(query)

	if result:
		actual_hit_pos = result.position
		hit_normal = result.normal

	# 3. Water Beam Line
	var line = get_pooled_water_line()
	if line and line.has_method("set_line"):
		if not (enable_audio and enable_vfx_sounds):
			_silence_audio_nodes(line)
		line.set_line(muzzle_pos, actual_hit_pos)

	# 4. Hit VFX (Splatter) oriented with surface normal
	if cur_hit_vfx_scene:
		var hit_vfx: Node3D = null
		var is_pooled_hit = (cur_hit_vfx_scene == hit_vfx_scene)
		if is_pooled_hit:
			hit_vfx = get_pooled_hit_vfx()
		else:
			hit_vfx = cur_hit_vfx_scene.instantiate() as Node3D
			var tree = get_tree()
			var container = tree.current_scene if (tree and tree.current_scene) else self
			container.add_child(hit_vfx)

		if hit_vfx:
			var normal = hit_normal
			if normal.length_squared() < 0.01:
				normal = Vector3.UP
			hit_vfx.global_position = actual_hit_pos + (normal * 0.01)

			var up_dir = Vector3.UP
			if abs(normal.dot(Vector3.UP)) > 0.999:
				up_dir = Vector3.FORWARD
			hit_vfx.look_at(hit_vfx.global_position + normal, up_dir)

			hit_vfx.position += hit_vfx.global_transform.basis * cur_impact_offset
			hit_vfx.scale = cur_impact_scale

			if hit_vfx.has_method("adjust_for_surface"):
				hit_vfx.adjust_for_surface(normal)

			if not (enable_audio and enable_vfx_sounds):
				_silence_audio_nodes(hit_vfx)

			hit_vfx.visible = true
			_trigger_vfx_node(hit_vfx, cur_impact_anim)

			var tree = get_tree()
			if tree:
				tree.create_timer(3.0).timeout.connect(func():
					if is_instance_valid(hit_vfx):
						if is_pooled_hit:
							hit_vfx.visible = false
						else:
							hit_vfx.queue_free()
				)
			elif not is_pooled_hit:
				hit_vfx.queue_free()

	if enable_audio and enable_vfx_sounds and SoundManager:
		SoundManager.play_3d("watergun_pistol_shoot", muzzle_pos, 0.0, -1.0, randf_range(0.92, 1.08))

	# 5. Crowd-on-crowd hit reaction
	if enable_hit_from_crowd:
		for member in active_members:
			if member != shooter and member.global_position.distance_to(actual_hit_pos) <= 1.5:
				var hit_dir = (actual_hit_pos - muzzle_pos).normalized()
				if member.has_method("take_hit"):
					member.take_hit({
						"hit_zone": ["chest", "body", "head"].pick_random(),
						"hit_direction": hit_dir,
						"source": shooter,
						"position": actual_hit_pos,
						"from_crowd": true
					})
				break

func _trigger_random_balloon() -> void:
	_candidate_shooters.clear()
	for m in active_members:
		if m is CrowdMember and m.is_row_active and not m.is_armed and not m.is_performing_action:
			_candidate_shooters.append(m)
	if _candidate_shooters.is_empty() or active_members.size() < 2:
		return

	var thrower = _candidate_shooters.pick_random() as CrowdMember
	_candidate_targets.clear()
	for m in active_members:
		if m is CrowdMember and m != thrower and m.is_row_active:
			_candidate_targets.append(m)
	if _candidate_targets.is_empty():
		return
	var target = _candidate_targets.pick_random()

	var target_pos = target.global_position
	thrower.throw_balloon_at(target_pos, _on_balloon_thrown)

func _on_balloon_thrown(thrower: Node3D, throw_pos: Vector3, target_pos: Vector3) -> void:
	var balloon = get_pooled_balloon()
	if not balloon:
		return

	if not (enable_audio and enable_vfx_sounds):
		_silence_audio_nodes(balloon)

	balloon.global_position = throw_pos
	if balloon.has_method("launch_pooled"):
		balloon.launch_pooled(
			target_pos,
			balloon_damage,
			2.0,
			2.5,
			1.2,
			func(splash_pos: Vector3):
				_on_balloon_splash(thrower, splash_pos)
		)

func _on_balloon_splash(thrower: Node3D, splash_pos: Vector3) -> void:
	if not enable_hit_from_crowd:
		return

	for member in active_members:
		if member != thrower and member.global_position.distance_to(splash_pos) <= 2.2:
			var hit_dir = (member.global_position - splash_pos).normalized()
			if hit_dir == Vector3.ZERO:
				hit_dir = Vector3.UP
			if member.has_method("take_hit"):
				member.take_hit({
					"hit_zone": "body",
					"hit_direction": hit_dir,
					"source": thrower,
					"position": splash_pos,
					"from_crowd": true
				})
