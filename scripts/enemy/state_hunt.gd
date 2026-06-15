class_name StateHunt
extends EnemyState

@export var move_speed: float = 2.0
@export var attack_cone_half_angle: float = 45.0
@export var attack_range: float = 0.8
@export var attack_state: String = "StateAttack"
@export var flee_range: float = 0.0
@export var flee_speed_multiplier: float = 1.2

@onready var nav_agent: NavigationAgent3D = enemy.get_node_or_null("NavigationAgent3D") if enemy else null

var _walk_anim: String = ""
var _is_fleeing: bool = false

func enter() -> void:
	print("[StateHunt] Entered Hunt.")
	_walk_anim = enemy.anim_set.random_walk()
	_play_anim(_walk_anim)
	_is_fleeing = false

func exit() -> void:
	pass

func physics_update(_delta: float) -> void:
	var target_pos: Vector3 = _get_target_position()
	var to_target: Vector3 = (target_pos - enemy.global_position)
	to_target.y = 0.0
	var flat_dist: float = to_target.length()

	if flat_dist < 0.1:
		_play_anim(enemy.anim_set.idle)
		return

	var dir_to_target: Vector3 = to_target.normalized()
	var forward: Vector3 = -enemy.global_transform.basis.z

	# ── Flee check ───────────────────────────────────────────────────────
	if flee_range > 0.0 and flat_dist < flee_range:
		_is_fleeing = true
		_flee(dir_to_target)
		return

	_is_fleeing = false

	# ── Behind check ─────────────────────────────────────────────────────
	var dot: float = forward.dot(dir_to_target)
	if dot < 0.0:
		state_machine.transition_to("StateTurnBack")
		return

	# ── Attack range + cone check ────────────────────────────────────────
	if flat_dist <= attack_range:
		var angle_to_target: float = rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
		if angle_to_target <= attack_cone_half_angle:
			state_machine.transition_to(attack_state)
			return

	# ── Move toward target ───────────────────────────────────────────────
	if nav_agent:
		nav_agent.target_position = target_pos

	var move_dir: Vector3
	if nav_agent and not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		move_dir = (next_pos - enemy.global_position).normalized()
	else:
		move_dir = dir_to_target
	move_dir.y = 0.0

	if move_dir.length() > 0.01:
		var target_vel = move_dir * move_speed
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(target_vel)
		else:
			enemy.velocity = target_vel
			enemy.move_and_slide()
		enemy.look_at(enemy.global_position + move_dir, Vector3.UP)
		_play_anim(_walk_anim)
	else:
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			enemy.velocity = Vector3.ZERO
		_play_anim(enemy.anim_set.idle)

func _flee(dir_to_player: Vector3) -> void:
	var flee_dir: Vector3 = -dir_to_player
	flee_dir.y = 0.0

	if nav_agent:
		nav_agent.target_position = enemy.global_position + flee_dir * attack_range

	if nav_agent and not nav_agent.is_navigation_finished():
		flee_dir = (nav_agent.get_next_path_position() - enemy.global_position).normalized()
		flee_dir.y = 0.0

	if flee_dir.length() > 0.01:
		var target_vel = flee_dir * move_speed * flee_speed_multiplier
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(target_vel)
		else:
			enemy.velocity = target_vel
			enemy.move_and_slide()
		enemy.look_at(enemy.global_position + (-flee_dir), Vector3.UP)
		_play_anim(_walk_anim)
	else:
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			enemy.velocity = Vector3.ZERO
		_play_anim(enemy.anim_set.idle)

func handle_hit(hit_data: Dictionary) -> String:
	var zone: String = hit_data.get("hit_zone", "body")
	match zone:
		"head", "foot", "left_leg", "right_leg":
			return "StateTakedownable"
		_:
			return "StateStun"

func _get_target_position() -> Vector3:
	var player := _get_player()
	return player.global_position if player else enemy.global_position

func _get_player() -> Node3D:
	var players = enemy.get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null
