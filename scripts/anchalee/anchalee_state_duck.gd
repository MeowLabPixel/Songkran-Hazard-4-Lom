class_name AnchaleeStateDuck
extends AnchaleeState

func enter() -> void:
	print("[Anchalee] Duck")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	
	_set_immune(true)
	
	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		tree.set("parameters/conditions/Duck_End", false)
		var pb = tree.get("parameters/playback")
		if pb: pb.travel("Duck")

func exit() -> void:
	# Immunity will be lifted in Getup or Idle instead of here,
	# because we transition to Getup from Duck and want to stay immune during Getup.
	pass

func physics_update(delta: float) -> void:
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	
	var should_duck = Anchalee.is_player_aiming_or_takedown() or (Anchalee.get_threat_count() >= 2 and Anchalee.roll_threat_duck())
	if not should_duck:
		if Anchalee.has_node("AnchaleeModel/AnimationTree"):
			var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
			tree.set("parameters/conditions/Duck_End", true)
		state_machine.transition_to("AnchaleeStateGetUp")

func _set_immune(is_immune: bool) -> void:
	if is_instance_valid(Anchalee):
		Anchalee.set_immune(is_immune)
