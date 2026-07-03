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

# ── Jink steering ──────────────────────────────────────────────────────────
@export_group("Jink Steering")
@export var jink_min_angle_deg: float = 45.0   ## Min deflection angle when stuck
@export var jink_max_angle_deg: float = 135.0  ## Max deflection angle when stuck
@export var jink_duration: float = 0.5         ## How long each jink lasts (s)
@export var jink_cooldown: float = 0.6         ## Minimum time between jinks (s)
@export var jink_stuck_threshold: float = 0.3  ## Stuck duration before jinking

var stuck_timer: float = 0.0
var _jink_cooldown_timer: float = 0.0
var _jink_angle_rad: float = 0.0
var _jink_active_timer: float = 0.0
var _jink_dir_sign: int = 1     # alternates left/right each jink
var _failed_jinks: int = 0

func enter() -> void:
	print("[Anchalee] Walk/Run")
	if is_instance_valid(Anchalee):
		Anchalee.set_player_collision(true)
		
	stuck_timer = 0.0
	_jink_cooldown_timer = 0.0
	_jink_angle_rad = 0.0
	_jink_active_timer = 0.0
	_jink_dir_sign = 1
	_failed_jinks = 0

func exit() -> void:
	if is_instance_valid(Anchalee):
		if Anchalee.nav_agent:
			Anchalee.nav_agent.avoidance_enabled = true
		Anchalee.player_is_sprinting = false
		Anchalee.is_walking_backward = false

func physics_update(delta: float) -> void:
	var aim_duck = Anchalee.is_player_aiming_or_takedown()
	var threat_duck = Anchalee.get_threat_count() >= 2
	if aim_duck or (threat_duck and Anchalee.roll_threat_duck()):
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
	var is_player_rotating = player and abs(player.get("angular_velocity")) > 0.1
	if not is_player_moving and not is_player_rotating:
		if (dist_to_target <= Anchalee.follow_stop_distance or Anchalee.is_player_in_friend_area or Anchalee.is_touching_player) and repulsion_vec.length() < 0.1:
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

	# ── Jink / stuck detection ──────────────────────────────────────────────
	if _jink_cooldown_timer > 0.0:
		_jink_cooldown_timer -= delta

	var cur_vel = Anchalee.velocity
	cur_vel.y = 0.0
	if cur_vel.length() < 0.2 and steer.length() > 0.01:
		stuck_timer += delta
		# Stage 2: trigger a jink if stuck long enough and cooldown elapsed
		if stuck_timer >= jink_stuck_threshold and _jink_cooldown_timer <= 0.0:
			var angle_deg = randf_range(jink_min_angle_deg, jink_max_angle_deg)
			_jink_angle_rad = deg_to_rad(angle_deg) * float(_jink_dir_sign)
			_jink_dir_sign *= -1
			_jink_active_timer = jink_duration
			_jink_cooldown_timer = jink_cooldown
			stuck_timer = 0.0
			_failed_jinks += 1
			print("[Anchalee] Jink #%d (%.0f°)" % [_failed_jinks, angle_deg * sign(_jink_angle_rad)])
			if _failed_jinks >= 3:
				print("[Anchalee] 3 jinks failed — transitioning to Idle")
				state_machine.transition_to("AnchaleeStateIdle")
				return
	else:
		if cur_vel.length() >= 0.2:
			stuck_timer = 0.0
			_failed_jinks = 0

	# Apply active jink rotation to steer
	if _jink_active_timer > 0.0:
		_jink_active_timer -= delta
		var cos_a = cos(_jink_angle_rad)
		var sin_a = sin(_jink_angle_rad)
		var jx = steer.x * cos_a - steer.z * sin_a
		var jz = steer.x * sin_a + steer.z * cos_a
		steer = Vector3(jx, 0.0, jz).normalized()
		
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
			if rotate_to_player and player:
				var target_y = player.global_rotation.y
				Anchalee.global_rotation.y = lerp_angle(Anchalee.global_rotation.y, target_y, walk_back_rotation_speed * delta)
			else:
				var target_y = atan2(-steer.x, -steer.z)
				Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, rotation_speed * delta)
		else:
			# Non-avoidance: move toward destination, but scale speed by alignment to avoid strafing
			var current_y = Anchalee.velocity.y
			var forward = -Anchalee.global_transform.basis.z
			if rotate_to_player:
				forward = Anchalee.global_transform.basis.z
			forward.y = 0.0
			forward = forward.normalized()
			
			var speed = target_vel.length()
			var speed_factor = 1.0
			if speed > 0.01:
				var target_dir = target_vel.normalized()
				var dot = forward.dot(target_dir)
				speed_factor = clampf(dot, 0.1, 1.0)
				if rotate_to_player:
					speed_factor = 1.0
			
			var desired_vel = target_vel * speed_factor
			Anchalee.velocity = Anchalee.velocity.move_toward(desired_vel, 15.0 * delta)
			Anchalee.velocity.y = current_y
			_apply_clamp_and_slide_collisions(steer)
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

# ─── Helpers ───────────────────────────────────────────────────────────────
## Runs move_and_slide(), then inspects slide collisions to:
##   • Player collision  → apply small friend nudge + reset to small jink angle
##   • Zombie collision  → bump jink angle toward large end
## Also strips any velocity component pointing at the player (can't push player).
func _apply_clamp_and_slide_collisions(steer: Vector3) -> void:
	Anchalee._clamp_velocity_toward_player()
	Anchalee.move_and_slide()

	var touching = false
	for i in Anchalee.get_slide_collision_count():
		var col = Anchalee.get_slide_collision(i)
		var collider = col.get_collider()
		if not is_instance_valid(collider): continue

		if collider.is_in_group("player"):
			touching = true
			# Use a small jink angle near the player
			jink_min_angle_deg = 15.0
			jink_max_angle_deg = 30.0

		elif collider.is_in_group("enemies"):
			# Zombie contact — use larger jink angles
			jink_min_angle_deg = 45.0
			jink_max_angle_deg = 135.0
	Anchalee.is_touching_player = touching
