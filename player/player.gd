class_name Player extends CharacterBody3D

@export_group("movement setting")
@export var walk_speed = 4.0
@export var walk_Back_speed = 2.0
@export var turn_speed:= 180.0
@export var quick_turn_speed:= 0.3 #in second
@export var run_speed:=6
@export var aim_bone: LookAtModifier3D
@export var aim_bone2: LookAtModifier3D
@export var max_tilt_angle: float = 6.0
@export var rotation_tilt_sensitivity: float = 2.0 # degrees of Z tilt per rad/sec of turn speed
@export var max_yaw_angle: float = 15.0
@export var rotation_yaw_sensitivity: float = 6.0 # degrees of Y yaw per rad/sec of turn speed

@export_group("animation setting")
#@export var anim_player:AnimationPlayer
@export var default_blend_time:= 0.5
@export var turn_anim_speed: float = 1.2
@export var turn_stop_anim_speed: float = 2.0
@export var turn_speed_scale_factor: float = 0.3  # how much faster each rad/s of turning adds
@export var anim: AnimationTree
var anim_playback = "parameters/Main/playback"

@export_group("Data setting")
@export var MaxHP = 100
@export var hitboxF: Area3D
@export var hitboxB: Area3D
@export var stun_detect: Area3D
@export var pickup_detect: Area3D

var HP = MaxHP
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
var is_aimming:bool = false
var is_reload:bool = false
var is_grab:bool = false
var is_knockdown:bool = false
var is_near_stunt:bool = false
var _last_grab_area: Area3D = null
var _last_grabber: Node = null

#gun
@export var gun_controller: GunController

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
@onready var cross_hair: TextureRect = $Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/TextureRect
@onready var reload_timer: Timer = $Reload_timer

#const BULLET = preload("uid://csdtdj7sci5vk")
#@@onready var bullet_lo: Node3D = $"Re4Lom Base Rig/rig/Skeleton3D/Gun/MeshInstance3D/Node3D"

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

func _ready() -> void:
	add_to_group("player")
	stun_detect.area_entered.connect(stun_detect_in)
	stun_detect.area_exited.connect(stun_detect_out)
	pickup_detect.area_entered.connect(pickup_detect_area)

	# Connect player hitbox zone signals (Grabbed/Attacked) to handlers
	_connect_player_hitboxes()

	if cross_hair:
		cross_hair.visible = false
		cross_hair.texture = crosshair_texture
		cross_hair.modulate = crosshair_color
		# Ensure size matches the image to maintain quality
		cross_hair.size = Vector2(512, 512)
		cross_hair.pivot_offset = Vector2(256, 256)
		cross_hair.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		
	last_y_rotation = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	if skeleton:
		skeleton.rotation = Vector3.ZERO
		var lean_modifier = preload("res://player/player_lean_modifier.gd").new()
		lean_modifier.name = "SpineLeanModifier"
		lean_modifier.max_tilt_angle = max_tilt_angle
		skeleton.add_child(lean_modifier)
	if rig:
		rig.rotation = Vector3.ZERO
	_setup_idle_turn_blending()
		
func _process(delta: float) -> void:
	update_crosshair_accuracy(delta)
	
	if skeleton:
		var lean_modifier = skeleton.get_node_or_null("SpineLeanModifier")
		if lean_modifier:
			lean_modifier.input_dir = Motion.input_dir
			
			var is_sprinting = false
			var sm = get_node_or_null("Statemachine")
			if sm and sm.current_state and sm.current_state.name == "Sprint":
				is_sprinting = true
			lean_modifier.is_sprinting = is_sprinting
			lean_modifier.is_aiming = is_aimming

	_update_skeleton_tilt(delta)
	_update_aim_target()
	_update_idle_turn_blend(delta)

func _update_aim_target() -> void:
	if aim_target and camera and camera.targetref:
		var lean_modifier = skeleton.get_node_or_null("SpineLeanModifier") as PlayerLeanModifier
		if lean_modifier:
			# Shift target based on movement lean to make arms and chest rotate into the lean
			var offset_x = -lean_modifier.current_tilt_z * 3.5
			var offset_y = -lean_modifier.current_tilt_x * 2.0
			var local_pos = camera.targetref.transform.origin
			var local_offset = local_pos + Vector3(offset_x, offset_y, 0.0)
			aim_target.global_position = camera.global_transform * local_offset
		else:
			aim_target.global_position = camera.targetref.global_position
			aim_target.global_position.y = camera.targetref.global_position.y

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
		return

	if gun_controller and gun_controller.current_gun:
		var gun: Gun = gun_controller.current_gun
		# Normalize spread based on the gun's min/max spread
		var spread_factor = clamp((gun.current_spread - gun.min_spread) / (gun.max_spread - gun.min_spread), 0.0, 1.0)
		var target_scale_val = lerp(min_scale, max_scale, spread_factor)

		cross_hair.scale = cross_hair.scale.lerp(Vector2(target_scale_val, target_scale_val), delta * 20.0)
		
func set_velocity_from_motion(vel: Vector3)-> void:
	velocity = vel

func _physics_process(_delta: float) -> void:
	move_and_slide()

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

func take_damage(amount: int) -> void:
	lost_HP(amount)
	print("[Player] Took %d damage — HP: %d/%d" % [amount, HP, MaxHP])

	if HP <= 0:
		print("[Player] Dead")

func lost_HP(amount):
	if HP -amount <= 0:
		HP = 0
	else:
		HP -=amount
		
func Heal(amount):
	if HP +amount >= MaxHP:
		HP = MaxHP
	else:
		HP +=amount
		
func stun_detect_in (area: Area3D):
	var body = _find_enemy_from_area(area)
	if body is EnemyBase :
		near_enemy_list.append(body)
	check_if_near_stun()

func stun_detect_out (area: Area3D):
	var body = _find_enemy_from_area(area)
	if body is EnemyBase and  near_enemy_list.has(body):
		var index = near_enemy_list.find(body,0)
		near_enemy_list.remove_at(index)
	check_if_near_stun()
		
func check_if_near_stun():
	is_near_stunt = false
	for i in near_enemy_list:
		var sm = i.get_node_or_null("EnemyStateMachine")
		if sm.current_state == sm._states["StateTakedownable"]:
			is_near_stunt = true

func aim_bone_on(value):
	aim_bone.active = value
	aim_bone2.active = value

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

func on_hitbox_grabbed_with_area(area: Area3D) -> void:
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

func attempt_takedown() -> void:
	# Called when player presses takedown and is_near_stunt is true.

	if not stun_detect:
		return
	# First try overlapping bodies on the takedown Area
	var areas := stun_detect.get_overlapping_areas()
	for a in areas:
		if not a:
			continue

		var enemy := _find_enemy_from_area(a)
		if enemy:
			
			var sm = enemy.get_node_or_null("EnemyStateMachine")
			if sm:
				
				var td = sm.get_node_or_null("StateTakedownable")
				if td:
					td.trigger_takedown()
					return
	# Fallback: use near_enemy_list (populated by stun_detect) to find a takedownable enemy
	for e in near_enemy_list:
		if not e:
			continue
		var sm2 = e.get_node_or_null("EnemyStateMachine")
		if sm2:
			var td2 = sm2.get_node_or_null("StateTakedownable")
			if td2:
				
				td2.trigger_takedown()
				return
	# Final fallback: search nearby enemies by group within a small radius
	var enemies = get_tree().get_nodes_in_group("enemy")
	var radius := 2.0
	for en in enemies:
		if not en:
			continue
		if en.global_position.distance_to(global_position) <= radius:
			var sm3 = en.get_node_or_null("EnemyStateMachine")
			if sm3:
				var td3 = sm3.get_node_or_null("StateTakedownable")
				if td3:
					td3.trigger_takedown()
					return

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
		
		# Transition out of turn-in-place state instantly to avoid blending with walk/run movement
		if anim:
			_smoothed_turn_speed = 0.0
			anim.set("parameters/Main/Idle/Pis/Blend2/blend_amount", 0.0)
			anim.set("parameters/Main/Idle/Pis/TimeScale/scale", 0.0)
			anim.set("parameters/Main/Idle/Shot/Blend2/blend_amount", 0.0)
			anim.set("parameters/Main/Idle/Shot/TimeScale/scale", 0.0)
			anim.set("parameters/Main/QT/Pis/Blend2/blend_amount", 0.0)
			anim.set("parameters/Main/QT/Pis/TimeScale/scale", 0.0)
			anim.set("parameters/Main/QT/Shot/Blend2/blend_amount", 0.0)
			anim.set("parameters/Main/QT/Shot/TimeScale/scale", 0.0)

	# Accumulate animation time
	var prev_anim_time = _anim_time
	if _is_turning and target_scale != 0.0:
		_anim_time += delta * target_scale
		# Wrap strictly since returning to neutral can cross boundaries now
		if _anim_time > 1.06:
			_anim_time -= 1.06
		elif _anim_time < 0.0:
			_anim_time += 1.06
		print("[AnimTime RealTime] ", snapped(_anim_time, 0.001), " | TargetScale: ", snapped(target_scale, 0.01), " | Returning: ", _is_returning_to_neutral)

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


func _trigger_turn_seek() -> void:
	if not anim:
		return
	print("[TurnSeek] Seeking walk_side to 0.53s")
	_anim_time = 0.53
	var paths = [
		"parameters/Main/Idle/Pis/TimeSeek/seek_request",
		"parameters/Main/Idle/Shot/TimeSeek/seek_request",
		"parameters/Main/QT/Pis/TimeSeek/seek_request",
		"parameters/Main/QT/Shot/TimeSeek/seek_request"
	]
	for path in paths:
		if anim.get(path) != null:
			anim.set(path, 0.53)
