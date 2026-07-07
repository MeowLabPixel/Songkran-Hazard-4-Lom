class_name AnchaleeStateHit
extends AnchaleeState

var _timer: float = 0.0

func enter() -> void:
	print("[Anchalee] Hit")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	_timer = 0.0
	
	# Play Anchalee get hit voice line
	SoundManager.play_3d("vo_anchalee_gethit", Anchalee)
	
	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb: pb.travel("Hit")

func exit() -> void:
	# Play recovery voice line when transitioning back
	SoundManager.play_3d("vo_anchalee_after_gethit", Anchalee)

func physics_update(delta: float) -> void:
	_timer += delta
	
	# Ensure she cannot move or slide while playing hit animation
	var current_y = Anchalee.velocity.y
	Anchalee.velocity = Vector3(0, current_y, 0)
	Anchalee.move_and_slide()
	
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
