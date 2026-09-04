class_name AnchaleeStateGetUp
extends AnchaleeState

var _timer: float = 0.0
var _immunity_lifted: bool = false  ## Tracks whether we already ended duck invincibility

func enter() -> void:
	print("[Anchalee] GetUp")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	_timer = 0.0
	_immunity_lifted = false  # reset so immunity ends at GetupAct 2 start
	SoundManager.play_3d("anchalee_ducking_getup", Anchalee)
	
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
	var player = Anchalee.get_player()
	if player and player.velocity.length_squared() > 0.01:
		Anchalee.move_and_slide()
	
	# If player died or aims at Anchalee while she is getting up, abort getup and duck back down immediately!
	if Anchalee.is_player_dead() or Anchalee.is_player_aiming_or_takedown():
		state_machine.transition_to("AnchaleeStateDuck")
		return
	
	_timer += delta
	if _timer > 4.0: # Fallback
		Anchalee.trigger_post_getup_jink = true
		state_machine.transition_to("AnchaleeStateWalk")
		return

	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb:
			var current = String(pb.get_current_node())
			# Lift invincibility as soon as GetupAct 2 begins — she can be hurt again
			if not _immunity_lifted and current == "GetupAct 2":
				_immunity_lifted = true
				_set_immune(false)
				print("[Anchalee] Immunity lifted at GetupAct 2")
			if current == "Idle" or current == "End" or current == "" or current == "Walk" or current == "Run":
				if _timer > 0.5:
					Anchalee.trigger_post_getup_jink = true
					state_machine.transition_to("AnchaleeStateWalk")

func _set_immune(is_immune: bool) -> void:
	if is_instance_valid(Anchalee):
		Anchalee.set_immune(is_immune)
