class_name AnchaleeStateIdle
extends AnchaleeState

func enter() -> void:
	print("[Anchalee] Idle")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.set_player_collision(false)
	
	# Use the AnimationTree if it's set up
	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb: pb.travel("Idle")

func physics_update(delta: float) -> void:
	if Anchalee.zombie_reaction_state == "none" and Anchalee.get_threat_count() >= 1:
		var threats = Anchalee.get_threat_count()
		var duck_chance = Anchalee.reaction_chance_duck if (threats >= 2 and Anchalee.duck_cooldown_timer <= 0.0) else 0.0
		var roll = randf()
		if roll <= duck_chance:
			Anchalee.zombie_reaction_state = "duck"
		elif roll <= duck_chance + Anchalee.reaction_chance_evade:
			Anchalee.zombie_reaction_state = "evade"
		else:
			Anchalee.zombie_reaction_state = "back_up"
		Anchalee.zombie_reaction_timer = Anchalee.zombie_reaction_cooldown
			
	var aim_duck = Anchalee.is_player_aiming_or_takedown()
	if aim_duck or Anchalee.zombie_reaction_state == "duck":
		state_machine.transition_to("AnchaleeStateDuck")
		return
		
	if Anchalee.zombie_reaction_state == "evade" or Anchalee.zombie_reaction_state == "back_up":
		state_machine.transition_to("AnchaleeStateWalk")
		return
		
	var target_pos = Anchalee.get_friend_target_pos()
	var to_target = target_pos - Anchalee.global_position
	to_target.y = 0.0
	var dist_to_target = to_target.length()
	
	# Walk if we are too far from our intended destination (FriendArea on player)
	var player = Anchalee.get_player()
	var is_in_near_area = false
	if player:
		var near_area = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/FriendNearArea")
		if near_area:
			is_in_near_area = near_area.overlaps_body(Anchalee)
			
	var has_reached_destination = is_in_near_area or Anchalee.is_player_in_friend_area or Anchalee.is_touching_player or dist_to_target <= Anchalee.get_effective_follow_stop_distance()
			
	var is_player_moving_backward = false
	if player:
		var player_forward = -player.global_transform.basis.z
		is_player_moving_backward = player.velocity.dot(player_forward) < -0.1 or Input.is_action_pressed("ui_down")
		
	var should_walk_back = is_player_moving_backward and is_in_near_area
	
	# Only transition to Walk if far away from player, backing up, sprinting, or significant movement when not at destination
	var player_sprinting = Anchalee.player_is_sprinting
	var is_far_away = dist_to_target > Anchalee.follow_start_distance
	var should_start_walking = is_far_away or should_walk_back or player_sprinting or (not has_reached_destination and player and player.velocity.length_squared() > 1.0)
	
	if should_start_walking:
		if should_walk_back:
			Anchalee.is_walking_backward = true
		else:
			Anchalee.is_walking_backward = false
		state_machine.transition_to("AnchaleeStateWalk")
		return
		
	var repulsion_vec = _get_repulsion()
	if repulsion_vec.length() > 0.1:
		Anchalee.is_walking_backward = false
		state_machine.transition_to("AnchaleeStateWalk")
		return

	# Maintain zero velocity in Idle
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	
	# Rear Threat Spotting: check for zombies behind player in attack prep range (4.0m)
	var rear_threat = Anchalee.get_rear_threat_behind_player(4.0) if player else null
	if rear_threat:
		var to_threat = (rear_threat.global_position - Anchalee.global_position)
		to_threat.y = 0.0
		if to_threat.length() > 0.1:
			var target_y = atan2(-to_threat.x, -to_threat.z)
			Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, 8.0 * delta)
		Anchalee.is_walking_backward = true
		state_machine.transition_to("AnchaleeStateWalk")
		return
	elif player:
		# Rotate to match player's facing direction when stopped in Idle
		var target_y = player.global_rotation.y
		Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, 10.0 * delta)

func _get_repulsion() -> Vector3:
	var repulsion_vec = Vector3.ZERO
	var repulsion_radius = 4.0
	for threat in Anchalee.nearby_threats:
		if not is_instance_valid(threat): continue
		var away = (Anchalee.global_position - threat.global_position)
		away.y = 0.0
		var d = away.length()
		if d < repulsion_radius and d > 0.01:
			repulsion_vec += away.normalized() * (1.0 - (d / repulsion_radius))
	return repulsion_vec
