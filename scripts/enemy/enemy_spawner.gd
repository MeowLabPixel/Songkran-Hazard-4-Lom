class_name EnemySpawner
extends Node3D

enum TriggerType { ON_ENTER_AREA, MANUAL, ON_START }
enum SpawnOrder { RANDOM, SEQUENTIAL }
enum SpawnPointSelection { RANDOM, SEQUENTIAL }

@export_category("Enemy Types")
## List of enemy scenes to spawn. (e.g. BalloonZom.tscn, GunZom.tscn, FMeleeZom.tscn, MMeleeZom.tscn)
@export var enemy_scenes: Array[PackedScene] = []

@export_category("Spawning Rules")
@export var trigger_type: TriggerType = TriggerType.ON_ENTER_AREA
@export var total_enemies_to_spawn: int = 5
@export var max_concurrent_enemies: int = 2
@export var spawn_cooldown: float = 2.0
@export var spawn_order: SpawnOrder = SpawnOrder.RANDOM
@export var spawn_point_selection: SpawnPointSelection = SpawnPointSelection.RANDOM
@export var stop_spawning_on_trigger_exit: bool = false

# Internal state
var _enemies_spawned_so_far: int = 0
var _current_active_enemies: int = 0
var _is_active: bool = false
var _cooldown_timer: float = 0.0
var _next_enemy_index: int = 0
var _next_spawn_point_index: int = 0
var _spawn_points: Array[Node3D] = []

@onready var trigger_area: Area3D = $TriggerArea
@onready var spawn_points_container: Node3D = $SpawnPoints

func _ready() -> void:
	if not trigger_area or not spawn_points_container:
		push_error("[EnemySpawner] Missing TriggerArea or SpawnPoints children.")
		return
	
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
	elif trigger_type == TriggerType.ON_START:
		start_spawning()
	
	set_process(false) # Process only runs when active

func _process(delta: float) -> void:
	if not _is_active:
		set_process(false)
		return
		
	# Check if we reached the limit
	if _enemies_spawned_so_far >= total_enemies_to_spawn:
		stop_spawning()
		return
		
	# Check cooldown and concurrent limits
	if _current_active_enemies < max_concurrent_enemies:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_spawn_enemy()
			_cooldown_timer = spawn_cooldown

func start_spawning() -> void:
	if _enemies_spawned_so_far >= total_enemies_to_spawn:
		return
	_is_active = true
	set_process(true)
	print("[EnemySpawner] Started spawning.")

func stop_spawning() -> void:
	_is_active = false
	set_process(false)
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
	var spawn_point: Node3D
	if spawn_point_selection == SpawnPointSelection.RANDOM:
		spawn_point = _spawn_points.pick_random()
	else:
		spawn_point = _spawn_points[_next_spawn_point_index]
		_next_spawn_point_index = (_next_spawn_point_index + 1) % _spawn_points.size()
		
	# Instantiate
	var enemy = scene_to_spawn.instantiate() as Node3D
	if not enemy:
		push_error("[EnemySpawner] Failed to instantiate enemy.")
		return
		
	# Add to main scene tree (not spawner, so it doesn't move if spawner moves, and is decoupled)
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_point.global_position
	enemy.global_rotation = spawn_point.global_rotation
	
	# Track
	_enemies_spawned_so_far += 1
	_current_active_enemies += 1
	
	# Listen for death to decrement active enemies.
	# EnemyBase uses `enemy_defeated` signal, or we can use `tree_exited`.
	if enemy.has_signal("enemy_defeated"):
		enemy.connect("enemy_defeated", _on_enemy_died, CONNECT_ONE_SHOT)
	else:
		# Fallback if it's not EnemyBase
		enemy.connect("tree_exited", _on_enemy_died, CONNECT_ONE_SHOT)
		
	print("[EnemySpawner] Spawned enemy (%d/%d). Active: %d" % [_enemies_spawned_so_far, total_enemies_to_spawn, _current_active_enemies])

func _on_enemy_died() -> void:
	_current_active_enemies -= 1
	_current_active_enemies = clampi(_current_active_enemies, 0, max_concurrent_enemies)

func _on_trigger_area_body_entered(body: Node3D) -> void:
	print("[EnemySpawner] Body entered trigger: ", body.name, " in groups: ", body.get_groups())
	# Allow both the player and Ashley to trigger the spawner
	if body.is_in_group("player") or body.name == "Player" or body.is_in_group("ashley") or "Ashley" in body.name:
		start_spawning()

func _on_trigger_area_body_exited(body: Node3D) -> void:
	if stop_spawning_on_trigger_exit:
		if body.is_in_group("player") or body.name == "Player":
			stop_spawning()
