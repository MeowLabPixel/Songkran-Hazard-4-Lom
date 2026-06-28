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
	# Assuming Anchalee's hurtbox is either her main collision layer or a specific Hurtbox Area3D
	# Usually Layer 1 is world, Layer 2 is player/friend, Layer 3 is enemies, etc.
	# Setting collision mask/layer so enemies can't hit her.
	# You can tweak this depending on how enemy hitboxes are set up.
	var hurtbox = Anchalee.get_node_or_null("HurtBox")
	if hurtbox and hurtbox is Area3D:
		hurtbox.set_deferred("monitorable", not is_immune)
		hurtbox.set_deferred("monitoring", not is_immune)
		
	# Also disable her main body collision layer matching enemies if needed
	# e.g., layer 2 is usually Player/Friend
	Anchalee.set_collision_layer_value(2, not is_immune)
