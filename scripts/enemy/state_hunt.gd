class_name StateHunt
extends EnemyState

@export var move_speed: float = 2.0
@export var attack_cone_half_angle: float = 45.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.3
@export var attack_state: String = "StateAttack"
@export var walk_back_range: float = 1.8
@export var guaranteed_grab_range: float = 1.0
@export var walk_back_speed_multiplier: float = 0.8

@export_group("Animation Timescales")
@export var walk_timescale: float = 1.0
@export var walk_back_timescale: float = -2.0

@export var stun_recovery_pause: float = 0.5

@export_group("Hunt Sprint")
@export var sprint_speed: float = 4.0
@export var sprint_timescale: float = 2.0
@export var sprint_duration_min: float = 1.5
@export var sprint_duration_max: float = 2.5
@export var sprint_cooldown_min: float = 3.0
@export var sprint_cooldown_max: float = 6.0
@export var sprint_activation_chance_per_sec: float = 0.2

static var sprinting_enemies: Array = []

var is_sprinting: bool = false
var _sprint_timer: float = 0.0
var _sprint_duration: float = 0.0
var _sprint_cooldown_timer: float = 0.0

var nav_agent: NavigationAgent3D:
	get: return enemy.get_node_or_null("NavigationAgent3D") if enemy else null

var _walk_anim: String = ""
var _is_fleeing: bool = false
var trigger_stun_recovery: bool = false
var trigger_attack_recovery: bool = false
var _stun_recovery_timer: float = 0.0
var _attack_recovery_timer: float = 0.0
var _path_update_timer: float = 0.0
var _getup_block_timer: float = 0.0

var _has_token: bool = false
var _selected_attack: String = ""
var _token_hold_elapsed: float = 0.0

@export_group("Attack Token Settings")
@export var attack_prep_range: float = 4.0
@export var token_max_hold_time: float = 5

@export_group("Circling / Pacing")
@export var circling_radius: float = 2.5
@export var circling_speed: float = 0.3

static func can_start_sprint() -> bool:
	var active_sprinters = []
	for s in sprinting_enemies:
		if is_instance_valid(s) and s.is_sprinting:
			active_sprinters.append(s)
	sprinting_enemies = active_sprinters

	var current_count = sprinting_enemies.size()
	if current_count >= 2:
		return false
	if current_count == 1:
		return randf() < 0.15
	return true

func initialize_state() -> void:
	if enemy and enemy.anim_set:
		_walk_anim = enemy.anim_set.get_walk_anim()

func trigger_getup_block(duration: float) -> void:
	_getup_block_timer = duration
	if enemy:
		enemy.attack_blocked = true

func is_in_vulnerable_getup() -> bool:
	return _getup_block_timer > 0.0

func enter() -> void:
	print("[StateHunt] Entered Hunt.")
	_is_fleeing = false
	is_sprinting = false
	_sprint_timer = 0.0
	_sprint_duration = 0.0
	_has_token = false
	_selected_attack = ""
	_token_hold_elapsed = 0.0
	
	if enemy and enemy.is_inside_tree() and enemy.get_tree().root.has_node("GameManager"):
		enemy.get_tree().root.get_node("GameManager").start_timer()
	
	if enemy and enemy.anim_set:
		_walk_anim = enemy.anim_set.get_walk_anim()
		_update_walk_timescale()

	var apply_offset: float = -1.0
	
	if _getup_block_timer > 0.0:
		# Let the get-up animation blend out naturally without forcing idle/walk
		return
	
	if trigger_stun_recovery:
		trigger_stun_recovery = false
		_stun_recovery_timer = stun_recovery_pause * 0.5
		# Don't force-play idle here — let the AnimationTree's own
		# blend transitions (hit_stun → End → hit → End) handle the smooth exit.
		# The recovery pause timer keeps the zombie still while the blend plays.
		return
		
	if trigger_attack_recovery:
		trigger_attack_recovery = false
		_attack_recovery_timer = 0.5 # Pause to allow attack recovery crossfade to play
		_play_anim(enemy.anim_set.idle)
	elif apply_offset >= 0.0:
		_play_anim(enemy.anim_set.idle)
		if enemy and enemy.anim_tree:
			enemy.get_tree().process_frame.connect(func():
				if is_instance_valid(enemy) and is_instance_valid(enemy.anim_tree):
					enemy.anim_tree.advance(apply_offset)
			, CONNECT_ONE_SHOT)
	else:
		_play_anim(_walk_anim)

func exit() -> void:
	_getup_block_timer = 0.0
	if enemy:
		enemy.attack_blocked = false
		if enemy.anim_player:
			enemy.anim_player.speed_scale = 1.0
		if enemy.has_meta("getup_elapsed_time"):
			enemy.remove_meta("getup_elapsed_time")
		if enemy.has_meta("getup_duration"):
			enemy.remove_meta("getup_duration")
		if enemy.anim_tree and "parameters/hit/Getup_End/conditions/idle_block" in enemy.anim_tree:
			enemy.anim_tree.set("parameters/hit/Getup_End/conditions/idle_block", false)
			
	if _has_token:
		if not state_machine or state_machine.next_state_name != "StateAttack":
			if enemy:
				var token_manager = enemy.get_node("/root/AttackTokenManager")
				token_manager.release_token(enemy)
		_has_token = false
		_selected_attack = ""
		
	if not state_machine or state_machine.next_state_name != "StateAttack":
		if enemy and enemy.anim_tree and enemy.anim_tree.active:
			if "parameters/Walk Zombie/Transition/transition_request" in enemy.anim_tree:
				enemy.anim_tree.set("parameters/Walk Zombie/Transition/transition_request", "default")
				
	_end_sprint()

func physics_update(_delta: float) -> void:
	# ─── Sprint Cooldown ─────────────────────────────────────────────────────
	if _sprint_cooldown_timer > 0.0:
		_sprint_cooldown_timer -= _delta

	# ─── Sprint Update ───────────────────────────────────────────────────────
	if is_sprinting:
		_sprint_timer += _delta
		if _sprint_timer >= _sprint_duration:
			_end_sprint()

	# Accumulate get-up elapsed time
	if enemy and enemy.has_meta("getup_elapsed_time"):
		var elapsed = enemy.get_meta("getup_elapsed_time") + _delta
		enemy.set_meta("getup_elapsed_time", elapsed)

	if _getup_block_timer > 0.0:
		if enemy and enemy.anim_tree:
			var root_pb = enemy.anim_tree.get("parameters/playback")
			var hit_pb = enemy.anim_tree.get("parameters/hit/playback")
			var getup_end_pb = enemy.anim_tree.get("parameters/hit/Getup_End/playback")
			var root_node = String(root_pb.get_current_node()) if root_pb else "none"
			var hit_node = String(hit_pb.get_current_node()) if hit_pb else "none"
			var getup_end_node = String(getup_end_pb.get_current_node()) if getup_end_pb else "none"
			print("[StateHunt debug] Timer: %.2f | Root Node: %s | Hit Node: %s | Getup_End Node: %s" % [_getup_block_timer, root_node, hit_node, getup_end_node])

		_getup_block_timer -= _delta
		if _getup_block_timer <= 0.0:
			if enemy:
				enemy.attack_blocked = false
				if enemy.anim_tree and "parameters/hit/Getup_End/conditions/idle_block" in enemy.anim_tree:
					enemy.anim_tree.set("parameters/hit/Getup_End/conditions/idle_block", true)
				if enemy.has_meta("getup_elapsed_time"):
					enemy.remove_meta("getup_elapsed_time")
				if enemy.has_meta("getup_duration"):
					enemy.remove_meta("getup_duration")
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
		return
		
	if _stun_recovery_timer > 0.0 or _attack_recovery_timer > 0.0:
		_stun_recovery_timer -= _delta
		_attack_recovery_timer -= _delta
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
		return
		
	var player := _get_player()
	
	# Stop hunting if player is dead
	var players = enemy.get_tree().get_nodes_in_group("player")
	var main_player = players[0] if players.size() > 0 else null
	if main_player and main_player.has_method("is_dead") and main_player.is_dead():
		_play_anim(enemy.anim_set.idle)
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
		return

	var player_pos: Vector3 = player.global_position if player else enemy.global_position
	var to_player: Vector3 = (player_pos - enemy.global_position)
	to_player.y = 0.0
	var dist_to_player: float = to_player.length()

	var target_pos: Vector3 = _get_target_position()
	var to_target: Vector3 = (target_pos - enemy.global_position)
	to_target.y = 0.0
	var flat_dist: float = to_target.length()

	if is_sprinting and dist_to_player <= 3.0:
		_end_sprint()

	if dist_to_player <= guaranteed_grab_range:
		if enemy and "guaranteed_grab_next_attack" in enemy:
			enemy.guaranteed_grab_next_attack = true

	var dir_to_player: Vector3 = to_player.normalized()
	var forward: Vector3 = -enemy.global_transform.basis.z

	var can_attack: bool = true
	if enemy and "last_attack_time" in enemy:
		can_attack = (Time.get_ticks_msec() / 1000.0) - enemy.last_attack_time >= attack_cooldown
		
	var is_restricted: bool = not can_attack or enemy.attack_blocked

	# ─── Walk back check ───────────────────────────────────────────────────────
	# Walk back if attack is on cooldown OR attacks are blocked (e.g. player grabbed)
	if is_restricted and walk_back_range > 0.0 and dist_to_player < walk_back_range:
		_is_fleeing = true
		_walk_back(dir_to_player, _delta)
		return

	_is_fleeing = false

	# ─── Behind check ──────────────────────────────────────────────────────────
	var path_dir_for_turn: Vector3 = Vector3.ZERO
	if nav_agent and not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var diff = next_pos - enemy.global_position
		diff.y = 0.0
		if diff.length() > 0.01:
			path_dir_for_turn = diff.normalized()
			
	var dot_player: float = forward.dot(dir_to_player)
	var dot_path: float = forward.dot(path_dir_for_turn) if path_dir_for_turn.length() > 0.01 else dot_player

	# Only turn back when BOTH the player and the actual path are behind us.
	# This prevents zombies from constantly turning back when they are forced to 
	# walk backwards to navigate around an obstacle, or when pushed by separation forces.
	if dot_player < -0.7 and dot_path < -0.5:
		state_machine.transition_to("StateTurnBack")
		return

	# ─── Global Cooldown Check ───────────────────────────────────────────────
	if is_restricted:
		# Stop the zombie completely during cooldown or grab blocks
		_play_anim(enemy.anim_set.idle)
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			enemy.velocity = Vector3.ZERO
			enemy.move_and_slide()
		return

	# ─── Attack Token and Delay Logic ─────────────────────────────────────────
	var token_manager = enemy.get_node("/root/AttackTokenManager")
	var manager_has_token = token_manager.has_token(enemy)
	
	if not _has_token:
		if manager_has_token:
			# Just gained the token!
			_has_token = true
			
			var attack_choice: String = ""
			var target = _get_player()
			var is_target_follower = target is CharacterBody3D and target.is_in_group("Anchalee")
			
			if is_target_follower:
				# Follower cannot be grabbed, only hit!
				var last_attack = enemy.last_normal_attack if enemy else ""
				if last_attack == "attack_1":
					attack_choice = "attack_2"
				elif last_attack == "attack_2":
					attack_choice = "attack_1"
				else:
					attack_choice = "attack_1" if randf() < 0.5 else "attack_2"
				if enemy:
					enemy.last_normal_attack = attack_choice
			else:
				# Normal player selection
				if enemy and enemy.guaranteed_grab_next_attack:
					attack_choice = "attack_grab"
					enemy.guaranteed_grab_next_attack = false
				elif randf() < 0.25:
					attack_choice = "attack_grab"
				else:
					var last_attack = enemy.last_normal_attack if enemy else ""
					if last_attack == "attack_1":
						attack_choice = "attack_2"
					elif last_attack == "attack_2":
						attack_choice = "attack_1"
					else:
						attack_choice = "attack_1" if randf() < 0.5 else "attack_2"
					
					if enemy:
						enemy.last_normal_attack = attack_choice
			
			_selected_attack = attack_choice
			if enemy:
				enemy.selected_attack_type = _selected_attack
			
			# Set the animation tree Transition parameter
			# Always use attack_1 or attack_2 walk variant (never attack_grab)
			var walk_transition = _selected_attack
			if walk_transition == "attack_grab":
				# Use a normal attack walk animation for grab prep
				var last_attack = enemy.last_normal_attack if enemy else ""
				if last_attack == "attack_1":
					walk_transition = "attack_2"
				else:
					walk_transition = "attack_1"
			if enemy.anim_tree and enemy.anim_tree.active:
				if "parameters/Walk Zombie/Transition/transition_request" in enemy.anim_tree:
					enemy.anim_tree.set("parameters/Walk Zombie/Transition/transition_request", "default")
					enemy.anim_tree.set("parameters/Walk Zombie/Transition/transition_request", walk_transition)
					print("[StateHunt] Set Walk transition request to: ", walk_transition, " (attack: ", _selected_attack, ")")
					
			_token_hold_elapsed = 0.0
			print("[StateHunt] %s received token. Selected: %s." % [enemy.name, _selected_attack])
	else:
		if not manager_has_token:
			# Lost the token (another zombie got closer and claimed it)
			_has_token = false
			_selected_attack = ""
			_token_hold_elapsed = 0.0
			print("[StateHunt] %s lost token (revoked)." % enemy.name)
		else:
			# Update holding timer
			_token_hold_elapsed += _delta
			
			# If we held it too long (2s max) without reaching attack range, release it!
			if _token_hold_elapsed >= token_max_hold_time:
				print("[StateHunt] %s held token for too long (timeout). Releasing." % enemy.name)
				token_manager.release_token(enemy)
				_has_token = false
				_selected_attack = ""
			else:
				# Check if we are now in the actual Attack Range (2m)
				if dist_to_player <= attack_range:
					var angle_to_player: float = rad_to_deg(acos(clampf(dot_player, -1.0, 1.0)))
					if angle_to_player <= attack_cone_half_angle and not enemy.attack_blocked:
						# Attack range reached! Transition immediately
						_has_token = false # Clear flag since StateAttack now owns the token life cycle
						state_machine.transition_to(attack_state)
						return

	# ─── Sprint Activation Check ─────────────────────────────────────────────
	if not is_sprinting and _sprint_cooldown_timer <= 0.0 and flat_dist > 3.0:
		if randf() < sprint_activation_chance_per_sec * _delta:
			if can_start_sprint():
				_start_sprint()

	# ── Move toward target ───────────────────────────────────────────────────────
	_path_update_timer -= _delta
	if _path_update_timer <= 0.0:
		if nav_agent:
			nav_agent.target_position = target_pos
		_path_update_timer = 0.2

	var move_dir: Vector3 = Vector3.ZERO
	var path_dir: Vector3 = Vector3.ZERO
	if nav_agent and not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var diff = next_pos - enemy.global_position
		diff.y = 0.0
		if diff.length() > 0.01:
			path_dir = diff.normalized()
			# Apply 30/60/90 degree avoidance steering to path_dir
			move_dir = _get_avoidance_direction(path_dir)
	move_dir.y = 0.0

	# ─── Separation / Repulsion from Other Zombies ─────────────────────────────
	# Add an active steer-away force if we are too close to other zombies.
	# This ensures they actively turn and walk around each other.
	var separation_force = Vector3.ZERO
	var close_count = 0
	for other in enemy.get_tree().get_nodes_in_group("enemies"):
		if other == enemy or not is_instance_valid(other) or other.is_defeated:
			continue
		var dist = enemy.global_position.distance_to(other.global_position)
		if dist < 1.2 and dist > 0.01:
			var push = (enemy.global_position - other.global_position).normalized()
			var strength = (1.2 - dist) / 1.2
			separation_force += push * strength
			close_count += 1
			
	# Only apply separation force if we are actively trying to navigate
	if path_dir.length() > 0.01 and close_count > 0:
		# Blend the steer-away vector into our movement direction
		move_dir = (move_dir + separation_force * 0.8).normalized()
		move_dir.y = 0.0

	var current_speed = sprint_speed if is_sprinting else move_speed
	if nav_agent:
		nav_agent.max_speed = current_speed

	if move_dir.length() > 0.01:
		# First, calculate the target direction and snap it to 15-degree increments
		var target_y = atan2(-move_dir.x, -move_dir.z)
		var step_rad = deg_to_rad(15.0)
		target_y = round(target_y / step_rad) * step_rad
		
		# Smoothly lerp towards the snapped target to prevent visual pops/jitter
		enemy.rotation.y = lerp_angle(enemy.rotation.y, target_y, 8.0 * enemy.get_physics_process_delta_time())

		# Set the movement velocity to be exactly in the direction the zombie is currently facing
		# This prevents any sliding walk look since they will always walk where they face.
		var forward_dir = -enemy.global_transform.basis.z.normalized()
		var target_vel = forward_dir * current_speed
		
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(target_vel)
			
		if not nav_agent or not nav_agent.avoidance_enabled:
			enemy.velocity = target_vel
			enemy.move_and_slide()
			
		_play_anim(_walk_anim)
	else:
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			enemy.velocity = Vector3.ZERO
			enemy.move_and_slide()
			
		# Face the player when standing still, snapped to 15-degree increments
		var target_y = atan2(-dir_to_player.x, -dir_to_player.z)
		var step_rad = deg_to_rad(15.0)
		target_y = round(target_y / step_rad) * step_rad
		
		enemy.rotation.y = lerp_angle(enemy.rotation.y, target_y, 8.0 * enemy.get_physics_process_delta_time())
		
		_play_anim(enemy.anim_set.idle)

func _play_anim(anim_name: String, sub_machine: String = "") -> void:
	if not enemy or not enemy.anim_tree: return
	
	var pb = enemy.anim_tree.get("parameters/playback")
	if pb and pb.get_current_node() == anim_name:
		# Keep TimeScale_Output updated even if we are already in the same state
		if not _is_fleeing:
			_apply_timescale()
		return
	
	# Apply timescale via AnimationTree parameter
	if not _is_fleeing:
		_apply_timescale()
	
	super._play_anim(anim_name, sub_machine)

func _walk_back(dir_to_player: Vector3, delta: float) -> void:
	var flee_dir: Vector3 = -dir_to_player
	flee_dir.y = 0.0

	_path_update_timer -= delta
	if _path_update_timer <= 0.0:
		if nav_agent:
			nav_agent.target_position = enemy.global_position + flee_dir * attack_range
		_path_update_timer = 0.2

	if nav_agent and not nav_agent.is_navigation_finished():
		flee_dir = (nav_agent.get_next_path_position() - enemy.global_position).normalized()
		flee_dir.y = 0.0

	if flee_dir.length() > 0.01:
		var target_vel = flee_dir * move_speed * walk_back_speed_multiplier
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.max_speed = move_speed * walk_back_speed_multiplier
			nav_agent.set_velocity(target_vel)
		else:
			enemy.velocity = target_vel
			enemy.move_and_slide()
			
		# Look AT the player, not away from the player! (snapped to 15-degree increments)
		var target_y = atan2(-dir_to_player.x, -dir_to_player.z)
		var step_rad = deg_to_rad(15.0)
		target_y = round(target_y / step_rad) * step_rad
		
		var current_y = enemy.rotation.y
		enemy.rotation.y = lerp_angle(current_y, target_y, 5.0 * enemy.get_physics_process_delta_time())
		
		_play_anim(_walk_anim)
		if enemy and enemy.anim_player:
			# Set timescale for backwards walk on AnimationPlayer
			enemy.anim_player.speed_scale = walk_back_timescale
	else:
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			enemy.velocity = Vector3.ZERO
			enemy.move_and_slide()
		_play_anim(enemy.anim_set.idle)

func handle_hit(hit_data: Dictionary) -> String:
	# Ignore hits during stun recovery pause to prevent animation tree freeze / lock
	if _stun_recovery_timer > 0.0:
		return ""

	var zone: String = hit_data.get("hit_zone", "body")
	
	if is_sprinting and zone in ["foot", "left_foot", "right_foot", "left_leg", "right_leg", "leg"]:
		var knockdown = state_machine._states.get("StateKnockdown")
		if knockdown:
			knockdown.knockdown_mode = "SWING_SHOT"
			knockdown.stun_type = "head"
		return "StateKnockdown"

	match zone:
		"head", "foot", "left_foot", "right_foot":
			return "StateTakedownable"
		_:
			return "StateStun"

func _start_sprint() -> void:
	if is_sprinting: return
	is_sprinting = true
	_sprint_timer = 0.0
	_sprint_duration = randf_range(sprint_duration_min, sprint_duration_max)
	if not sprinting_enemies.has(self):
		sprinting_enemies.append(self)
	
	print("[StateHunt] %s started sprinting! Duration: %.2f" % [enemy.name, _sprint_duration])
	_update_walk_timescale()

func _end_sprint() -> void:
	if not is_sprinting: return
	is_sprinting = false
	_sprint_cooldown_timer = randf_range(sprint_cooldown_min, sprint_cooldown_max)
	sprinting_enemies.erase(self)
	
	print("[StateHunt] %s ended sprinting." % enemy.name)
	_update_walk_timescale()

func _update_walk_timescale() -> void:
	if not _is_fleeing:
		_apply_timescale()

func _apply_timescale() -> void:
	if enemy and enemy.anim_tree and enemy.anim_tree.active:
		var scale = sprint_timescale if is_sprinting else walk_timescale
		if "parameters/Walk Zombie/TimeScale_Output/scale" in enemy.anim_tree:
			enemy.anim_tree.set("parameters/Walk Zombie/TimeScale_Output/scale", scale)
	# Keep anim_player speed_scale at 1.0 since TimeScale_Output handles it
	if enemy and enemy.anim_player:
		enemy.anim_player.speed_scale = 1.0

func _get_target_position() -> Vector3:
	var player := _get_player()
	if not player:
		return enemy.global_position
		
	var to_player = player.global_position - enemy.global_position
	to_player.y = 0.0
	var dist = to_player.length()
	
	# If close to the player but without an attack token, circle/pace around them
	var is_waiting = dist < circling_radius + 1.0 and not _has_token
	
	if is_waiting:
		var dir = 1.0 if (enemy.get_instance_id() % 2 == 0) else -1.0
		var time_sec = Time.get_ticks_msec() * 0.001
		var angle_offset = deg_to_rad(enemy.get_instance_id() % 360)
		var current_angle = time_sec * circling_speed * dir + angle_offset
		
		var offset = Vector3(cos(current_angle), 0.0, sin(current_angle)) * circling_radius
		return player.global_position + offset
		
	return player.global_position

func _get_player() -> Node3D:
	if enemy and enemy.has_method("get_current_target"):
		return enemy.get_current_target()
	var players = enemy.get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func is_movement_blocked() -> bool:
	return _getup_block_timer > 0.0 or _stun_recovery_timer > 0.0 or _attack_recovery_timer > 0.0

func _get_avoidance_direction(base_dir: Vector3) -> Vector3:
	if not enemy or not enemy.is_inside_tree() or base_dir.length() <= 0.01:
		return base_dir
		
	var space_state = enemy.get_world_3d().direct_space_state
	var start = enemy.global_position + Vector3(0, 1.0, 0) # Cast at chest height
	
	# Helper to check if a specific direction is blocked by wall or other zombies
	var is_blocked = func(dir: Vector3) -> bool:
		# 1. Physics raycast check (environment/static obstacles)
		var end = start + dir * 1.5
		var query = PhysicsRayQueryParameters3D.create(start, end)
		query.exclude = [enemy.get_rid()]
		var result = space_state.intersect_ray(query)
		if not result.is_empty():
			return true
			
		# 2. Check for other zombies blocking in that direction
		for other in enemy.get_tree().get_nodes_in_group("enemies"):
			if other == enemy or not is_instance_valid(other) or other.is_defeated:
				continue
			var dist = enemy.global_position.distance_to(other.global_position)
			if dist < 1.3:
				var to_other = (other.global_position - enemy.global_position).normalized()
				if dir.dot(to_other) > 0.707: # Other zombie is in front of this direction
					return true
		return false

	# If the direct path is not blocked, proceed straight
	if not is_blocked.call(base_dir):
		return base_dir
		
	# Find closest blocking zombie to decide which way to turn first
	var min_dist = 999.0
	var closest_other = null
	for other in enemy.get_tree().get_nodes_in_group("enemies"):
		if other == enemy or not is_instance_valid(other) or other.is_defeated:
			continue
		var dist = enemy.global_position.distance_to(other.global_position)
		if dist < 1.5:
			var to_other = (other.global_position - enemy.global_position).normalized()
			if base_dir.dot(to_other) > 0.5:
				if dist < min_dist:
					min_dist = dist
					closest_other = other
					
	var steer_left_first = true
	if closest_other:
		var to_other = (closest_other.global_position - enemy.global_position).normalized()
		var cross = base_dir.cross(to_other)
		if cross.y > 0:
			steer_left_first = false # Steer right first

	var angles = [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]
	if not steer_left_first:
		angles = [-30.0, 30.0, -60.0, 60.0, -90.0, 90.0]
		
	for angle in angles:
		var rad = deg_to_rad(angle)
		var rotated_dir = base_dir.rotated(Vector3.UP, rad).normalized()
		if not is_blocked.call(rotated_dir):
			return rotated_dir
			
	# If everything is blocked, fallback to base direction
	return base_dir
