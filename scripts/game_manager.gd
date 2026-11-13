extends Node

signal game_ended
signal phase_changed(new_phase: GamePhase)

const SURVIVAL_LIMIT: float = 600.0 # 10 minutes
var kill_limit: int = 22

enum GamePhase { FIRST_WAVE = 0, MEET_MERCHANT = 1, FINAL_WAVE = 2 }
var game_phase: GamePhase = GamePhase.FIRST_WAVE
var first_wave_target: int = 10
var final_wave_target: int = 12
var first_wave_kills: int = 0
var final_wave_kills: int = 0

enum Difficulty { EXPERT, CASUAL }
var difficulty: Difficulty = Difficulty.EXPERT:
	set(val):
		difficulty = val
		apply_difficulty_settings()

func apply_difficulty_settings() -> void:
	if difficulty == Difficulty.CASUAL:
		first_wave_target = 8 # 2 pre-placed + 6 spawned
		final_wave_target = 10
		kill_limit = 18 # (2 + 6) + 10
	else:
		first_wave_target = 10 # 2 pre-placed + 8 spawned
		final_wave_target = 12
		kill_limit = 22 # (2 + 8) + 12

const SAVE_PATH = "user://game_settings.cfg"
var expert_mode_played: bool = true
var casual_mode_new: bool = false
var fps_cap: int = 60:
	set = set_fps_cap

func set_fps_cap(value: int) -> void:
	fps_cap = maxi(0, value)
	Engine.max_fps = fps_cap
	print("[GameManager] FPS cap set to: %d" % fps_cap)

func get_fps_cap() -> int:
	return fps_cap

var survival_time_elapsed: float = 0.0
var kill_count: int = 0
var is_timer_active: bool = false
var is_game_ended: bool = false
var is_game_active: bool = false

enum MovementType { HYBRID_RETRO, MODERN, TANK }
var movement_type: MovementType = MovementType.HYBRID_RETRO
var movement_type_selected: bool = false
var selected_language: String = "en"
enum CameraRecoilMode { DISABLED = 0, WEAKPOINT_ONLY = 1, ENABLED = 2 }
var camera_recoil_mode: CameraRecoilMode = CameraRecoilMode.ENABLED

func set_camera_recoil_mode(mode_val) -> void:
	if mode_val is int or mode_val is CameraRecoilMode:
		camera_recoil_mode = mode_val as CameraRecoilMode
		var cams = get_tree().get_nodes_in_group("player_camera") if get_tree() else []
		for cam in cams:
			if cam.has_method("set_camera_recoil_mode"):
				cam.set_camera_recoil_mode(mode_val)

func get_camera_recoil_mode() -> CameraRecoilMode:
	return camera_recoil_mode

func set_camera_recoil_enabled(enabled: bool) -> void:
	set_camera_recoil_mode(CameraRecoilMode.ENABLED if enabled else CameraRecoilMode.DISABLED)

func is_camera_recoil_enabled() -> bool:
	return camera_recoil_mode != CameraRecoilMode.DISABLED

var enable_arm_recoil: bool = true
var enable_crosshair_recoil: bool = true

func set_arm_recoil_enabled(enabled: bool) -> void:
	enable_arm_recoil = enabled

func set_crosshair_recoil_enabled(enabled: bool) -> void:
	enable_crosshair_recoil = enabled

# --- UI & Footage Capture settings ---
var show_gameplay_ui: bool = true
var show_player_stat_ui: bool = true
var show_reload_qte: bool = true
var show_grab_qte: bool = true
var show_die_screen: bool = true
var show_takedown_prompt: bool = true
var show_crosshair: bool = true
var look_at_player_camera: bool = false
var debug_visualize_raycast: bool = false

# --- Performance / Debug Stats Overlay (FPS & Draw Calls) ---
var show_perf_overlay: bool = false
var _perf_canvas: CanvasLayer = null
var _perf_label: Label = null
var _perf_update_timer: float = 0.0
const PERF_UPDATE_INTERVAL: float = 0.1 # Update 10 times/sec to prevent string allocation churn
var pause_menu: PauseMenu = null

signal perf_overlay_visibility_changed(is_visible: bool)

func toggle_perf_overlay() -> void:
	set_perf_overlay_visible(not show_perf_overlay)

func set_perf_overlay_visible(is_visible: bool) -> void:
	show_perf_overlay = is_visible
	if _perf_canvas:
		_perf_canvas.visible = is_visible
	print("[GameManager] Performance overlay toggled: ", is_visible)
	perf_overlay_visibility_changed.emit(is_visible)

signal gameplay_ui_visibility_changed(is_visible: bool)
signal look_at_player_camera_changed(is_looking_at_player: bool)
signal debug_visualize_raycast_changed(is_enabled: bool)

func toggle_debug_visualize_raycast() -> void:
	set_debug_visualize_raycast(not debug_visualize_raycast)

func set_debug_visualize_raycast(enabled: bool) -> void:
	debug_visualize_raycast = enabled
	print("[GameManager] Debug Raycast Visualization toggled: ", enabled)
	debug_visualize_raycast_changed.emit(enabled)

func toggle_look_at_player_camera() -> void:
	set_look_at_player_camera(not look_at_player_camera)

func set_look_at_player_camera(enabled: bool) -> void:
	look_at_player_camera = enabled
	print("[GameManager] Look-at-Player Camera toggled: ", enabled)
	look_at_player_camera_changed.emit(enabled)
	var cams = get_tree().get_nodes_in_group("player_camera") if get_tree() else []
	for cam in cams:
		if cam.has_method("set_look_at_player"):
			cam.set_look_at_player(enabled)

func toggle_gameplay_ui() -> void:
	set_gameplay_ui_visible(not show_gameplay_ui)

func set_gameplay_ui_visible(is_visible: bool) -> void:
	show_gameplay_ui = is_visible
	show_player_stat_ui = is_visible
	show_reload_qte = is_visible
	show_grab_qte = is_visible
	show_die_screen = is_visible
	show_takedown_prompt = is_visible
	show_crosshair = is_visible
	print("[GameManager] Gameplay UI visibility toggled: ", is_visible)
	gameplay_ui_visibility_changed.emit(is_visible)
	
	# Update active Player Stat UI
	var ui_nodes = get_tree().get_nodes_in_group("player_ui") if get_tree() else []
	for ui_node in ui_nodes:
		if ui_node is CanvasLayer:
			ui_node.visible = is_visible
			
	# Update active QTE HUDs
	var qte_huds = get_tree().get_nodes_in_group("qte_hud") if get_tree() else []
	for qte in qte_huds:
		if qte is CanvasLayer:
			qte.visible = is_visible

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


func save_settings() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(expert_mode_played)
		file.store_var(casual_mode_new)
		file.store_var(fps_cap)
		file.close()

func load_settings() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var val1 = file.get_var()
			if val1 is bool:
				expert_mode_played = true # Casual mode is always unlocked from the start
			if not file.eof_reached():
				var val2 = file.get_var()
				if val2 is bool:
					casual_mode_new = val2
			if not file.eof_reached():
				var val3 = file.get_var()
				if val3 is int:
					fps_cap = val3
			file.close()
	Engine.max_fps = fps_cap

func _setup_perf_overlay() -> void:
	_perf_canvas = CanvasLayer.new()
	_perf_canvas.layer = 125 # Above normal game UI
	_perf_canvas.name = "PerformanceOverlay"
	add_child(_perf_canvas)

	_perf_label = Label.new()
	_perf_label.name = "PerfLabel"
	_perf_label.position = Vector2(24, 24)
	_perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Clean styling with contrast outline and shadow
	_perf_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 1.0)) # Lime green
	_perf_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_perf_label.add_theme_constant_override("shadow_offset_x", 1)
	_perf_label.add_theme_constant_override("shadow_offset_y", 1)
	_perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_perf_label.add_theme_constant_override("outline_size", 2)
	_perf_canvas.add_child(_perf_label)
	
	_perf_canvas.visible = show_perf_overlay

func _update_perf_overlay(delta: float) -> void:
	if not show_perf_overlay or not _perf_label:
		return
		
	_perf_update_timer += delta
	if _perf_update_timer >= PERF_UPDATE_INTERVAL:
		_perf_update_timer = 0.0
		var fps = Engine.get_frames_per_second()
		var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_perf_label.text = "FPS: %d\nDraw Calls: %d" % [fps, draw_calls]

func _setup_pause_menu() -> void:
	if pause_menu and is_instance_valid(pause_menu):
		return
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	_setup_perf_overlay()
	_setup_pause_menu()
	# Reset state when autoload loads
	reset_game()

func start_game() -> void:
	reset_game()
	is_game_active = true
	if difficulty == Difficulty.EXPERT:
		if not expert_mode_played:
			expert_mode_played = true
			casual_mode_new = true
			save_settings()
	print("[GameManager] Game loop started. Survive 10 minutes or defeat %d villagers." % kill_limit)

func reset_game() -> void:
	if pause_menu and is_instance_valid(pause_menu):
		pause_menu.force_close()
	elif get_tree() and get_tree().paused:
		get_tree().paused = false
	Engine.time_scale = 1.0
	survival_time_elapsed = 0.0
	kill_count = 0
	is_game_ended = false
	is_game_active = false
	is_timer_active = false
	
	apply_difficulty_settings()
	game_phase = GamePhase.FIRST_WAVE
	first_wave_kills = 0
	final_wave_kills = 0
	phase_changed.emit(game_phase)
	
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
	
	# Clear gameplay singletons and object pools
	if has_node("/root/ItemManager"):
		get_node("/root/ItemManager").reset()
	if has_node("/root/EnemyPool"):
		get_node("/root/EnemyPool").clear_pools()
	ItemPickup.clear_pool()
	if has_node("/root/EnemyRegistry"):
		var reg = get_node("/root/EnemyRegistry")
		if reg and "_active_enemies" in reg:
			reg._active_enemies.clear()
		if reg and "_combat_enemies" in reg:
			reg._combat_enemies.clear()
	if has_node("/root/AttackTokenManager"):
		get_node("/root/AttackTokenManager")._clear_all_tokens()

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
	var pre_placed = 0
	for enemy in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.process_mode != Node.PROCESS_MODE_DISABLED and enemy.can_process():
			pre_placed += 1
	var spawner_spawn_count = 0
	for spawner in registered_spawners:
		if is_instance_valid(spawner):
			spawner_spawn_count += spawner.total_enemies_to_spawn
	total_enemies_in_level = pre_placed + spawner_spawn_count
	print("[GameManager] Total enemies in level initialized: %d (Pre-placed: %d, Spawner spawn: %d)" % [total_enemies_in_level, pre_placed, spawner_spawn_count])

func _process(delta: float) -> void:
	_update_perf_overlay(delta)

	# Auto-start game if launched directly into world scene in editor/debug mode
	if not is_game_active and not is_game_ended:
		var current_tree := get_tree()
		if current_tree and current_tree.current_scene and current_tree.current_scene.scene_file_path.to_lower().contains("world"):
			start_game()

	if not is_game_active or is_game_ended:
		return
		
	# Only tick time if the timer has been activated and we are in the gameplay world scene and not paused
	var tree := get_tree()
	if tree and not tree.paused and tree.current_scene and is_timer_active and tree.current_scene.scene_file_path.to_lower().contains("world"):
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
		
	print("[GameManager] Villager defeated! Total kills: %d/%d (Combo: %d, Max Combo: %d)" % [kill_count, kill_limit, current_combo, highest_combo])
	if game_phase == GamePhase.FIRST_WAVE:
		first_wave_kills += 1
		print("[GameManager] First wave kill: %d/%d" % [first_wave_kills, first_wave_target])
		if first_wave_kills >= first_wave_target:
			game_phase = GamePhase.MEET_MERCHANT
			phase_changed.emit(game_phase)
			print("[GameManager] First wave complete (%d kills)! Objective: Go meet the mysterious merchant in the alley." % first_wave_target)
	elif game_phase == GamePhase.FINAL_WAVE:
		final_wave_kills += 1
		print("[GameManager] Final wave kill: %d/%d" % [final_wave_kills, final_wave_target])
		if final_wave_kills >= final_wave_target:
			print("[GameManager] Final kill threshold reached (%d kills)! Ending game." % final_wave_target)
			end_game()

	# Safety net: Always end the game if total kill limit is reached regardless of phase
	if kill_count >= kill_limit and not is_game_ended:
		print("[GameManager] Overall kill limit (%d) reached! Ending game." % kill_limit)
		end_game()

func notify_merchant_met() -> void:
	if game_phase == GamePhase.MEET_MERCHANT or (game_phase == GamePhase.FIRST_WAVE and first_wave_kills >= first_wave_target):
		game_phase = GamePhase.FINAL_WAVE
		phase_changed.emit(game_phase)
		print("[GameManager] Player met the mysterious merchant in the alley! Final phase started: %d kills target." % final_wave_target)

func end_game() -> void:
	if is_game_ended:
		return
	if pause_menu and is_instance_valid(pause_menu):
		pause_menu.force_close()
	is_game_ended = true
	is_game_active = false
	game_outcome = Outcome.VICTORY
	game_ended.emit()
	
	var tree := get_tree()
	if not tree:
		return

	# Disable all registered spawners right away
	for spawner in registered_spawners:
		if is_instance_valid(spawner):
			spawner.stop_spawning()

	# If victory is triggered by kill count limit, immediately defeat all active zombies
	if kill_count >= kill_limit:
		var enemies = tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy.is_defeated:
				enemy.current_hp = 0.0
				if enemy.has_signal("health_changed"):
					enemy.health_changed.emit(0.0, enemy.MAX_HP)
				if enemy.has_method("_trigger_defeat"):
					enemy._trigger_defeat()

	# Wait 3 seconds before transitioning to the result screen
	await tree.create_timer(3.0).timeout
	
	# If the game was reset or restarted during the wait, do not transition
	if not is_game_ended:
		return
		
	# Load the victory ending/result screen
	tree.change_scene_to_file("res://scenes/result_screen_victory.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_BACKSPACE:
			restart_game_to_disclaimer()
		elif event.keycode == KEY_EQUAL:
			toggle_gameplay_ui()
		elif event.keycode == KEY_MINUS:
			toggle_look_at_player_camera()
		elif event.keycode == KEY_0:
			toggle_debug_visualize_raycast()
		elif event.keycode == KEY_9 or event.keycode == KEY_F3:
			toggle_perf_overlay()

func restart_game_to_disclaimer() -> void:
	print("[GameManager] Backspace pressed. Game fully reset (Difficulty: %s, Kill Limit: %d). Returning to menu." % [Difficulty.keys()[difficulty], kill_limit])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	reset_game()
	movement_type_selected = false
	save_settings()
	if typeof(SoundManager) != TYPE_NIL and SoundManager.has_method("stop_music"):
		SoundManager.stop_music()
	var tree := get_tree()
	if tree:
		tree.call_deferred("change_scene_to_file", "res://scenes/startup.tscn")
