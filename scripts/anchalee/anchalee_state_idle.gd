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
	var aim_duck = Anchalee.is_player_aiming_or_takedown()
	var threat_duck = Anchalee.get_threat_count() >= 2
	if aim_duck or (threat_duck and Anchalee.roll_threat_duck()):
		state_machine.transition_to("AnchaleeStateDuck")
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
			
	var is_player_moving_backward = false
	if player:
		var player_forward = -player.global_transform.basis.z
		is_player_moving_backward = player.velocity.dot(player_forward) < -0.1 or Input.is_action_pressed("ui_down")
		
	var should_walk_back = is_player_moving_backward and is_in_near_area
	
	var is_player_moving = player and player.velocity.length_squared() > 0.1
	if dist_to_target > Anchalee.follow_start_distance or should_walk_back or is_player_moving:
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
	
	# Rotate to match player's facing direction
	if player:
		# player.global_rotation.y is the direction the player is facing
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
