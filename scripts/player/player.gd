class_name Player extends CharacterBody3D

@export_group("movement setting")
@export var movement_type_override: GameManager.MovementType = GameManager.MovementType.HYBRID_RETRO:
	set(val):
		movement_type_override = val
		if Engine.is_editor_hint() or is_node_ready():
			GameManager.movement_type = val
@export var walk_speed: float = 3.0
@export var walk_Back_speed: float = 2.5
@export var turn_speed: float = 180.0
@export var quick_turn_speed: float = 0.3 #in second
@export var quick_turn_cooldown_duration: float = 0.5 # cooldown in seconds before another quick turn
@export var run_speed: float = 4.5
@export var aim_bone: LookAtModifier3D
@export var aim_bone2: LookAtModifier3D
@export var max_tilt_angle: float = 6.0
@export var rotation_tilt_sensitivity: float = 2.0 # degrees of Z tilt per rad/sec of turn speed
@export var max_yaw_angle: float = 15.0
@export var rotation_yaw_sensitivity: float = 6.0 # degrees of Y yaw per rad/sec of turn speed

@export_group("animation setting")
#@export var anim_player:AnimationPlayer
@export var walk_anim_speed: float = 1.2
@export var walk_back_anim_speed: float = 1.2
@export var walk_side_anim_speed: float = 1.2
@export var sprint_anim_speed: float = 2.0
@export var default_blend_time:= 0.5
@export var turn_anim_speed: float = 1.2
@export var turn_stop_anim_speed: float = 2.0
@export var turn_speed_scale_factor: float = 0.3  # how much faster each rad/s of turning adds
@export var anim: AnimationTree
var anim_playback = "parameters/Main/playback"
var _walk_markers: Array[float] = [0.5, 1.0]
var _turn_markers: Array[float] = [0.5, 1.0]
var _last_norm_pos: float = -1.0
var _turn_last_norm_pos: float = -1.0
var _last_step_time: int = 0
var _pending_stop_footstep: bool = false

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

func trigger_shoulder_recoil(kick_z: float = 0.06, kick_pitch: float = 0.08) -> void:
	if skeleton:
		var lean_modifier = skeleton.get_node_or_null("SpineLeanModifier") as PlayerLeanModifier
		if lean_modifier and lean_modifier.has_method("trigger_shoulder_recoil"):
			lean_modifier.trigger_shoulder_recoil(kick_z, kick_pitch)

@export_group("Data setting")
@export var MaxHP = 150
@export var hitboxF: Area3D
@export var hitboxB: Area3D
@export var stun_detect: Area3D
@export var pickup_detect: Area3D

var HP = MaxHP
var takedown_target: Node = null
var takedown_prompt_label: Label = null
var hit_damage_already_applied: bool = false
var pending_die_after_hit: bool = false
var Hit_info = {
	"bullet": null,
	"location": null
}

#timer
#@onready var knockdown_timer: Timer = $Knockdown_timer
#
#@export_group("GUN setting")
#@export var Pistol: Gun
#@export var Shotgun: Gun
#@export var Rifle: Gun




#QTE
@onready var qte: CanvasLayer = $Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/QTE
@onready var qte_bar: ProgressBar = $Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/QTE/ProgressBar
var start_qte = false

#Die
@onready var die: CanvasLayer = $Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/Die
@onready var die_anim: AnimationPlayer = $Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/Die/AnimationPlayer

const GRAVITY = -9.81
var is_quick_turn: bool = false
var is_stunned: bool = false
var quick_turn_cooldown: float = 0.0
var is_aimming:bool = false
var focus_progress: float = 0.0
var aim_blocked_until_release: bool = false
var is_reload:bool = false
var superpump_cooldown: float = 0.0
var is_grab:bool = false
var is_knockdown:bool = false
var is_near_stunt:bool = false
var _last_grab_area: Area3D = null
var _last_grabber: Node = null

#gun
@export var gun_controller: GunController
@export var face_controller: PlayerFaceController

@export_group("Aim Settings")
@export var aim_head_focus_pitch_down: float = 0.4
var current_focus_pitch_weight: float = 0.0

@export_group("NPC Head Glance")
@export var enable_npc_head_glance: bool = true
@export var max_npc_glance_distance: float = 7.0
@export var npc_glance_exit_multiplier: float = 1.25
@export var npc_glance_fov_deg: float = 72.0
@export var npc_glance_max_angle_deg: float = 45.0
@export_range(0.0, 1.0, 0.05) var npc_glance_head_influence: float = 0.6
@export var head_turn_speed: float = 5.0
@export var glance_exit_speed: float = 3.5
@export var head_look_depth: float = 15.0
@export var npc_groups: Array[String] = ["Anchalee", "npc", "enemies"]
var current_npc_glance_pos: Vector3 = Vector3.ZERO
var active_glance_npc: Node3D = null
var current_head_influence: float = 0.25
var glance_recovery_cooldown: float = 0.0
var _was_in_action_state: bool = false

#var GunA = {
	#"name": "pistol",
	#"Gun" : Pistol
#}
#var GunB = {
	#"name": "shotgun",
	#"Gun" : Shotgun
#}
#var GunC = {
	#"name": "rifle",
	#"Gun" : Rifle
#}
#var Gun = [GunA,GunB,GunC]
#var curr_gun = Gun[0]
#var curr_gun_index = 0
var near_enemy_list = []

@export_group("Crosshair")
@export var crosshair_texture: Texture2D
@export var min_scale: float = 0.5
@export var max_scale: float = 2.0
@export var crosshair_color: Color = Color.WHITE

@onready var camera: Node3D = $Camera
@onready var skeleton: Node3D = $"Re4Lom Base Rig/rig/Skeleton3D"
@onready var rig: Node3D = $"Re4Lom Base Rig/rig"
@onready var aim_target: Node3D = $Aim_target
var aim_target_head: Marker3D

@export var aim_visual_offset: Vector3 = Vector3(0.0, 0.25, 0.0)
@export var aim_parallax_correction: float = 1.5 # Dynamically pulls the gun right when aiming left
var true_aim_position: Vector3 = Vector3.ZERO
var nav_agent: NavigationAgent3D = null
var player_obstacle: NavigationObstacle3D = null

const TILT_SPEED = 10.0
var last_y_rotation: float = 0.0
var angular_velocity: float = 0.0
var _smoothed_turn_speed: float = 0.0
var _smoothed_angular_velocity: float = 0.0
var _is_turning: bool = false
var _last_active_turn_state: String = ""
var _turn_direction: float = 0.0
var _return_direction: float = 0.0
var _last_active_scale: float = 1.0
var _last_speed_mult: float = 1.0
var _linger_speed_mult: float = 0.4
var _anim_time: float = 0.53
var _is_returning_to_neutral: bool = false
var _stop_timer: float = 0.0
var _peak_blend: float = 0.0
var _current_turn_anim_scale: float = 0.0
@onready var cross_hair: Control = $Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/Die/TextureRect
@onready var reload_timer: Timer = $Reload_timer

#const BULLET = preload("uid://csdtdj7sci5vk")
#@@onready var bullet_lo: Node3D = $"Re4Lom Base Rig/rig/Skeleton3D/Gun/MeshInstance3D/Node3D"

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

func _ready() -> void:
	add_to_group("player")
	if not face_controller:
		face_controller = get_node_or_null("PlayerFaceController") as PlayerFaceController
	if get_tree().root.has_node("GameManager") and GameManager.difficulty == GameManager.Difficulty.CASUAL:
		MaxHP = 210
	else:
		HP = MaxHP

	if not GameManager.movement_type_selected:
		GameManager.movement_type = movement_type_override
	
	# Adjust player movement speed and animation scale based on movement control type
	var speed_mult := 1.0
	match GameManager.movement_type:
		GameManager.MovementType.HYBRID_RETRO: # Type A
			speed_mult = 1.3
		GameManager.MovementType.MODERN:       # Type B
			speed_mult = 1.0
		GameManager.MovementType.TANK:         # Type C
			speed_mult = 1.5

	if walk_speed == null: walk_speed = 3.0
	if walk_Back_speed == null: walk_Back_speed = 2.5
	if run_speed == null: run_speed = 4.5
	if walk_anim_speed == null: walk_anim_speed = 1.2
	if walk_back_anim_speed == null: walk_back_anim_speed = 1.2
	if walk_side_anim_speed == null: walk_side_anim_speed = 1.2
	if sprint_anim_speed == null: sprint_anim_speed = 2.0

	walk_speed *= speed_mult
	walk_Back_speed *= speed_mult
	run_speed *= speed_mult
	
	walk_anim_speed *= speed_mult
	walk_back_anim_speed *= speed_mult
	walk_side_anim_speed *= speed_mult
	sprint_anim_speed *= speed_mult

	if anim:
		anim.active = true
		var anim_player = anim.get_node_or_null(anim.anim_player) as AnimationPlayer
		if anim_player:
			_walk_markers = _get_footstep_markers(anim_player, "walk/walk_fw")
			_turn_markers = _get_footstep_markers(anim_player, "walk/walk_side")
	add_to_group("player")
	
	# Start playing ambient/non-combat music when entering the world scene
	SoundManager.play_music_non_combat()
	
	# Defer animation start to allow Godot to finish skeleton bone binding
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(self) and anim:
			var pb = anim.get(anim_playback)
			if pb:
				pb.start("Idle")
				
				# Call set_gun_anim to update sub-state conditions after snapping to Idle
				var idle_state = get_node_or_null("Statemachine/Idle")
				if idle_state and idle_state.has_method("set_gun_anim"):
					idle_state.set_gun_anim()
	)
	
	# Enable collision mask for Layer 3 (Enemies) so the player physically collides with enemies
	set_collision_mask_value(3, true)
	
	# Attach scale fix programmatically to player Area3D nodes to prevent Jolt Physics warnings
	var scale_fix_script = load("res://scripts/enemy/hitbox_scale_fix.gd")
	for path in [
		"Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox",
		"Re4Lom Base Rig/rig/Skeleton3D/spine02/Stunned detect2",
		"Re4Lom Base Rig/rig/Skeleton3D/spine02/Pickup2",
		"Re4Lom Base Rig/rig/Skeleton3D/FriendArea",
		"Re4Lom Base Rig/rig/Skeleton3D/FriendNearArea"
	]:
		var node = get_node_or_null(path)
		if node and node is Area3D:
			node.set_script(scale_fix_script)
			node.set_physics_process(true)
	# Configure FriendNearArea collision mask to detect Anchalee (layer 5, value 16)
	var near_area = get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/FriendNearArea")
	if near_area:
		near_area.collision_mask = 15 | 16
	
	# Add a NavigationObstacle3D to Hitbox_F2 (hitboxF) so that the follower/zombies avoid the player's physical space
	if hitboxF:
		player_obstacle = NavigationObstacle3D.new()
		player_obstacle.name = "PlayerAvoidanceObstacle"
		player_obstacle.radius = 0.5
		player_obstacle.avoidance_enabled = true
		hitboxF.add_child(player_obstacle)

	nav_agent = get_node_or_null("NavigationAgent3D")
	var td_hitbox = get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox")
	if td_hitbox:
		td_hitbox.collision_mask = 8198 # Detect enemy hitboxes & CharacterBody3D (layers 2, 3 & 14)
		td_hitbox.collision_layer = 0 # No layer needed for detection
	
	pickup_detect.area_entered.connect(pickup_detect_area)

	# Create programmatic takedown prompt UI
	var prompt_layer = CanvasLayer.new()
	add_child(prompt_layer)
	
	takedown_prompt_label = Label.new()
	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language
		
	if lang == "th":
		takedown_prompt_label.text = "กด E เพื่อปะแป้ง"
		takedown_prompt_label.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Bold.ttf"))
	else:
		takedown_prompt_label.text = "[E] Takedown"
		
	takedown_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	takedown_prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	takedown_prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	takedown_prompt_label.offset_left = -200
	takedown_prompt_label.offset_right = 200
	takedown_prompt_label.offset_top = -150
	takedown_prompt_label.offset_bottom = -50
	
	takedown_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	takedown_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	takedown_prompt_label.add_theme_font_size_override("font_size", 36)
	takedown_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	takedown_prompt_label.add_theme_constant_override("outline_size", 8)
	takedown_prompt_label.add_theme_color_override("font_color", Color.YELLOW)
	
	prompt_layer.add_child(takedown_prompt_label)
	takedown_prompt_label.visible = false

	# Connect player hitbox zone signals (Grabbed/Attacked) to handlers
	_connect_player_hitboxes()

	# Connect restart/exit buttons
	var btn_restart = get_node_or_null("Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/Die/ButtonsContainer/RestartButton")
	if btn_restart:
		btn_restart.pressed.connect(_on_restart_pressed)
	var btn_exit = get_node_or_null("Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/Die/ButtonsContainer/ExitButton")
	if btn_exit:
		btn_exit.pressed.connect(_on_exit_pressed)

	if cross_hair:
		cross_hair.visible = false
		cross_hair.scale = Vector2.ONE
		cross_hair.size = Vector2(512, 512)
		cross_hair.pivot_offset = Vector2(256, 256)
		cross_hair.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		
	last_y_rotation = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	if skeleton:
		skeleton.rotation = Vector3.ZERO
		var lean_modifier = preload("res://scripts/player/player_lean_modifier.gd").new()
		lean_modifier.name = "SpineLeanModifier"
		lean_modifier.max_tilt_angle = max_tilt_angle
		skeleton.add_child(lean_modifier)
		
		# Create a separate aim target for the head so it doesn't drop down during sprint/lean
		var head_lookat = skeleton.get_node_or_null("HeadLookAt")
		if head_lookat:
			aim_target_head = Marker3D.new()
			aim_target_head.name = "Aim_target_head"
			aim_target_head.position = Vector3(0, 1.6, -15.0) # Pre-position forward to avoid startup head-jerk!
			skeleton.add_child(aim_target_head) # Parent to skeleton so rig turning inertia doesn't snap it!
			head_lookat.target_node = head_lookat.get_path_to(aim_target_head)
			# Enable secondary rotation so the head can twist left/right to look at the crosshair
			head_lookat.use_secondary_rotation = true
			head_lookat.use_angle_limitation = true
			# Don't set symmetry_limitation — preserve original asymmetric pitch limits from the scene
			head_lookat.secondary_positive_limit_angle = deg_to_rad(npc_glance_max_angle_deg)
			head_lookat.secondary_negative_limit_angle = deg_to_rad(npc_glance_max_angle_deg)
			head_lookat.secondary_positive_damp_threshold = 0.7
			head_lookat.secondary_negative_damp_threshold = 0.7
			
		# Enable secondary rotation so the spine can twist left/right to aim!
		if aim_bone:
			aim_bone.use_secondary_rotation = true
		if aim_bone2:
			aim_bone2.use_secondary_rotation = true
			
	if rig:
		rig.rotation = Vector3.ZERO
	_setup_idle_turn_blending()
		
var current_aim_influence: float = 0.25

func _process(delta: float) -> void:
	if superpump_cooldown > 0.0:
		superpump_cooldown -= delta
	if glance_recovery_cooldown > 0.0:
		glance_recovery_cooldown -= delta
		
	# Track action state transitions to trigger recovery cooldown when returning to Idle/locomotion
	var current_sm = get_node_or_null("Statemachine")
	var current_state_name = current_sm.current_state.name if (current_sm and current_sm.current_state) else ""
	var is_cam_action = camera and camera.has_method("is_action_camera_active") and camera.is_action_camera_active()
	var is_in_action = is_aimming or is_grab or is_quick_turn or is_cam_action or (current_state_name != "" and current_state_name not in ["Idle", "Run", "Walk", "Sprint"])
	if is_in_action:
		_was_in_action_state = true
		glance_recovery_cooldown = 0.8
	elif _was_in_action_state:
		_was_in_action_state = false
		glance_recovery_cooldown = 0.8
		
	update_crosshair_accuracy(delta)
	
	if cross_hair and camera:
		var screen_size = get_viewport().get_visible_rect().size
		var center = screen_size / 2.0
		
		# Scale the crosshair speed uniformly based on screen height (prevents stretching on wide monitors)
		var crosshair_speed = screen_size.y * 1.25
		var offset_pixels = Vector2(camera.aim_offset.x, camera.aim_offset.y) * crosshair_speed
		
		cross_hair.position = center - (cross_hair.size / 2.0) + offset_pixels
		
		if is_aimming:
			cross_hair.show()
		else:
			cross_hair.hide()
	
	# Smoothly blend the aiming influence for spine/chest bones
	var target_influence = 1.0 if is_aimming else 0.25
	if is_quick_turn:
		target_influence = 0.0
		
	current_aim_influence = lerpf(current_aim_influence, target_influence, delta * 15.0)
	
	# Determine head glance influence:
	# 1.0 when Aiming
	# 0.8 to 1.0 when Glancing at active NPC target (based on movement)
	# 0.0 during Action States (Grab, Win/Fail, Get Hit, Takedown, Quick Turn, Action Camera, or default Idle without NPC)
	var glance_inf = 1.0
	if active_glance_npc:
		var sm = get_node_or_null("Statemachine")
		var is_sprint_state = sm and sm.current_state and sm.current_state.name == "Sprint"
		if is_sprint_state:
			glance_inf = 0.8
		elif Motion.input_dir != Vector2.ZERO:
			glance_inf = 0.9
		else:
			glance_inf = 1.0

	var target_head_inf: float = 0.0
	if is_aimming:
		target_head_inf = 1.0
	elif active_glance_npc and glance_recovery_cooldown <= 0.0 and not is_grab and not is_quick_turn and not is_cam_action:
		target_head_inf = glance_inf
	else:
		target_head_inf = 0.0

	# Asymmetrical blending: brisk entry (10.0), smooth and gentle exit (glance_exit_speed)
	var inf_blend_speed = 10.0 if target_head_inf > current_head_influence else glance_exit_speed
	current_head_influence = lerpf(current_head_influence, target_head_inf, delta * inf_blend_speed)
	
	if aim_bone:
		aim_bone.influence = current_aim_influence
	if aim_bone2:
		aim_bone2.influence = current_aim_influence
		
	if skeleton:
		var head_lookat = skeleton.get_node_or_null("HeadLookAt")
		if head_lookat:
			# Ensure horizontal twisting is always on so the head can lead turns!
			head_lookat.use_secondary_rotation = true
			head_lookat.use_angle_limitation = true
			# Smoothly expand secondary horizontal rotation limits when aiming so crosshair tracking is unconstrained
			var glance_limit = deg_to_rad(npc_glance_max_angle_deg)
			var current_secondary_limit = lerpf(glance_limit, PI, current_focus_pitch_weight)
			head_lookat.secondary_positive_limit_angle = current_secondary_limit
			head_lookat.secondary_negative_limit_angle = current_secondary_limit
			# Fade out head look IK during quickturn to prevent neck snapping!
			if GameManager.movement_type == GameManager.MovementType.TANK and not is_aimming and not is_grab:
				head_lookat.influence = 1.0
			else:
				head_lookat.influence = current_head_influence
			
		var lean_modifier = skeleton.get_node_or_null("SpineLeanModifier")
		if lean_modifier:
			var sm = get_node_or_null("Statemachine")
			var is_reloading = sm and sm.current_state and sm.current_state.name == "Reload"
			
			lean_modifier.is_grab = is_grab
			
			if is_reloading:
				lean_modifier.input_dir = Vector2.ZERO
				lean_modifier.is_sprinting = false
				lean_modifier.is_aiming = false
				lean_modifier.is_reloading = true
				lean_modifier.is_rotating_in_place = false
				lean_modifier.rotating_in_place_speed = 0.0
			else:
				lean_modifier.is_reloading = false
				lean_modifier.input_dir = Motion.input_dir
				
				var is_sprinting = false
				if sm and sm.current_state and sm.current_state.name == "Sprint":
					is_sprinting = true
				lean_modifier.is_sprinting = is_sprinting
				lean_modifier.is_aiming = is_aimming
				lean_modifier.is_rotating_in_place = (
					Motion.input_dir == Vector2.ZERO 
					and _is_turning 
					and not is_grab
				)
				lean_modifier.rotating_in_place_speed = abs(_current_turn_anim_scale)

	_update_skeleton_tilt(delta)
	_update_aim_target(delta)
	_update_idle_turn_blend(delta)
	check_if_near_stun()

func _update_aim_target(delta: float) -> void:
	if aim_target and camera and camera.targetref:
		# Project the UI crosshair into 3D space so gun and head point EXACTLY at it!
		var screen_size = get_viewport().get_visible_rect().size
		var screen_center = screen_size / 2.0
		var crosshair_speed = screen_size.y * 1.25
		var offset_pixels = Vector2(camera.aim_offset.x, camera.aim_offset.y) * crosshair_speed
		var crosshair_center = screen_center + offset_pixels
		
		var distance = camera.global_position.distance_to(camera.targetref.global_position)
		var projected_target = camera.camera.project_position(crosshair_center, distance)

		var lean_modifier = skeleton.get_node_or_null("SpineLeanModifier") as PlayerLeanModifier
		if lean_modifier:
			# Let player_lean_modifier.gd handle the actual bone tilt.
			# We only apply the procedural bobbing offset so the LookAt modifier makes the chest/arms bounce!
			var bob_x = lean_modifier.current_bob_x
			var bob_y = lean_modifier.current_bob_y
			var cam_basis = camera.global_transform.basis
			var target_bob = (cam_basis.x * bob_x + cam_basis.y * bob_y) * 15.0 * lean_modifier.arm_bob_multiplier
			
			# Cast a ray from the camera exactly through the crosshair to find the physical target!
			var space_state = get_world_3d().direct_space_state
			var ray_origin = camera.camera.project_ray_origin(crosshair_center)
			var ray_dir = camera.camera.project_ray_normal(crosshair_center)
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
			query.collision_mask = 1 | 8192 # Detect Layer 1 (World) and Layer 14 (Hitboxes), ignore root body shapes
			
			# Exclude the player from this targeting raycast
			var exclude_nodes: Array = []
			for child in get_children():
				if child is CollisionObject3D:
					exclude_nodes.append(child.get_rid())
			query.exclude = exclude_nodes
			
			var raw_target_pos = projected_target
			var result = space_state.intersect_ray(query)
			if result:
				raw_target_pos = result.position
			
			if true_aim_position == Vector3.ZERO:
				true_aim_position = raw_target_pos
			else:
				# Smoothly lerp depth transitions so raycast edge shifts don't snap target position
				true_aim_position = true_aim_position.lerp(raw_target_pos, delta * 15.0)
			
			# Shift the visual target to compensate for spine/shoulder parallax
			var total_offset = aim_visual_offset
			
			# Aiming across the screen causes horizontal parallax. Dynamically correct it for both sides!
			total_offset.x += (-camera.aim_offset.x) * aim_parallax_correction
				
			var visual_shift = camera.global_transform.basis * total_offset
			aim_target.global_position = projected_target + visual_shift
		else:
			aim_target.global_position = camera.targetref.global_position
			aim_target.global_position.y = camera.targetref.global_position.y
			
		if aim_target_head:
			if GameManager.movement_type == GameManager.MovementType.TANK and not is_aimming and not is_grab:
				# Tank Control look-around head rotation based on mouse
				var look_dir = Vector3(0, 0, -5.0)
				var pitch = -camera.tank_look_around.y
				var yaw = -camera.tank_look_around.x
				var rotated_dir = look_dir.rotated(Vector3(1, 0, 0), pitch).rotated(Vector3(0, 1, 0), yaw)
				var target_local = Vector3(0, 1.6, 0) + rotated_dir
				aim_target_head.position = aim_target_head.position.lerp(target_local, delta * 15.0)
			else:
				# Calculate default forward target (centered shoulder offset with turning lead)
				var default_forward_target: Vector3
				if camera and is_instance_valid(camera.targetref):
					var default_forward = camera.targetref.global_position
					var default_player_local = to_local(default_forward)
					default_player_local.x = 0.0
					default_player_local.x -= angular_velocity * 0.75
					default_forward_target = to_global(default_player_local)
				else:
					default_forward_target = global_transform.origin + (-global_transform.basis.z * 15.0) + Vector3(0, 1.6, 0)

				# Determine glance target (raw NPC position or default forward — native LookAtModifier3D handles angle limit)
				var raw_npc_pos = _find_nearby_npc_target()
				var destination_target_global = raw_npc_pos if raw_npc_pos != Vector3.ZERO else default_forward_target
				
				# Smoothly update glance tracking position: active turn when looking at NPC, gentle exit when returning to forward facing
				if current_npc_glance_pos == Vector3.ZERO:
					current_npc_glance_pos = default_forward_target
				elif not is_aimming:
					var current_target_turn_speed = head_turn_speed if raw_npc_pos != Vector3.ZERO else glance_exit_speed
					current_npc_glance_pos = current_npc_glance_pos.lerp(destination_target_global, delta * current_target_turn_speed)
				
				# Smoothly blend focus weight when entering or exiting aim state
				var target_focus_weight = 1.0 if is_aimming else 0.0
				var focus_speed = 10.0 if is_aimming else 6.0
				current_focus_pitch_weight = lerpf(current_focus_pitch_weight, target_focus_weight, delta * focus_speed)
				
				# Compute head origin before target selection so we can lock glance Y height
				var head_origin_global = skeleton.global_position + Vector3(0, 1.6, 0) if skeleton else global_position + Vector3(0, 1.6, 0)
				
				# Target selection: immediate crosshair when aiming, smooth glance when not aiming
				var ideal_target_global: Vector3
				if is_aimming:
					current_npc_glance_pos = Vector3.ZERO # Reset so glance resumes naturally on release
					ideal_target_global = projected_target
				else:
					ideal_target_global = current_npc_glance_pos
					# Lock vertical to player head height during NPC glance so head only rotates horizontally
					ideal_target_global.y = head_origin_global.y
				
				# Project to fixed depth to eliminate distance distortions
				var aim_vec = ideal_target_global - head_origin_global
				var aim_dir = -global_transform.basis.z if aim_vec.length_squared() < 0.0001 else aim_vec.normalized()
				var fixed_depth_global = head_origin_global + aim_dir * head_look_depth
				
				# Convert to skeleton local space
				var target_local = skeleton.to_local(fixed_depth_global) if skeleton else to_local(fixed_depth_global)
				if absf(target_local.x) < 0.001:
					target_local.x = 0.001
				
				if current_focus_pitch_weight > 0.001:
					var focus_pitch_offset = lerpf(0.0, aim_head_focus_pitch_down, current_focus_pitch_weight)
					var dynamic_y_offset = (0.75 * current_focus_pitch_weight) + focus_pitch_offset
					target_local.y -= dynamic_y_offset
				
				# Single consistent-speed head turn — smoothly handles all transitions
				var turn_speed = lerpf(head_turn_speed, 24.0, current_focus_pitch_weight)
				aim_target_head.position = aim_target_head.position.lerp(target_local, delta * turn_speed)

func _find_nearby_npc_target() -> Vector3:
	if not enable_npc_head_glance:
		active_glance_npc = null
		return Vector3.ZERO

	# Block glance during post-action recovery blend-out (0.8s cooldown)
	if glance_recovery_cooldown > 0.0:
		active_glance_npc = null
		return Vector3.ZERO

	# Block glance during action camera sequences (Grab Win/Fail, Get Hit camera, etc.)
	if camera and camera.has_method("is_action_camera_active") and camera.is_action_camera_active():
		active_glance_npc = null
		return Vector3.ZERO

	# Disable glance during boolean flag actions
	if is_aimming or is_grab or is_quick_turn:
		active_glance_npc = null
		return Vector3.ZERO

	# Only allow glance when state machine is in clean locomotion/idle states (blocks Grab Fail/Win/Getup, Reload, Get_hit, Takedown, Die, etc.)
	var sm = get_node_or_null("Statemachine")
	if sm and sm.current_state:
		var s_name = sm.current_state.name
		if s_name not in ["Idle", "Run", "Walk", "Sprint"]:
			active_glance_npc = null
			return Vector3.ZERO

	# Also block glance while AnimationTree root is still blending out of "Grab" path
	# (is_grab becomes false before the Win/Fail/Getup animation fully blends back to Main)
	if anim:
		var root_pb = anim.get("parameters/playback")
		if root_pb:
			var root_node = String(root_pb.get_current_node())
			if root_node == "Grab":
				active_glance_npc = null
				return Vector3.ZERO

	var player_head_pos = skeleton.global_position + Vector3(0, 1.6, 0) if skeleton else global_position + Vector3(0, 1.6, 0)
	var forward_dir = -global_transform.basis.z
	
	# Side detection cone based on inspector FOV angle
	var fov_threshold = cos(deg_to_rad(npc_glance_fov_deg))
	
	# Entry detection threshold
	var entry_dist_sq = max_npc_glance_distance * max_npc_glance_distance
	
	# Dynamic exit hysteresis threshold: scales with npc_glance_exit_multiplier!
	var dynamic_exit_distance = max_npc_glance_distance * npc_glance_exit_multiplier
	var exit_dist_sq = dynamic_exit_distance * dynamic_exit_distance
	
	# Validate currently active target first using the dynamic exit distance band
	var closest_target_node: Node3D = null
	var closest_npc_pos = Vector3.ZERO
	var min_dist_sq = entry_dist_sq
	
	if is_instance_valid(active_glance_npc) and active_glance_npc is Node3D:
		var current_npc_pos = active_glance_npc.global_position + Vector3(0, 1.5, 0)
		var exact_head = active_glance_npc.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/Head")
		if exact_head and exact_head is Node3D:
			current_npc_pos = exact_head.global_position
			
		var dist_sq = player_head_pos.distance_squared_to(current_npc_pos)
		var dir_to_npc = (current_npc_pos - player_head_pos).normalized()
		if dist_sq < exit_dist_sq and forward_dir.dot(dir_to_npc) > fov_threshold:
			closest_target_node = active_glance_npc
			closest_npc_pos = current_npc_pos
			min_dist_sq = dist_sq
	
	for group_name in npc_groups:
		var nodes = get_tree().get_nodes_in_group(group_name)
		for node in nodes:
			if not is_instance_valid(node) or node == self or node == active_glance_npc:
				continue
			if node is Node3D:
				var npc_pos = node.global_position + Vector3(0, 1.5, 0)
				var exact_head = node.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/Head")
				if exact_head and exact_head is Node3D:
					npc_pos = exact_head.global_position
				elif "skeleton" in node and node.skeleton:
					var skel = node.skeleton
					var head_idx = skel.find_bone("DEF-spine.006")
					if head_idx != -1:
						npc_pos = skel.to_global(skel.get_bone_global_pose(head_idx).origin)
				
				var dist_sq = player_head_pos.distance_squared_to(npc_pos)
				if dist_sq < min_dist_sq:
					var dir_to_npc = (npc_pos - player_head_pos).normalized()
					if forward_dir.dot(dir_to_npc) > fov_threshold:
						min_dist_sq = dist_sq
						closest_npc_pos = npc_pos
						closest_target_node = node as Node3D
						
	active_glance_npc = closest_target_node
	return closest_npc_pos

func _update_skeleton_tilt(delta: float) -> void:
	if not rig:
		return

	# Calculate character's angular velocity around Y (yaw)
	var current_y_rot = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	var rotation_delta = angle_difference(last_y_rotation, current_y_rot)
	last_y_rotation = current_y_rot

	# Turn right (angular_velocity < 0) -> lean right (positive Z tilt)
	# Turn left (angular_velocity > 0) -> lean left (negative Z tilt)
	angular_velocity = 0.0
	if delta > 0.0:
		angular_velocity = rotation_delta / delta
	
	# Smooth the turn speed for step detection — reduces noise spikes
	# Fast smoothing toward higher values, fast decay toward zero.
	var raw_speed = abs(angular_velocity)
	if raw_speed > _smoothed_turn_speed:
		_smoothed_turn_speed = lerp(_smoothed_turn_speed, raw_speed, delta * 25.0)
	else:
		_smoothed_turn_speed = lerp(_smoothed_turn_speed, raw_speed, delta * 18.0)

	# Smooth directional angular velocity to eliminate visual jitter from mouse polling
	_smoothed_angular_velocity = lerp(_smoothed_angular_velocity, angular_velocity, delta * 15.0)

	var current_tilt_sensitivity = rotation_tilt_sensitivity * 0.5 if is_aimming else rotation_tilt_sensitivity
	var turn_tilt_deg = -_smoothed_angular_velocity * current_tilt_sensitivity
	var turn_tilt_rad = deg_to_rad(turn_tilt_deg)
	
	# Reduce yaw sensitivity by half when aiming to keep shots steady
	var current_yaw_sensitivity = rotation_yaw_sensitivity * 0.5 if is_aimming else rotation_yaw_sensitivity
	var turn_yaw_deg = _smoothed_angular_velocity * current_yaw_sensitivity
	var turn_yaw_rad = deg_to_rad(turn_yaw_deg)

	# For Z turning lean, clamp it to the max tilt angle
	var target_z = clamp(turn_tilt_rad, deg_to_rad(-max_tilt_angle), deg_to_rad(max_tilt_angle))
	var target_y = clamp(turn_yaw_rad, deg_to_rad(-max_yaw_angle), deg_to_rad(max_yaw_angle))
	
	var sm = get_node_or_null("Statemachine")
	var is_reloading = sm and sm.current_state and sm.current_state.name == "Reload"
	if is_reloading:
		target_z = 0.0
		target_y = 0.0

	# Rotate the rig node on the Z-axis (roll) and Y-axis (yaw) for turning inertia
	# We don't tilt on X here since walk tilt is handled by SpineLeanModifier
	rig.rotation.x = lerp_angle(rig.rotation.x, 0.0, delta * TILT_SPEED)
	rig.rotation.y = lerp_angle(rig.rotation.y, target_y, delta * TILT_SPEED)
	rig.rotation.z = lerp_angle(rig.rotation.z, target_z, delta * TILT_SPEED)

func update_crosshair_accuracy(delta: float) -> void:
	if not cross_hair:
		return

	cross_hair.visible = is_aimming
	if not cross_hair.visible:
		focus_progress = 0.0
		return

	# Determine focus time based on air percentage
	var focus_time = 0.5
	if gun_controller and gun_controller.current_gun:
		var gun = gun_controller.current_gun
		var air_pct = gun.air / gun.max_air
		if air_pct < 0.5:
			if get_tree().root.has_node("GameManager") and GameManager.difficulty == GameManager.Difficulty.CASUAL:
				focus_time = 0.5 / 0.75 # penalty is -25% (speed is 0.75x normal)
			else:
				focus_time = 1.0 # penalty is -50% (speed is 0.50x normal)
			
	# Update focus progress
	var old_focus = focus_progress
	focus_progress += delta / focus_time
	focus_progress = clamp(focus_progress, 0.0, 1.0)
	
	# If just became fully focused, play a subtle pop animation
	if old_focus < 1.0 and focus_progress >= 1.0:
		var tween = create_tween()
		tween.tween_property(cross_hair, "scale", Vector2(1.15, 1.15), 0.07).set_ease(Tween.EASE_OUT)
		tween.tween_property(cross_hair, "scale", Vector2(1.0, 1.0), 0.07).set_ease(Tween.EASE_IN)
	
	# Update gun current_spread based on focus progress
	if gun_controller and gun_controller.current_gun:
		var gun = gun_controller.current_gun
		gun.current_spread = lerp(gun.max_spread, gun.min_spread, focus_progress)

func get_damage_multiplier() -> float:
	var mult = 1.0
	
	# 1. Focus bonus (50% increase)
	if focus_progress >= 1.0:
		mult *= 1.5
		
	# 2. Air-based reduction: discrete -10% for air < 50%, -15% for air <= 30%
	if gun_controller and gun_controller.current_gun:
		var gun = gun_controller.current_gun
		var air_pct = gun.air / gun.max_air
		if air_pct < 0.5:
			var reduction = 0.15 if air_pct <= 0.3 else 0.10
			mult *= (1.0 - reduction)
			
	return mult

func notify_shot_fired() -> void:
	# Reset focus on shooting
	focus_progress = 0.0

func spawn_damage_popup(text_content: String, color: Color) -> void:
	if not cross_hair:
		return
		
	var label = Label.new()
	label.text = text_content
	label.set_script(preload("res://scripts/ui/popup_label.gd"))
	
	# Style the label
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_override("font", preload("res://scenes/font/iannnnnVCD 2007 Bold.ttf"))
	
	# Position: randomly left or right of the crosshair center
	var offset_x = randf_range(45.0, 75.0)
	if randf() > 0.5:
		offset_x = -offset_x
	var offset_y = randf_range(-15.0, 15.0)
	
	label.position = (cross_hair.size / 2.0) + Vector2(offset_x, offset_y) - Vector2(50, 10)
	
	# Give it a physics trajectory
	label.set("velocity", Vector2(offset_x * 1.5, randf_range(-150.0, -100.0)))
	label.set("gravity", 500.0)
	label.set("life_time", 1.2)
	
	cross_hair.add_child(label)
		
func set_velocity_from_motion(vel: Vector3)-> void:
	velocity = vel

func _physics_process(_delta: float) -> void:
	if quick_turn_cooldown > 0.0:
		quick_turn_cooldown -= _delta
		
	var sm = get_node_or_null("Statemachine")
	if sm and sm.current_state:
		var s_name = sm.current_state.name
		if s_name == "Reload" or (s_name == "Grab" and not sm.current_state.get("is_exiting")):
			# Check if reload state permits movement
			var block_move = true
			if s_name == "Reload":
				var rel_state = sm.current_state
				var is_pistol_qte = is_instance_valid(rel_state.get("qte_hud")) and rel_state.qte_hud.mode == "qte"
				if is_pistol_qte and not rel_state.get("block_movement_during_qte"):
					block_move = false
			
			if block_move:
				velocity.x = 0.0
				velocity.z = 0.0
		
	move_and_slide()
	
	# Process footstep sound logic based on animation play position and loaded markers
	if HP > 0:
		var statemachine = get_node_or_null("Statemachine")
		if statemachine and statemachine.current_state and statemachine.current_state.name in ["Idle", "Aim", "Run", "Sprint"]:
			var pb = anim.get(anim_playback)
			if pb:
				var current_node = pb.get_current_node()
				var is_moving = Vector2(velocity.x, velocity.z).length_squared() > 0.05 or Motion.input_dir != Vector2.ZERO
				var is_sprinting = (statemachine.current_state.name == "Sprint") or (Input.is_action_pressed("sprint") and not is_aimming)
				var min_cooldown = 110 if is_sprinting else 200

				if is_moving and (current_node == "Run" or current_node == "Aim" or current_node == "Sprint"):
					# Walking or sprinting
					_turn_last_norm_pos = -1.0 # reset turn pos
					_pending_stop_footstep = true
					var length = 0.8 if is_sprinting else 1.0
					var play_pos = pb.get_current_play_position()
					var norm_pos = fmod(play_pos / length, 1.0)
					
					# Check crossings for each marker
					if _last_norm_pos >= 0.0:
						for marker_ratio in _walk_markers:
							if _last_norm_pos > norm_pos: # Wrap around!
								if _last_norm_pos < marker_ratio or norm_pos >= marker_ratio:
									var now = Time.get_ticks_msec()
									if now - _last_step_time > min_cooldown:
										_last_step_time = now
										SoundManager.play_3d("leon_footstep", self)
									break
							else:
								if _last_norm_pos < marker_ratio and norm_pos >= marker_ratio:
									var now = Time.get_ticks_msec()
									if now - _last_step_time > min_cooldown:
										_last_step_time = now
										SoundManager.play_3d("leon_footstep", self)
									break
					_last_norm_pos = norm_pos
				elif _is_turning and abs(_current_turn_anim_scale) > 0.01:
					# Rotating in place
					_last_norm_pos = -1.0 # reset walk pos
					_pending_stop_footstep = false
				else:
					# Stopped moving and stopped rotating
					if _pending_stop_footstep and current_node == "Idle":
						var now = Time.get_ticks_msec()
						if now - _last_step_time > min_cooldown:
							_last_step_time = now
							SoundManager.play_3d("leon_footstep", self)
						_pending_stop_footstep = false
					_last_norm_pos = -1.0
					_turn_last_norm_pos = fmod(_anim_time / 1.06, 1.0)

			else:
				_last_norm_pos = -1.0
				_turn_last_norm_pos = fmod(_anim_time / 1.06, 1.0)
		else:
			_last_norm_pos = -1.0
			_turn_last_norm_pos = fmod(_anim_time / 1.06, 1.0)
	else:
		_last_norm_pos = -1.0
		_turn_last_norm_pos = -1.0


	

	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(velocity)
	if player_obstacle:
		player_obstacle.velocity = velocity
		# Disable avoidance when aiming to prevent enemies/follower from sliding/dodging sideways 
		# due to skeleton/Hitbox_F2 rotation sweeps.
		player_obstacle.avoidance_enabled = not is_aimming

#func change_gun():
#	if gun_controller:
#		gun_controller.next_gun()
#		curr_gun_index = gun_controller.current_gun_index
#	else:
#		if curr_gun_index == gun_list.size()-1:
#			curr_gun_index = 0
#		else:
#			curr_gun_index +=1
#		curr_gun = gun_list[curr_gun_index]

func is_invulnerable() -> bool:
	# 1. Check StateMachine state
	var sm = get_node_or_null("Statemachine")
	if sm and sm.current_state:
		var state_name = sm.current_state.name
		if state_name in ["Grab", "Get_hit", "Knockdown", "Takedown", "Die"]:
			return true
			
	# 2. Check AnimationTree active state (to prevent desyncs during animation transitions)
	if anim:
		var pb = anim.get("parameters/playback")
		if pb:
			var current_node = String(pb.get_current_node())
			if current_node in ["Hit", "Grab", "Knockdown", "Takedown", "Die"]:
				return true
				
	return false

func take_damage(amount: int, ignore_stun_and_invulnerable: bool = false) -> void:
	if not ignore_stun_and_invulnerable and (is_stunned or is_invulnerable()):
		return
	lost_HP(amount)
	print("[Player] Took %d damage — HP: %d/%d" % [amount, HP, MaxHP])
	if face_controller:
		face_controller.notify_hit()

	var is_fatal: bool = (HP <= 0)

	# Transition to Get_hit state for melee hit (both non-fatal and fatal hits play hit reaction first)
	var sm = get_node_or_null("Statemachine")
	if sm and sm.current_state and sm.current_state.name != "Get_hit" and sm.current_state.name != "Grab" and sm.current_state.name != "Die" and sm.current_state.name != "Knockdown" and sm.current_state.name != "Takedown":
		hit_damage_already_applied = true
		pending_die_after_hit = is_fatal
		
		# Determine hit direction from currently overlapping enemy attacks
		var location = null
		if hitboxF:
			for area in hitboxF.get_overlapping_areas():
				if area.is_in_group("enemy_attack"):
					location = "front"
					break
		if location == null and hitboxB:
			for area in hitboxB.get_overlapping_areas():
				if area.is_in_group("enemy_attack"):
					location = "back"
					break
		
		if location == null:
			# Fallback: check if Hit_info already has a location (e.g. from bullet body_entered)
			if Hit_info.location != null:
				location = Hit_info.location
			else:
				location = "front"
				
		Hit_info.location = location
		sm._change_state("Get_hit")
	elif is_fatal:
		force_die()

func lost_HP(amount):
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_player_damage(amount)
	if HP -amount <= 0:
		HP = 0
	else:
		HP -=amount
	
	if camera and camera.has_method("trigger_get_hit_shake"):
		var loc = Hit_info.location if ("location" in Hit_info and Hit_info.location) else "front"
		camera.trigger_get_hit_shake(loc)

func force_die() -> void:
	var already_dead = (HP <= 0)
	HP = 0
	if not already_dead:
		print("[Player] Force Dead")
		var sm = get_node_or_null("Statemachine")
		if sm and sm.current_state and sm.current_state.name != "Die":
			sm._change_state("Die")
		
		# Kill follower
		var follower = get_tree().get_first_node_in_group("Anchalee")
		if follower and follower.has_method("kill_anchalee"):
			follower.kill_anchalee()

func is_dead() -> bool:
	return HP <= 0

func _on_restart_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().call_deferred("change_scene_to_file", "res://scenes/startup.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
		
func Heal(amount):
	if HP +amount >= MaxHP:
		HP = MaxHP
	else:
		HP +=amount
		
func check_if_near_stun():
	is_near_stunt = false
	near_enemy_list.clear()
	
	if not stun_detect:
		if takedown_prompt_label:
			takedown_prompt_label.visible = false
		return
		
	var areas := stun_detect.get_overlapping_areas()
	for a in areas:
		if not a:
			continue
		var body = _find_enemy_from_area(a)
		if body is EnemyBase and not body.is_defeated:
			if not near_enemy_list.has(body):
				near_enemy_list.append(body)
				
	var valid_list = []
	for i in near_enemy_list:
		if is_instance_valid(i) and not i.is_queued_for_deletion():
			valid_list.append(i)
			if i.has_method("is_takedownable") and i.is_takedownable():
				is_near_stunt = true
	near_enemy_list = valid_list
	
	var sm_player = get_node_or_null("Statemachine")
	if sm_player and sm_player.current_state and sm_player.current_state.name in ["Takedown", "Grab", "Get_hit", "Die"]:
		is_near_stunt = false
	
	if takedown_prompt_label:
		takedown_prompt_label.visible = is_near_stunt

func aim_bone_on(value):
	aim_bone.active = value
	aim_bone2.active = value

func cancel_aim() -> void:
	is_aimming = false
	aim_blocked_until_release = true
	aim_bone_on(false)
	if camera and camera.has_method("exit_aim"):
		camera.exit_aim()

func can_aim() -> bool:
	if HP <= 0:
		return false
	if is_grab:
		return false
		
	var sm = get_node_or_null("Statemachine")
	if sm and sm.current_state:
		var state_name = sm.current_state.name
		if state_name in ["Grab", "Get_hit", "Knockdown", "Takedown", "Die", "Reload"]:
			return false
			
	if anim:
		var pb = anim.get("parameters/playback")
		if pb:
			var current_node = String(pb.get_current_node())
			if current_node in ["Hit", "Grab", "Knockdown", "Takedown", "Die"]:
				return false
				
	return true

func pickup_detect_area(area: Area3D):
	if area.is_in_group("object"):
		area._collect()

func _connect_player_hitboxes() -> void:
	var nodes = get_tree().get_nodes_in_group("player_hitbox")
	for area in nodes:
		for child in area.get_children():
			if child is PlayerHitboxZone:
				# Connect with argument (the area that triggered the grab)
				if not child.Grabbed.is_connected(on_hitbox_grabbed_with_area):
					child.Grabbed.connect(on_hitbox_grabbed_with_area)
	if hitboxF and not hitboxF.body_entered.is_connected(_on_hitbox_body_entered_front):
		hitboxF.body_entered.connect(_on_hitbox_body_entered_front)
	if hitboxB and not hitboxB.body_entered.is_connected(_on_hitbox_body_entered_back):
		hitboxB.body_entered.connect(_on_hitbox_body_entered_back)

func _on_hitbox_body_entered_front(body: Node3D) -> void:
	_on_hitbox_body_entered(body, "front")

func _on_hitbox_body_entered_back(body: Node3D) -> void:
	_on_hitbox_body_entered(body, "back")

func _on_hitbox_body_entered(body: Node3D, location: String) -> void:
	if is_stunned or is_invulnerable():
		return
	
	# Only count actual bullets/projectiles
	if not (body.is_in_group("bullet") or body.is_in_group("enemy_projectile") or body.is_in_group("projectile")):
		return
	
	# Bullet hit
	Hit_info.bullet = body
	Hit_info.location = location
	hit_damage_already_applied = false
	
	var sm = get_node_or_null("Statemachine")
	if sm and sm.current_state and sm.current_state.name != "Get_hit" and sm.current_state.name != "Grab" and sm.current_state.name != "Die" and sm.current_state.name != "Knockdown" and sm.current_state.name != "Takedown":
		sm._change_state("Get_hit")

func on_hitbox_grabbed_with_area(area: Area3D) -> void:
	if is_invulnerable():
		print("[Player] Ignore grab because player is invulnerable")
		return

	# Store the last grab source so player_grab can reference enemy UI
	self._last_grab_area = area
	# Try to find an enemy node associated with the area
	var possible_enemy = null
	if area.has_node("../"):
		# area is likely child of a BoneAttachment or enemy node
		possible_enemy = area.get_parent()
	# set a property for debugging/usage by states
	self._last_grabber = possible_enemy
	# Switch to Grab state on player's state machine
	var sm = get_node_or_null("Statemachine")
	if sm:
		sm._change_state("Grab")

	if camera and camera.has_method("trigger_grab_shake"):
		camera.trigger_grab_shake()

func attempt_takedown() -> bool:
	# Called when player presses takedown and is_near_stunt is true.
	if not stun_detect:
		return false
	takedown_target = null
	
	var best_enemy: Node = null
	var best_score: float = -99999.0
	
	# Detect center & forward vector of Stunned detect2 / player
	var detector_pos: Vector3 = stun_detect.global_position
	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	
	var candidates: Array[Node] = []
	var areas := stun_detect.get_overlapping_areas()
	for a in areas:
		if not a:
			continue
		var enemy := _find_enemy_from_area(a)
		if enemy and not (enemy in candidates):
			candidates.append(enemy)
			
	for e in near_enemy_list:
		if e and not (e in candidates):
			candidates.append(e)
			
	for enemy in candidates:
		if enemy.has_method("is_takedownable") and enemy.is_takedownable():
			var to_enemy = (enemy.global_position - detector_pos)
			to_enemy.y = 0.0
			var dist = to_enemy.length()
			var dir = to_enemy.normalized() if dist > 0.001 else forward_dir
			
			# Score combines forward alignment (dot product) and distance
			var dot = forward_dir.dot(dir) # 1.0 = directly in front
			var score = (dot * 10.0) - dist
			
			if score > best_score:
				best_score = score
				best_enemy = enemy
				
	if best_enemy:
		takedown_target = best_enemy
		return true
		
	return false

func _find_enemy_from_area(area: Area3D) -> Node:
	var node = area
	while node:
		if node is EnemyBase:
			return node
		node = node.get_parent()
	return null


func _on_stunned_detect_2_area_entered(_area: Area3D) -> void:
	pass


func _on_stunned_detect_2_area_exited(_area: Area3D) -> void:
	pass


func _setup_idle_turn_blending() -> void:
	if not anim:
		return
	
	var root = anim.tree_root as AnimationNodeStateMachine
	if not root:
		return
	var main_state = root.get_node("Main") as AnimationNodeStateMachine
	if not main_state:
		return
		
	var idle_sm = main_state.get_node("Idle") as AnimationNodeStateMachine
	if idle_sm:
		_apply_blend_trees_to_sm(idle_sm)
		
	var qt_sm = main_state.get_node("QT") as AnimationNodeStateMachine
	if qt_sm:
		_apply_blend_trees_to_sm(qt_sm, true)


func _apply_blend_trees_to_sm(sm: AnimationNodeStateMachine, is_qt: bool = false) -> void:
	var leg_bones = [
		"DEF-thigh.L", "DEF-thigh.R",
		"DEF-shin.L", "DEF-shin.R",
		"DEF-foot.L", "DEF-foot.R",
		"DEF-toe.L", "DEF-toe.R",
		"ORG-thigh.L", "ORG-thigh.R",
		"ORG-shin.L", "ORG-shin.R",
		"ORG-foot.L", "ORG-foot.R",
		"ORG-toe.L", "ORG-toe.R"
	]

	var upper_body_bones = [
		"DEF-spine", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003", "DEF-spine.004", "DEF-spine.005", "DEF-spine.006",
		"MCH-hand_ik.parent.R", "MCH-spine", "MCH-torso.parent", "MCH-upper_arm_ik_target.parent.L", "MCH-upper_arm_ik_target.parent.R",
		"chest", "hand_ik.R", "spine_fk", "torso", "upper_arm_ik_target.L", "upper_arm_ik_target.R"
	]

	# 1. Setup Pistol (Pis)
	var pis_blend_tree = AnimationNodeBlendTree.new()
	
	var pis_idle_anim = AnimationNodeAnimation.new()
	pis_idle_anim.animation = "Gun_idle/pis_idle"
	pis_blend_tree.add_node("IdleAnim", pis_idle_anim)
	
	var walk_side_anim = AnimationNodeAnimation.new()
	walk_side_anim.animation = "walk/walk_side"
	pis_blend_tree.add_node("WalkSideAnim", walk_side_anim)
	
	var seek_node = AnimationNodeTimeSeek.new()
	pis_blend_tree.add_node("TimeSeek", seek_node)
	
	var time_scale_node = AnimationNodeTimeScale.new()
	pis_blend_tree.add_node("TimeScale", time_scale_node)
	
	var blend_node = AnimationNodeBlend2.new()
	blend_node.filter_enabled = true
	for bone in leg_bones:
		blend_node.set_filter_path(NodePath("rig/Skeleton3D:" + bone), true)
	pis_blend_tree.add_node("Blend2", blend_node)
	
	if is_qt:
		var qt_anim = AnimationNodeAnimation.new()
		qt_anim.animation = "QT/Base"
		pis_blend_tree.add_node("QTAnim", qt_anim)
		
		var upper_blend_node = AnimationNodeBlend2.new()
		upper_blend_node.filter_enabled = true
		for bone in upper_body_bones:
			upper_blend_node.set_filter_path(NodePath("rig/Skeleton3D:" + bone), true)
		pis_blend_tree.add_node("UpperBlend", upper_blend_node)
		
		pis_blend_tree.connect_node("TimeSeek", 0, "WalkSideAnim")
		pis_blend_tree.connect_node("TimeScale", 0, "TimeSeek")
		pis_blend_tree.connect_node("Blend2", 0, "IdleAnim")
		pis_blend_tree.connect_node("Blend2", 1, "TimeScale")
		pis_blend_tree.connect_node("UpperBlend", 0, "Blend2")
		pis_blend_tree.connect_node("UpperBlend", 1, "QTAnim")
		pis_blend_tree.connect_node("output", 0, "UpperBlend")
	else:
		pis_blend_tree.connect_node("TimeSeek", 0, "WalkSideAnim")
		pis_blend_tree.connect_node("TimeScale", 0, "TimeSeek")
		pis_blend_tree.connect_node("Blend2", 0, "IdleAnim")
		pis_blend_tree.connect_node("Blend2", 1, "TimeScale")
		pis_blend_tree.connect_node("output", 0, "Blend2")
	
	sm.remove_node("Pis")
	sm.add_node("Pis", pis_blend_tree)

	# 2. Setup Shotgun/Rifle (Shot)
	var shot_blend_tree = AnimationNodeBlendTree.new()
	
	var shot_idle_anim = AnimationNodeAnimation.new()
	shot_idle_anim.animation = "Gun_idle/shotgun_idle"
	shot_blend_tree.add_node("IdleAnim", shot_idle_anim)
	
	var shot_walk_side_anim = AnimationNodeAnimation.new()
	shot_walk_side_anim.animation = "walk/walk_side"
	shot_blend_tree.add_node("WalkSideAnim", shot_walk_side_anim)
	
	var shot_seek_node = AnimationNodeTimeSeek.new()
	shot_blend_tree.add_node("TimeSeek", shot_seek_node)
	
	var shot_time_scale_node = AnimationNodeTimeScale.new()
	shot_blend_tree.add_node("TimeScale", shot_time_scale_node)
	
	var shot_blend_node = AnimationNodeBlend2.new()
	shot_blend_node.filter_enabled = true
	for bone in leg_bones:
		shot_blend_node.set_filter_path(NodePath("rig/Skeleton3D:" + bone), true)
	shot_blend_tree.add_node("Blend2", shot_blend_node)
	
	if is_qt:
		var shot_qt_anim = AnimationNodeAnimation.new()
		shot_qt_anim.animation = "QT/Base"
		shot_blend_tree.add_node("QTAnim", shot_qt_anim)
		
		var shot_upper_blend_node = AnimationNodeBlend2.new()
		shot_upper_blend_node.filter_enabled = true
		for bone in upper_body_bones:
			shot_upper_blend_node.set_filter_path(NodePath("rig/Skeleton3D:" + bone), true)
		shot_blend_tree.add_node("UpperBlend", shot_upper_blend_node)
		
		shot_blend_tree.connect_node("TimeSeek", 0, "WalkSideAnim")
		shot_blend_tree.connect_node("TimeScale", 0, "TimeSeek")
		shot_blend_tree.connect_node("Blend2", 0, "IdleAnim")
		shot_blend_tree.connect_node("Blend2", 1, "TimeScale")
		shot_blend_tree.connect_node("UpperBlend", 0, "Blend2")
		shot_blend_tree.connect_node("UpperBlend", 1, "QTAnim")
		shot_blend_tree.connect_node("output", 0, "UpperBlend")
	else:
		shot_blend_tree.connect_node("TimeSeek", 0, "WalkSideAnim")
		shot_blend_tree.connect_node("TimeScale", 0, "TimeSeek")
		shot_blend_tree.connect_node("Blend2", 0, "IdleAnim")
		shot_blend_tree.connect_node("Blend2", 1, "TimeScale")
		shot_blend_tree.connect_node("output", 0, "Blend2")
	
	sm.remove_node("Shot")
	sm.add_node("Shot", shot_blend_tree)

	# 3. Recreate transitions
	var t_start_pis = AnimationNodeStateMachineTransition.new()
	t_start_pis.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	t_start_pis.advance_condition = "pis"
	sm.add_transition("Start", "Pis", t_start_pis)
	
	var t_start_shot = AnimationNodeStateMachineTransition.new()
	t_start_shot.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	t_start_shot.advance_condition = "shot"
	sm.add_transition("Start", "Shot", t_start_shot)
	
	var t_pis_shot = AnimationNodeStateMachineTransition.new()
	t_pis_shot.xfade_time = 0.2
	sm.add_transition("Pis", "Shot", t_pis_shot)
	
	var t_shot_pis = AnimationNodeStateMachineTransition.new()
	t_shot_pis.xfade_time = 0.2
	sm.add_transition("Shot", "Pis", t_shot_pis)

	var t_pis_end = AnimationNodeStateMachineTransition.new()
	t_pis_end.xfade_time = 0.2
	sm.add_transition("Pis", "End", t_pis_end)
	
	var t_shot_end = AnimationNodeStateMachineTransition.new()
	t_shot_end.xfade_time = 0.2
	sm.add_transition("Shot", "End", t_shot_end)
func _update_idle_turn_blend(delta: float) -> void:
	if not anim:
		return
		
	# Check if the player is in the Idle or Quick_turn state of the StateMachine
	var is_active_state = false
	var sm = get_node_or_null("Statemachine")
	var current_state_name = ""
	if sm and sm.current_state:
		current_state_name = sm.current_state.name
		if current_state_name == "Idle" or current_state_name == "Quick_turn":
			is_active_state = true
		
	var target_blend = 0.0
	var target_scale = _last_active_scale
	
	if is_active_state:
		var turn_speed = _smoothed_turn_speed
		# Hysteresis threshold to prevent jitter when turning mouse slowly
		var is_turning_now = false
		if _is_turning:
			is_turning_now = (turn_speed > 0.015)
		else:
			is_turning_now = (turn_speed > 0.08)
		
		if is_turning_now:
			_is_returning_to_neutral = false
			_stop_timer = 0.0
			
			# Update turning direction with latching logic:
			# Keep turning one way until we stop or move mouse in opposite direction with threshold
			if _turn_direction == 0.0:
				if angular_velocity > 0.01:
					_turn_direction = 1.0 # Left
				elif angular_velocity < -0.01:
					_turn_direction = -1.0 # Right
			else:
				# Opposing threshold to change direction
				if _turn_direction == 1.0 and angular_velocity < -0.1:
					_turn_direction = -1.0
				elif _turn_direction == -1.0 and angular_velocity > 0.1:
					_turn_direction = 1.0
			
			# Speed mult: 0.6 at minimum (slow turn) up to 1.2 at max turn speed.
			var speed_mult = clamp(0.6 + _smoothed_turn_speed * turn_speed_scale_factor, 0.6, 1.2)
			var scale_magnitude = turn_anim_speed * speed_mult
			_last_speed_mult = speed_mult
			_linger_speed_mult = speed_mult  # track live; will decay slowly once stop step begins
			
			# If turning left, scale is negative (play backward), else positive
			target_scale = -scale_magnitude if _turn_direction == 1.0 else scale_magnitude
			_last_active_scale = target_scale
			
			if not _is_turning:
				_is_turning = true
				_peak_blend = 0.0
				_trigger_turn_seek()
				
			target_blend = 1.0
			
			var c_blend = anim.get("parameters/Main/Idle/Pis/Blend2/blend_amount")
			if c_blend != null:
				_peak_blend = max(_peak_blend, c_blend)
		else:
			# Stopped rotating. Start returning to neutral instantly.
			if _is_turning and not _is_returning_to_neutral:
				_is_returning_to_neutral = true
				
				# If within uncommitted range, take shortest path. Otherwise continue current direction.
				if _anim_time > 0.35 and _anim_time < 0.73:
					_return_direction = 1.0 if (0.53 - _anim_time) > 0.0 else -1.0
				else:
					# Continue in current playback direction (-1 for Left, 1 for Right)
					_return_direction = -1.0 if _turn_direction == 1.0 else 1.0
					
			if _is_returning_to_neutral:
				if _return_direction == 0.0:
					target_blend = 0.0
					target_scale = 0.0
				else:
					target_blend = _peak_blend
					var completion_speed = turn_stop_anim_speed * _linger_speed_mult
					target_scale = completion_speed * _return_direction
			else:
				target_blend = 0.0
				target_scale = 0.0
		
		_last_active_turn_state = current_state_name
	else:
		_is_returning_to_neutral = false
		_stop_timer = 0.0
		_last_active_turn_state = ""
		target_blend = 0.0
		target_scale = 0.0
		_is_turning = false
		_turn_direction = 0.0
		_return_direction = 0.0
		_peak_blend = 0.0
		
		# Allow the turn-in-place animation parameters to decay smoothly in the background
		# during the crossfade transition to walk/run instead of snapping instantly.
		if anim:
			_smoothed_turn_speed = 0.0

	# Accumulate animation time and evaluate RealTime boundary footstep triggers
	var prev_anim_time = _anim_time
	if _is_turning and target_scale != 0.0:
		_anim_time += delta * target_scale
		var unwrapped_anim_time = _anim_time
		
		# Wrap strictly since returning to neutral can cross boundaries now
		if _anim_time > 1.06:
			_anim_time -= 1.06
		elif _anim_time < 0.0:
			_anim_time += 1.06
			
		print("[AnimTime RealTime] ", snapped(_anim_time, 0.001), " | TargetScale: ", snapped(target_scale, 0.01), " | Returning: ", _is_returning_to_neutral)

		# RealTime Footstep Trigger Detection for turning
		var turn_cooldown = clamp(200.0 / max(abs(target_scale), 0.5), 80.0, 250.0)
		var crossed_turn_step = false
		
		if target_scale > 0.0:
			# Forward Playback (Turning Right)
			# Check crossing 1.06 (or loop wrap)
			if (prev_anim_time < 1.06 and unwrapped_anim_time >= 1.06) or (unwrapped_anim_time < prev_anim_time and prev_anim_time > 0.8):
				crossed_turn_step = true
			# Check crossing 0.53
			elif prev_anim_time < 0.53 and _anim_time >= 0.53:
				crossed_turn_step = true
		else:
			# Backward Playback (Turning Left)
			# Check crossing 0.00 (or loop wrap)
			if (prev_anim_time > 0.00 and unwrapped_anim_time <= 0.00) or (unwrapped_anim_time > prev_anim_time and prev_anim_time < 0.2):
				crossed_turn_step = true
			# Check crossing 0.53
			elif prev_anim_time > 0.53 and _anim_time <= 0.53:
				crossed_turn_step = true
				
		if crossed_turn_step:
			var now = Time.get_ticks_msec()
			if now - _last_step_time > turn_cooldown:
				_last_step_time = now
				SoundManager.play_3d("leon_footstep", self)



	# Check for 0.53 boundary crossing while returning to neutral
	if _is_returning_to_neutral:
		var crossed_neutral = false
		if target_scale > 0.0:
			if prev_anim_time < 0.53 and _anim_time >= 0.53:
				crossed_neutral = true
		elif target_scale < 0.0:
			if prev_anim_time > 0.53 and _anim_time <= 0.53:
				crossed_neutral = true
				
		if crossed_neutral:
			_anim_time = 0.53
			_return_direction = 0.0
			_trigger_turn_seek()

	# Smoothly update the blend amount in the AnimationTree for Idle
	var current_blend = anim.get("parameters/Main/Idle/Pis/Blend2/blend_amount")
	var new_blend = 0.0
	if current_blend != null:
		new_blend = lerp(current_blend, target_blend, delta * 8.0)
		anim.set("parameters/Main/Idle/Pis/Blend2/blend_amount", new_blend)
		anim.set("parameters/Main/Idle/Pis/TimeScale/scale", target_scale)
		
	var current_blend_shot = anim.get("parameters/Main/Idle/Shot/Blend2/blend_amount")
	var new_blend_shot = 0.0
	if current_blend_shot != null:
		new_blend_shot = lerp(current_blend_shot, target_blend, delta * 8.0)
		anim.set("parameters/Main/Idle/Shot/Blend2/blend_amount", new_blend_shot)
		anim.set("parameters/Main/Idle/Shot/TimeScale/scale", target_scale)

	# Smoothly update the blend amount in the AnimationTree for QT
	var current_blend_qt = anim.get("parameters/Main/QT/Pis/Blend2/blend_amount")
	var new_blend_qt = 0.0
	if current_blend_qt != null:
		new_blend_qt = lerp(current_blend_qt, target_blend, delta * 8.0)
		anim.set("parameters/Main/QT/Pis/Blend2/blend_amount", new_blend_qt)
		anim.set("parameters/Main/QT/Pis/TimeScale/scale", target_scale)
		anim.set("parameters/Main/QT/Pis/UpperBlend/blend_amount", 1.0)
		
	var current_blend_qt_shot = anim.get("parameters/Main/QT/Shot/Blend2/blend_amount")
	var new_blend_qt_shot = 0.0
	if current_blend_qt_shot != null:
		new_blend_qt_shot = lerp(current_blend_qt_shot, target_blend, delta * 8.0)
		anim.set("parameters/Main/QT/Shot/Blend2/blend_amount", new_blend_qt_shot)
		anim.set("parameters/Main/QT/Shot/TimeScale/scale", target_scale)
		anim.set("parameters/Main/QT/Shot/UpperBlend/blend_amount", 1.0)

	# Reset state variables when all active turn blends have faded out below 0.02
	if _is_turning:
		var max_current_blend = 0.0
		if current_blend != null:
			max_current_blend = max(max_current_blend, new_blend)
		if current_blend_shot != null:
			max_current_blend = max(max_current_blend, new_blend_shot)
		if current_blend_qt != null:
			max_current_blend = max(max_current_blend, new_blend_qt)
		if current_blend_qt_shot != null:
			max_current_blend = max(max_current_blend, new_blend_qt_shot)
			
		if max_current_blend < 0.02:
			_is_turning = false
			_turn_direction = 0.0
			_return_direction = 0.0
			_peak_blend = 0.0
			_anim_time = 0.53
			_last_active_scale = 1.0
			_last_speed_mult = 1.0
			_linger_speed_mult = 0.4
			_stop_timer = 0.0
			_is_returning_to_neutral = false
			_smoothed_turn_speed = 0.0

	_current_turn_anim_scale = target_scale if _is_turning else 0.0


func _trigger_turn_seek() -> void:
	if not anim:
		return
	print("[TurnSeek] Seeking walk_side to 0.53s")
	_anim_time = 0.53
	_turn_last_norm_pos = 0.50
	_last_step_time = 0
	_pending_stop_footstep = false
	var paths = [
		"parameters/Main/Idle/Pis/TimeSeek/seek_request",
		"parameters/Main/Idle/Shot/TimeSeek/seek_request",
		"parameters/Main/QT/Pis/TimeSeek/seek_request",
		"parameters/Main/QT/Shot/TimeSeek/seek_request"
	]
	for path in paths:
		if anim.get(path) != null:
			anim.set(path, 0.53)
