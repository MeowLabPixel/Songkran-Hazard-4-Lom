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
var _override_meshes: Array[MeshInstance3D] = []
var _hiding_spot: Vector3 = Vector3.ZERO
var _use_hiding: bool = false

var nav_agent: NavigationAgent3D:
	get: return enemy.get_node_or_null("NavigationAgent3D") if enemy else null

func enter() -> void:
	player_is_aiming = false
	_was_aiming      = false
	_walking         = false
	_fading          = false
	_defeat_timer    = 0.0
	_use_hiding      = false
	_hiding_spot     = Vector3.ZERO
	_override_meshes.clear()
	
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
		enemy.show() # Ensure the enemy is visible when re-pooling/starting
		enemy.set_collision_mask_value(1, false)
		
	print("[StateDefeated] Enemy defeated!")
	
	# Trigger transition to the defeated state machine in AnimationTree
	if enemy and enemy.anim_tree:
		enemy.anim_tree.set("parameters/conditions/defeated", true)
		
	_play_anim(enemy.anim_set.dead, "defeated")

func exit() -> void:
	if enemy and enemy.anim_tree:
		enemy.anim_tree.set("parameters/conditions/defeated", false)
	_restore_materials()

func physics_update(_delta: float) -> void:
	if not enemy:
		return

	if not _walking:
		# Poll the AnimationTree to detect transition to the dead walk animation
		if enemy.anim_tree:
			var pb = enemy.anim_tree.get("parameters/defeated/playback")
			if pb:
				var current = String(pb.get_current_node())
				if current == enemy.anim_set.dead_walk or "walk" in current.to_lower():
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
			var move_dir = diff.normalized()
			
			# Rotate to face movement direction
			if move_dir.length() > 0.01:
				var target_y = atan2(-move_dir.x, -move_dir.z)
				enemy.rotation.y = lerp_angle(enemy.rotation.y, target_y, 6.0 * _delta)
			
			# Restrict physical velocity strictly to current forward direction
			var forward_dir = -enemy.global_transform.basis.z.normalized()
			var target_vel = forward_dir * move_speed
			
			enemy.velocity = target_vel
			enemy.move_and_slide()
		else:
			# If nav_agent finished but we didn't hit distance check (e.g. wall block), fade out
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

		var flee_dir: Vector3 = -to_player.normalized()
		var target_vel = flee_dir * move_speed
		
		enemy.velocity = target_vel
		enemy.move_and_slide()
		
		if flee_dir.length() > 0.01:
			var target_y = atan2(-flee_dir.x, -flee_dir.z)
			enemy.rotation.y = lerp_angle(enemy.rotation.y, target_y, 8.0 * _delta)

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
		
	# Find all MeshInstance3Ds under the enemy
	var meshes: Array[MeshInstance3D] = []
	var stack = [enemy]
	while stack.size() > 0:
		var curr = stack.pop_back()
		if curr is MeshInstance3D:
			meshes.append(curr)
		for child in curr.get_children():
			stack.append(child)
			
	# Duplicate materials and enable transparency override
	var materials: Array[BaseMaterial3D] = []
	_override_meshes = meshes
	for mesh in meshes:
		if mesh.mesh:
			for i in mesh.mesh.get_surface_count():
				var mat = mesh.get_active_material(i)
				if mat is BaseMaterial3D:
					var dup_mat = mat.duplicate() as BaseMaterial3D
					dup_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mesh.set_surface_override_material(i, dup_mat)
					materials.append(dup_mat)
					
	# Create a tween to fade out the alpha first
	var tween = enemy.create_tween()
	
	# 1. Fade all materials in parallel
	tween.set_parallel(true)
	for mat in materials:
		tween.tween_property(mat, "albedo_color:a", 0.0, fade_duration).set_trans(Tween.TRANS_LINEAR)
		
	# 2. Once fully transparent, start sinking
	tween.set_parallel(false)
	var target_y = enemy.global_position.y - sink_depth
	tween.tween_property(enemy, "global_position:y", target_y, sink_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 3. After sinking, hide the enemy and restore default materials
	tween.tween_callback(func():
		enemy.hide()
		_restore_materials()
	)

func _restore_materials() -> void:
	# Clear override materials so mesh uses default materials next time it is re-spawned
	for mesh in _override_meshes:
		if is_instance_valid(mesh) and mesh.mesh:
			for i in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(i, null)
	_override_meshes.clear()
