class_name StateHitPush
extends EnemyState

@export var push_speed: float = 3.0
@export var push_decay: float = 8.0

var push_direction: Vector3 = Vector3.ZERO
var _grace_timer: float = 0.0
var _current_push_anim: String = ""
var _current_push_speed: float = 0.0

func enter() -> void:
	_grace_timer = 0.0
	_current_push_speed = push_speed
	print("[StateHitPush] Push! Enemy: %s, Direction: %s" % [enemy.name, push_direction])
	if enemy:
		enemy.velocity = push_direction * _current_push_speed
		enemy.move_and_slide()
	
	# Randomly choose Push_L or Push_R
	var push_anims = ["Push_L", "Push_R"]
	_current_push_anim = push_anims[randi() % 2]
	_force_anim_instant(_current_push_anim, "hit/hit_push")

func exit() -> void:
	_current_push_anim = ""
	push_direction = Vector3.ZERO
	_current_push_speed = 0.0
	if enemy:
		enemy.reset_getup_conditions()

func physics_update(delta: float) -> void:
	_grace_timer += delta
	
	if enemy and _current_push_speed > 0.0:
		_current_push_speed = move_toward(_current_push_speed, 0.0, push_decay * delta)
		enemy.velocity = push_direction * _current_push_speed
		enemy.move_and_slide()
		
	# Wait a moment for the AnimationTree to process the travel() call
	if _grace_timer < 0.1:
		return
	
	# Timeout fallback
	if _grace_timer >= 2.0:
		var hunt = state_machine._states.get("StateHunt")
		state_machine.transition_to("StateHunt")
		return

	# Poll the hit_push playback to detect when the substate reaches "End"
	if enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/hit/hit_push/playback")
		if pb:
			var current = String(pb.get_current_node())
			if current == "End" or current == "":
				var hunt = state_machine._states.get("StateHunt")
				state_machine.transition_to("StateHunt")

func handle_hit(hit_data: Dictionary) -> String:
	var hit_type: String = hit_data.get("hit_type", "")
	if hit_type in ["takedown", "takedown_splash"]:
		return "StateKnockdown"

	# If hit while pushed, can transition to Takedownable or standard stun
	var zone: String = hit_data.get("hit_zone", "body")
	_current_push_speed = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
	match zone:
		"head", "foot", "left_foot", "right_foot":
			return "StateTakedownable"
		_:
			return "StateStun"
