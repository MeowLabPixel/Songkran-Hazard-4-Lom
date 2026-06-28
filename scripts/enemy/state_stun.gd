class_name StateStun
extends EnemyState


var hit_zone: String = "body"
var _grace_timer: float = 0.0
var _current_stun_anim: String = ""
var _has_started_playing: bool = false

func enter() -> void:
	_grace_timer = 0.0
	_has_started_playing = false
	print("[StateStun] Stun! Zone: %s" % hit_zone)
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	var anim: String = enemy.anim_set.hit_reaction(hit_zone)
	_current_stun_anim = anim
	_force_anim_instant(anim, "hit/hit_stun")

func exit() -> void:
	match hit_zone:
		"left_arm": enemy.next_idle_offset = 3.4
		"right_arm": enemy.next_idle_offset = 8.6
		"left_leg", "right_leg": enemy.next_idle_offset = 5.0
		_: enemy.next_idle_offset = 11.6
	hit_zone = "body"
	_current_stun_anim = ""
	_has_started_playing = false
	if enemy:
		enemy.reset_getup_conditions()

func physics_update(delta: float) -> void:
	_grace_timer += delta
	# Wait a moment for the AnimationTree to process the travel() call
	if _grace_timer < 0.1:
		return
	
	# Fallback: if the stun animation takes more than 2.0s to finish/blend, transition back anyway
	if _grace_timer >= 2.0:
		var hunt = state_machine._states.get("StateHunt")
		if hunt:
			hunt.trigger_stun_recovery = true
		state_machine.transition_to("StateHunt")
		return

	# Poll the hit_stun playback — when the AnimationTree naturally
	# reaches "End" via its own blend transitions, we transition out.
	if enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/hit/hit_stun/playback")
		if pb:
			var current = String(pb.get_current_node())
			if current == _current_stun_anim:
				_has_started_playing = true
			
			if current == "End" or (current == "Start" and _grace_timer > 0.5):
				# If we haven't started playing after 0.5s and it's stuck in Start, or if it naturally reached End
				var hunt = state_machine._states.get("StateHunt")
				if hunt:
					hunt.trigger_stun_recovery = true
				state_machine.transition_to("StateHunt")
				return
				
			if _has_started_playing and current == "End":
				var hunt = state_machine._states.get("StateHunt")
				if hunt:
					hunt.trigger_stun_recovery = true
				state_machine.transition_to("StateHunt")

func handle_hit(hit_data: Dictionary) -> String:
	var zone: String = hit_data.get("hit_zone", "body")
	match zone:
		"head", "foot", "left_foot", "right_foot":
			return "StateTakedownable"
		_:
			var new_anim: String = enemy.anim_set.hit_reaction(zone)
			
			var actual_anim: String = _current_stun_anim
			if enemy and enemy.anim_tree:
				var pb = enemy.anim_tree.get("parameters/hit/hit_stun/playback")
				if pb:
					actual_anim = String(pb.get_current_node())
					
			if new_anim == actual_anim:
				print("[StateStun] Hit in zone '%s' leads to same animation '%s' — ignoring reset." % [zone, new_anim])
				return ""
				
			print("[StateStun] Hit in zone '%s' leads to different animation '%s' (was '%s') — resetting stun duration." % [zone, new_anim, actual_anim])
			_grace_timer = 0.0
			hit_zone = zone
			_current_stun_anim = new_anim
			_force_anim_instant(new_anim, "hit/hit_stun")
			return ""
