class_name AnchaleeStateDuck
extends AnchaleeState

var _scared_duck_sfx: Node = null

func enter() -> void:
	print("[Anchalee] Duck")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	
	_set_immune(true)
	
	# Play scared duck loop voice line
	_scared_duck_sfx = SoundManager.play_3d("vo_anchalee_Scared_Duck", Anchalee)
	
	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		tree.set("parameters/conditions/Duck_End", false)
		var pb = tree.get("parameters/playback")
		if pb: pb.travel("Duck")

func exit() -> void:
	# Stop scared duck voice line
	if is_instance_valid(_scared_duck_sfx):
		_scared_duck_sfx.stop()
		_scared_duck_sfx.queue_free()
		
	# Immunity will be lifted in Getup or Idle instead of here,
	# because we transition to Getup from Duck and want to stay immune during Getup.
	pass

func physics_update(delta: float) -> void:
	Anchalee.velocity = Vector3.ZERO
	var player = Anchalee.get_player()
	if player and player.velocity.length_squared() > 0.01:
		Anchalee.move_and_slide()
	
	var is_zombie_near = Anchalee.zombie_reaction_state == "duck" or Anchalee.get_threat_count() > 0
	var should_duck = Anchalee.is_player_aiming_or_takedown() or is_zombie_near
	if not should_duck:
		if Anchalee.has_node("AnchaleeModel/AnimationTree"):
			var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
			tree.set("parameters/conditions/Duck_End", true)
		state_machine.transition_to("AnchaleeStateGetUp")

func _set_immune(is_immune: bool) -> void:
	if is_instance_valid(Anchalee):
		Anchalee.set_immune(is_immune)
