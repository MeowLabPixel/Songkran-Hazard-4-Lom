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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Reset state when autoload loads
	reset_game()

func start_game() -> void:
	reset_game()
	is_game_active = true
	print("[GameManager] Game loop started. Survive 5 minutes or defeat 21 villagers.")

func reset_game() -> void:
	survival_time_elapsed = 0.0
	kill_count = 0
	is_game_ended = false
	is_game_active = false
	is_timer_active = false

func start_timer() -> void:
	if not is_game_active or is_game_ended:
		return
	if not is_timer_active:
		is_timer_active = true
		print("[GameManager] Time limit timer started! Combat/spawner has begun.")

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

func register_kill() -> void:
	if not is_game_active or is_game_ended:
		return
		
	kill_count += 1
	print("[GameManager] Villager defeated! Total kills: %d/%d" % [kill_count, KILL_LIMIT])
	if kill_count >= KILL_LIMIT:
		print("[GameManager] Kill threshold reached! Ending game.")
		end_game()

func end_game() -> void:
	if is_game_ended:
		return
	is_game_ended = true
	is_game_active = false
	game_ended.emit()
	
	# Load the ending screen
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ending_screen.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_BACKSPACE:
			restart_game_to_disclaimer()

func restart_game_to_disclaimer() -> void:
	print("[GameManager] Backspace pressed. Resetting game and restarting to disclaimer scene.")
	reset_game()
	movement_type_selected = false
	if has_node("/root/ItemManager"):
		get_node("/root/ItemManager").reset()
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/disclaimer.tscn")
