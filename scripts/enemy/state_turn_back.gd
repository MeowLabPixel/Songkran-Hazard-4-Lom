class_name StateTurnBack
extends EnemyState

@export var turn_duration: float = 0.25

var _timer: float = 0.0
var _start_y: float = 0.0
var _target_y: float = 0.0

func enter() -> void:
	_timer = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
		_start_y = enemy.rotation.y
		_target_y = _start_y + PI
	print("[StateTurnBack] Turning 180°.")
	_play_anim(enemy.anim_set.idle)

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	_timer += delta
	var t: float = clampf(_timer / turn_duration, 0.0, 1.0)
	if enemy:
		enemy.rotation.y = lerp_angle(_start_y, _target_y, t)
	if _timer >= turn_duration:
		if enemy:
			enemy.rotation.y = wrapf(_target_y, -PI, PI)
		state_machine.transition_to("StateHunt")

func handle_hit(hit_data: Dictionary) -> String:
	var zone: String = hit_data.get("hit_zone", "body")
	match zone:
		"head", "foot", "left_foot", "right_foot":
			return "StateTakedownable"
		_:
			return "StateStun"
