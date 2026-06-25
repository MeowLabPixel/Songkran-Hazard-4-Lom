class_name AnchaleeStateHit
extends AnchaleeState

var _timer: float = 0.0

func enter() -> void:
	print("[Anchalee] Hit")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	_timer = 0.0
	
	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb: pb.travel("Hit")

func physics_update(delta: float) -> void:
	_timer += delta
	# Fallback timer in case AnimationTree state tracking is tricky.
	if _timer > 1.5:
		state_machine.transition_to("AnchaleeStateIdle")
		return

	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb:
			var current = String(pb.get_current_node())
			# If the hit animation has finished and returned to Idle
			if current == "Idle" or current == "End" or current == "":
				if _timer > 0.2: # Give it a brief moment to start playing
					state_machine.transition_to("AnchaleeStateIdle")
