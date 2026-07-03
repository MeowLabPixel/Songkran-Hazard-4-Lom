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

# ─── Health ────────────────────────────────────────────────────────────────
@export var max_health: int = 100
var health: int = max_health
var is_dead: bool = false

# ─── Following ─────────────────────────────────────────────────────────────
@export_group("Following")
@export var follow_start_distance: float = 1.3
@export var follow_stop_distance: float = 0.85
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

var _has_rolled_takedown_duck: bool = false
var _takedown_duck_roll: bool = false

var zombie_reaction_state: String = "none"
var zombie_reaction_timer: float = 0.0
@export var zombie_reaction_cooldown: float = 2.5
@export var reaction_chance_duck: float = 0.30
@export var reaction_chance_evade: float = 0.40
# The remaining percentage will be used for "back_up"

## Set by states when Anchalee is stuck.
var is_cornered: bool = false:
	set(value):
		if value == is_cornered:
			return
		is_cornered = value
		if is_node_ready() and help_label:
			help_label.visible = value

func _ready() -> void:
	if has_node("AnchaleeModel/AnimationPlayer"):
		anim_player = $AnchaleeModel/AnimationPlayer
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

	# Setup lean modifier programmatically
	var skel = get_node_or_null("AnchaleeModel/rig_002/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton")
	if not skel:
		skel = find_child("OriginalSkeleton", true, false)
	if skel:
		var lean = AnchaleeLeanModifier.new()
		lean.anchalee = self
		lean.name = "AnchaleeLeanModifier"
		skel.add_child(lean)

func _unhandled_input(event: InputEvent) -> void:
	pass # Wait behavior replaced by dynamic Idle/Walk

func kill_anchalee() -> void:
	if is_dead:
		return
	health = 0
	is_dead = true
	print("[Anchalee] Force Dead.")
	state_machine.transition_to("AnchaleeStateDie")
	
	# Kill player
	var player = get_player()
	if player and player.has_method("force_die"):
		player.force_die()

## Called by enemy attack hitboxes to damage Anchalee.
func take_damage(amount: int, _hit_data: Dictionary = {}) -> void:
	if is_dead:
		return
		
	# Immunity is now fully handled by physics layers via set_immune().
	# If the hitboxes are hit, she takes damage.
		
	health -= amount
	print("[Anchalee] Took %d damage -- HP: %d/%d" % [amount, health, max_health])
	if health <= 0:
		kill_anchalee()
		return
	state_machine.transition_to("AnchaleeStateHit")

## Called by player gun/bullets (friendly fire)
func take_hit(hit_data: Dictionary) -> void:
	if is_dead: return
	var amount = hit_data.get("damage", 10)
	health -= amount
	print("[Anchalee] Friendly Fire! Took %d damage -- HP: %d/%d" % [amount, health, max_health])
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

func get_effective_follow_stop_distance() -> float:
	var dist = follow_stop_distance
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
		
		# Offset back if player is moving backward or turning right (ang_vel < -0.1) while standing still
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
					if "defeated" in state_name or "stun" in state_name or "push" in state_name or "takedown" in state_name or "knockdown" in state_name or "getup" in state_name or "get_up" in state_name:
						is_active_threat = false
			
			if is_active_threat:
				count += 1
				
	nearby_threats = valid_threats
	return count

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
