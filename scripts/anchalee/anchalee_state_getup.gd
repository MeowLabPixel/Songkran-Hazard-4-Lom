class_name AnchaleeStateGetUp
extends AnchaleeState

var _timer: float = 0.0

func enter() -> void:
	print("[Anchalee] GetUp")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	_timer = 0.0
	
	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb: 
			# Travel to GetupAct 1, AnimationTree should handle transition to GetupAct 2 then Idle
			pb.travel("GetupAct 1")

func exit() -> void:
	_set_immune(false)

func physics_update(delta: float) -> void:
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	
	_timer += delta
	if _timer > 4.0: # Fallback
		state_machine.transition_to("AnchaleeStateIdle")
		return

	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb:
			var current = String(pb.get_current_node())
			if current == "Idle" or current == "End" or current == "" or current == "Walk" or current == "Run":
				if _timer > 0.5:
					state_machine.transition_to("AnchaleeStateIdle")

func _set_immune(is_immune: bool) -> void:
	var hurtbox = Anchalee.get_node_or_null("HurtBox")
	if hurtbox and hurtbox is Area3D:
		hurtbox.set_deferred("monitorable", not is_immune)
		hurtbox.set_deferred("monitoring", not is_immune)
	Anchalee.set_collision_layer_value(2, not is_immune)
