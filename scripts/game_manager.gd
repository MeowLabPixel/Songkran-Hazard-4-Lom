extends Node

signal game_ended

const SURVIVAL_LIMIT: float = 600.0 # 10 minutes
const KILL_LIMIT: int = 15

var survival_time_elapsed: float = 0.0
var kill_count: int = 0
var is_timer_active: bool = false
var is_game_ended: bool = false
var is_game_active: bool = false

enum MovementType { HYBRID_RETRO, MODERN, TANK }
var movement_type: MovementType = MovementType.HYBRID_RETRO
var movement_type_selected: bool = false
var selected_language: String = "en"

# --- New Result Screen / Statistics variables ---
enum Outcome { VICTORY, DEFEAT_PLAYER, DEFEAT_ANCHALEE }
var game_outcome: Outcome = Outcome.VICTORY

var player_damage_taken: float = 0.0
var anchalee_damage_taken: float = 0.0
var shots_fired: int = 0
var shots_hit: int = 0
var water_consumed: float = 0.0
var takedown_count: int = 0
var highest_combo: int = 0
var total_enemies_in_level: int = 0

# Combo helper state
var current_combo: int = 0
var last_kill_time: float = -999.0
const COMBO_WINDOW: float = 7.0 # seconds to chain kills

# Spawner registration helper
var registered_spawners: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Reset state when autoload loads
	reset_game()

func start_game() -> void:
	reset_game()
	is_game_active = true
	print("[GameManager] Game loop started. Survive 10 minutes or defeat 15 villagers.")

func reset_game() -> void:
	survival_time_elapsed = 0.0
	kill_count = 0
	is_game_ended = false
	is_game_active = false
	is_timer_active = false
	
	# Reset all performance metrics
	game_outcome = Outcome.VICTORY
	player_damage_taken = 0.0
	anchalee_damage_taken = 0.0
	shots_fired = 0
	shots_hit = 0
	water_consumed = 0.0
	takedown_count = 0
	highest_combo = 0
	current_combo = 0
	last_kill_time = -999.0
	total_enemies_in_level = 0
	registered_spawners.clear()

func register_spawner(spawner) -> void:
	if not registered_spawners.has(spawner):
		registered_spawners.append(spawner)

func start_timer() -> void:
	if not is_game_active or is_game_ended:
		return
	if not is_timer_active:
		is_timer_active = true
		print("[GameManager] Time limit timer started! Combat/spawner has begun.")
		# Initialize total enemy count on the next frame so spawners are fully ready
		call_deferred("_initialize_total_enemies")

func _initialize_total_enemies() -> void:
	var tree = get_tree()
	if not tree:
		return
	var pre_placed = tree.get_nodes_in_group("enemies").size()
	var spawner_spawn_count = 0
	for spawner in registered_spawners:
		if is_instance_valid(spawner):
			spawner_spawn_count += spawner.total_enemies_to_spawn
	total_enemies_in_level = pre_placed + spawner_spawn_count
	print("[GameManager] Total enemies in level initialized: %d (Pre-placed: %d, Spawner spawn: %d)" % [total_enemies_in_level, pre_placed, spawner_spawn_count])

func _process(delta: float) -> void:
	if not is_game_active or is_game_ended:
		return
		
	# Only tick time if the timer has been activated and we are in the gameplay world scene
	var tree := get_tree()
	if tree and tree.current_scene and is_timer_active and tree.current_scene.scene_file_path.ends_with("world.tscn"):
		survival_time_elapsed += delta
		if survival_time_elapsed >= SURVIVAL_LIMIT:
			print("[GameManager] Time limit reached! Ending game.")
			end_game()

func register_shot_fired(water_used: float) -> void:
	if not is_game_active or is_game_ended:
		return
	shots_fired += 1
	water_consumed += water_used

func register_shot_hit() -> void:
	if not is_game_active or is_game_ended:
		return
	shots_hit += 1

func register_player_damage(amount: float) -> void:
	if not is_game_active or is_game_ended:
		return
	player_damage_taken += amount
	print("[GameManager] Tracked player damage: +%f (Total: %f)" % [amount, player_damage_taken])

func register_anchalee_damage(amount: float) -> void:
	if not is_game_active or is_game_ended:
		return
	anchalee_damage_taken += amount
	print("[GameManager] Tracked Anchalee damage: +%f (Total: %f)" % [amount, anchalee_damage_taken])

func register_kill(is_takedown: bool = false) -> void:
	if not is_game_active or is_game_ended:
		return
		
	kill_count += 1
	
	if is_takedown:
		takedown_count += 1
		print("[GameManager] Takedown registered! Total takedowns: %d" % takedown_count)
		
	# Handle combo tracking
	var current_time = survival_time_elapsed
	if current_time - last_kill_time <= COMBO_WINDOW:
		current_combo += 1
	else:
		current_combo = 1
	last_kill_time = current_time
	if current_combo > highest_combo:
		highest_combo = current_combo
		
	print("[GameManager] Villager defeated! Total kills: %d/%d (Combo: %d, Max Combo: %d)" % [kill_count, KILL_LIMIT, current_combo, highest_combo])
	if kill_count >= KILL_LIMIT:
		print("[GameManager] Kill threshold reached! Ending game.")
		end_game()

func end_game() -> void:
	if is_game_ended:
		return
	is_game_ended = true
	is_game_active = false
	game_outcome = Outcome.VICTORY
	game_ended.emit()
	
	var tree := get_tree()
	if not tree:
		return

	# If victory is triggered by kill count limit, immediately defeat all active zombies
	if kill_count >= KILL_LIMIT:
		var enemies = tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy.is_defeated:
				enemy.current_hp = 0.0
				if enemy.has_signal("health_changed"):
					enemy.health_changed.emit(0.0, enemy.MAX_HP)
				if enemy.has_method("_trigger_defeat"):
					enemy._trigger_defeat()

	# Wait 3 seconds before transitioning to the result screen
	await tree.create_timer(6.0).timeout
	
	# If the game was reset or restarted during the wait, do not transition
	if not is_game_ended:
		return
		
	# Load the victory ending/result screen
	tree.change_scene_to_file("res://scenes/result_screen_victory.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_BACKSPACE:
			restart_game_to_disclaimer()

func restart_game_to_disclaimer() -> void:
	print("[GameManager] Backspace pressed. Resetting game and restarting to startup main menu.")
	reset_game()
	movement_type_selected = false
	if has_node("/root/ItemManager"):
		get_node("/root/ItemManager").reset()
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/startup.tscn")
