class_name StateTurnBack
extends EnemyState

@export var turn_duration: float = 1.5

var _timer: float = 0.0
var _target_basis: Basis

func enter() -> void:
	_timer = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	print("[StateTurnBack] Turning 180°.")
	_target_basis = enemy.global_transform.basis.rotated(Vector3.UP, PI)
	_play_anim(enemy.anim_set.idle)

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	_timer += delta
	var t: float = clampf(_timer / turn_duration, 0.0, 1.0)
	var from_basis: Basis = enemy.global_transform.basis.orthonormalized()
	enemy.global_transform.basis = from_basis.slerp(_target_basis.orthonormalized(), t)
	if _timer >= turn_duration:
		enemy.global_transform.basis = _target_basis.orthonormalized()
		state_machine.transition_to("StateHunt")

func handle_hit(hit_data: Dictionary) -> String:
	var zone: String = hit_data.get("hit_zone", "body")
	match zone:
		"head", "foot", "left_foot", "right_foot":
			return "StateTakedownable"
		_:
			return "StateStun"
