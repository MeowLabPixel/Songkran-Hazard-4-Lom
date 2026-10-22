@tool
extends Node3D

# ─── Exported Properties & Toggles ──────────────────────────────────────────

@export_group("Editor Preview")
@export var preview_in_editor: bool = true: ## Toggle to show or hide the live crowd preview in the Godot 3D editor
	set(val):
		preview_in_editor = val
		_on_setting_changed()

@export_group("Crowd Spawning")
@export var spawn_area_size: Vector3 = Vector3(10, 2, 3): ## Size of the spawn area box (X: Width, Y: Height, Z: Depth). Automatically updates the shape in the editor!
	set(val):
		spawn_area_size = val
		_update_spawn_shapes()
		_on_setting_changed()
@export var sync_invisible_wall: bool = true: ## Automatically sync InvisibleWall shape size with spawn_area_size
	set(val):
		sync_invisible_wall = val
		if val:
			_update_spawn_shapes()
@export var enable_spawning: bool = true:
	set(val):
		enable_spawning = val
		_on_setting_changed()
@export var use_density_mode: bool = true: ## When true, crowd count is calculated from Area3D footprint * crowd_density
	set(val):
		use_density_mode = val
		_on_setting_changed()
@export_range(0.01, 1.0, 0.01) var crowd_density: float = 0.12: ## Crowd density (members per m² of the Area3D box footprint)
	set(val):
		crowd_density = val
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

@export_group("Appearance & Animation")
@export var enable_random_textures: bool = true:
	set(val):
		enable_random_textures = val
		_on_setting_changed()
@export var min_same_color_distance: float = 2.5: ## Minimum distance between crowd members sharing the same shirt color
	set(val):
		min_same_color_distance = val
		_on_setting_changed()
@export var material_uv1_scale: Vector3 = Vector3(0.5, 0.5, 0.05):
	set(val):
		material_uv1_scale = val
		_setup_materials()
@export var material_uv1_offset: Vector3 = Vector3.ZERO:
	set(val):
		material_uv1_offset = val
		_setup_materials()
@export_range(0.1, 3.0, 0.05) var dance_animation_speed: float = 1.0: ## Speed slider for dance animations
	set(val):
		dance_animation_speed = val
		_on_setting_changed()
@export_range(0.1, 3.0, 0.05) var range_animation_speed: float = 1.0: ## Speed slider for ranged water gun reload and shot animations
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
@export var min_gun_spacing: float = 3.0: ## Minimum distance between crowd members equipped with water guns
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
		if value:
			reroll()

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
var _water_line_index: int = 0
var _balloon_index: int = 0

var shot_timer: float = 0.0
var next_shot_time: float = 2.0
var balloon_timer: float = 0.0
var next_balloon_time: float = 4.0

var is_visible: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _update_spawn_shapes() -> void:
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

func _sync_initial_spawn_size() -> void:
	var area = get_node_or_null("CrowdSpawnArea")
	if area:
		var col_shape = area.get_node_or_null("CrowdSpawnArea") as CollisionShape3D
		if col_shape and col_shape.shape is BoxShape3D:
			var box = col_shape.shape as BoxShape3D
			if spawn_area_size == Vector3(10, 2, 3) and box.size != Vector3(10, 2, 3):
				spawn_area_size = box.size
			else:
				_update_spawn_shapes()
		else:
			_update_spawn_shapes()

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		(func():
			if is_inside_tree() and preview_in_editor:
				_sync_initial_spawn_size()
				_setup_materials()
				_setup_crowd()
		).call_deferred()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		_clear_preview_crowd()

func _on_setting_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		if preview_in_editor:
			regenerate_crowd()
		else:
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
	custom_seed = randi() % 1000000 + 1
	use_custom_seed = true
	reroll_seed = false
	notify_property_list_changed()
	print("[Crowd] Rerolled seed: %d" % custom_seed)
	if is_inside_tree():
		regenerate_crowd()

func _clear_preview_crowd() -> void:
	var existing_male = get_node_or_null("CrowdMaleModel") as Node3D
	for child in get_children():
		if child != existing_male and (child is CrowdMember or child.has_meta("is_crowd_preview")):
			if child.get_parent() == self:
				remove_child(child)
			child.queue_free()
	active_members.clear()

func regenerate_crowd() -> void:
	_clear_preview_crowd()
	_setup_crowd()

func _setup_materials() -> void:
	var mats = get_shared_materials()
	for mat in mats:
		if mat is StandardMaterial3D:
			mat.uv1_scale = material_uv1_scale
			mat.uv1_offset = material_uv1_offset
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true

# ─── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_update_spawn_shapes()
	_setup_materials()
	if Engine.is_editor_hint():
		if preview_in_editor:
			_setup_crowd()
		return

	_init_pools()
	_setup_visibility_notifier()
	_setup_crowd()

	next_shot_time = _rng.randf_range(shot_interval_min, shot_interval_max)
	next_balloon_time = _rng.randf_range(balloon_throw_interval_min, balloon_throw_interval_max)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not is_visible:
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

# ─── Visibility Optimization ───────────────────────────────────────────────

func _setup_visibility_notifier() -> void:
	var bounds = get_spawn_bounds()
	var notifier = VisibleOnScreenNotifier3D.new()
	# Expand AABB slightly so animations don't pop when grazing camera edges
	var margin = Vector3(2.0, 2.0, 2.0)
	notifier.aabb = AABB(bounds.position - margin, bounds.size + margin * 2.0)
	notifier.screen_entered.connect(func(): is_visible = true)
	notifier.screen_exited.connect(func(): is_visible = false)
	add_child(notifier)

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

func _trigger_vfx_node(vfx_node: Node, anim_name: String = "") -> void:
	if not vfx_node:
		return

	if vfx_node.has_method("play"):
		vfx_node.play(false, false, false)
		return

	if vfx_node is GPUParticles3D:
		if "visible" in vfx_node: vfx_node.visible = true
		vfx_node.restart()
		vfx_node.emitting = true

	var sub_emitters: Array = []
	if vfx_node is GPUParticles3D and vfx_node.sub_emitter != ^"":
		var target = vfx_node.get_node_or_null(vfx_node.sub_emitter)
		if target: sub_emitters.append(target)
	for p in vfx_node.find_children("*", "GPUParticles3D", true, false):
		if p is GPUParticles3D and p.sub_emitter != ^"":
			var target = p.get_node_or_null(p.sub_emitter)
			if target: sub_emitters.append(target)

	for child in vfx_node.find_children("*", "GPUParticles3D", true, false):
		if child is GPUParticles3D:
			if sub_emitters.has(child):
				continue
			if "visible" in child: child.visible = true
			child.restart()
			child.emitting = true

	var anim_players: Array = []
	if vfx_node is AnimationPlayer:
		anim_players.append(vfx_node)
	for child in vfx_node.find_children("*", "AnimationPlayer", true, false):
		if child is AnimationPlayer:
			anim_players.append(child)

	for ap in anim_players:
		if ap is AnimationPlayer:
			if anim_name != "" and ap.has_animation(anim_name):
				ap.play(anim_name)

# ─── Spawn Area & Collision Detection ──────────────────────────────────────

func get_spawn_bounds() -> AABB:
	var area = get_node_or_null("CrowdSpawnArea")
	if area:
		var col_shape = area.get_node_or_null("CrowdSpawnArea") as CollisionShape3D
		if col_shape and col_shape.shape is BoxShape3D:
			var box = col_shape.shape as BoxShape3D
			var scale_factor = col_shape.global_transform.basis.get_scale().abs()
			var size = box.size * scale_factor
			var center = col_shape.global_position
			return AABB(center - size * 0.5, size)
	return AABB(global_position - Vector3(spawn_area_size.x * 0.5, 0, spawn_area_size.z * 0.5), spawn_area_size)

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
	ray_query.exclude = placed_rids
	var res = space_state.intersect_ray(ray_query)
	if not res.is_empty():
		var hit_norm = res.normal
		var hit_y = res.position.y
		if hit_y <= (bounds.end.y + 0.1) and hit_y >= ray_bottom and hit_norm.y >= ground_snap_min_normal_y:
			return { "valid": true, "position": Vector3(pos.x, hit_y, pos.z) }
	return { "valid": false, "position": pos }

func find_valid_spawn_position(bounds: AABB, placed_positions: Array[Vector3], placed_rids: Array[RID] = [], rng: RandomNumberGenerator = null, max_attempts: int = 80) -> Dictionary:
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
		var rx = active_rng.randf_range(bounds.position.x, bounds.end.x)
		var rz = active_rng.randf_range(bounds.position.z, bounds.end.z)

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

# ─── Crowd Initialization & Member Setup ───────────────────────────────────

func _setup_crowd() -> void:
	_clear_preview_crowd()

	# Initialize deterministic or random seed
	if use_custom_seed:
		_rng.seed = custom_seed
	else:
		_rng.randomize()

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
		target_count = max(1, int(round(area_m2 * crowd_density)))

	if not enable_spawning:
		target_count = 1 if existing_male else 0

	for i in range(target_count):
		# 1. Determine valid ground position FIRST
		var spawn_info = find_valid_spawn_position(bounds, placed_positions, placed_rids, _rng)
		if not spawn_info.found:
			if i == 0 and existing_male:
				var snap_res = _snap_point_to_ground(get_world_3d().direct_space_state, existing_male.global_position, bounds, placed_rids)
				if snap_res.valid:
					existing_male.global_position = snap_res.position
			break

		var spawn_pos: Vector3 = spawn_info.position
		var member: Node3D = null

		if i == 0 and existing_male:
			member = existing_male
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
			member = scene_to_use.instantiate() as Node3D
			member.set_meta("is_crowd_preview", true)
			add_child(member)

		placed_positions.append(spawn_pos)
		member.global_position = spawn_pos
		member.rotation.y = _rng.randf_range(0.0, TAU)

		# Collect RIDs from placed member to exclude from future spawn raycasts/shapes
		if member is CollisionObject3D:
			placed_rids.append(member.get_rid())
		for child in member.find_children("*", "CollisionObject3D", true, false):
			var co = child as CollisionObject3D
			if co:
				placed_rids.append(co.get_rid())

		# Attach script dynamically if not already attached via Editor UI
		if not (member is CrowdMember):
			var crowd_member_script = preload("res://scripts/crowd_member.gd")
			member.set_script(crowd_member_script)

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

			var chosen_color_idx: int = 0
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

		var config = {
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
		}

		if member.has_method("setup_member"):
			member.setup_member(has_gun, mat, config)

		active_members.append(member)

# ─── Random Actions (Shooting & Balloon Throwing) ───────────────────────────

func _trigger_random_shot() -> void:
	var armed_members = active_members.filter(func(m):
		return (m is CrowdMember) and m.is_armed and not m.is_performing_action
	)
	if armed_members.is_empty() or active_members.size() < 2:
		return

	var shooter = armed_members.pick_random() as CrowdMember
	var targets = active_members.filter(func(m): return m != shooter)
	if targets.is_empty():
		return
	var target = targets.pick_random()

	var target_aim = target.global_position + Vector3(
		randf_range(-0.15, 0.15),
		randf_range(0.8, 1.4),
		randf_range(-0.15, 0.15)
	)

	shooter.shoot_at(target_aim, _on_water_gun_fired)

func _on_water_gun_fired(shooter: Node3D, muzzle_pos: Vector3, target_pos: Vector3) -> void:
	var cur_shot_vfx_scene = shot_vfx_scene if shot_vfx_scene else water_line_scene
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
		if "shot_vfx_scene" in gun and gun.shot_vfx_scene != null:
			cur_shot_vfx_scene = gun.shot_vfx_scene
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
		var muzzle_vfx = cur_muzzle_vfx_scene.instantiate() as Node3D
		if muzzle_vfx:
			var tree = get_tree()
			var container = tree.current_scene if (tree and tree.current_scene) else self
			container.add_child(muzzle_vfx)

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
			_trigger_vfx_node(muzzle_vfx, cur_muzzle_anim)

			if tree:
				tree.create_timer(1.2).timeout.connect(func():
					if is_instance_valid(muzzle_vfx):
						muzzle_vfx.queue_free()
				)
			else:
				muzzle_vfx.queue_free()

	# 2. Physics Raycast for surface detection and normal
	var actual_hit_pos: Vector3 = target_pos
	var hit_normal: Vector3 = (muzzle_pos - target_pos).normalized()
	if hit_normal.length_squared() < 0.01:
		hit_normal = Vector3.UP

	var space_state = get_world_3d().direct_space_state
	var dir = (target_pos - muzzle_pos).normalized()
	var ray_end = muzzle_pos + dir * 50.0

	var exclude: Array[RID] = []
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
		var hit_vfx = cur_hit_vfx_scene.instantiate() as Node3D
		if hit_vfx:
			var tree = get_tree()
			var container = tree.current_scene if (tree and tree.current_scene) else self
			container.add_child(hit_vfx)

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

			_trigger_vfx_node(hit_vfx, cur_impact_anim)

			if tree:
				tree.create_timer(3.0).timeout.connect(func():
					if is_instance_valid(hit_vfx):
						hit_vfx.queue_free()
				)
			else:
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
	var ready_members = active_members.filter(func(m):
		return (m is CrowdMember) and not m.is_performing_action
	)
	if ready_members.is_empty() or active_members.size() < 2:
		return

	var thrower = ready_members.pick_random() as CrowdMember
	var targets = active_members.filter(func(m): return m != thrower)
	if targets.is_empty():
		return
	var target = targets.pick_random()

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
