class_name StateIdle
extends EnemyState

@export var detection_radius: float = 10.0

var combat_initiated: bool = false
var _idle_timer: float = 0.0
var _idle_interval: float = 3.0
var _is_first_enter: bool = true

func enter() -> void:
	combat_initiated = false
	_idle_timer = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	_play_anim(enemy.anim_set.idle)
	print("[StateIdle] Entered Idle.")
	
	if _is_first_enter and enemy and enemy.anim_tree:
		_is_first_enter = false
		# Wait one frame for the AnimationTree to start playing Idle, then fast-forward it
		enemy.get_tree().process_frame.connect(func():
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
		state_machine.transition_to("StateHunt")
		return
	_idle_timer += delta
	if _idle_timer >= _idle_interval:
		_idle_timer = 0.0
		_idle_interval = randf_range(2.0, 5.0)
		_play_anim(enemy.anim_set.idle)

func handle_hit(_hit_data: Dictionary) -> String:
	combat_initiated = true
	var zone: String = _hit_data.get("hit_zone", "body")
	match zone:
		"head", "foot", "left_foot", "right_foot":
			return "StateTakedownable"
		_:
			return "StateStun"

func _get_player() -> Node3D:
	var players = enemy.get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null
