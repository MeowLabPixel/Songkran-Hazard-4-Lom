class_name EnemySpawner
extends Node3D

enum TriggerType { ON_ENTER_AREA, MANUAL, ON_START, AFTER_SHOP_EXIT }
enum SpawnOrder { RANDOM, SEQUENTIAL }
enum SpawnPointSelection { RANDOM, SEQUENTIAL }

@export_category("Enemy Types")
## List of enemy scenes to spawn. (e.g. BalloonZom.tscn, GunZom.tscn, FMeleeZom.tscn, MMeleeZom.tscn)
@export var enemy_scenes: Array[PackedScene] = []

@export_category("Spawning Rules")
@export var trigger_type: TriggerType = TriggerType.ON_ENTER_AREA
@export var wait_for_shop_exit: bool = false
@export var shop_exit_delay: float = 1.0
@export var required_kills_in_area: int = 0

@export_category("Economy & Drops")
## Extra coins added to each coin drop min and max for enemies spawned by this spawner.
@export var extra_coin_drop: int = 0
## Explicit minimum coin drop count (overrides enemy default if > 0).
@export var override_coin_min: int = 0
## Explicit maximum coin drop count (overrides enemy default if > 0).
@export var override_coin_max: int = 0
## Minimum distance (in meters) a spawn point must be from the player to be chosen. Set to 0 to disable.
@export var min_distance_from_player: float = 0.0
@export var total_enemies_to_spawn: int = 5
@export var max_concurrent_enemies: int = 2
@export var spawn_cooldown: float = 2.0
@export var spawn_order: SpawnOrder = SpawnOrder.RANDOM
@export var spawn_point_selection: SpawnPointSelection = SpawnPointSelection.RANDOM
@export var stop_spawning_on_trigger_exit: bool = false
@export var debug_logs: bool = false

# Internal state
var _enemies_spawned_so_far: int = 0
var _wave1_spawn_count: int = 0
var _current_wave: int = 1
var _current_active_enemies: int = 0
var _is_active: bool = false
var _cooldown_timer: float = 0.0
var _next_enemy_index: int = 0
var _next_spawn_point_index: int = 0
var _spawn_points: Array[Node3D] = []
var _kills_in_area_count: int = 0
var _player_entered_trigger: bool = false
var _counted_dead_enemies: Dictionary = {}
var _shop_has_exited: bool = false

@onready var trigger_area: Area3D = $TriggerArea
@onready var spawn_points_container: Node3D = $SpawnPoints

func get_wave1_spawn_limit() -> int:
	if get_tree() and get_tree().root.has_node("GameManager"):
		var gm = get_tree().root.get_node("GameManager")
		if gm.difficulty == gm.Difficulty.CASUAL:
			return 6
		else:
			return 8
	return 8

func _apply_wave_difficulty_settings() -> void:
	if not is_inside_tree():
		return
	var tree = get_tree()
	if not tree or not tree.root.has_node("GameManager"):
		return
	var gm = tree.root.get_node("GameManager")
	var is_casual = (gm.difficulty == gm.Difficulty.CASUAL)
	
	if gm.game_phase == gm.GamePhase.FIRST_WAVE:
		_current_wave = 1
		if is_casual:
			max_concurrent_enemies = 3
			spawn_cooldown = 1.0
		else:
			max_concurrent_enemies = 4
			spawn_cooldown = 0.5
	elif gm.game_phase == gm.GamePhase.MEET_MERCHANT:
		stop_spawning()
	elif gm.game_phase == gm.GamePhase.FINAL_WAVE:
		_current_wave = 2
		if is_casual:
			max_concurrent_enemies = 4
			spawn_cooldown = 0.5
		else:
			max_concurrent_enemies = 5
			spawn_cooldown = 0.5
		if not gm.is_game_ended and _enemies_spawned_so_far < total_enemies_to_spawn:
			if not wait_for_shop_exit or _shop_has_exited:
				start_spawning()

func _on_game_phase_changed(new_phase) -> void:
	if get_tree() and get_tree().root.has_node("GameManager"):
		var gm = get_tree().root.get_node("GameManager")
		if new_phase == gm.GamePhase.FIRST_WAVE:
			_wave1_spawn_count = 0
			_current_wave = 1
			_shop_has_exited = false
	_apply_wave_difficulty_settings()

func _ready() -> void:
	if not trigger_area or not spawn_points_container:
		push_error("[EnemySpawner] Missing TriggerArea or SpawnPoints children.")
		return
	
	# Register with GameManager
	if get_tree().root.has_node("GameManager"):
		var gm = get_tree().root.get_node("GameManager")
		gm.register_spawner(self)
		if not gm.phase_changed.is_connected(_on_game_phase_changed):
			gm.phase_changed.connect(_on_game_phase_changed)
		_apply_wave_difficulty_settings()
		
	# Gather all Marker3D or Node3D spawn points
	for child in spawn_points_container.get_children():
		if child is Node3D:
			_spawn_points.append(child)
			
	if _spawn_points.is_empty():
		push_warning("[EnemySpawner] No spawn points defined under SpawnPoints node. Spawning at spawner root.")
		_spawn_points.append(self)
		
	# Setup trigger
	if trigger_type == TriggerType.ON_ENTER_AREA:
		trigger_area.body_entered.connect(_on_trigger_area_body_entered)
		if stop_spawning_on_trigger_exit:
			trigger_area.body_exited.connect(_on_trigger_area_body_exited)
		set_process(false)
		call_deferred("_check_initial_overlap")
	elif trigger_type == TriggerType.ON_START:
		if required_kills_in_area <= 0:
			start_spawning()
		else:
			set_process(false)
			if debug_logs:
				print("[EnemySpawner] Waiting for %d kills inside TriggerArea before spawning (ON_START)." % required_kills_in_area)
	elif trigger_type == TriggerType.AFTER_SHOP_EXIT:
		set_process(false)
		if debug_logs:
			print("[EnemySpawner] Spawner waiting for player to exit merchant shop (AFTER_SHOP_EXIT).")
	else:
		set_process(false)

	if trigger_type == TriggerType.AFTER_SHOP_EXIT or wait_for_shop_exit:
		_setup_merchant_listener()
		call_deferred("_setup_merchant_listener")

	# Listen for enemy deaths in the scene to track kills inside TriggerArea
	EnemyRegistry.get_singleton().enemy_defeated.connect(_on_any_enemy_defeated)

func _check_initial_overlap() -> void:
	if not _is_active and trigger_type == TriggerType.ON_ENTER_AREA:
		var player = _get_player()
		if player and is_point_inside_trigger_area(player.global_position, 5.0):
			_player_entered_trigger = true
			_check_spawning_conditions()
			return
		if is_instance_valid(trigger_area):
			for body in trigger_area.get_overlapping_bodies():
				_on_trigger_area_body_entered(body)
				if _is_active:
					break

func _on_any_enemy_defeated(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	var inst_id = enemy.get_instance_id()
	if _counted_dead_enemies.has(inst_id):
		return
		
	if is_point_inside_trigger_area(enemy.global_position, 8.0) or (is_instance_valid(trigger_area) and trigger_area.overlaps_body(enemy)):
		_counted_dead_enemies[inst_id] = true
		_kills_in_area_count += 1
		if debug_logs:
			print("[EnemySpawner] Kill inside TriggerArea: %d/%d (Enemy: %s)" % [_kills_in_area_count, required_kills_in_area, enemy.name])
		_check_spawning_conditions()

func _check_spawning_conditions() -> void:
	if _is_active:
		return
	if _enemies_spawned_so_far >= total_enemies_to_spawn:
		return
	if wait_for_shop_exit and not _shop_has_exited:
		return
		
	if _kills_in_area_count < required_kills_in_area:
		return
		
	if trigger_type == TriggerType.ON_START:
		if debug_logs:
			print("[EnemySpawner] Required kills inside area reached! Starting spawner (ON_START).")
		start_spawning()
	elif trigger_type == TriggerType.ON_ENTER_AREA:
		if not _player_entered_trigger:
			var player = _get_player()
			if player and is_point_inside_trigger_area(player.global_position, 5.0):
				_player_entered_trigger = true
		if _player_entered_trigger:
			if debug_logs:
				print("[EnemySpawner] Required kills inside area reached and player present! Starting spawner.")
			start_spawning()
		else:
			if debug_logs:
				print("[EnemySpawner] Required kills inside area reached! Waiting for player to enter TriggerArea.")
	elif trigger_type == TriggerType.AFTER_SHOP_EXIT:
		if _shop_has_exited:
			start_spawning()


func _setup_merchant_listener() -> void:
	var merchants = get_tree().get_nodes_in_group("merchant") if get_tree() else []
	for m in merchants:
		_hook_merchant(m)

	if merchants.is_empty() and get_tree():
		if get_tree().current_scene:
			for m in get_tree().current_scene.find_children("*", "Merchant", true, false):
				_hook_merchant(m)
		if get_tree().root:
			for m in get_tree().root.find_children("*", "Merchant", true, false):
				_hook_merchant(m)

	if get_tree() and not get_tree().node_added.is_connected(_on_node_added_check_merchant):
		get_tree().node_added.connect(_on_node_added_check_merchant)

func _on_node_added_check_merchant(node: Node) -> void:
	if node is Merchant or node.is_in_group("merchant"):
		_hook_merchant(node)

func _hook_merchant(m: Node) -> void:
	if not is_instance_valid(m):
		return
	if m.has_signal("shop_exited") and not m.is_connected("shop_exited", _on_merchant_shop_exited):
		m.connect("shop_exited", _on_merchant_shop_exited)
		if debug_logs:
			print("[EnemySpawner] %s successfully hooked to merchant '%s' shop_exited signal!" % [name, m.name])
		var tree = get_tree()
		if tree and tree.node_added.is_connected(_on_node_added_check_merchant):
			tree.node_added.disconnect(_on_node_added_check_merchant)

func _exit_tree() -> void:
	var reg = EnemyRegistry.get_singleton()
	if reg and reg.enemy_defeated.is_connected(_on_any_enemy_defeated):
		reg.enemy_defeated.disconnect(_on_any_enemy_defeated)
	var tree = get_tree()
	if tree:
		if tree.node_added.is_connected(_on_node_added_check_merchant):
			tree.node_added.disconnect(_on_node_added_check_merchant)

func _on_merchant_shop_exited() -> void:
	if not is_inside_tree():
		return
	var tree = get_tree()
	if not tree:
		return
	if _shop_has_exited:
		return

	# Prevent starting Wave 2 early if player talks to merchant during Wave 1
	if tree.root.has_node("GameManager"):
		var gm = tree.root.get_node("GameManager")
		if gm.game_phase == gm.GamePhase.FIRST_WAVE and gm.first_wave_kills < gm.first_wave_target:
			if debug_logs:
				print("[EnemySpawner] Merchant shop exited, but First Wave is still in progress (%d/%d kills). Spawner waiting." % [gm.first_wave_kills, gm.first_wave_target])
			return

	if debug_logs:
		print("[EnemySpawner] Merchant shop exited detected by %s!" % name)
	_shop_has_exited = true

	# If required kills haven't been met yet, wait for them to finish (they will trigger _check_spawning_conditions)
	if required_kills_in_area > 0 and _kills_in_area_count < required_kills_in_area:
		if debug_logs:
			print("[EnemySpawner] Shop exited, waiting for kills in area: %d/%d before starting wave." % [_kills_in_area_count, required_kills_in_area])
		return

	if trigger_type == TriggerType.AFTER_SHOP_EXIT:
		if shop_exit_delay > 0.0:
			tree.create_timer(shop_exit_delay).timeout.connect(func():
				if not is_inside_tree():
					return
				if not _is_active and _enemies_spawned_so_far < total_enemies_to_spawn:
					if debug_logs:
						print("[EnemySpawner] Starting spawning after shop exit delay on %s!" % name)
					start_spawning()
			)
		else:
			if not _is_active and _enemies_spawned_so_far < total_enemies_to_spawn:
				if debug_logs:
					print("[EnemySpawner] Starting spawning immediately after shop exit on %s!" % name)
				start_spawning()
	elif trigger_type == TriggerType.ON_ENTER_AREA and wait_for_shop_exit:
		_check_spawning_conditions()

func is_point_inside_trigger_area(global_pos: Vector3, margin: float = 0.0) -> bool:
	if not is_instance_valid(trigger_area):
		return false
		
	for child in trigger_area.get_children():
		if child is CollisionShape3D and is_instance_valid(child.shape):
			var local_pos = child.global_transform.affine_inverse() * global_pos
			var shape = child.shape
			if shape is BoxShape3D:
				var half = (shape.size * 0.5) + Vector3(margin, margin, margin)
				if abs(local_pos.x) <= half.x and abs(local_pos.y) <= half.y and abs(local_pos.z) <= half.z:
					return true
			elif shape is SphereShape3D:
				if local_pos.length() <= (shape.radius + margin):
					return true
			elif shape is CylinderShape3D:
				var half_h = (shape.height * 0.5) + margin
				if abs(local_pos.y) <= half_h and Vector2(local_pos.x, local_pos.z).length() <= (shape.radius + margin):
					return true
			elif shape is CapsuleShape3D:
				var r = shape.radius + margin
				var half_h = maxf(0.0, (shape.height * 0.5) - shape.radius) + margin
				var clamped_y = clampf(local_pos.y, -half_h, half_h)
				var dist_sq = Vector3(local_pos.x, local_pos.y - clamped_y, local_pos.z).length_squared()
				if dist_sq <= r * r:
					return true
	return false

func _process(delta: float) -> void:
	if not _is_active:
		set_process(false)
		return
		
	# Check if we reached the limit
	if _enemies_spawned_so_far >= total_enemies_to_spawn:
		stop_spawning()
		return
		
	# In Wave 1, limit spawned enemies to the Wave 1 spawn cap (6 for Casual, 8 for Expert)
	if _current_wave == 1 and _wave1_spawn_count >= get_wave1_spawn_limit():
		return
		
	# Check cooldown and concurrent limits (counting all active/undefeated enemies in the scene)
	if _get_active_enemies_count_in_scene() < max_concurrent_enemies:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			if not EnemyPool.can_spawn_this_frame():
				return # Defer spawn by 1 frame to time-slice multi-spawner bursts
			_spawn_enemy()
			EnemyPool.register_spawn_frame()
			_cooldown_timer = spawn_cooldown

func start_spawning() -> void:
	if _enemies_spawned_so_far >= total_enemies_to_spawn:
		return
	_is_active = true
	set_process(true)
	if debug_logs:
		print("[EnemySpawner] Started spawning.")
	if is_inside_tree() and get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").start_timer()

func stop_spawning() -> void:
	_is_active = false
	set_process(false)
	if debug_logs:
		print("[EnemySpawner] Stopped spawning.")

func _spawn_enemy() -> void:
	if enemy_scenes.is_empty():
		push_error("[EnemySpawner] No enemy scenes assigned.")
		stop_spawning()
		return
		
	# Pick enemy
	var scene_to_spawn: PackedScene
	if spawn_order == SpawnOrder.RANDOM:
		scene_to_spawn = enemy_scenes.pick_random()
	else:
		scene_to_spawn = enemy_scenes[_next_enemy_index]
		_next_enemy_index = (_next_enemy_index + 1) % enemy_scenes.size()
		
	if not scene_to_spawn:
		push_error("[EnemySpawner] Empty PackedScene in array.")
		return
		
	# Pick point
	var spawn_point: Node3D = _pick_spawn_point()
	if not spawn_point:
		spawn_point = self
		
	# Acquire from EnemyPool (recycles instance or creates if needed)
	var xform = Transform3D(spawn_point.global_basis, spawn_point.global_position)
	var enemy = EnemyPool.acquire(scene_to_spawn, xform, get_tree().current_scene)
	if not enemy:
		push_error("[EnemySpawner] Failed to acquire enemy.")
		return

	# Apply coin drop overrides if configured (Option B)
	if "drop_table" in enemy and (extra_coin_drop > 0 or override_coin_min > 0 or override_coin_max > 0):
		var new_drop_table: Array[Dictionary] = []
		for entry in enemy.drop_table:
			var copied = entry.duplicate()
			if copied.get("item_type", "") == "coin":
				if override_coin_min > 0:
					copied["count_min"] = override_coin_min
				elif extra_coin_drop > 0:
					copied["count_min"] = copied.get("count_min", 2) + extra_coin_drop

				if override_coin_max > 0:
					copied["count_max"] = override_coin_max
				elif extra_coin_drop > 0:
					copied["count_max"] = copied.get("count_max", 4) + extra_coin_drop
			new_drop_table.append(copied)
		enemy.drop_table = new_drop_table
	
	# Force spawned enemy to combat mode (StateHunt) immediately
	if enemy.has_node("EnemyStateMachine"):
		var sm = enemy.get_node("EnemyStateMachine")
		if sm and sm.has_method("transition_to"):
			sm.transition_to("StateHunt")
	
	# Track
	_enemies_spawned_so_far += 1
	if _current_wave == 1:
		_wave1_spawn_count += 1
		print("[EnemySpawner] Wave 1 spawned: %d/%d" % [_wave1_spawn_count, get_wave1_spawn_limit()])
	_current_active_enemies += 1
	
	# Listen for death to decrement active enemies.
	# EnemyBase uses `enemy_defeated` signal, or we can use `tree_exited`.
	if enemy.has_signal("enemy_defeated"):
		enemy.connect("enemy_defeated", _on_enemy_died, CONNECT_ONE_SHOT)
	else:
		# Fallback if it's not EnemyBase
		enemy.connect("tree_exited", _on_enemy_died, CONNECT_ONE_SHOT)
		
	if debug_logs:
		print("[EnemySpawner] Spawned enemy (%d/%d). Spawner Active: %d, Total Scene Active: %d" % [_enemies_spawned_so_far, total_enemies_to_spawn, _current_active_enemies, _get_active_enemies_count_in_scene()])

func _on_enemy_died() -> void:
	_current_active_enemies -= 1
	_current_active_enemies = clampi(_current_active_enemies, 0, max_concurrent_enemies)

func _get_player() -> Node3D:
	return EnemyRegistry.get_player()

func _pick_spawn_point() -> Node3D:
	if _spawn_points.is_empty():
		return self
		
	var candidates: Array[Node3D] = []
	var player = _get_player()
	
	if player and min_distance_from_player > 0.0:
		var min_dist_sq = min_distance_from_player * min_distance_from_player
		for pt in _spawn_points:
			if is_instance_valid(pt):
				var dist_sq = pt.global_position.distance_squared_to(player.global_position)
				if dist_sq >= min_dist_sq:
					candidates.append(pt)
					
		# Fallback: if all spawn points are within min_distance_from_player, pick the furthest one from the player
		if candidates.is_empty():
			var furthest_pt: Node3D = null
			var max_dist_sq: float = -1.0
			for pt in _spawn_points:
				if is_instance_valid(pt):
					var dist_sq = pt.global_position.distance_squared_to(player.global_position)
					if dist_sq > max_dist_sq:
						max_dist_sq = dist_sq
						furthest_pt = pt
			if furthest_pt:
				return furthest_pt
	else:
		candidates = _spawn_points
		
	if candidates.is_empty():
		candidates = _spawn_points
		
	if spawn_point_selection == SpawnPointSelection.RANDOM:
		return candidates.pick_random()
	else:
		var pt = candidates[_next_spawn_point_index % candidates.size()]
		_next_spawn_point_index = (_next_spawn_point_index + 1) % candidates.size()
		return pt

func _on_trigger_area_body_entered(body: Node3D) -> void:
	if debug_logs:
		print("[EnemySpawner] Body entered trigger: ", body.name, " in groups: ", body.get_groups())

	# Allow both the player and Anchalee to trigger the spawner
	if body.is_in_group("player") or body.name.to_lower() == "player" or body.is_in_group("anchalee") or body.is_in_group("Anchalee") or "anchalee" in body.name.to_lower():
		_player_entered_trigger = true
		_check_spawning_conditions()

func _on_trigger_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name.to_lower() == "player":
		_player_entered_trigger = false
		if stop_spawning_on_trigger_exit:
			stop_spawning()

func _get_active_enemies_count_in_scene() -> int:
	return EnemyRegistry.get_active_count()
