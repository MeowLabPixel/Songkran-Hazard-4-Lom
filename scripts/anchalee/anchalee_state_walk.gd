class_name AnchaleeStateWalk
extends AnchaleeState

@export var walk_speed: float = 3.5
@export var near_walk_speed: float = 2.8
@export var run_speed: float = 5.0
@export var walk_back_speed: float = 2.5
@export var repulsion_radius: float = 4.0
@export var rotation_speed: float = 10.0
@export var walk_back_rotation_speed: float = 3.0
@export var disable_avoidance_distance: float = 1.2
@export var stuck_timeout: float = 1.0

var stuck_timer: float = 0.0

func enter() -> void:
	print("[Anchalee] Walk/Run")
	stuck_timer = 0.0

func exit() -> void:
	if is_instance_valid(Anchalee):
		if Anchalee.nav_agent:
			Anchalee.nav_agent.avoidance_enabled = true
		Anchalee.player_is_sprinting = false
		Anchalee.is_walking_backward = false

func physics_update(delta: float) -> void:
	if Anchalee.is_player_aiming_or_takedown() or Anchalee.get_threat_count() >= 2:
		state_machine.transition_to("AnchaleeStateDuck")
		return

	var player = Anchalee.get_player()
	if not player:
		state_machine.transition_to("AnchaleeStateIdle")
		return

	var target_pos = Anchalee.get_friend_target_pos()
	var to_target = target_pos - Anchalee.global_position
	to_target.y = 0.0
	var dist_to_target = to_target.length()
	
	# Maintain walking backward & sprinting sub-behaviors dynamically via FriendNearArea
	var is_in_near_area = false
	if player:
		var near_area = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/FriendNearArea")
		if near_area:
			is_in_near_area = near_area.overlaps_body(Anchalee)
		
	# 1. Sprinting sub-behavior: when player is sprinting and they are near each other (in NearShape)
	var player_sprinting = false
	if player:
		var sm = player.get_node_or_null("Statemachine")
		if sm and sm.get("current_state") and sm.current_state.name == "Sprint":
			player_sprinting = true
			
	if player_sprinting and is_in_near_area:
		Anchalee.player_is_sprinting = true
	else:
		Anchalee.player_is_sprinting = false
		
	# 2. Walking backward sub-behavior: when player is walking backward and they are near each other (in NearShape)
	var is_player_moving_backward = false
	if player:
		var player_forward = -player.global_transform.basis.z
		is_player_moving_backward = player.velocity.dot(player_forward) < -0.1 or Input.is_action_pressed("ui_down")
		
	if is_player_moving_backward and is_in_near_area:
		Anchalee.is_walking_backward = true
	else:
		Anchalee.is_walking_backward = false
		
	if Anchalee.is_walking_backward:
		# Use raw target position for instant responsiveness when walking backward
		Anchalee.nav_agent.target_position = target_pos
	else:
		# Use smoothed target position for organic lag/inertia during normal follow
		Anchalee.nav_agent.target_position = Anchalee.smoothed_target_pos
	
	# Repulsion logic from zombies
	var repulsion_vec = Vector3.ZERO
	for threat in Anchalee.nearby_threats:
		if not is_instance_valid(threat): continue
		var away = (Anchalee.global_position - threat.global_position)
		away.y = 0.0
		var d = away.length()
		if d < repulsion_radius and d > 0.01:
			repulsion_vec += away.normalized() * (1.0 - (d / repulsion_radius))
			
	# Stop if we are close enough to the target destination (FriendArea) or if player is in friend area.
	# However, if the player is actively moving, stay in Walk state to follow smoothly.
	var is_player_moving = player and player.velocity.length_squared() > 0.1
	if not is_player_moving:
		if (dist_to_target <= Anchalee.follow_stop_distance or Anchalee.is_player_in_friend_area) and repulsion_vec.length() < 0.1:
			state_machine.transition_to("AnchaleeStateIdle")
			return

	var move_dir = Vector3.ZERO
	var is_fallback = false
	if not Anchalee.nav_agent.is_navigation_finished():
		var next_pos = Anchalee.nav_agent.get_next_path_position()
		var diff = next_pos - Anchalee.global_position
		diff.y = 0.0
		if diff.length() > 0.01:
			move_dir = diff.normalized()
			
	# Fallback if navigation fails/finished but player is still moving or we are far from target
	if move_dir.length() < 0.01 and (dist_to_target > Anchalee.follow_stop_distance or is_player_moving):
		move_dir = to_target.normalized()
		is_fallback = true
			
	# Blend pathfinding with repulsion
	var steer = (move_dir + repulsion_vec).normalized()
	if steer.length() < 0.01:
		steer = move_dir

	# If stuck against an obstacle/wall while trying to steer, transition back to Idle
	var cur_vel = Anchalee.velocity
	cur_vel.y = 0.0
	if cur_vel.length() < 0.2 and steer.length() > 0.01:
		stuck_timer += delta
		if stuck_timer >= stuck_timeout:
			print("[Anchalee] Stuck detected against obstacle, transitioning to Idle")
			state_machine.transition_to("AnchaleeStateIdle")
			return
	else:
		stuck_timer = 0.0
		
	# (walking backward state maintained at the top of physics_update)

	# If we are close to the target (FriendArea) or in fallback, disable avoidance to allow standing exactly on it/smooth motion
	var use_avoidance = dist_to_target > disable_avoidance_distance and not is_fallback
	if Anchalee.nav_agent.avoidance_enabled != use_avoidance:
		Anchalee.nav_agent.avoidance_enabled = use_avoidance

	var is_far = not is_in_near_area
	var is_running = is_far or Anchalee.player_is_sprinting
	
	var current_speed = walk_speed
	if is_running:
		current_speed = run_speed
	elif is_in_near_area:
		current_speed = near_walk_speed
		
	if Anchalee.is_walking_backward:
		current_speed = walk_back_speed
	
	if steer.length() > 0.01:
		var target_vel = steer * current_speed
		
		if is_player_moving and player:
			# If we are close to the target position, blend our velocity with the player's velocity
			# to follow them smoothly and match their speed.
			if dist_to_target < 1.2:
				var blend = clampf(dist_to_target / 1.2, 0.0, 1.0)
				target_vel = lerp(player.velocity, target_vel, blend)
		
		var rotate_to_player = Anchalee.is_walking_backward and is_in_near_area
		
		if Anchalee.nav_agent.avoidance_enabled:
			Anchalee.nav_agent.max_speed = current_speed
			Anchalee.nav_agent.set_velocity(target_vel)
			cur_vel = Anchalee.velocity
			cur_vel.y = 0.0
			if rotate_to_player and player:
				var target_y = player.global_rotation.y
				Anchalee.global_rotation.y = lerp_angle(Anchalee.global_rotation.y, target_y, walk_back_rotation_speed * delta)
			elif cur_vel.length() > 0.1:
				var target_y = atan2(-cur_vel.x, -cur_vel.z)
				Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, rotation_speed * delta)
		else:
			# Non-avoidance: lerp velocity to add smooth inertia
			var current_y = Anchalee.velocity.y
			Anchalee.velocity = Anchalee.velocity.move_toward(target_vel, 10.0 * delta)
			Anchalee.velocity.y = current_y
			Anchalee.move_and_slide()
			if rotate_to_player and player:
				var target_y = player.global_rotation.y
				Anchalee.global_rotation.y = lerp_angle(Anchalee.global_rotation.y, target_y, walk_back_rotation_speed * delta)
			else:
				var target_y = atan2(-steer.x, -steer.z)
				Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, rotation_speed * delta)
			
		# Handle animations
		if Anchalee.has_node("AnchaleeModel/AnimationTree"):
			var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
			var pb = tree.get("parameters/playback")
			if pb:
				pb.travel("Walk")
	else:
		if Anchalee.nav_agent.avoidance_enabled:
			Anchalee.nav_agent.set_velocity(Vector3.ZERO)
		else:
			# Decelerate smoothly to stop
			var current_y = Anchalee.velocity.y
			Anchalee.velocity = Anchalee.velocity.move_toward(Vector3.ZERO, 10.0 * delta)
			Anchalee.velocity.y = current_y
			Anchalee.move_and_slide()
			
		# Play idle if stuck
		if Anchalee.has_node("AnchaleeModel/AnimationTree"):
			var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
			var pb = tree.get("parameters/playback")
			if pb: pb.travel("Idle")
