class_name StateDefeated
extends EnemyState

@export var move_speed: float = 1.2   # slower shamble than a hunting zombie

var player_is_aiming: bool = false
var _was_aiming: bool      = false
var _walking: bool         = false   # true once the dead intro anim finishes

@onready var nav_agent: NavigationAgent3D = enemy.get_node_or_null("NavigationAgent3D") if enemy else null

func enter() -> void:
	player_is_aiming = false
	_was_aiming      = false
	_walking         = false
	print("[StateDefeated] Enemy defeated!")
	_play_anim(enemy.anim_set.dead)
	enemy.anim_player.animation_finished.connect(_on_dead_anim_finished, CONNECT_ONE_SHOT)

func _on_dead_anim_finished(_anim_name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	_walking = true
	_play_anim(enemy.anim_set.dead_walk)

func exit() -> void:
	if enemy.anim_player.animation_finished.is_connected(_on_dead_anim_finished):
		enemy.anim_player.animation_finished.disconnect(_on_dead_anim_finished)

func physics_update(_delta: float) -> void:
	if not _walking:
		return

	# ── Animation toggle when player aims / stops aiming ────────────────────
	if player_is_aiming and not _was_aiming:
		_was_aiming = true
		_play_anim(enemy.anim_set.dead_walk)
	elif not player_is_aiming and _was_aiming:
		_was_aiming = false
		_play_anim(enemy.anim_set.dead)

	# ── Walk away from the player every frame ───────────────────────────
	var player := _get_player()
	if player == null:
		return

	var to_player: Vector3 = player.global_position - enemy.global_position
	to_player.y = 0.0

	# Once far enough away, stop moving
	if to_player.length() > 20.0:
		enemy.velocity = Vector3.ZERO
		return

	# Guard: if zombie is directly on top of player, skip movement/rotation
	if to_player.length() < 0.1:
		enemy.velocity = Vector3.ZERO
		return

	var flee_dir: Vector3 = -to_player.normalized()
	var target_vel = flee_dir * move_speed
	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(target_vel)
	else:
		enemy.velocity = target_vel
		enemy.move_and_slide()
	enemy.look_at(enemy.global_position + flee_dir, Vector3.UP)

func handle_hit(_hit_data: Dictionary) -> String:
	return ""

func set_aimed_at(aimed: bool) -> void:
	player_is_aiming = aimed

# ── Helpers ────────────────────────────────────────────────────
func _get_player() -> Node3D:
	var players := enemy.get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null
