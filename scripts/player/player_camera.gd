extends Node3D

@export var character: CharacterBody3D
@export var edge_spring_arm: SpringArm3D
@export var rear_spring_arm: SpringArm3D
@export var camera_align_speed:float = 0.2
@export var camera: Camera3D
@export var aim_rear_spring_arm_length:float =0.5
@export var aim_edge_spring_arm_length:float =0.5
@export var aim_edge_spring_arm_length_left:float =0.25
@export var aim_speed:float =0.2
@export var aim_fov:float =55
@export var sprint_fov:float =90
@export var sprint_tween_speed:float =0.5
@export var target: Marker3D
@export var targetref: Marker3D

@export_group("Footage Capture & View Mode")
@export var look_at_player: bool = false: set = set_look_at_player
@export var look_at_player_distance_offset: float = 0.0
@export var look_at_player_x: float = -1.28

func set_look_at_player(val: bool) -> void:
	look_at_player = val

func is_look_at_player() -> bool:
	return look_at_player

func toggle_look_at_player() -> void:
	set_look_at_player(not look_at_player)

func get_forward_aim_basis() -> Basis:
	if not look_at_player:
		return global_transform.basis
	return global_transform.basis.rotated(Vector3.UP, PI)

@export_group("Aim Settings")
@export var auto_swap_wall_distance: float = 0.5

@export_group("Rear Collision Radius")
@export var rear_collision_radius_center: float = 0.1
@export var rear_collision_radius_right: float = 0.01
@export var rear_collision_radius_left: float = 0.1

@export_group("Camera Collision Smoothing")
@export var min_collision_distance: float = 0.3
@export var max_collision_distance: float = 3.0
@export var camera_collision_zoom_in_speed: float = 25.0
@export var camera_collision_zoom_out_speed: float = 8.0

var collision_target_length: float = 1.5
var collision_smoothed_target: float = 1.5
var collision_current_length: float = 1.5

var original_rear_collision_mask: int = 0

var current_local_transform: Transform3D
var ideal_camera_marker: Marker3D
var auto_swapped_to_left: bool = false
var is_hitting_wall: bool = false

var camera_rotation: Vector2= Vector2.ZERO
var target_camera_rotation: Vector2 = Vector2.ZERO
@export var camera_smoothing_speed: float = 25.0 # Lower is smoother, higher is more responsive
var pending_camera_rotation: Vector2 = Vector2.ZERO
var mouse_sensitivity: float = 0.002

# Modern 3D Camera Screen Shake
enum CameraShakeMode { DISABLED = 0, WEAKPOINT_ONLY = 1, ENABLED = 2 }
@export_group("Camera Shake Settings")
@export var camera_shake_mode: CameraShakeMode = CameraShakeMode.ENABLED
@export var enable_camera_shake: bool = true
@export var max_shake_offset: Vector3 = Vector3(0.35, 0.35, 0.20)
@export var max_shake_roll: float = 0.08
@export var max_shake_pitch: float = 0.05
@export var max_shake_yaw: float = 0.04

@export_subgroup("Gun Shake")
@export var gun_shake_intensity: float = 1.0
@export var gun_shake_decay: float = 12.0

@export_subgroup("Weakpoint Shake")
@export var weakpoint_shake_intensity: float = 0.60
@export var weakpoint_shake_decay: float = 14.0

@export_subgroup("Takedown Shake")
@export var takedown_shake_intensity: float = 0.75
@export var takedown_shake_decay: float = 10.0

@export_subgroup("Get Hit Shake")
@export var get_hit_shake_intensity: float = 0.65
@export var get_hit_shake_decay: float = 16.0

@export_subgroup("Grab Shake")
@export var grab_shake_intensity: float = 0.85
@export var grab_shake_decay: float = 8.0

var camera_trauma: float = 0.0
var shake_decay_speed: float = 12.0

func set_camera_shake_mode(mode_val) -> void:
	if mode_val is int or mode_val is CameraShakeMode:
		camera_shake_mode = mode_val as CameraShakeMode

# Forwarding alias for backwards compatibility
func set_camera_recoil_mode(mode_val) -> void:
	set_camera_shake_mode(mode_val)

func add_shake(trauma: float) -> void:
	if not enable_camera_shake:
		return
	camera_trauma = clampf(camera_trauma + trauma, 0.0, 1.0)

func trigger_gun_shake(shake_amount: float = 0.08) -> void:
	if not enable_camera_shake or camera_shake_mode == CameraShakeMode.DISABLED:
		return
	shake_decay_speed = gun_shake_decay
	var trauma = (shake_amount if shake_amount > 0.0 else 0.08) * 8.0 * gun_shake_intensity
	add_shake(trauma)

func trigger_weakpoint_shake() -> void:
	if not enable_camera_shake or camera_shake_mode == CameraShakeMode.DISABLED:
		return
	shake_decay_speed = weakpoint_shake_decay
	add_shake(weakpoint_shake_intensity)

func trigger_takedown_shake() -> void:
	if not enable_camera_shake or camera_shake_mode == CameraShakeMode.DISABLED:
		return
	shake_decay_speed = takedown_shake_decay
	add_shake(takedown_shake_intensity)

func trigger_get_hit_shake(hit_location: String = "front") -> void:
	if not enable_camera_shake or camera_shake_mode == CameraShakeMode.DISABLED:
		return
	shake_decay_speed = get_hit_shake_decay
	var trauma = get_hit_shake_intensity
	if hit_location == "back":
		trauma *= 1.15 # Slightly heavier punch for back hits
	add_shake(trauma)

func trigger_grab_shake() -> void:
	if not enable_camera_shake or camera_shake_mode == CameraShakeMode.DISABLED:
		return
	shake_decay_speed = grab_shake_decay
	add_shake(grab_shake_intensity)

func add_recoil(pitch: float = 0.0, yaw: float = 0.0, fov_kick: float = 0.0, shake: float = 0.04, is_weakpoint_hit: bool = false) -> void:
	if camera_shake_mode == CameraShakeMode.DISABLED:
		return
	if camera_shake_mode == CameraShakeMode.WEAKPOINT_ONLY and not is_weakpoint_hit:
		return
	trigger_gun_shake(shake)

# Smooth independent camera breathing sway (no noise coupling)
var camera_sway_offset: Vector2 = Vector2.ZERO
@export_group("Camera Aim Sway")
@export var enable_camera_aim_sway: bool = true
@export var camera_sway_pitch: float = 0.0008
@export var camera_sway_yaw: float = 0.0005
@export var camera_sway_speed: float = 1.1
@export var max_look_up: float = 1.4 # ~80 degrees up
@export var max_look_down: float = 1.4 # ~80 degrees down
@export var look_up_lift_amount: float = 1.5 # How much the camera lifts when looking up
@export var look_down_lift_amount: float = 1.5 # How much the camera lifts when looking down
@export var tank_look_down_lift: float = -0.2 # Tank mode custom look down lift multiplier
@export var tank_snap_back_speed: float = 6.0 # Tank mode camera snap back speed
var aim_offset: Vector2 = Vector2.ZERO
var tank_look_around: Vector2 = Vector2.ZERO
var was_aiming: bool = false
var was_grab: bool = false
var target_tank_look_around: Vector2 = Vector2.ZERO
var time_since_last_mouse_move: float = 0.0
var _tank_turn_velocity: float = 0.0

@export_group("Aim Deadzones")
@export var aim_deadzone_left: float = 0.15 # Small limit on left to avoid body blocking
@export var aim_deadzone_right: float = 0.35 # Larger limit on right
@export var aim_deadzone_up: float = 0.2
@export var aim_deadzone_down: float = 0.2

var camera_tween:Tween
enum cameraalign{LEFT=-1,RIGHT=1,CENTER=0}
var current_camera_align:cameraalign = cameraalign.RIGHT

var base_position_x: float = 0.0
var base_position_y: float = 0.0
var base_position_z: float = 0.0
var action_offset_y: float = 0.0
var offset_tween: Tween

var action_offset_x: float = 0.0
var offset_x_tween: Tween

var action_pitch: float = 0.0
var pitch_tween: Tween

var base_spring_length: float = 0.0
var action_spring_length: float = 0.0
var spring_tween: Tween

var takedown_roll_offset: float = 0.0
var takedown_fov_offset: float = 0.0
var takedown_cam_tween: Tween = null

func set_action_offset_y(target_offset: float, duration: float) -> void:
	if offset_tween:
		offset_tween.kill()
	offset_tween = get_tree().create_tween()
	offset_tween.tween_property(self, "action_offset_y", target_offset, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func set_action_offset_x(target_offset: float, duration: float) -> void:
	if offset_x_tween:
		offset_x_tween.kill()
	offset_x_tween = get_tree().create_tween()
	offset_x_tween.tween_property(self, "action_offset_x", target_offset, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func set_action_pitch(target_pitch_degrees: float, duration: float) -> void:
	if pitch_tween:
		pitch_tween.kill()
	pitch_tween = get_tree().create_tween()
	pitch_tween.tween_property(self, "action_pitch", deg_to_rad(target_pitch_degrees), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func set_action_spring_length(target_offset: float, duration: float) -> void:
	if spring_tween:
		spring_tween.kill()
	spring_tween = get_tree().create_tween()
	spring_tween.tween_property(self, "action_spring_length", target_offset, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

var active_camera_smoothing_speed: float = 25.0
var smoothing_speed_tween: Tween
var takedown_yaw_offset: float = 0.0
var takedown_yaw_tween: Tween = null

func trigger_hybrid_takedown_yaw_sweep(target_diff: float, duration: float) -> void:
	if takedown_yaw_tween and takedown_yaw_tween.is_valid():
		takedown_yaw_tween.kill()
		
	takedown_yaw_offset = 0.0
	takedown_yaw_tween = create_tween()
	takedown_yaw_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	takedown_yaw_tween.tween_property(self, "takedown_yaw_offset", target_diff, duration)
	takedown_yaw_tween.tween_callback(func():
		target_camera_rotation.x += takedown_yaw_offset
		takedown_yaw_offset = 0.0
	)



func start_takedown_windup_zoom_in(duration: float = 0.35) -> void:
	if takedown_cam_tween and takedown_cam_tween.is_valid():
		takedown_cam_tween.kill()
		
	if smoothing_speed_tween and smoothing_speed_tween.is_valid():
		smoothing_speed_tween.kill()
		
	smoothing_speed_tween = create_tween()
	smoothing_speed_tween.tween_property(self, "active_camera_smoothing_speed", 10.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
	takedown_cam_tween = create_tween()
	takedown_cam_tween.set_parallel(true)
	
	# Windup Phase: Dynamic camera blend based on rotation distance
	set_action_offset_y(-0.55, duration)
	set_action_offset_x(0.55, duration)
	set_action_pitch(-1.0, duration)
	set_action_spring_length(-0.25, duration)
	
	takedown_cam_tween.tween_property(self, "takedown_roll_offset", deg_to_rad(-0.8), duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	takedown_cam_tween.tween_property(self, "takedown_fov_offset", -5.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)







func start_takedown_camera_transition() -> void:
	start_takedown_windup_zoom_in()

func trigger_takedown_release_zoom_out() -> void:
	if takedown_cam_tween and takedown_cam_tween.is_valid():
		takedown_cam_tween.kill()
		
	takedown_cam_tween = create_tween()
	takedown_cam_tween.set_parallel(true)
	
	# Release Phase: Softened quick zoom OUT (expand FOV wide +10°, extend spring arm backward +0.45m), stronger left trucking sweep (-1.65m X), reduced downward Y offset (-0.15m)
	set_action_offset_y(-0.15, 0.10)
	set_action_offset_x(-1.65, 0.10) # Stronger leftward trucking offset (-1.65m) during release
	set_action_pitch(1.0, 0.10)
	set_action_spring_length(0.45, 0.10)



	
	takedown_cam_tween.tween_property(self, "takedown_roll_offset", deg_to_rad(0.8), 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	takedown_cam_tween.tween_property(self, "takedown_fov_offset", 10.0, 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)




	
	# Smooth follow-through easing back toward neutral
	takedown_cam_tween.chain().tween_property(self, "takedown_fov_offset", 4.0, 0.30)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	takedown_cam_tween.parallel().tween_property(self, "takedown_roll_offset", deg_to_rad(0.0), 0.30)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func trigger_takedown_impact_fov_kick() -> void:
	trigger_takedown_release_zoom_out()

func exit_takedown_camera_transition() -> void:
	if takedown_cam_tween and takedown_cam_tween.is_valid():
		takedown_cam_tween.kill()
		
	if takedown_yaw_tween and takedown_yaw_tween.is_valid():
		takedown_yaw_tween.kill()
	takedown_yaw_offset = 0.0
		
	if smoothing_speed_tween and smoothing_speed_tween.is_valid():
		smoothing_speed_tween.kill()

		
	smoothing_speed_tween = create_tween()
	smoothing_speed_tween.tween_property(self, "active_camera_smoothing_speed", camera_smoothing_speed, 0.50)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
	set_action_offset_y(0.0, 0.45)
	set_action_offset_x(0.0, 0.45)
	set_action_pitch(0.0, 0.45)
	set_action_spring_length(0.0, 0.45)
	
	takedown_cam_tween = create_tween()
	takedown_cam_tween.set_parallel(true)
	takedown_cam_tween.tween_property(self, "takedown_roll_offset", 0.0, 0.45)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	takedown_cam_tween.tween_property(self, "takedown_fov_offset", 0.0, 0.45)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func is_action_camera_active() -> bool:
	if is_death_camera_active:
		return true
	var is_offsetting = absf(action_offset_x) > 0.01 or absf(action_offset_y) > 0.01 or absf(action_pitch) > 0.01 or absf(action_spring_length) > 0.01
	var is_tweening = (offset_x_tween != null and offset_x_tween.is_running()) or (offset_tween != null and offset_tween.is_running()) or (pitch_tween != null and pitch_tween.is_running()) or (spring_tween != null and spring_tween.is_running())
	return is_offsetting or is_tweening

# Cinematic Overhead Pull-Back Death Camera
@export var death_cam_dutch_tilt_angle: float = 15.0
@export var death_cam_overhead_pitch: float = 85.0
var is_death_camera_active: bool = false
var death_cam_start_pos: Vector3 = Vector3.ZERO
var death_cam_start_quat: Quaternion = Quaternion.IDENTITY
var death_cam_target_center: Vector3 = Vector3.ZERO
var death_cam_overhead_quat: Quaternion = Quaternion.IDENTITY
var death_cam_mid_height: float = 3.5
var death_cam_max_height: float = 6.0
var death_cam_elapsed: float = 0.0
var death_cam_phase1_duration: float = 1.3
var death_cam_phase2_duration: float = 2.7
var death_cam_start_fov: float = 65.0

func start_death_camera() -> void:
	if is_death_camera_active:
		return
	is_death_camera_active = true
	death_cam_elapsed = 0.0
	
	# Terminate any running action/camera tweens
	if offset_tween and offset_tween.is_valid(): offset_tween.kill()
	if offset_x_tween and offset_x_tween.is_valid(): offset_x_tween.kill()
	if pitch_tween and pitch_tween.is_valid(): pitch_tween.kill()
	if spring_tween and spring_tween.is_valid(): spring_tween.kill()
	if takedown_cam_tween and takedown_cam_tween.is_valid(): takedown_cam_tween.kill()
	if camera_tween and camera_tween.is_valid(): camera_tween.kill()
	if takedown_yaw_tween and takedown_yaw_tween.is_valid(): takedown_yaw_tween.kill()
	if smoothing_speed_tween and smoothing_speed_tween.is_valid(): smoothing_speed_tween.kill()
	
	if camera:
		death_cam_start_pos = camera.global_position
		death_cam_start_quat = camera.global_transform.basis.get_rotation_quaternion()
		death_cam_start_fov = camera.fov
	else:
		death_cam_start_pos = global_position
		death_cam_start_quat = global_transform.basis.get_rotation_quaternion()
		death_cam_start_fov = defaut_camera_fov
		
	# Center on the fallen character body (slightly elevated from floor)
	if character:
		death_cam_target_center = character.global_position + Vector3(0, 0.3, 0)
	else:
		death_cam_target_center = global_position + Vector3(0, 0.3, 0)
		
	# Check for ceiling clearance above player using raycast
	var space_state = get_world_3d().direct_space_state
	var ray = PhysicsRayQueryParameters3D.create(death_cam_target_center, death_cam_target_center + Vector3(0, 8.0, 0), 1)
	ray.exclude = get_camera_exclusion_rids()
	var hit = space_state.intersect_ray(ray)
	
	death_cam_max_height = 5.8
	if hit:
		death_cam_max_height = maxf(hit.position.y - death_cam_target_center.y - 0.5, 2.2)
	death_cam_mid_height = clampf(death_cam_max_height * 0.60, 2.0, 3.4)
	
	# Determine overhead orientation:
	# Looking down towards player with UP vector aligned to player's current view heading so screen doesn't snap/flip
	var forward_heading = -global_transform.basis.z
	forward_heading.y = 0.0
	if forward_heading.length_squared() < 0.01 and character:
		forward_heading = -character.global_transform.basis.z
		forward_heading.y = 0.0
	if forward_heading.length_squared() < 0.01:
		forward_heading = Vector3.FORWARD
	forward_heading = forward_heading.normalized()
	
	# Construct orthogonal overhead basis at death_cam_overhead_pitch (e.g. 85 deg steep overhead plunge)
	var pitch_rad = deg_to_rad(clampf(death_cam_overhead_pitch, 60.0, 90.0))
	var look_down = (Vector3.DOWN * sin(pitch_rad) + forward_heading * cos(pitch_rad)).normalized()
	var right = look_down.cross(forward_heading).normalized()
	var true_up = right.cross(look_down).normalized()
	var overhead_basis = Basis(right, true_up, -look_down)
	death_cam_overhead_quat = overhead_basis.get_rotation_quaternion()

func _process_death_camera(delta: float) -> void:
	if not camera:
		return
		
	death_cam_elapsed += delta
	
	# Phase 1: Smoothly rise and tilt down into centered top-down view (0.0 to 1.3s)
	var phase1_t = clampf(death_cam_elapsed / death_cam_phase1_duration, 0.0, 1.0)
	var smooth_p1 = 1.0 - pow(1.0 - phase1_t, 3.0)
	
	# Phase 2: Slow crane pull-back / zoom-out (1.3s to 4.0s)
	var phase2_elapsed = maxf(0.0, death_cam_elapsed - death_cam_phase1_duration)
	var phase2_t = clampf(phase2_elapsed / death_cam_phase2_duration, 0.0, 1.0)
	var smooth_p2 = -(cos(PI * phase2_t) - 1.0) * 0.5
	
	# Interpolate horizontal position (center directly on player)
	var cur_x = lerpf(death_cam_start_pos.x, death_cam_target_center.x, smooth_p1)
	var cur_z = lerpf(death_cam_start_pos.z, death_cam_target_center.z, smooth_p1)
	
	# Height: Arc up to mid_height in Phase 1, then slowly pull back higher to max_height in Phase 2
	var cur_y: float
	if phase1_t < 1.0:
		cur_y = lerpf(death_cam_start_pos.y, death_cam_target_center.y + death_cam_mid_height, smooth_p1)
	else:
		cur_y = lerpf(death_cam_target_center.y + death_cam_mid_height, death_cam_target_center.y + death_cam_max_height, smooth_p2)
		
	# Slerp rotation to top-down overhead
	var cur_quat = death_cam_start_quat.slerp(death_cam_overhead_quat, smooth_p1)
	
	# Subtle rotational drift during Phase 2 (+2.5 degrees around Y) for cinematic film feel
	if phase2_t > 0.0:
		var drift_quat = Quaternion(Vector3.UP, deg_to_rad(2.5 * smooth_p2))
		cur_quat = drift_quat * cur_quat
		
	# Smoothly lerp into Dutch tilt motion (roll around optical view axis)
	var mid_dutch = death_cam_dutch_tilt_angle * 0.75
	var cur_dutch_deg: float
	if phase1_t < 1.0:
		cur_dutch_deg = lerpf(0.0, mid_dutch, smooth_p1)
	else:
		cur_dutch_deg = lerpf(mid_dutch, death_cam_dutch_tilt_angle, smooth_p2)
		
	var dutch_quat = Quaternion(Vector3.FORWARD, deg_to_rad(cur_dutch_deg))
	cur_quat = cur_quat * dutch_quat
		
	camera.global_transform = Transform3D(Basis(cur_quat), Vector3(cur_x, cur_y, cur_z))
	
	# Subtle FOV expansion (+8 degrees) for dramatic scale during pull-back
	var target_fov = death_cam_start_fov + 8.0
	camera.fov = lerpf(death_cam_start_fov, target_fov, smooth_p2)


@onready var defaut_edge_spring_arm_length: float = edge_spring_arm.spring_length
@onready var defaut_rear_spring_arm_length: float = rear_spring_arm.spring_length
@onready var defaut_camera_fov:float = camera.fov



func _ready() -> void:
	add_to_group("player_camera")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_position_x = position.x
	base_position_y = position.y
	base_position_z = position.z
	base_spring_length = defaut_rear_spring_arm_length
	collision_target_length = defaut_rear_spring_arm_length
	collision_smoothed_target = defaut_rear_spring_arm_length
	collision_current_length = defaut_rear_spring_arm_length
	
	if get_tree() and get_tree().root.has_node("GameManager"):
		var gm = get_tree().root.get_node("GameManager")
		if "look_at_player_camera" in gm:
			look_at_player = gm.look_at_player_camera

	# Initialize camera rotation from character's starting rotation in the editor
	if character:
		var init_y = character.rotation.y
		camera_rotation.x = -init_y
		target_camera_rotation.x = -init_y
		
	if camera:
		camera.set_as_top_level(true)
		
	if rear_spring_arm:
		ideal_camera_marker = Marker3D.new()
		rear_spring_arm.add_child(ideal_camera_marker)
		current_local_transform = global_transform.affine_inverse() * camera.global_transform
		
		original_rear_collision_mask = rear_spring_arm.collision_mask
		rear_spring_arm.collision_mask = 0
		
		if rear_spring_arm.shape:
			rear_spring_arm.shape = rear_spring_arm.shape.duplicate()
			
	set_camera_alignment(current_camera_align)
	


func check_auto_shoulder_swap() -> void:
	if not character:
		return
		
	var is_sprinting = false
	var sm = character.get_node_or_null("Statemachine")
	if sm and sm.get("current_state") and sm.current_state.name == "Sprint":
		is_sprinting = true
		
	var space_state = get_world_3d().direct_space_state
	var right_dir = character.global_transform.basis.x
	var origin = character.global_position + Vector3(0, 1.0, 0) # Chest height
	var target_pos = origin + right_dir * auto_swap_wall_distance
	
	var query = PhysicsRayQueryParameters3D.create(origin, target_pos, 1) # Layer 1
	query.exclude = get_camera_exclusion_rids()
	var result = space_state.intersect_ray(query)
	
	if result and not is_sprinting:
		# Wall detected on the right and not sprinting
		if current_camera_align == cameraalign.RIGHT:
			auto_swapped_to_left = true
			swap_camera_align()
	else:
		# No wall on the right (or player is sprinting)
		if auto_swapped_to_left and current_camera_align == cameraalign.LEFT:
			auto_swapped_to_left = false
			swap_camera_align()

func _process(delta: float) -> void:
	if is_death_camera_active:
		_process_death_camera(delta)
		return

	var is_aiming_now = character and character.is_aimming
	var is_grab_now = character and character.is_grab
	
	if GameManager.movement_type == GameManager.MovementType.TANK:
		if is_aiming_now and not was_aiming:
			target_camera_rotation.x += tank_look_around.x
			camera_rotation.x += tank_look_around.x
			target_camera_rotation.y = tank_look_around.y
			camera_rotation.y = tank_look_around.y
			tank_look_around = Vector2.ZERO
			target_tank_look_around = Vector2.ZERO
		elif is_grab_now and not was_grab:
			target_camera_rotation.x += tank_look_around.x
			camera_rotation.x += tank_look_around.x
			target_camera_rotation.y = tank_look_around.y
			camera_rotation.y = tank_look_around.y
			tank_look_around = Vector2.ZERO
			target_tank_look_around = Vector2.ZERO
			
		# Handle keyboard turning and look-around snapping when not aiming and not in grab loop
		if not is_aiming_now and not is_grab_now:
			var turn_input = 0.0
			if Input.is_action_pressed("ui_left"):
				turn_input -= 1.0
			if Input.is_action_pressed("ui_right"):
				turn_input += 1.0
			var accel = 7.0
			var decel = 9.0
			if abs(turn_input) > 0.0:
				_tank_turn_velocity = move_toward(_tank_turn_velocity, turn_input, delta * accel)
			else:
				_tank_turn_velocity = move_toward(_tank_turn_velocity, 0.0, delta * decel)
			
			var turn_speed_rad = deg_to_rad(character.turn_speed) if character else 2.5
			var turn_amount = _tank_turn_velocity * turn_speed_rad * delta
			target_camera_rotation.x += turn_amount
			
			# Check if player is active (walking or turning)
			var is_walking = Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back")
			var is_turning = abs(turn_input) > 0.0
			var is_moving = is_walking or is_turning
			
			time_since_last_mouse_move += delta
			if is_moving or time_since_last_mouse_move > 0.2:
				var active_snap_speed = tank_snap_back_speed
				if is_moving:
					active_snap_speed *= 1.5
				target_tank_look_around = target_tank_look_around.lerp(Vector2.ZERO, delta * active_snap_speed)
				
			# Smoothly interpolate active look-around
			tank_look_around = tank_look_around.lerp(target_tank_look_around, delta * 8.0)
			
	was_aiming = is_aiming_now
	was_grab = is_grab_now

	if character and not character.is_aimming:
		aim_offset = aim_offset.lerp(Vector2.ZERO, delta * 15.0)
		
	check_auto_shoulder_swap()
		
	# Smoothly apply the deadzone excess rotation for a heavier, cinematic feel
	if pending_camera_rotation.length_squared() > 0.000001:
		var applied = pending_camera_rotation * min(delta * 15.0, 1.0)
		target_camera_rotation += applied
		target_camera_rotation.y = clamp(target_camera_rotation.y, -max_look_up, max_look_down)
		pending_camera_rotation -= applied
		
	# Add inertia/smoothing to general camera movement
	camera_rotation = camera_rotation.lerp(target_camera_rotation, delta * active_camera_smoothing_speed)


	# Smoothly decay modern camera shake trauma
	if camera_trauma > 0.0:
		camera_trauma = maxf(0.0, camera_trauma - delta * shake_decay_speed)

	# Smooth independent camera breathing sway — only when aiming, no noise coupling
	var is_aiming_cam = character and character.is_aimming
	if enable_camera_aim_sway and is_aiming_cam:
		var t = Time.get_ticks_msec() * 0.001
		var target_cam_sway = Vector2(
			sin(t * camera_sway_speed) * camera_sway_yaw,
			sin(t * camera_sway_speed * 1.3) * camera_sway_pitch
		)
		camera_sway_offset = camera_sway_offset.lerp(target_cam_sway, delta * 3.0)
	else:
		camera_sway_offset = camera_sway_offset.lerp(Vector2.ZERO, delta * 3.0)

	_apply_camera_rotation(delta)
	
	if rear_spring_arm:
		var desired_rear_length = base_spring_length + action_spring_length
		var raw_hit_length = desired_rear_length
		
		is_hitting_wall = false
		if original_rear_collision_mask != 0 and rear_spring_arm.shape:
			var space_state = get_world_3d().direct_space_state
			var origin = global_transform.origin
			var forward = -global_transform.basis.z
			origin += forward * 0.5 # Match the original 0.5 forward offset
			
			var shape_query = PhysicsShapeQueryParameters3D.new()
			shape_query.shape = rear_spring_arm.shape
			shape_query.transform = Transform3D(global_transform.basis, origin)
			shape_query.motion = global_transform.basis.z * desired_rear_length
			shape_query.collision_mask = original_rear_collision_mask
			shape_query.exclude = get_camera_exclusion_rids()
				
			var result = space_state.cast_motion(shape_query)
			if result.size() > 0 and result[0] < 1.0:
				raw_hit_length = desired_rear_length * result[0]
				is_hitting_wall = true
				
		# Only apply max limit if we are actively hitting a wall. 
		# This prevents the max zoom limit from capping normal gameplay distance.
		if is_hitting_wall:
			collision_target_length = clamp(raw_hit_length, min_collision_distance, max_collision_distance)
		else:
			collision_target_length = max(raw_hit_length, min_collision_distance)
		
		# Double-lerp for flawless ease-in / ease-out smoothing!
		var lerp_speed = camera_collision_zoom_in_speed
		if collision_target_length > collision_current_length + 0.01:
			lerp_speed = camera_collision_zoom_out_speed
			
		collision_smoothed_target = lerp(collision_smoothed_target, collision_target_length, delta * lerp_speed)
		collision_current_length = lerp(collision_current_length, collision_smoothed_target, delta * lerp_speed)
		
		rear_spring_arm.spring_length = collision_current_length

	# Custom Smooth Camera Collision
	if camera and ideal_camera_marker:
		# Calculate where the camera *wants* to be in local space of the pivot
		var target_local_transform = global_transform.affine_inverse() * ideal_camera_marker.global_transform
		
		# The local offset is now simply interpolated fast to follow the fully-smoothed spring arm!
		current_local_transform = current_local_transform.interpolate_with(target_local_transform, delta * 25.0)
		
		# Apply the smoothed local offset to the pivot's current global transform
		camera.global_transform = global_transform * current_local_transform
		
		var is_aiming_now_calc = character and character.is_aimming
		var is_grab_now_calc = character and character.is_grab
		if GameManager.movement_type == GameManager.MovementType.TANK and not is_aiming_now_calc and not is_grab_now_calc:
			camera.rotate_object_local(Vector3(0, 1, 0), -tank_look_around.x)
			camera.rotate_object_local(Vector3(1, 0, 0), -tank_look_around.y)

		# Apply modern 3D camera screen shake after global_transform pass (100% immune to transform overwrites)
		if enable_camera_shake and camera_trauma > 0.0:
			var amount = camera_trauma * camera_trauma
			var t = Time.get_ticks_msec() * 0.035
			var noise_x = sin(t * 1.7) * cos(t * 2.3)
			var noise_y = cos(t * 1.9) * sin(t * 2.7)
			var noise_pitch = sin(t * 2.1) * cos(t * 1.5)
			var noise_yaw = cos(t * 2.4) * sin(t * 1.8)
			var noise_roll = sin(t * 2.5) * cos(t * 1.3)

			camera.h_offset = noise_x * max_shake_offset.x * amount
			camera.v_offset = noise_y * max_shake_offset.y * amount
			camera.rotate_object_local(Vector3(1, 0, 0), noise_pitch * max_shake_pitch * amount)
			camera.rotate_object_local(Vector3(0, 1, 0), noise_yaw * max_shake_yaw * amount)
			camera.rotate_object_local(Vector3(0, 0, 1), noise_roll * max_shake_roll * amount)
		else:
			camera.h_offset = lerpf(camera.h_offset, 0.0, delta * 20.0)
			camera.v_offset = lerpf(camera.v_offset, 0.0, delta * 20.0)
			
		# Apply procedural takedown Dutch roll tilt & FOV punch
		if absf(takedown_roll_offset) > 0.0001:
			camera.rotate_object_local(Vector3(0, 0, 1), takedown_roll_offset)

		if absf(takedown_fov_offset) > 0.01:
			camera.fov = clampf(defaut_camera_fov + takedown_fov_offset, 35.0, 110.0)
			


func _input(event: InputEvent)-> void:
	if is_death_camera_active:
		return
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
	if event is InputEventMouseMotion:
		var mouse_event: Vector2 = event.screen_relative * mouse_sensitivity
		camera_look(mouse_event)
	#if event.is_action_pressed("swap_camera_alignment"):
		#swap_camera_align()
	if event.is_action_pressed("aim"):
		if character.has_method("can_aim") and not character.can_aim():
			return
		if not character.aim_blocked_until_release:
			enter_aim()
	if event.is_action_released("aim"):
		# Always clear the block when aim is released so re-press works
		if is_instance_valid(character):
			character.aim_blocked_until_release = false
			
			var sm = character.get_node_or_null("Statemachine")
			if sm and sm.current_state:
				if sm.current_state.name == "Reload":
					return
				if sm.current_state.name == "Aim":
					if sm.current_state.get("is_shot_queued") or sm.current_state.get("shot_exit_lock_timer") > 0.0:
						return
				
		exit_aim()

func camera_look(mouse_movement: Vector2)-> void:
	if is_death_camera_active:
		return
	var is_aiming_now = character and character.is_aimming
	var is_grab_now = character and character.is_grab
	
	if is_aiming_now:
		aim_offset += mouse_movement
		
		var excess_vector = Vector2.ZERO
		
		var current_deadzone_left = aim_deadzone_left
		var current_deadzone_right = aim_deadzone_right
		if current_camera_align == cameraalign.LEFT:
			current_deadzone_left = aim_deadzone_right
			current_deadzone_right = aim_deadzone_left
			
		# Asymmetrical X boundaries
		if aim_offset.x > current_deadzone_right:
			excess_vector.x = aim_offset.x - current_deadzone_right
			aim_offset.x = current_deadzone_right
		elif aim_offset.x < -current_deadzone_left:
			excess_vector.x = aim_offset.x + current_deadzone_left
			aim_offset.x = -current_deadzone_left
			
		# Asymmetrical Y boundaries
		if aim_offset.y > aim_deadzone_down:
			excess_vector.y = aim_offset.y - aim_deadzone_down
			aim_offset.y = aim_deadzone_down
		elif aim_offset.y < -aim_deadzone_up:
			excess_vector.y = aim_offset.y + aim_deadzone_up
			aim_offset.y = -aim_deadzone_up
			
		pending_camera_rotation += excess_vector
	elif GameManager.movement_type == GameManager.MovementType.TANK and not is_grab_now:
		time_since_last_mouse_move = 0.0
		# Tank look around: Left 20° (-0.349 rad), Right 15° (0.2618 rad), Up 10° (-0.1745 rad), Down 15° (0.2618 rad)
		target_tank_look_around += mouse_movement
		target_tank_look_around.x = clamp(target_tank_look_around.x, -0.349, 0.2618)
		target_tank_look_around.y = clamp(target_tank_look_around.y, -0.1745, 0.2618)
	else:
		target_camera_rotation += mouse_movement
		target_camera_rotation.y = clamp(target_camera_rotation.y, -max_look_up, max_look_down)
		
func _apply_camera_rotation(delta: float = 0.016) -> void:
	camera_rotation.y = clamp(camera_rotation.y, -max_look_up, max_look_down)
	
	transform.basis = Basis()
	
	var is_aiming_now = character and character.is_aimming
	var is_grab_now = character and character.is_grab
	
	if not character.is_quick_turn:
		character.transform.basis = Basis()
		character.rotate_object_local(Vector3(0,1,0), -(camera_rotation.x + takedown_yaw_offset))

	if look_at_player:
		rotate_object_local(Vector3(0, 1, 0), PI)
		position.x = -look_at_player_x
		position.z = -base_position_z + look_at_player_distance_offset
	else:
		position.x = base_position_x
		position.z = base_position_z
		
	if GameManager.movement_type == GameManager.MovementType.TANK and not is_aiming_now and not is_grab_now:
		rotate_object_local(Vector3(1, 0, 0), action_pitch)
	else:
		rotate_object_local(Vector3(1, 0, 0), -camera_rotation.y + action_pitch)

	# Apply camera sway as a final additive tilt on the camera only (after all base rotation)
	if camera_sway_offset.length_squared() > 0.000001:
		rotate_object_local(Vector3(1, 0, 0), camera_sway_offset.y)
		rotate_object_local(Vector3(0, 1, 0), camera_sway_offset.x)
	
	# Dynamically push the camera's pivot UP when looking up or down to prevent the body from blocking the view!
	var vertical_angle = camera_rotation.y
	var current_look_up_lift = look_up_lift_amount
	var current_look_down_lift = look_down_lift_amount
	
	if GameManager.movement_type == GameManager.MovementType.TANK and not is_aiming_now and not is_grab_now:
		vertical_angle = tank_look_around.y
		current_look_down_lift = tank_look_down_lift
		
	if vertical_angle < 0.0: # Looking UP
		position.y = base_position_y + action_offset_y + (abs(vertical_angle) * current_look_up_lift)
	else: # Looking DOWN
		position.y = base_position_y + action_offset_y + (abs(vertical_angle) * current_look_down_lift)

func swap_camera_align()-> void:
	match current_camera_align:
		cameraalign.LEFT:
			set_camera_alignment(cameraalign.RIGHT)
		cameraalign.RIGHT:
			set_camera_alignment(cameraalign.LEFT)
		cameraalign.CENTER:	
			return	
			
	var new_pos = get_target_edge_length()
	set_rear_spring_pos(new_pos,camera_align_speed)

func get_target_edge_length() -> float:
	if character and character.is_aimming:
		if current_camera_align == cameraalign.LEFT:
			return aim_edge_spring_arm_length_left * current_camera_align
		else:
			return aim_edge_spring_arm_length * current_camera_align
	else:
		if current_camera_align == cameraalign.LEFT:
			return aim_edge_spring_arm_length_left * current_camera_align
		else:
			return defaut_edge_spring_arm_length * current_camera_align
	
func set_camera_alignment(alignment: cameraalign)-> void:
	current_camera_align = alignment
	update_collision_radius()

func update_collision_radius() -> void:
	if rear_spring_arm and rear_spring_arm.shape is SphereShape3D:
		var target_radius = rear_collision_radius_center
		if character and character.is_aimming:
			match current_camera_align:
				cameraalign.CENTER:
					target_radius = rear_collision_radius_center
				cameraalign.RIGHT:
					target_radius = rear_collision_radius_right
				cameraalign.LEFT:
					target_radius = rear_collision_radius_left
					
		# Enforce a minimum radius of 0.01 to prevent Jolt Physics build shape errors
		rear_spring_arm.shape.radius = maxf(target_radius, 0.01)

func get_camera_exclusion_rids() -> Array[RID]:
	var excludes: Array[RID] = []
	if character:
		excludes.append(character.get_rid())
		
	var anchalees = get_tree().get_nodes_in_group("Anchalee")
	for anchalee in anchalees:
		if anchalee is CollisionObject3D:
			excludes.append(anchalee.get_rid())
			
	return excludes

func set_camera_pos(pos:float,speed:float)-> void:
	if camera_tween:
		camera_tween.kill()
		
	camera_tween = get_tree().create_tween()
	if camera_tween:
		camera_tween.set_trans(Tween.TRANS_EXPO)
		camera_tween.set_ease(Tween.EASE_OUT)	
		camera_tween.tween_property(edge_spring_arm,"spring_length",pos,speed)

func set_rear_spring_pos(pos: float, speed: float)-> void:
	if camera_tween:
		camera_tween.kill()
		
	camera_tween = get_tree().create_tween()
	if camera_tween:
		camera_tween.set_trans(Tween.TRANS_EXPO)
		camera_tween.set_ease(Tween.EASE_OUT)	
		camera_tween.tween_property(edge_spring_arm,"spring_length",pos,speed)
	
func enter_aim(set_aiming: bool = true)-> void:
	if camera_tween:
		camera_tween.kill()
	if offset_tween:
		offset_tween.kill()
	if pitch_tween:
		pitch_tween.kill()
	if spring_tween:
		spring_tween.kill()
		
	if set_aiming:
		character.is_aimming = true	
	else:
		character.is_aimming = false
		
	update_collision_radius()
			
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",aim_fov,aim_speed)
	
	camera_tween.tween_property(edge_spring_arm,"spring_length",get_target_edge_length(),aim_speed)
	camera_tween.tween_property(self,"base_spring_length",aim_rear_spring_arm_length,aim_speed)
	
	camera_tween.tween_property(self, "action_offset_y", 0.0, aim_speed)
	camera_tween.tween_property(self, "action_pitch", 0.0, aim_speed)
	camera_tween.tween_property(self, "action_spring_length", 0.0, aim_speed)
func exit_aim(set_aiming: bool = true)-> void:
	if camera_tween:
		camera_tween.kill()
	if set_aiming:
		character.is_aimming = false		
	update_collision_radius()
		
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",defaut_camera_fov,aim_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",get_target_edge_length(),aim_speed)
	camera_tween.tween_property(self,"base_spring_length",defaut_rear_spring_arm_length,aim_speed)
	
func enter_sprint()-> void:
	if camera_tween:
		camera_tween.kill()
	
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",sprint_fov,sprint_tween_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",get_target_edge_length(),sprint_tween_speed)
	camera_tween.tween_property(self,"base_spring_length",defaut_rear_spring_arm_length,aim_speed)
func exit_sprint()-> void:
	if character.is_aimming:
		return
		
	if camera_tween:
		camera_tween.kill()
		
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",defaut_camera_fov,aim_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",get_target_edge_length(),aim_speed)
	camera_tween.tween_property(self,"base_spring_length",defaut_rear_spring_arm_length,aim_speed)
	
