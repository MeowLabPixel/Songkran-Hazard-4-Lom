## AnchaleeBase: root script for the Anchalee follower character.
## Handles the state machine, threat tracking, and exposes helpers to states.
class_name AnchaleeBase
extends CharacterBody3D

# ─── Signals ───────────────────────────────────────────────────────────────
signal threat_entered()
signal threat_cleared()
signal player_entered_friend_area()
signal player_exited_friend_area()

# ─── References ────────────────────────────────────────────────────────────
@onready var state_machine: AnchaleeStateMachine = $AnchaleeStateMachine
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var threat_area: Area3D = $ThreatArea
@onready var friend_area: Area3D = get_node_or_null("FriendArea")
@onready var help_label: Label3D = get_node_or_null("HelpLabel")
@onready var rig: Node3D = $AnchaleeModel/rig_002
var anim_player: AnimationPlayer = null  # assigned at runtime once model is finalized
var lean_modifier: AnchaleeLeanModifier = null

# ─── Health & Face Controller ──────────────────────────────────────────────
@export var face_controller: AnchaleeFaceController
@export var max_health: int = 100
var health: int = max_health
var is_dead: bool = false

# ─── Following ─────────────────────────────────────────────────────────────
@export_group("Following")
@export var follow_start_distance: float = 1.3
@export var follow_start_distance_combat: float = 1.3
@export var follow_start_distance_calm: float = 2.8
@export var follow_stop_distance: float = 0.85
@export var follow_stop_distance_combat: float = 0.85
@export var follow_stop_distance_calm: float = 1.6
@export var camera_collision_avoidance_distance: float = 0.2
@export var friend_area_push_back_offset: float = 0.8

@export_group("Aim Detection")
@export var aim_detect_radius: float = 2.0

@export_group("Procedural Turn Lean")
@export var rotation_tilt_sensitivity: float = 3.5
@export var rotation_yaw_sensitivity: float = 6.0
@export var max_tilt_angle: float = 6.0
@export var max_yaw_angle: float = 15.0
@export var turn_tilt_speed: float = 10.0

@export_group("Head Look At & Glance")
@export var enable_head_glance: bool = true
@export var max_glance_distance: float = 6.0
@export var glance_exit_multiplier: float = 1.25
@export var glance_fov_deg: float = 80.0
@export var glance_max_angle_deg: float = 45.0
@export var head_turn_speed: float = 5.0
@export var glance_exit_speed: float = 3.5
@export var head_look_depth: float = 15.0
@export var sprint_pitch_down: float = 1.2
@export var enable_item_spotting: bool = true
@export var enable_comedy_features: bool = true

@export_group("Idle Anim Head Window")
@export var enable_idle_anim_head_window: bool = true
@export var idle_anim_head_turn_start: float = 1.7
@export var idle_anim_head_turn_end: float = 4.2
@export var idle_anim_length: float = 8.333333

var aim_target_head: Marker3D = null
var head_lookat: LookAtModifier3D = null
var current_glance_pos: Vector3 = Vector3.ZERO
var active_glance_target: Node3D = null
var current_head_influence: float = 0.0
var current_sprint_pitch_weight: float = 0.0
var glance_recovery_cooldown: float = 0.0
var current_anim_name: String = ""
var current_anim_time: float = 0.0
var _idle_anim_time: float = 0.0
var _was_in_action_state: bool = false
var _friendly_side_eye_timer: float = 0.0
var _stare_timer: float = 0.0
var _stare_look_away_timer: float = 0.0
var _cornered_look_timer: float = 0.0
var _cornered_look_target_leon: bool = false
var _item_spot_cooldown: float = 0.0

var last_y_rotation: float = 0.0
var _smoothed_angular_velocity: float = 0.0
var has_initialized_rotation: bool = false

# ─── Tracking ───────────────────────────────────────────────────────
## All CharacterBody3D nodes (enemies) currently inside the threat radius.
var nearby_threats: Array = []
var is_player_in_friend_area: bool = false
var is_walking_backward: bool = false
var player_is_sprinting: bool = false
var is_touching_player: bool = false
var smoothed_target_pos: Vector3 = Vector3.ZERO
var _walk_markers: Array[float] = [0.5, 1.0]
var _last_norm_pos: float = -1.0
var _last_step_time: int = 0

func _get_footstep_markers(anim_player: AnimationPlayer, anim_name: String) -> Array[float]:
	var result: Array[float] = [0.5, 1.0]
	if not anim_player or not anim_player.has_animation(anim_name):
		return result
	var anim_res = anim_player.get_animation(anim_name)
	if not anim_res:
		return result
		
	var markers = anim_res.get_marker_names()
	if markers.size() > 0:
		var temp: Array[float] = []
		var length = anim_res.length
		if length <= 0.0:
			length = 1.0
		for m_name in markers:
			if "step" in String(m_name).to_lower():
				var t = anim_res.get_marker_time(m_name)
				temp.append(fmod(t / length, 1.0))
		if temp.size() > 0:
			temp.sort()
			result = temp
	return result

var _has_rolled_takedown_duck: bool = false
var _takedown_duck_roll: bool = false

var zombie_reaction_state: String = "none"
var zombie_reaction_timer: float = 0.0
var duck_cooldown_timer: float = 0.0
var trigger_post_getup_jink: bool = false
@export var duck_cooldown_duration: float = 4.0
@export var zombie_reaction_cooldown: float = 2.5
@export var reaction_chance_duck: float = 0.30
@export var reaction_chance_evade: float = 0.40
# The remaining percentage will be used for "back_up"

func start_duck_cooldown() -> void:
	duck_cooldown_timer = duck_cooldown_duration

## Set by states when Anchalee is stuck.
var is_cornered: bool = false:
	set(value):
		if value == is_cornered:
			return
		is_cornered = value
		if is_node_ready() and help_label:
			help_label.visible = value

func _ready() -> void:
	if not face_controller:
		face_controller = get_node_or_null("AnchaleeFaceController") as AnchaleeFaceController
		if not face_controller:
			face_controller = find_child("AnchaleeFaceController", true, false) as AnchaleeFaceController
	if has_node("AnchaleeModel/AnimationPlayer"):
		anim_player = $AnchaleeModel/AnimationPlayer
		_walk_markers = _get_footstep_markers(anim_player, "Walk -loop")
	health = max_health
	add_to_group("Anchalee")
	
	# Set Layer 5 (value 16) and Mask 1 (value 1) + Mask 3 (value 4) so she collides with world and zombies
	set_collision_layer_value(5, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)  # Detect player so physics resolves contact (player can push her)
	set_collision_mask_value(3, true)
	# Set Mask 4 (value 8) so she is blocked by invisible walls
	set_collision_mask_value(4, true)
	

	# Configure threat_area and friend_area collision settings programmatically
	# to prevent them from colliding with player weapon raycasts and projectiles (layer = 0)
	if threat_area:
		threat_area.collision_layer = 0
		threat_area.collision_mask = 1 | 4 | 8192 # Detect enemies on layer 1, layer 3 (Enemies), & layer 14
		threat_area.body_entered.connect(_on_threat_entered)
		threat_area.body_exited.connect(_on_threat_exited)
	
	if friend_area:
		friend_area.collision_layer = 0
		friend_area.collision_mask = 1 | 14 # Detect player on layer 1 & layer 14
		friend_area.body_entered.connect(_on_friend_entered)
		friend_area.body_exited.connect(_on_friend_exited)
	
	# Start in Idle state
	state_machine.initialize("AnchaleeStateIdle")
	state_machine.state_changed.connect(_on_state_changed)
	
	if nav_agent:
		nav_agent.target_desired_distance = follow_stop_distance
		nav_agent.velocity_computed.connect(_on_nav_velocity_computed)
	
	# Initial check for player in friend area
	if friend_area:
		for body in friend_area.get_overlapping_bodies():
			if body.is_in_group("player"):
				is_player_in_friend_area = true
				break

	# Setup lean modifier & LookAtModifier3D programmatically
	var skel = get_node_or_null("AnchaleeModel/rig_002/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton")
	if not skel:
		skel = find_child("OriginalSkeleton", true, false)
	if skel:
		var lean = AnchaleeLeanModifier.new()
		lean.anchalee = self
		lean.name = "AnchaleeLeanModifier"
		skel.add_child(lean)
		lean_modifier = lean

		# Setup Head Look-At IK (1:1 with Player system)
		var hl = skel.get_node_or_null("HeadLookAt") as LookAtModifier3D
		if not hl:
			hl = LookAtModifier3D.new()
			hl.name = "HeadLookAt"
			hl.bone_name = "DEF-spine.006"
			var b_idx = skel.find_bone("DEF-spine.006")
			hl.bone = b_idx if b_idx != -1 else 7
			hl.primary_rotation_axis = Vector3.AXIS_X
			hl.use_secondary_rotation = true
			hl.use_angle_limitation = true
			hl.symmetry_limitation = false
			hl.primary_positive_limit_angle = deg_to_rad(30.0)
			hl.primary_negative_limit_angle = deg_to_rad(30.0)
			hl.primary_positive_damp_threshold = 1.0
			hl.primary_negative_damp_threshold = 1.0
			hl.secondary_positive_limit_angle = deg_to_rad(glance_max_angle_deg)
			hl.secondary_negative_limit_angle = deg_to_rad(glance_max_angle_deg)
			hl.secondary_positive_damp_threshold = 0.7
			hl.secondary_negative_damp_threshold = 0.7
			skel.add_child(hl)

		aim_target_head = Marker3D.new()
		aim_target_head.name = "Aim_target_head"
		aim_target_head.position = Vector3(0, 1.4, -15.0) # Pre-position forward to avoid startup jerk
		skel.add_child(aim_target_head)
		hl.target_node = hl.get_path_to(aim_target_head)
		head_lookat = hl

func trigger_hit_lean(hit_data: Dictionary = {}) -> void:
	if lean_modifier and is_instance_valid(lean_modifier):
		lean_modifier.apply_hit_force(hit_data)
	else:
		var lean = find_child("AnchaleeLeanModifier", true, false) as AnchaleeLeanModifier
		if lean:
			lean_modifier = lean
			lean.apply_hit_force(hit_data)

func _unhandled_input(event: InputEvent) -> void:
	pass # Wait behavior replaced by dynamic Idle/Walk

func kill_anchalee() -> void:
	if is_dead:
		return
	health = 0
	is_dead = true
	print("[Anchalee] Force Dead.")
	
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").game_outcome = GameManager.Outcome.DEFEAT_ANCHALEE
		
	state_machine.transition_to("AnchaleeStateDie")
	
	# Kill player
	var player = get_player()
	if player and player.has_method("force_die"):
		player.force_die()

## Called by enemy attack hitboxes to damage Anchalee.
## Supports both Anchalee format (amount, hit_data_dict) and combat format (amount, ignore_stun_or_is_grab, attacker).
func take_damage(amount: int, arg2: Variant = {}, attacker: Node3D = null) -> void:
	if is_dead:
		return
		
	# Immunity is now fully handled by physics layers via set_immune().
	# If the hitboxes are hit, she takes damage.
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_anchalee_damage(amount)
		
	health -= amount
	print("[Anchalee] Took %d damage -- HP: %d/%d" % [amount, health, max_health])
	
	var hit_data: Dictionary = {}
	if arg2 is Dictionary:
		hit_data = arg2
	elif arg2 is bool:
		var hit_dir := Vector3.ZERO
		var hit_pos := Vector3.ZERO
		if is_instance_valid(attacker):
			hit_pos = attacker.global_position
			hit_dir = (global_position - attacker.global_position).normalized()
			hit_dir.y = 0.0
			if hit_dir.length_squared() > 0.001:
				hit_dir = hit_dir.normalized()
		hit_data = {
			"damage": amount,
			"position": hit_pos,
			"hit_direction": hit_dir,
			"attacker": attacker
		}
	
	trigger_hit_lean(hit_data)
	if health <= 0:
		kill_anchalee()
		return
	if face_controller:
		face_controller.notify_hit(1.0)
	state_machine.transition_to("AnchaleeStateHit")

## Called by player gun/bullets (friendly fire)
func take_hit(hit_data: Dictionary) -> void:
	if is_dead: return
	var amount = hit_data.get("damage", 10)
	
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_anchalee_damage(amount)
		
	health -= amount
	print("[Anchalee] Friendly Fire! Took %d damage -- HP: %d/%d" % [amount, health, max_health])
	trigger_hit_lean(hit_data)
	_friendly_side_eye_timer = 2.0
	if face_controller:
		face_controller.notify_hit(1.0)
	if health <= 0:
		kill_anchalee()
		return
	state_machine.transition_to("AnchaleeStateHit")

# --- Sensor callbacks ---
func _on_threat_entered(body: Node3D) -> void:
	if body == self: return
	if body is CharacterBody3D and body.is_in_group("enemies") and body not in nearby_threats:
		nearby_threats.append(body)
		threat_entered.emit()

func _on_threat_exited(body: Node3D) -> void:
	if nearby_threats.has(body):
		nearby_threats.erase(body)
		if nearby_threats.is_empty():
			is_cornered = false
			threat_cleared.emit()

func _on_friend_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_in_friend_area = true
		player_entered_friend_area.emit()

func _on_friend_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_in_friend_area = false
		player_exited_friend_area.emit()

# ─── Helpers for states ────────────────────────────────────────────────────

func get_player() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func is_player_dead() -> bool:
	var player = get_player()
	if not is_instance_valid(player):
		return false
	if player.has_method("is_dead"):
		if player.is_dead():
			return true
	elif player.get("is_dead") is bool and player.get("is_dead"):
		return true
	if "HP" in player and player.HP <= 0:
		return true
	var p_sm = player.get_node_or_null("Statemachine")
	if p_sm and p_sm.get("current_state") and p_sm.current_state.name == "Die":
		return true
	return false

func on_player_died() -> void:
	if is_dead:
		return
	print("[Anchalee] Player died — entering infinite ducking state")
	if state_machine and state_machine.get_current_state_name() != "AnchaleeStateDuck":
		state_machine.transition_to("AnchaleeStateDuck")

func is_in_combat() -> bool:
	if nearby_threats.size() > 0:
		return true
	var player = get_player()
	if is_instance_valid(player):
		if player.get("is_aimming") == true:
			return true
		var p_sm = player.get_node_or_null("Statemachine")
		if p_sm and p_sm.get("current_state") and p_sm.current_state.name in ["Combat", "Attack", "Takedown", "Hit", "Grab"]:
			return true
	var sound_mgr = get_node_or_null("/root/SoundManager")
	if sound_mgr and "_current_music_state" in sound_mgr:
		if sound_mgr._current_music_state in ["CombatStart", "CombatLoop"]:
			return true
	return false

func get_effective_follow_start_distance() -> float:
	if is_in_combat():
		return follow_start_distance_combat
	return follow_start_distance_calm

func get_effective_follow_stop_distance() -> float:
	var dist = follow_stop_distance_combat if is_in_combat() else follow_stop_distance_calm
	var player = get_player()
	if player and player.get("camera") and player.camera.get("is_hitting_wall"):
		dist += camera_collision_avoidance_distance
	return dist

func get_friend_target_pos() -> Vector3:
	var player = get_player()
	if not player: return global_position
	
	# If player is in grab or get hit states, flee from them!
	var player_sm = player.get_node_or_null("Statemachine")
	if player_sm and player_sm.get("current_state"):
		var state_name = player_sm.current_state.name
		if state_name in ["Grab", "Get_hit"]:
			var to_self = global_position - player.global_position
			to_self.y = 0.0
			var dist = to_self.length()
			var flee_dir = to_self.normalized() if dist > 0.1 else -player.global_transform.basis.z
			# Target a point 5.0 meters away from the threat (player/zombie)
			return player.global_position + flee_dir * 2.5

	# Look for the FriendArea node on the player scene
	var friend_area_node = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/FriendArea")
	if friend_area_node:
		var pos = friend_area_node.global_position
		
		# In combat, offset back/left based on player rotation to prevent blocking aim/movement
		if is_in_combat():
			var player_forward = -player.global_transform.basis.z
			var is_player_moving_backward = player.velocity.dot(player_forward) < -0.1 or Input.is_action_pressed("ui_down")
			var ang_vel = player.get("angular_velocity")
			var is_player_standing_still = player.velocity.length_squared() < 0.01
			var is_turning_right = ang_vel and ang_vel < -0.1 and is_player_standing_still
			
			if is_player_moving_backward or is_turning_right:
				var back_dir = player.global_transform.basis.z.normalized()
				pos += back_dir * friend_area_push_back_offset
				
			# Offset to the left if the player is rotating left (ang_vel > 0.1) while standing still
			if ang_vel and ang_vel > 0.1 and is_player_standing_still:
				var left_dir = friend_area_node.global_transform.basis.x.normalized()
				var offset_amount = clampf(abs(ang_vel) * 0.4, 0.0, 1.2)
				pos += left_dir * offset_amount
		return pos
	return player.global_position

## Zero out any velocity component that would push the player away.
## This lets the player push Anchalee, but not the reverse.
func _clamp_velocity_toward_player() -> void:
	var player = get_player()
	if not player: return
	var to_player = (player.global_position - global_position)
	to_player.y = 0.0
	var dist = to_player.length()
	if dist < 0.85 and dist > 0.01:
		var dir = to_player / dist
		var proj = velocity.dot(dir)
		if proj > 0.0:
			velocity -= dir * proj  # strip the component pointing at the player

func _physics_process(delta: float) -> void:
	if zombie_reaction_timer > 0.0:
		zombie_reaction_timer -= delta
		if zombie_reaction_timer <= 0.0:
			zombie_reaction_state = "none"
			
	if duck_cooldown_timer > 0.0:
		duck_cooldown_timer -= delta
			
	if is_dead: return
	
	if nav_agent:
		nav_agent.target_desired_distance = get_effective_follow_stop_distance()
	var target_pos = get_friend_target_pos()
	if smoothed_target_pos == Vector3.ZERO:
		smoothed_target_pos = global_position
		
	var player = get_player()
	var is_player_moving = player and player.velocity.length_squared() > 0.05
	var is_player_rotating = player and abs(player.get("angular_velocity")) > 0.1
	
	if is_player_moving or is_player_rotating:
		smoothed_target_pos = smoothed_target_pos.lerp(target_pos, delta * 6.0)
	else:
		smoothed_target_pos = target_pos # Instantly snap target to stop drifting past player

	# Update near-area tracking
	if player:
		var near_area = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/FriendNearArea")
		var is_near = false
		if near_area and near_area is Area3D:
			is_near = near_area.overlaps_body(self)
			
		if is_near != is_player_in_friend_area:
			is_player_in_friend_area = is_near
			if is_near:
				player_entered_friend_area.emit()
			else:
				player_exited_friend_area.emit()
				


	# Turn tilt calculation (root tilt when rotating)
	var current_y_rot = global_rotation.y
	if not has_initialized_rotation:
		last_y_rotation = current_y_rot
		has_initialized_rotation = true
		
	var rotation_delta = angle_difference(last_y_rotation, current_y_rot)
	last_y_rotation = current_y_rot
	
	var angular_velocity = 0.0
	if delta > 0.0:
		angular_velocity = rotation_delta / delta
		
	_smoothed_angular_velocity = lerp(_smoothed_angular_velocity, angular_velocity, delta * 15.0)
	
	# Only apply turn lean when in walking state
	var is_walking = false
	if state_machine and state_machine.current_state and state_machine.current_state.name == "AnchaleeStateWalk":
		is_walking = true
		
	var turn_tilt_deg = 0.0
	var turn_yaw_deg = 0.0
	if is_walking:
		turn_tilt_deg = -_smoothed_angular_velocity * rotation_tilt_sensitivity
		turn_yaw_deg = _smoothed_angular_velocity * rotation_yaw_sensitivity
		
	var turn_tilt_rad = deg_to_rad(turn_tilt_deg)
	var turn_yaw_rad = deg_to_rad(turn_yaw_deg)
	
	var target_z = clamp(turn_tilt_rad, deg_to_rad(-max_tilt_angle), deg_to_rad(max_tilt_angle))
	var target_y = clamp(turn_yaw_rad, deg_to_rad(-max_yaw_angle), deg_to_rad(max_yaw_angle))
	
	if rig:
		rig.rotation.x = lerp_angle(rig.rotation.x, 0.0, delta * turn_tilt_speed)
		rig.rotation.y = lerp_angle(rig.rotation.y, target_y, delta * turn_tilt_speed)
		rig.rotation.z = lerp_angle(rig.rotation.z, target_z, delta * turn_tilt_speed)

	# Manage collision shape size based on ducking state
	var current_state_name = state_machine.get_current_state_name() if state_machine else ""
	var target_height = 1.6469727
	var target_col_y = 0.8234863
	
	if current_state_name in ["AnchaleeStateDuck", "AnchaleeStateGetUp"]:
		target_height = 0.8
		target_col_y = 0.4
		
	if has_node("CollisionShape3D"):
		var col = $CollisionShape3D as CollisionShape3D
		if col and col.shape is CapsuleShape3D:
			if col.shape.height != target_height:
				if not col.shape.resource_local_to_scene:
					col.shape = col.shape.duplicate()
				col.shape.height = target_height
				col.position.y = target_col_y

	# Process footstep sound logic based on animation play position and loaded markers
	if not is_dead:
		var tree = get_node_or_null("AnchaleeModel/AnimationTree")
		if tree and tree.active:
			var pb = tree.get("parameters/playback")
			if pb:
				var current_node = pb.get_current_node()
				if current_node == "Walk":
					var is_moving = Vector2(velocity.x, velocity.z).length_squared() > 0.05
					if is_moving:
						var length = 0.8 if velocity.length_squared() > 10.0 else 1.0
						var play_pos = pb.get_current_play_position()
						var norm_pos = fmod(play_pos / length, 1.0)
						
						# Check crossings for each marker
						if _last_norm_pos >= 0.0:
							for marker_ratio in _walk_markers:
								if _last_norm_pos > norm_pos: # Wrap around!
									if _last_norm_pos < marker_ratio or norm_pos >= marker_ratio:
										var now = Time.get_ticks_msec()
										if now - _last_step_time > 220:
											_last_step_time = now
											SoundManager.play_3d("anchalee_footstep", self)
										break
								else:
									if _last_norm_pos < marker_ratio and norm_pos >= marker_ratio:
										var now = Time.get_ticks_msec()
										if now - _last_step_time > 220:
											_last_step_time = now
											SoundManager.play_3d("anchalee_footstep", self)
										break
						_last_norm_pos = norm_pos
					else:
						if _last_norm_pos >= 0.0:
							var now = Time.get_ticks_msec()
							if now - _last_step_time > 220:
								_last_step_time = now
								SoundManager.play_3d("anchalee_footstep", self)
						_last_norm_pos = -1.0
				else:
					if _last_norm_pos >= 0.0:
						var now = Time.get_ticks_msec()
						if now - _last_step_time > 220:
							_last_step_time = now
							SoundManager.play_3d("anchalee_footstep", self)
					_last_norm_pos = -1.0
			else:
				_last_norm_pos = -1.0
		else:
			_last_norm_pos = -1.0
	else:
		_last_norm_pos = -1.0



func get_threat_count() -> int:
	# Clean up any dead or freed enemies from the list
	var valid_threats = []
	var count = 0
	
	for threat in nearby_threats:
		if is_instance_valid(threat) and not threat.is_queued_for_deletion():
			valid_threats.append(threat)
			
			var is_active_threat = true
			if threat.is_defeated:
				is_active_threat = false
			else:
				var sm = threat.state_machine
				if sm and sm.current_state:
					var state_name = sm.current_state.name.to_lower()
					# Exclude defeated, hit, push, stun, takedown, knockdown, and getup states
					if "hit" in state_name or "defeated" in state_name or "stun" in state_name or "push" in state_name or "takedown" in state_name or "knockdown" in state_name or "getup" in state_name or "get_up" in state_name:
						is_active_threat = false
			
			if is_active_threat:
				count += 1
				
	nearby_threats = valid_threats
	return count

func get_rear_threat_behind_player(prep_range: float = 4.0) -> Node3D:
	var player = get_player()
	if not player or not is_instance_valid(self): return null
	var player_forward = -player.global_transform.basis.z
	player_forward.y = 0.0
	if player_forward.length() < 0.01: return null
	player_forward = player_forward.normalized()
	
	var closest_threat: Node3D = null
	var closest_dist: float = prep_range
	
	for threat in nearby_threats:
		if not is_instance_valid(threat) or threat.is_queued_for_deletion() or threat.is_defeated:
			continue
		var sm = threat.state_machine
		if sm and sm.current_state:
			var state_name = sm.current_state.name.to_lower()
			if "hit" in state_name or "defeated" in state_name or "stun" in state_name or "push" in state_name or "takedown" in state_name or "knockdown" in state_name or "getup" in state_name or "get_up" in state_name:
				continue
				
		var to_threat = threat.global_position - player.global_position
		to_threat.y = 0.0
		var dist = to_threat.length()
		if dist <= prep_range:
			to_threat = to_threat.normalized()
			# Dot product < -0.2 means zombie is in the rear 120° arc behind player's facing direction
			if player_forward.dot(to_threat) < -0.2:
				if dist < closest_dist:
					closest_dist = dist
					closest_threat = threat
	return closest_threat

func _distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab = b - a
	var ap = p - a
	var ab_len_sq = ab.length_squared()
	if ab_len_sq < 0.0001:
		return ap.length()
	var t = ap.dot(ab) / ab_len_sq
	t = clampf(t, 0.0, 1.0)
	var closest_point = a + ab * t
	return p.distance_to(closest_point)

func is_player_aiming_or_takedown() -> bool:
	var player = get_player()
	if not player: return false
	
	# 1. Aiming duck detection: only when player is aiming AND the aiming ray (large crosshair) overlaps Anchalee
	if player.get("is_aimming") == true:
		var camera = player.get_node_or_null("Camera")
		if camera and camera.get("camera"):
			var camera3d = camera.get("camera") as Camera3D
			if camera3d:
				var screen_size = get_viewport().get_visible_rect().size
				var screen_center = screen_size / 2.0
				var crosshair_speed = screen_size.y * 1.25
				var offset_x = camera.get("aim_offset").x * crosshair_speed
				var crosshair_center = Vector2(screen_center.x + offset_x, screen_center.y)
				
				var ray_origin = camera3d.project_ray_origin(crosshair_center)
				var ray_dir = camera3d.project_ray_normal(crosshair_center)
				
				# Math: Distance from Anchalee center to the camera look ray
				var anchalee_center = global_position + Vector3(0, 0.8, 0)
				var to_center = anchalee_center - ray_origin
				var t = to_center.dot(ray_dir)
				t = maxf(t, 0.0)
				var closest_point = ray_origin + ray_dir * t
				var distance_to_ray = anchalee_center.distance_to(closest_point)
				
				if distance_to_ray <= aim_detect_radius:
					return true # Guaranteed duck for Aim
			
	# 2. Takedown duck detection: only when player is in Takedown state AND she is within 1.5m
	var sm = player.get_node_or_null("Statemachine")
	if sm and sm.get("current_state"):
		if sm.current_state.name == "Takedown":
			var dist = global_position.distance_to(player.global_position)
			if dist <= 1.5:
				if not _has_rolled_takedown_duck:
					_has_rolled_takedown_duck = true
					_takedown_duck_roll = randf() < 0.5
				return _takedown_duck_roll
				
	_has_rolled_takedown_duck = false
	return false

## Sets immunity/invincibility for Anchalee by disabling her head and body hurtboxes.
func set_immune(is_immune: bool) -> void:
	# Head hurtbox Area3D
	var head_hurtbox = get_node_or_null("AnchaleeModel/rig_002/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/HitboxAttachHead/HitboxHead")
	if head_hurtbox and head_hurtbox is Area3D:
		head_hurtbox.set_deferred("monitorable", not is_immune)
		head_hurtbox.set_deferred("monitoring", not is_immune)
		
	# Body hurtbox Area3D
	var body_hurtbox = get_node_or_null("AnchaleeModel/rig_002/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/BoneAttachment3D/HurtboxBody")
	if body_hurtbox and body_hurtbox is Area3D:
		body_hurtbox.set_deferred("monitorable", not is_immune)
		body_hurtbox.set_deferred("monitoring", not is_immune)

	# Toggle player collision layer
	set_collision_layer_value(2, not is_immune)

# ─── Debug ─────────────────────────────────────────────────────────────────
func set_player_collision(enabled: bool) -> void:
	var player = get_player()
	if not player: return
	if enabled:
		remove_collision_exception_with(player)
	else:
		add_collision_exception_with(player)

func _on_state_changed(old_state: String, new_state: String) -> void:
	print("[Anchalee] State: %s → %s" % [old_state, new_state])

# ─── Navigation ────────────────────────────────────────────────────────────
func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	# Only apply avoidance velocity when Anchalee is actively moving in the Walk state.
	# All other states manage their own velocity and move_and_slide() calls.
	if not state_machine or not state_machine.current_state:
		return
	if state_machine.current_state.name != "AnchaleeStateWalk":
		return
	
	var current_y = velocity.y
	var speed = safe_velocity.length()
	
	# Project movement toward safe_velocity, scaling speed by alignment to avoid strafing
	var forward = -global_transform.basis.z
	if is_walking_backward:
		forward = global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	var speed_factor = 1.0
	if speed > 0.01:
		var target_dir = safe_velocity.normalized()
		var dot = forward.dot(target_dir)
		speed_factor = clampf(dot, 0.1, 1.0)
		if is_walking_backward:
			speed_factor = 1.0
			
	var desired_vel = safe_velocity * speed_factor
	velocity = velocity.move_toward(desired_vel, 15.0 * get_physics_process_delta_time())
	velocity.y = current_y
	_clamp_velocity_toward_player()  # Never push the player
	move_and_slide()
	
	# Track if we are touching the player during navigation movement
	var touching = false
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if is_instance_valid(collider) and collider.is_in_group("player"):
			touching = true
			break
	is_touching_player = touching


func step_1() -> void:
	if not is_dead:
		SoundManager.play_3d("anchalee_footstep", self)


func step_2() -> void:
	if not is_dead:
		SoundManager.play_3d("anchalee_footstep", self)


# ─── Head Look-At IK & Companion Interactive System ─────────────────────────

func is_sprinting_active() -> bool:
	return player_is_sprinting or velocity.length() > 3.8

func is_jinking_active() -> bool:
	if trigger_post_getup_jink:
		return true
	if state_machine and state_machine.current_state:
		var cur_state = state_machine.current_state
		if cur_state.get("_jink_phase") != null and int(cur_state._jink_phase) > 0:
			return true
	return false

func _get_head_origin_global() -> Vector3:
	return global_position + Vector3(0, 1.4, 0)

func _get_node_head_or_pos(node: Node3D) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.ZERO
	if node.is_in_group("player") or node.name == "player" or node.name == "Player":
		return node.global_position + Vector3(0, 1.6, 0)
	if node.is_in_group("enemies") or "health" in node:
		return node.global_position + Vector3(0, 1.5, 0)
	return node.global_position + Vector3(0, 1.5, 0)

func _find_nearby_item_target(head_pos: Vector3, forward_dir: Vector3, fov_thresh: float) -> Vector3:
	var items = get_tree().get_nodes_in_group("object")
	var closest_pos = Vector3.ZERO
	var min_dist_sq = 3.5 * 3.5
	for item in items:
		if not is_instance_valid(item) or not item is Node3D:
			continue
		var i_pos = item.global_position + Vector3(0, 0.2, 0)
		var d_sq = head_pos.distance_squared_to(i_pos)
		if d_sq < min_dist_sq:
			var dir_to_i = (i_pos - head_pos).normalized()
			if forward_dir.dot(dir_to_i) > fov_thresh:
				min_dist_sq = d_sq
				closest_pos = i_pos
	return closest_pos

func _find_glance_target(delta: float) -> Vector3:
	if not enable_head_glance or is_dead:
		active_glance_target = null
		return Vector3.ZERO

	# Safety: Block glance during action recovery cooldown (0.8s)
	if glance_recovery_cooldown > 0.0:
		active_glance_target = null
		return Vector3.ZERO

	# Safety: Block glance during action states (Duck, GetUp, Hit, Die)
	var current_state = state_machine.get_current_state_name() if state_machine else ""
	if current_state in ["AnchaleeStateDuck", "AnchaleeStateGetUp", "AnchaleeStateHit", "AnchaleeStateDie"]:
		active_glance_target = null
		return Vector3.ZERO

	# Priority 0: Jinking locomotion override -> Strictly forward facing with turn lead
	if is_jinking_active():
		active_glance_target = null
		return Vector3.ZERO

	# Priority 0b: Sprinting locomotion -> Can look at active zombie IN FRONT
	if is_sprinting_active():
		var forward_dir_sprint = -global_transform.basis.z
		var anchalee_head_pos_sprint = _get_head_origin_global()
		var fov_thresh_sprint = cos(deg_to_rad(60.0))
		var closest_fwd_threat: Node3D = null
		var closest_fwd_pos = Vector3.ZERO
		var min_fwd_dist_sq = max_glance_distance * max_glance_distance

		# Hysteresis on active sprint glance target
		if is_instance_valid(active_glance_target) and active_glance_target in nearby_threats:
			var t_pos = _get_node_head_or_pos(active_glance_target)
			var d_sq = anchalee_head_pos_sprint.distance_squared_to(t_pos)
			var dir_to_t = (t_pos - anchalee_head_pos_sprint).normalized()
			var exit_dist_sq_sprint = (max_glance_distance * glance_exit_multiplier) * (max_glance_distance * glance_exit_multiplier)
			if d_sq < exit_dist_sq_sprint and forward_dir_sprint.dot(dir_to_t) > fov_thresh_sprint:
				closest_fwd_threat = active_glance_target
				closest_fwd_pos = t_pos
				min_fwd_dist_sq = d_sq

		for threat in nearby_threats:
			if not is_instance_valid(threat) or threat == active_glance_target or threat.is_queued_for_deletion() or threat.is_defeated:
				continue
			var t_pos = _get_node_head_or_pos(threat)
			var d_sq = anchalee_head_pos_sprint.distance_squared_to(t_pos)
			if d_sq < min_fwd_dist_sq:
				var dir_to_t = (t_pos - anchalee_head_pos_sprint).normalized()
				if forward_dir_sprint.dot(dir_to_t) > fov_thresh_sprint:
					min_fwd_dist_sq = d_sq
					closest_fwd_threat = threat
					closest_fwd_pos = t_pos

		if closest_fwd_threat:
			active_glance_target = closest_fwd_threat
			return closest_fwd_pos
		else:
			active_glance_target = null
			return Vector3.ZERO # Strictly forward with downward pitch

	var player = get_player()

	# Priority 1 (Comedy): Side-Eye after Friendly Fire / Splash (2.0s timer)
	if enable_comedy_features and _friendly_side_eye_timer > 0.0 and is_instance_valid(player):
		active_glance_target = player
		return _get_node_head_or_pos(player)

	# Priority 2: Gun Muzzle / Crosshair Aim Threat ("Don't Splash Me!")
	if is_instance_valid(player) and player.get("is_aimming") == true:
		if is_player_aiming_or_takedown():
			active_glance_target = player
			var gun_controller = player.get("gun_controller")
			if gun_controller and gun_controller.current_gun and gun_controller.current_gun.spawn_point:
				return gun_controller.current_gun.spawn_point.global_position
			return _get_node_head_or_pos(player)

	# Priority 3: Combat Witnessing (Player Melee Takedown nearby)
	if is_instance_valid(player):
		var p_sm = player.get_node_or_null("Statemachine")
		if p_sm and p_sm.get("current_state") and p_sm.current_state.name == "Takedown":
			var takedown_dist = global_position.distance_to(player.global_position)
			if takedown_dist <= 4.0:
				active_glance_target = player
				return _get_node_head_or_pos(player)

	# Priority 4: Danger Radar (Rear Flanking Threat on Player)
	var rear_threat = get_rear_threat_behind_player(4.5)
	if is_instance_valid(rear_threat):
		active_glance_target = rear_threat
		return _get_node_head_or_pos(rear_threat)

	# Priority 5: Approaching Active Threat in Vision Cone
	var forward_dir = -global_transform.basis.z
	var anchalee_head_pos = _get_head_origin_global()
	var fov_threshold = cos(deg_to_rad(glance_fov_deg))
	var entry_dist_sq = max_glance_distance * max_glance_distance
	var exit_dist_sq = (max_glance_distance * glance_exit_multiplier) * (max_glance_distance * glance_exit_multiplier)

	var closest_threat: Node3D = null
	var closest_threat_pos = Vector3.ZERO
	var min_threat_dist_sq = entry_dist_sq

	# Hysteresis check on current active threat target
	if is_instance_valid(active_glance_target) and active_glance_target in nearby_threats:
		var t_pos = _get_node_head_or_pos(active_glance_target)
		var d_sq = anchalee_head_pos.distance_squared_to(t_pos)
		var dir_to_t = (t_pos - anchalee_head_pos).normalized()
		if d_sq < exit_dist_sq and forward_dir.dot(dir_to_t) > fov_threshold:
			closest_threat = active_glance_target
			closest_threat_pos = t_pos
			min_threat_dist_sq = d_sq

	for threat in nearby_threats:
		if not is_instance_valid(threat) or threat == active_glance_target or threat.is_queued_for_deletion() or threat.is_defeated:
			continue
		var t_pos = _get_node_head_or_pos(threat)
		var d_sq = anchalee_head_pos.distance_squared_to(t_pos)
		if d_sq < min_threat_dist_sq:
			var dir_to_t = (t_pos - anchalee_head_pos).normalized()
			if forward_dir.dot(dir_to_t) > fov_threshold:
				min_threat_dist_sq = d_sq
				closest_threat = threat
				closest_threat_pos = t_pos

	if closest_threat:
		# Priority 5b: Cornered Panic Alternating Glance
		if is_cornered and is_instance_valid(player):
			if _cornered_look_target_leon:
				active_glance_target = player
				return _get_node_head_or_pos(player)
			else:
				active_glance_target = closest_threat
				return closest_threat_pos
		active_glance_target = closest_threat
		return closest_threat_pos

	# Priority 6: Staring Contest / Direct Eye Contact / Companion Voice
	if is_instance_valid(player):
		var p_pos = _get_node_head_or_pos(player)
		var p_dist_sq = anchalee_head_pos.distance_squared_to(p_pos)
		var dir_to_p = (p_pos - anchalee_head_pos).normalized()
		var in_fov = forward_dir.dot(dir_to_p) > fov_threshold
		var is_player_close = p_dist_sq < (4.0 * 4.0)

		# Priority 6b (Comedy): Player Spin Dizziness check
		var player_ang_vel = absf(float(player.get("angular_velocity"))) if "angular_velocity" in player else 0.0
		var is_player_spinning = player_ang_vel > 6.0
		if enable_comedy_features and is_player_spinning:
			_stare_timer = 0.0
			_stare_look_away_timer = 0.0
			active_glance_target = null
			return Vector3.ZERO # Look forward in bewilderment

		# Priority 6a (Comedy): Staring Contest
		var is_both_idle = velocity.length_squared() < 0.05 and player.velocity.length_squared() < 0.05
		var p_forward = -player.global_transform.basis.z
		var is_player_staring = p_forward.dot(-dir_to_p) > 0.85

		if enable_comedy_features and is_both_idle and is_player_close and is_player_staring and in_fov:
			_stare_timer += delta
			if _stare_timer > 3.5:
				if _stare_look_away_timer <= 0.0:
					_stare_look_away_timer = 1.8
		else:
			_stare_timer = maxf(0.0, _stare_timer - delta * 2.0)

		if _stare_look_away_timer > 0.0:
			active_glance_target = null
			var awkward_pos = anchalee_head_pos + (global_transform.basis.x * 1.5 + Vector3.UP * 0.8 - global_transform.basis.z * 10.0)
			return awkward_pos

		# Priority 6c: Direct eye contact during speech or calm proximity
		var is_speaking_active = (face_controller and face_controller.is_speaking) or p_dist_sq < (2.2 * 2.2)
		if in_fov and (p_dist_sq < entry_dist_sq or is_speaking_active):
			active_glance_target = player
			return p_pos

	# Priority 7: Curiosity / Item Spotting Hint
	if enable_item_spotting and _item_spot_cooldown <= 0.0:
		var item_pos = _find_nearby_item_target(anchalee_head_pos, forward_dir, fov_threshold)
		if item_pos != Vector3.ZERO:
			active_glance_target = null
			return item_pos

	active_glance_target = null
	return Vector3.ZERO

func _process(delta: float) -> void:
	if is_dead:
		if head_lookat:
			head_lookat.influence = 0.0
		return

	# Decrement timers
	if glance_recovery_cooldown > 0.0:
		glance_recovery_cooldown -= delta
	if _friendly_side_eye_timer > 0.0:
		_friendly_side_eye_timer -= delta
	if _stare_look_away_timer > 0.0:
		_stare_look_away_timer -= delta
	if _item_spot_cooldown > 0.0:
		_item_spot_cooldown -= delta

	# Cornered panic glance oscillator
	if is_cornered:
		_cornered_look_timer += delta
		if _cornered_look_timer >= 1.2:
			_cornered_look_timer = 0.0
			_cornered_look_target_leon = not _cornered_look_target_leon
	else:
		_cornered_look_timer = 0.0
		_cornered_look_target_leon = false

	# Action state gating for recovery cooldown (Duck, GetUp, Hit, Die)
	var current_state = state_machine.get_current_state_name() if state_machine else ""
	var is_in_action = current_state in ["AnchaleeStateDuck", "AnchaleeStateGetUp", "AnchaleeStateHit", "AnchaleeStateDie"]
	if is_in_action:
		_was_in_action_state = true
		glance_recovery_cooldown = 0.8
	elif _was_in_action_state:
		_was_in_action_state = false
		glance_recovery_cooldown = 0.8

	# Accurately track real-time animation name and anim_time from AnimationTree / AnimationPlayer
	var anim_tree = get_node_or_null("AnchaleeModel/AnimationTree") as AnimationTree
	var is_in_idle_anim_head_turn = false

	if anim_tree and anim_tree.active:
		var root_pb = anim_tree.get("parameters/playback")
		var current_root_state = String(root_pb.get_current_node()) if root_pb else ""
		
		# If inside Idle, query the nested Idle_Loop state machine (Root > Idle > Idle_Loop : IDLE_HeadTurn)
		if current_root_state == "Idle" or current_state == "AnchaleeStateIdle":
			var idle_pb = anim_tree.get("parameters/Idle/Idle_Loop/playback")
			if idle_pb:
				current_anim_name = String(idle_pb.get_current_node()).strip_edges()
				current_anim_time = idle_pb.get_current_play_position()
				if enable_idle_anim_head_window and current_anim_name == "IDLE_HeadTurn":
					if current_anim_time >= idle_anim_head_turn_start and current_anim_time <= idle_anim_head_turn_end:
						if not is_in_combat():
							is_in_idle_anim_head_turn = true
			else:
				current_anim_name = current_root_state
				current_anim_time = root_pb.get_current_play_position() if root_pb else 0.0
		else:
			current_anim_name = current_root_state
			current_anim_time = root_pb.get_current_play_position() if root_pb else 0.0
	elif anim_player and anim_player.is_playing():
		current_anim_name = anim_player.current_animation
		current_anim_time = anim_player.current_animation_position

	# Compute default forward target with turning angular velocity lead
	var default_local = Vector3(0.0, 1.4, -head_look_depth)
	default_local.x -= _smoothed_angular_velocity * 0.75
	var default_forward_target = to_global(default_local)

	# Determine destination glance target
	var raw_target_pos = _find_glance_target(delta)
	var destination_target_global = raw_target_pos if raw_target_pos != Vector3.ZERO else default_forward_target

	# Smoothly interpolate glance tracking position
	if current_glance_pos == Vector3.ZERO:
		current_glance_pos = default_forward_target
	else:
		var target_turn_speed = head_turn_speed if raw_target_pos != Vector3.ZERO else glance_exit_speed
		current_glance_pos = current_glance_pos.lerp(destination_target_global, delta * target_turn_speed)

	# Lock vertical height to head origin for pure horizontal head rotation
	var head_origin_global = _get_head_origin_global()
	var to_target_vec = current_glance_pos - head_origin_global
	to_target_vec.y = 0.0 # Strict horizontal 2D plane projection
	var dist_to_target = to_target_vec.length()

	# Project onto fixed 15m spherical depth shell to eliminate proximity distortion
	var aim_dir = -global_transform.basis.z
	if dist_to_target > 0.01:
		var look_dir = to_target_vec / dist_to_target
		# If very close (< 0.8m), smoothly blend towards forward facing to prevent twitching inside personal space
		if dist_to_target < 0.8:
			var blend = clampf(dist_to_target / 0.8, 0.0, 1.0)
			aim_dir = (-global_transform.basis.z).slerp(look_dir, blend).normalized()
		else:
			aim_dir = look_dir

	var fixed_depth_global = head_origin_global + aim_dir * head_look_depth

	# Convert to skeleton local space and update Marker3D
	var skel = get_node_or_null("AnchaleeModel/rig_002/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton")
	var target_local = skel.to_local(fixed_depth_global) if skel else to_local(fixed_depth_global)
	if absf(target_local.x) < 0.001:
		target_local.x = 0.001

	# Smoothly blend sprint/jink downward pitch weight
	var target_sprint_pitch_weight = 1.0 if (is_sprinting_active() or is_jinking_active()) else 0.0
	current_sprint_pitch_weight = lerpf(current_sprint_pitch_weight, target_sprint_pitch_weight, delta * 10.0)

	# Additively apply downward head pitch during sprint / jink across all targets
	if current_sprint_pitch_weight > 0.001:
		target_local.y -= sprint_pitch_down * current_sprint_pitch_weight

	if aim_target_head:
		aim_target_head.position = aim_target_head.position.lerp(target_local, delta * head_turn_speed)

	# Determine target influence
	var target_head_inf = 0.0
	if is_in_action or glance_recovery_cooldown > 0.0 or is_in_idle_anim_head_turn:
		target_head_inf = 0.0 # Yield to baked idle turn or action state
	elif is_sprinting_active() or is_jinking_active():
		target_head_inf = 0.9 # Look forward / at threat with turn leading
	elif active_glance_target != null or raw_target_pos != Vector3.ZERO:
		target_head_inf = 1.0
	else:
		target_head_inf = 0.9 # Default forward facing

	# Asymmetrical blending: brisk entry (10.0), smooth exit (glance_exit_speed)
	var inf_blend_speed = 10.0 if target_head_inf > current_head_influence else glance_exit_speed
	current_head_influence = lerpf(current_head_influence, target_head_inf, delta * inf_blend_speed)

	if head_lookat:
		# Dynamic pitch limits: wide 30° during sprint/jink for running dip, tight ±6° during idle/walk for steady level gaze
		if is_sprinting_active() or is_jinking_active():
			head_lookat.primary_positive_limit_angle = deg_to_rad(30.0)
			head_lookat.primary_negative_limit_angle = deg_to_rad(30.0)
		else:
			head_lookat.primary_positive_limit_angle = deg_to_rad(6.0)
			head_lookat.primary_negative_limit_angle = deg_to_rad(6.0)
		head_lookat.influence = current_head_influence
