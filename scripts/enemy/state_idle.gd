class_name StateIdle
extends EnemyState

@export var detection_radius: float = 10.0

var combat_initiated: bool = false
var _idle_timer: float = 0.0
var _idle_interval: float = 3.0
var _is_first_enter: bool = true

func enter() -> void:
	combat_initiated = _is_any_other_zombie_in_combat()
	_idle_timer = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	_play_anim(enemy.anim_set.idle)
	if enemy and enemy.get("show_debug_label") == true:
		print("[StateIdle] Entered Idle.")
	
	if _is_first_enter and enemy and enemy.is_inside_tree() and enemy.anim_tree:
		_is_first_enter = false
		var tree = enemy.get_tree()
		if tree:
			tree.process_frame.connect(func():
				if is_instance_valid(enemy) and is_instance_valid(enemy.anim_tree):
					enemy.anim_tree.advance(randf_range(0.0, 5.0))
			, CONNECT_ONE_SHOT)

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	var player := _get_player()
	if not player:
		return
	var dist: float = enemy.global_position.distance_to(player.global_position)
	if dist <= detection_radius or combat_initiated:
		_alert_all_zombies()
		state_machine.transition_to("StateHunt")
		return
	_idle_timer += delta
	if _idle_timer >= _idle_interval:
		_idle_timer = 0.0
		_idle_interval = randf_range(2.0, 5.0)
		_play_anim(enemy.anim_set.idle)

func handle_hit(_hit_data: Dictionary) -> String:
	combat_initiated = true
	_alert_all_zombies()
	var zone: String = _hit_data.get("hit_zone", "body")
	match zone:
		"head", "foot", "left_foot", "right_foot":
			return "StateTakedownable"
		_:
			return "StateStun"

func _get_player() -> Node3D:
	var players = enemy.get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func _alert_all_zombies() -> void:
	if not enemy or not enemy.is_inside_tree():
		return
		
	var tree = enemy.get_tree()
	if not tree:
		return
		
	# Play combat music
	var music = tree.current_scene.get_node_or_null("MusicPlayer2D")
	if not music:
		music = tree.current_scene.get_node_or_null("AudioStreamPlayer2D")
	if music and music is AudioStreamPlayer2D and not music.playing:
		music.play()
		if enemy.get("show_debug_label") == true:
			print("Combat music started.")
		
	if tree.root.has_node("GameManager"):
		tree.root.get_node("GameManager").start_timer()

	var enemies = enemy.get_tree().get_nodes_in_group("enemies")
	for other_enemy in enemies:
		if is_instance_valid(other_enemy) and other_enemy != enemy:
			var sm = other_enemy.get_node_or_null("EnemyStateMachine")
			if sm:
				var idle_state = sm.get_node_or_null("StateIdle")
				if idle_state and "combat_initiated" in idle_state:
					idle_state.combat_initiated = true

func _is_any_other_zombie_in_combat() -> bool:
	if not enemy or not enemy.is_inside_tree():
		return false
	var enemies = enemy.get_tree().get_nodes_in_group("enemies")
	for other_enemy in enemies:
		if is_instance_valid(other_enemy) and other_enemy != enemy:
			var sm = other_enemy.get_node_or_null("EnemyStateMachine")
			if sm and sm.current_state:
				var state_name = sm.current_state.name
				if state_name != "StateIdle" and state_name != "StateDefeated":
					return true
	return false
