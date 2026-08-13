class_name AnchaleeStateDuck
extends AnchaleeState

@export var max_duck_duration: float = 1.8

var _scared_duck_sfx: Node = null
var _duck_timer: float = 0.0

func enter() -> void:
	print("[Anchalee] Duck")
	_duck_timer = 0.0
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	
	_set_immune(true)
	SoundManager.play_3d("anchalee_ducking_start", Anchalee)
	
	# Play scared duck loop voice line if ducking due to threats
	var is_threat = Anchalee.zombie_reaction_state == "duck" or Anchalee.get_threat_count() > 0
	if is_threat:
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
	
	_duck_timer += delta
	
	# Priority 1: Player aiming/takedown — ALWAYS stay ducked while player is actively aiming directly at her!
	if Anchalee.is_player_aiming_or_takedown():
		_duck_timer = 0.0 # Reset duck timer while player is actively aiming so she never gets up into gunfire
		return
		
	# Priority 2: Player moving away — if player runs away (> 3.0m), interrupt ducking to follow player
	var is_player_far = player and Anchalee.global_position.distance_to(player.global_position) > 3.0
	
	# Priority 3: Zombie threat duck — capped at max_duck_duration (1.8s)
	var is_zombie_duck = Anchalee.zombie_reaction_state == "duck" and _duck_timer < max_duck_duration
	
	var should_stay_ducked = is_zombie_duck and not is_player_far
	if not should_stay_ducked:
		# Trigger duck cooldown and switch to evade if threats remain
		Anchalee.start_duck_cooldown()
		if Anchalee.get_threat_count() > 0:
			Anchalee.zombie_reaction_state = "evade"
			
		if Anchalee.has_node("AnchaleeModel/AnimationTree"):
			var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
			tree.set("parameters/conditions/Duck_End", true)
		state_machine.transition_to("AnchaleeStateGetUp")

func _set_immune(is_immune: bool) -> void:
	if is_instance_valid(Anchalee):
		Anchalee.set_immune(is_immune)
