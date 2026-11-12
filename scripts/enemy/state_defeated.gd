class_name StateDefeated
extends EnemyState

@export var move_speed: float = 1.2   # slower shamble than a hunting zombie
@export var fade_duration: float = 1.5
@export var sink_duration: float = 1.0
@export var sink_depth: float = 0.8
@export var fallback_walk_time: float = 3.0
@export var hiding_timeout: float = 8.0
@export var search_distances: Array[float] = [6.0, 10.0, 14.0]

var player_is_aiming: bool = false
var _was_aiming: bool      = false
var _walking: bool         = false   # true once the dead intro anim finishes
var _fading: bool          = false
var _defeat_timer: float   = 0.0
var _startup_duration: float = 1.0
var _startup_timer: float = 0.0
var _override_meshes: Array[MeshInstance3D] = []
var _hiding_spot: Vector3 = Vector3.ZERO
var _use_hiding: bool = false
var _last_steer_side: float = 0.0
var _stuck_timer: float = 0.0
var _pushed_enemies_in_walk: Array[Node] = []

var nav_agent: NavigationAgent3D:
	get: return enemy.get_node_or_null("NavigationAgent3D") if enemy else null

func enter() -> void:
	player_is_aiming = false
	_was_aiming      = false
	_walking         = false
	_fading          = false
	_defeat_timer    = 0.0
	_startup_timer   = 0.0
	_startup_duration = 1.0
	_stuck_timer     = 0.0
	_last_steer_side = 0.0
	_use_hiding      = false
	_hiding_spot     = Vector3.ZERO
	_override_meshes.clear()
	_pushed_enemies_in_walk.clear()
	
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
		enemy.show() # Ensure the enemy is visible when re-pooling/starting
		enemy.collision_layer = 0
		enemy.collision_mask = 1 # Keep environment/floor collision active (Layer 1)
		if nav_agent:
			nav_agent.avoidance_enabled = false
		
		# Compute startup animation duration to prevent premature walking
		if enemy.anim_player and enemy.anim_player.has_animation(enemy.anim_set.dead):
			var base_len = enemy.anim_player.get_animation(enemy.anim_set.dead).length
			var ts: float = 1.0
			if enemy.anim_tree:
				var ts_val = enemy.anim_tree.get("parameters/defeated/" + enemy.anim_set.dead + "/TimeScale/scale")
				if typeof(ts_val) in [TYPE_FLOAT, TYPE_INT] and float(ts_val) > 0.0:
					ts = float(ts_val)
			_startup_duration = base_len / ts
		
	if enemy and enemy.show_debug_label:
		print("[StateDefeated] Enemy defeated! Startup dur: ", _startup_duration)
	
	# Trigger transition to the defeated state machine in AnimationTree
	if enemy and enemy.anim_tree:
		enemy.anim_tree.set("parameters/conditions/defeated", true)
		
	_force_anim_instant(enemy.anim_set.dead, "defeated")

func exit() -> void:
	if enemy and enemy.anim_tree:
		enemy.anim_tree.set("parameters/conditions/defeated", false)
	_restore_materials()

func physics_update(_delta: float) -> void:
	if not enemy:
		return

	if not _walking:
		_startup_timer += _delta
		if not enemy.is_on_floor():
			enemy.velocity.x = 0.0
			enemy.velocity.z = 0.0
			enemy.velocity.y -= 9.8 * _delta
			enemy.move_and_slide()
		else:
			enemy.velocity = Vector3.ZERO
		# Poll the AnimationTree to detect transition to the dead walk animation
		if enemy.anim_tree:
			var pb = enemy.anim_tree.get("parameters/defeated/playback")
			if pb:
				var current = String(pb.get_current_node())
				var is_dead_walk = (current == enemy.anim_set.dead_walk)
				# Require startup animation to finish playing before starting walk navigation:
				# Either node transitioned cleanly to dead_walk AND at least 0.3s passed,
				# OR the full startup duration has elapsed.
				if (is_dead_walk and _startup_timer >= 0.3) or (_startup_timer >= _startup_duration):
					_walking = true
					_defeat_timer = 0.0
					
					# Find a hiding spot out of player sight
					var player = _get_player()
					if player:
						var spot = _find_hiding_spot(player)
						if spot != Vector3.ZERO:
							_hiding_spot = spot
							_use_hiding = true
							if nav_agent:
								nav_agent.target_position = _hiding_spot
							print("[StateDefeated] Found hiding spot at: ", _hiding_spot)
						else:
							_use_hiding = false
							print("[StateDefeated] No hiding spot found, falling back to walk-away.")
		return

	if _fading:
		return

	if _use_hiding:
		_defeat_timer += _delta
		
		# Distance check: have we arrived at the hiding spot?
		var dist_to_spot = enemy.global_position.distance_to(_hiding_spot)
		# Fallback: if stuck or took too long, fade out anyway
		if dist_to_spot < 1.0 or _defeat_timer >= hiding_timeout:
			_fading = true
			_fade_out_and_hide()
			return

		# Move along navigation path
		if nav_agent and not nav_agent.is_navigation_finished():
			var next_pos = nav_agent.get_next_path_position()
			var diff = next_pos - enemy.global_position
			diff.y = 0.0
			var path_dir = diff.normalized()
			var move_dir = _get_avoidance_direction(path_dir)
			
			# Add separation force & push active zombies away within 0.8m
			var separation_force = Vector3.ZERO
			var close_count = 0
			for other in enemy.get_tree().get_nodes_in_group("enemies"):
				if other == enemy or not is_instance_valid(other) or other.is_defeated:
					continue
				var dist = enemy.global_position.distance_to(other.global_position)
				if dist < 0.8 and dist > 0.01:
					var push = (enemy.global_position - other.global_position).normalized()
					var strength = (0.8 - dist) / 0.8
					separation_force += push * strength
					close_count += 1
					
					# Also push the active zombie away
					if not other in _pushed_enemies_in_walk:
						_pushed_enemies_in_walk.append(other)
						var push_dir = (other.global_position - enemy.global_position).normalized()
						push_dir.y = 0.0
						push_dir = push_dir.normalized()
						other.take_hit({
							"damage": 0,
							"hit_type": "push",
							"hit_direction": push_dir,
							"source": enemy
						})
			if path_dir.length() > 0.01 and close_count > 0:
				move_dir = (move_dir + separation_force * 0.8).normalized()
				move_dir.y = 0.0
			
			# Rotate to face movement direction, snapped to 30-degree increments
			if move_dir.length() > 0.01:
				var target_y = atan2(-move_dir.x, -move_dir.z)
				var step_rad = deg_to_rad(30.0)
				target_y = round(target_y / step_rad) * step_rad

				var actual_speed = enemy.get_real_velocity().slide(Vector3.UP).length()
				if actual_speed < 0.15:
					_stuck_timer += _delta
					if _stuck_timer >= 0.4:
						_stuck_timer = 0.0
						_last_steer_side = -_last_steer_side if _last_steer_side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
				else:
					_stuck_timer = 0.0

				var rot_weight = 6.0
				if actual_speed < move_speed * 0.5:
					var block_factor = 1.0 - (actual_speed / (move_speed * 0.5))
					rot_weight = lerpf(6.0, 12.0, block_factor)

				enemy.rotation.y = lerp_angle(enemy.rotation.y, target_y, rot_weight * _delta)
			
			# Restrict physical velocity strictly to current forward direction
			var forward_dir = -enemy.global_transform.basis.z.normalized()
			var target_vel = forward_dir * move_speed
			if not enemy.is_on_floor():
				target_vel.y = enemy.velocity.y - 9.8 * _delta
			else:
				target_vel.y = -0.1
			
			enemy.velocity = target_vel
			enemy.move_and_slide()
		else:
			# If nav_agent finished but we didn't hit distance check (e.g. wall block), fade out
			if not enemy.is_on_floor():
				enemy.velocity.y -= 9.8 * _delta
			else:
				enemy.velocity.y = 0.0
			enemy.move_and_slide()
			_fading = true
			_fade_out_and_hide()
	else:
		# Fallback: Walk away from the player for fallback_walk_time, then fade out
		_defeat_timer += _delta
		if _defeat_timer >= fallback_walk_time:
			_fading = true
			_fade_out_and_hide()
			return

		var player := _get_player()
		if player == null:
			enemy.velocity = Vector3.ZERO
			return

		var to_player: Vector3 = player.global_position - enemy.global_position
		to_player.y = 0.0

		if to_player.length() < 0.1:
			enemy.velocity = Vector3.ZERO
			return

		var raw_flee_dir: Vector3 = -to_player.normalized()
		var move_dir = _get_avoidance_direction(raw_flee_dir)

		# Add separation force & push active zombies away within 0.8m
		var separation_force = Vector3.ZERO
		var close_count = 0
		for other in enemy.get_tree().get_nodes_in_group("enemies"):
			if other == enemy or not is_instance_valid(other) or other.is_defeated:
				continue
			var dist = enemy.global_position.distance_to(other.global_position)
			if dist < 0.8 and dist > 0.01:
				var push = (enemy.global_position - other.global_position).normalized()
				var strength = (0.8 - dist) / 0.8
				separation_force += push * strength
				close_count += 1
				if not other in _pushed_enemies_in_walk:
					_pushed_enemies_in_walk.append(other)
					var push_dir = (other.global_position - enemy.global_position).normalized()
					push_dir.y = 0.0
					push_dir = push_dir.normalized()
					other.take_hit({
						"damage": 0,
						"hit_type": "push",
						"hit_direction": push_dir,
						"source": enemy
					})
		if raw_flee_dir.length() > 0.01 and close_count > 0:
			move_dir = (move_dir + separation_force * 0.8).normalized()
			move_dir.y = 0.0

		var actual_speed = enemy.get_real_velocity().slide(Vector3.UP).length()
		if actual_speed < 0.15:
			_stuck_timer += _delta
			if _stuck_timer >= 0.4:
				_stuck_timer = 0.0
				_last_steer_side = -_last_steer_side if _last_steer_side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
		else:
			_stuck_timer = 0.0

		if move_dir.length() > 0.01:
			var target_y = atan2(-move_dir.x, -move_dir.z)
			var step_rad = deg_to_rad(30.0)
			target_y = round(target_y / step_rad) * step_rad

			var rot_weight = 6.0
			if actual_speed < move_speed * 0.5:
				var block_factor = 1.0 - (actual_speed / (move_speed * 0.5))
				rot_weight = lerpf(6.0, 12.0, block_factor)

			enemy.rotation.y = lerp_angle(enemy.rotation.y, target_y, rot_weight * _delta)

		var forward_dir = -enemy.global_transform.basis.z.normalized()
		var target_vel = forward_dir * move_speed
		if not enemy.is_on_floor():
			target_vel.y = enemy.velocity.y - 9.8 * _delta
		else:
			target_vel.y = -0.1

		enemy.velocity = target_vel
		enemy.move_and_slide()

func handle_hit(_hit_data: Dictionary) -> String:
	return ""

func set_aimed_at(aimed: bool) -> void:
	player_is_aiming = aimed

# ── Helpers ────────────────────────────────────────────────────
func _get_player() -> Node3D:
	var players := enemy.get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func _is_point_hidden_from_player(point: Vector3, player: Node3D) -> bool:
	if not player or not enemy:
		return false
		
	var space_state = enemy.get_world_3d().direct_space_state
	var start_pos = player.global_position
	# Use player camera or head height if available
	if player.has_node("Camera3D"):
		start_pos = player.get_node("Camera3D").global_position
	elif player.has_node("Head"):
		start_pos = player.get_node("Head").global_position
	else:
		start_pos.y += 1.6 # fallback to normal human height
		
	# Raycast from player height to zombie head height at target point
	var query = PhysicsRayQueryParameters3D.create(start_pos, point + Vector3(0, 1.2, 0))
	query.exclude = [player.get_rid(), enemy.get_rid()]
	# Collide with environment layers (layer 1 is standard static body)
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	if result:
		# Ray hit a wall or obstacle before reaching the target point, meaning it's hidden!
		return true
		
	return false

func _find_hiding_spot(player: Node3D) -> Vector3:
	if not enemy or not player:
		return Vector3.ZERO
		
	var navigation_map = enemy.get_world_3d().navigation_map
	var base_pos = enemy.global_position
	
	# Sample distances and directions around the zombie
	var distances = search_distances
	var angles = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
	
	var best_spot = Vector3.ZERO
	var best_dist = 999.0
	
	for dist in distances:
		for angle_deg in angles:
			var angle_rad = deg_to_rad(angle_deg)
			var offset = Vector3(cos(angle_rad), 0, sin(angle_rad)) * dist
			var test_pos = base_pos + offset
			
			# Project target spot onto the navigation map
			var nav_pos = NavigationServer3D.map_get_closest_point(navigation_map, test_pos)
			if nav_pos.distance_to(test_pos) > 2.0:
				continue # Point is too far off NavMesh
				
			if _is_point_hidden_from_player(nav_pos, player):
				var path_dist = nav_pos.distance_to(base_pos)
				# Prefer closer hiding spots that are at least 4 meters away to make it look natural
				if path_dist > 4.0 and path_dist < best_dist:
					best_dist = path_dist
					best_spot = nav_pos
					
	return best_spot

func _fade_out_and_hide() -> void:
	if not enemy:
		return
		
	var meshes: Array[MeshInstance3D] = []
	if "_enemy_meshes" in enemy and not enemy._enemy_meshes.is_empty():
		meshes = enemy._enemy_meshes
	else:
		var stack = [enemy]
		while stack.size() > 0:
			var curr = stack.pop_back()
			if curr is MeshInstance3D:
				meshes.append(curr)
			for child in curr.get_children():
				stack.append(child)
				
	_override_meshes = meshes
	
	# Tween mesh transparency directly (ZERO material duplication, zero shader compile stalls)
	var tween = enemy.create_tween()
	tween.set_parallel(true)
	for mesh in meshes:
		if is_instance_valid(mesh):
			tween.tween_property(mesh, "transparency", 1.0, fade_duration).set_trans(Tween.TRANS_LINEAR)
		
	# 2. Once fully transparent, start sinking
	tween.set_parallel(false)
	tween.tween_callback(func():
		if is_instance_valid(enemy):
			enemy.collision_mask = 0
	)
	var target_y = enemy.global_position.y - sink_depth
	tween.tween_property(enemy, "global_position:y", target_y, sink_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 3. After sinking, hide the enemy, restore transparency, and release to pool (or free)
	tween.tween_callback(func():
		if is_instance_valid(enemy):
			enemy.hide()
			_restore_materials()
			if EnemyPool.is_pooled(enemy):
				EnemyPool.release(enemy)
			else:
				enemy.queue_free()
	)

func _restore_materials() -> void:
	for mesh in _override_meshes:
		if is_instance_valid(mesh):
			mesh.transparency = 0.0
	_override_meshes.clear()

func _get_avoidance_direction(base_dir: Vector3) -> Vector3:
	if not enemy or not enemy.is_inside_tree() or base_dir.length() <= 0.01:
		return base_dir
		
	var space_state = enemy.get_world_3d().direct_space_state
	var start = enemy.global_position + Vector3(0, 0.8, 0) # Cast at chest/center height
	
	# Wall normal from physics body contact if already touching a wall
	var wall_contact_normal = Vector3.ZERO
	if enemy.is_on_wall():
		wall_contact_normal = enemy.get_wall_normal()
		wall_contact_normal.y = 0.0
		if wall_contact_normal.length() > 0.01:
			wall_contact_normal = wall_contact_normal.normalized()
			
	# Helper to check if a specific direction is blocked by wall or other zombies
	var is_blocked = func(dir: Vector3) -> bool:
		# If touching a wall, reject directions pushing back into the wall
		if wall_contact_normal != Vector3.ZERO and dir.dot(wall_contact_normal) < 0.05:
			return true

		# 1. Physics raycast check (environment/static obstacles on Layer 1) across 3 probes (Center, Left shoulder, Right shoulder)
		var side_offset = dir.cross(Vector3.UP).normalized() * 0.28
		for offset in [Vector3.ZERO, -side_offset, side_offset]:
			var p_start = start + offset
			var p_end = p_start + dir * 1.5
			var query = PhysicsRayQueryParameters3D.create(p_start, p_end)
			query.collision_mask = 1 # Environment / Static World only (Layer 1)
			query.exclude = [enemy.get_rid()]
			var result = space_state.intersect_ray(query)
			if not result.is_empty():
				return true
			
		# 2. Check for other zombies blocking in that direction
		for other in enemy.get_tree().get_nodes_in_group("enemies"):
			if other == enemy or not is_instance_valid(other) or other.is_defeated:
				continue
			var dist = enemy.global_position.distance_to(other.global_position)
			if dist < 1.5:
				var to_other = (other.global_position - enemy.global_position).normalized()
				if dir.dot(to_other) > 0.5: # Other zombie is in front of this direction (60 degrees)
					return true
		return false

	# If touching a wall and pushing into it, deflect base_dir along wall plane
	var effective_base_dir = base_dir
	if wall_contact_normal != Vector3.ZERO and base_dir.dot(wall_contact_normal) < 0.0:
		var slide_dir = base_dir.slide(wall_contact_normal)
		slide_dir.y = 0.0
		if slide_dir.length() > 0.01:
			effective_base_dir = slide_dir.normalized()

	# If the direct path is not blocked, proceed straight
	if not is_blocked.call(effective_base_dir):
		return effective_base_dir
		
	# Check if environment wall blocked base_dir across the 3 probes
	var env_hit_pos: Vector3 = Vector3.ZERO
	var env_hit_normal: Vector3 = wall_contact_normal
	var hit_side: float = 0.0 # -1.0 = left shoulder hit, 1.0 = right shoulder hit
	var min_env_dist = 999.0
	var side_offset = effective_base_dir.cross(Vector3.UP).normalized() * 0.28
	
	for side_mult in [0.0, -1.0, 1.0]:
		var offset = side_offset * side_mult
		var p_start = start + offset
		var p_end = p_start + effective_base_dir * 1.5
		var env_query = PhysicsRayQueryParameters3D.create(p_start, p_end)
		env_query.collision_mask = 1 # Layer 1 only
		env_query.exclude = [enemy.get_rid()]
		var env_result = space_state.intersect_ray(env_query)
		if not env_result.is_empty():
			var dist = p_start.distance_to(env_result.position)
			if dist < min_env_dist:
				min_env_dist = dist
				env_hit_pos = env_result.position
				env_hit_normal = env_result.normal
				hit_side = side_mult
		
	# Find closest blocking zombie to decide which way to turn first
	var min_dist = 999.0
	var closest_other = null
	for other in enemy.get_tree().get_nodes_in_group("enemies"):
		if other == enemy or not is_instance_valid(other) or other.is_defeated:
			continue
		var dist = enemy.global_position.distance_to(other.global_position)
		if dist < 1.5:
			var to_other = (other.global_position - enemy.global_position).normalized()
			if effective_base_dir.dot(to_other) > 0.5:
				if dist < min_dist:
					min_dist = dist
					closest_other = other
					
	var zombie_dist = min_dist
	var env_dist = min_env_dist if env_hit_pos != Vector3.ZERO else (0.1 if wall_contact_normal != Vector3.ZERO else 999.0)

	var steer_left_first = true
	if closest_other and zombie_dist <= env_dist:
		var to_other = (closest_other.global_position - enemy.global_position).normalized()
		var cross = effective_base_dir.cross(to_other)
		if abs(cross.y) < 0.1:
			if _last_steer_side != 0.0:
				steer_left_first = (_last_steer_side > 0.0)
			else:
				steer_left_first = true
				_last_steer_side = 1.0
		else:
			if cross.y > 0:
				steer_left_first = false # Steer right first away from zombie on left
				_last_steer_side = -1.0
			else:
				steer_left_first = true # Steer left first away from zombie on right
				_last_steer_side = 1.0
	elif env_hit_pos != Vector3.ZERO or env_hit_normal != Vector3.ZERO:
		if hit_side < 0.0:
			# Left shoulder hit wall corner -> steer right first
			steer_left_first = false
			_last_steer_side = -1.0
		elif hit_side > 0.0:
			# Right shoulder hit wall corner -> steer left first
			steer_left_first = true
			_last_steer_side = 1.0
		else:
			var to_wall = (env_hit_pos - start) if env_hit_pos != Vector3.ZERO else -env_hit_normal
			to_wall.y = 0.0
			if to_wall.length() > 0.01:
				to_wall = to_wall.normalized()
				var cross = effective_base_dir.cross(to_wall)
				if abs(cross.y) < 0.1 and env_hit_normal != Vector3.ZERO:
					var cross_norm = effective_base_dir.cross(env_hit_normal)
					if cross_norm.y > 0:
						steer_left_first = false # Wall normal leans right, steer right
						_last_steer_side = -1.0
					elif cross_norm.y < 0:
						steer_left_first = true # Wall normal leans left, steer left
						_last_steer_side = 1.0
					else:
						if _last_steer_side != 0.0:
							steer_left_first = (_last_steer_side > 0.0)
						else:
							steer_left_first = true
							_last_steer_side = 1.0
				else:
					if cross.y > 0:
						steer_left_first = false # Wall hit is on the left, steer right away from it
						_last_steer_side = -1.0
					else:
						steer_left_first = true # Wall hit is on the right, steer left away from it
						_last_steer_side = 1.0
	else:
		_last_steer_side = 0.0

	var angles = [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]
	if not steer_left_first:
		angles = [-30.0, 30.0, -60.0, 60.0, -90.0, 90.0]
		
	for angle in angles:
		var rad = deg_to_rad(angle)
		var rotated_dir = effective_base_dir.rotated(Vector3.UP, rad).normalized()
		if not is_blocked.call(rotated_dir):
			return rotated_dir
			
	# If everything is blocked, fallback to effective base direction
	return effective_base_dir
