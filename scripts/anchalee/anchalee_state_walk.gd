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
var _jink_phase: int = 0

# Breathing audio tracking
var _active_breath_sfx: Node = null
var _current_breath_event: String = ""

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
	_jink_phase = 0

func exit() -> void:
	# Stop walk/run breathing sound
	if is_instance_valid(_active_breath_sfx):
		_active_breath_sfx.stop()
		_active_breath_sfx.queue_free()
	_active_breath_sfx = null
	_current_breath_event = ""
	
	if is_instance_valid(Anchalee):
		if Anchalee.nav_agent:
			Anchalee.nav_agent.avoidance_enabled = true
		Anchalee.player_is_sprinting = false
		Anchalee.is_walking_backward = false

func physics_update(delta: float) -> void:
	if Anchalee.zombie_reaction_state == "none" and Anchalee.get_threat_count() >= 1:
		var threats = Anchalee.get_threat_count()
		var duck_chance = Anchalee.reaction_chance_duck if threats >= 2 else 0.0
		var roll = randf()
		if roll <= duck_chance:
			Anchalee.zombie_reaction_state = "duck"
		elif roll <= duck_chance + Anchalee.reaction_chance_evade:
			Anchalee.zombie_reaction_state = "evade"
		else:
			Anchalee.zombie_reaction_state = "back_up"
		Anchalee.zombie_reaction_timer = Anchalee.zombie_reaction_cooldown
		
		# Play warning sound on random threat reaction behavior
		SoundManager.play_3d("vo_anchalee_warning", Anchalee)
			
	var aim_duck = Anchalee.is_player_aiming_or_takedown()
	if aim_duck or Anchalee.zombie_reaction_state == "duck":
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
	
	var move_dir = Vector3.ZERO
	var is_fallback = false
	if not Anchalee.nav_agent.is_navigation_finished():
		var next_pos = Anchalee.nav_agent.get_next_path_position()
		var diff = next_pos - Anchalee.global_position
		diff.y = 0.0
		if diff.length() > 0.01:
			move_dir = diff.normalized()

	# Tangential Evasion & Back Up logic from zombies
	var repulsion_vec = Vector3.ZERO
	var closest_zombie_pos = Vector3.ZERO
	var closest_zombie_dist = 999.0
	
	for threat in Anchalee.nearby_threats:
		if not is_instance_valid(threat): continue
		var away = (Anchalee.global_position - threat.global_position)
		away.y = 0.0
		var d = away.length()
		
		if d < closest_zombie_dist:
			closest_zombie_dist = d
			closest_zombie_pos = threat.global_position
			
		if d < repulsion_radius and d > 0.01:
			var push_away = away.normalized()
			var tangent_left = Vector3(-push_away.z, 0, push_away.x)
			var tangent_right = Vector3(push_away.z, 0, -push_away.x)
			
			var tangent = tangent_left
			if move_dir.dot(tangent_right) > move_dir.dot(tangent_left):
				tangent = tangent_right
				
			var weight = 1.0 - (d / repulsion_radius)
			# Blend tangent (80%) and outward push (20%)
			repulsion_vec += (tangent * 0.8 + push_away * 0.2).normalized() * weight

	if Anchalee.zombie_reaction_state == "back_up" and closest_zombie_dist < 999.0:
		var away_from_zombie = (Anchalee.global_position - closest_zombie_pos)
		away_from_zombie.y = 0.0
		if away_from_zombie.length() > 0.01:
			move_dir = away_from_zombie.normalized()
			Anchalee.is_walking_backward = true
			repulsion_vec = Vector3.ZERO # Ignore normal tangental evasion while deliberately backing up
			
	# Stop if we are close enough to the target destination (FriendArea) or if player is in friend area.
	# However, if the player is actively moving, stay in Walk state to follow smoothly.
	var is_player_moving = player and player.velocity.length_squared() > 0.1
	var is_player_rotating = player and abs(player.get("angular_velocity")) > 0.1
	if not is_player_moving and not is_player_rotating and Anchalee.zombie_reaction_state != "back_up":
		if (dist_to_target <= Anchalee.get_effective_follow_stop_distance() or Anchalee.is_player_in_friend_area or Anchalee.is_touching_player) and repulsion_vec.length() < 0.1:
			state_machine.transition_to("AnchaleeStateIdle")
			return
			
	# Fallback if navigation fails/finished but player is still moving or we are far from target
	if move_dir.length() < 0.01 and (dist_to_target > Anchalee.get_effective_follow_stop_distance() or is_player_moving):
		move_dir = to_target.normalized()
		is_fallback = true
			
	# Blend pathfinding with repulsion
	var steer = (move_dir + repulsion_vec).normalized()
	if steer.length() < 0.01:
		steer = move_dir
		
	# Physical Collision Steering Offset (45 degrees)
	var colliding_with_obstacle = false
	var obstacle_normal = Vector3.ZERO
	for i in range(Anchalee.get_slide_collision_count()):
		var collision = Anchalee.get_slide_collision(i)
		var collider = collision.get_collider()
		if collider and (collider.is_in_group("enemy") or collider.is_in_group("player")):
			colliding_with_obstacle = true
			obstacle_normal = collision.get_normal()
			obstacle_normal.y = 0.0
			obstacle_normal = obstacle_normal.normalized()
			break
			
	if colliding_with_obstacle and steer.length() > 0.01 and obstacle_normal.length() > 0.01:
		var tangent_left = Vector3(-obstacle_normal.z, 0, obstacle_normal.x)
		var tangent_right = Vector3(obstacle_normal.z, 0, -obstacle_normal.x)
		var chosen_tangent = tangent_left
		if steer.dot(tangent_right) > steer.dot(tangent_left):
			chosen_tangent = tangent_right
		# Heavily weight the tangent to steer sharply (up to 75-90 degrees) along the surface to avoid sticking
		steer = (steer + chosen_tangent * 2.5).normalized()

	# ── Jink / stuck detection ──────────────────────────────────────────────
	if _jink_cooldown_timer > 0.0:
		_jink_cooldown_timer -= delta

	var cur_vel = Anchalee.velocity
	cur_vel.y = 0.0
	if _jink_phase == 0:
		var is_preemptive_evade = Anchalee.zombie_reaction_state == "evade"
		if (cur_vel.length() < 0.2 and steer.length() > 0.01) or is_preemptive_evade:
			stuck_timer += delta
			# Stage 2: trigger a jink if stuck long enough and cooldown elapsed, or if preemptive
			if (stuck_timer >= jink_stuck_threshold and _jink_cooldown_timer <= 0.0) or is_preemptive_evade:
				var angle_deg = randf_range(45.0, 135.0) if is_preemptive_evade else randf_range(jink_min_angle_deg, jink_max_angle_deg)
				_jink_angle_rad = deg_to_rad(angle_deg) * float(_jink_dir_sign)
				_jink_dir_sign *= -1
				_jink_active_timer = 0.3 # Phase 1 duration
				_jink_phase = 1
				stuck_timer = 0.0
				_failed_jinks += 1
				Anchalee.zombie_reaction_state = "evading"
				print("[Anchalee] Stop & Rotate #%d (%.0f°) Preemptive: %s" % [_failed_jinks, angle_deg * sign(_jink_angle_rad), is_preemptive_evade])
				if _failed_jinks >= 3 and not is_preemptive_evade:
					print("[Anchalee] 3 jinks failed — transitioning to Idle")
					state_machine.transition_to("AnchaleeStateIdle")
					return
		else:
			if cur_vel.length() >= 0.2:
				stuck_timer = 0.0
				_failed_jinks = 0

	# Apply active jink rotation to steer
	if _jink_phase > 0:
		_jink_active_timer -= delta
		var cos_a = cos(_jink_angle_rad)
		var sin_a = sin(_jink_angle_rad)
		var jx = steer.x * cos_a - steer.z * sin_a
		var jz = steer.x * sin_a + steer.z * cos_a
		steer = Vector3(jx, 0.0, jz).normalized()
		
		if _jink_phase == 1 and _jink_active_timer <= 0.0:
			_jink_phase = 2
			_jink_active_timer = jink_duration
		elif _jink_phase == 2 and _jink_active_timer <= 0.0:
			_jink_phase = 0
			_jink_cooldown_timer = jink_cooldown
		
	# (walking backward state maintained at the top of physics_update)

	# If we are close to the target (FriendArea) or in fallback, disable avoidance to allow standing exactly on it/smooth motion
	var use_avoidance = dist_to_target > disable_avoidance_distance and not is_fallback
	if Anchalee.nav_agent.avoidance_enabled != use_avoidance:
		Anchalee.nav_agent.avoidance_enabled = use_avoidance

	var is_far = not is_in_near_area
	var is_running = is_far or Anchalee.player_is_sprinting
	
	# Dynamic breathing SFX manager
	var target_event = "vo_anchalee_Exhausted" if is_running else "vo_anchalee_Panting"
	if _current_breath_event != target_event or _active_breath_sfx == null or not is_instance_valid(_active_breath_sfx) or not _active_breath_sfx.playing:
		if is_instance_valid(_active_breath_sfx):
			_active_breath_sfx.stop()
			_active_breath_sfx.queue_free()
		_current_breath_event = target_event
		_active_breath_sfx = SoundManager.play_3d(target_event, Anchalee)
	
	var current_speed = walk_speed
	if is_running:
		current_speed = run_speed
	elif is_in_near_area:
		current_speed = near_walk_speed
		
	if Anchalee.is_walking_backward:
		current_speed = walk_back_speed
	
	if steer.length() > 0.01:
		var target_vel = steer * current_speed
		
		if _jink_phase == 1:
			target_vel = Vector3.ZERO
		
		if is_player_moving and player and _jink_phase == 0:
			# If we are close to the target position, blend our velocity with the player's velocity
			# to follow them smoothly and match their speed.
			if dist_to_target < 1.2:
				var blend = clampf(dist_to_target / 1.2, 0.0, 1.0)
				target_vel = lerp(player.velocity, target_vel, blend)
		
		var rotate_to_player = Anchalee.is_walking_backward and is_in_near_area and _jink_phase == 0
		
		if Anchalee.nav_agent.avoidance_enabled and _jink_phase != 1:
			Anchalee.nav_agent.max_speed = current_speed
			Anchalee.nav_agent.set_velocity(target_vel)
			if rotate_to_player and player:
				var target_y = player.global_rotation.y
				Anchalee.global_rotation.y = lerp_angle(Anchalee.global_rotation.y, target_y, walk_back_rotation_speed * delta)
			else:
				var look_dir = Anchalee.velocity
				look_dir.y = 0.0
				if look_dir.length_squared() > 0.01:
					var target_y = atan2(-look_dir.x, -look_dir.z)
					Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, rotation_speed * delta)
				else:
					var target_y = atan2(-steer.x, -steer.z)
					Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, rotation_speed * delta)
				
			# Handle animations
			if Anchalee.has_node("AnchaleeModel/AnimationTree"):
				var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
				var pb = tree.get("parameters/playback")
				if pb:
					pb.travel("Walk")
				var current_spd = Anchalee.velocity.length()
				var anim_scale = clampf((current_spd / walk_speed) * 1.25, 0.5, 3.0)
				tree.set("parameters/Walk/TimeScale/scale", anim_scale)
		else:
			# Non-avoidance or Phase 1 Stop & Rotate
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
				var look_dir = Anchalee.velocity
				look_dir.y = 0.0
				var target_y = 0.0
				if look_dir.length_squared() > 0.01:
					target_y = atan2(-look_dir.x, -look_dir.z)
				else:
					target_y = atan2(-steer.x, -steer.z)
					
				var r_speed = rotation_speed * 1.5 if _jink_phase == 1 else rotation_speed
				Anchalee.rotation.y = lerp_angle(Anchalee.rotation.y, target_y, r_speed * delta)
			
			# Handle animations
			if Anchalee.has_node("AnchaleeModel/AnimationTree"):
				var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
				var pb = tree.get("parameters/playback")
				if pb:
					if _jink_phase == 1:
						pb.travel("Idle")
					else:
						pb.travel("Walk")
				var current_spd = Anchalee.velocity.length()
				var anim_scale = clampf((current_spd / walk_speed) * 1.25, 0.5, 3.0)
				tree.set("parameters/Walk/TimeScale/scale", anim_scale)
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
