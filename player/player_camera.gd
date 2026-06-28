extends Node3D

@export var character: CharacterBody3D
@export var edge_spring_arm: SpringArm3D
@export var rear_spring_arm: SpringArm3D
@export var camera_align_speed:float = 0.2
@export var camera: Camera3D
@export var aim_rear_spring_arm_length:float =0.5
@export var aim_edge_spring_arm_length:float =0.5
@export var aim_speed:float =0.2
@export var aim_fov:float =55
@export var sprint_fov:float =90
@export var sprint_tween_speed:float =0.5
@export var target: Marker3D
@export var targetref: Marker3D

var camera_rotation: Vector2= Vector2.ZERO
var target_camera_rotation: Vector2 = Vector2.ZERO
@export var camera_smoothing_speed: float = 25.0 # Lower is smoother, higher is more responsive
var pending_camera_rotation: Vector2 = Vector2.ZERO
var mouse_sensitivity: float = 0.002
@export var max_look_up: float = 1.4 # ~80 degrees up
@export var max_look_down: float = 1.4 # ~80 degrees down
@export var look_up_lift_amount: float = 1.5 # How much the camera lifts when looking up
@export var look_down_lift_amount: float = 1.5 # How much the camera lifts when looking down
var aim_offset: Vector2 = Vector2.ZERO

@export_group("Aim Deadzones")
@export var aim_deadzone_left: float = 0.15 # Small limit on left to avoid body blocking
@export var aim_deadzone_right: float = 0.35 # Larger limit on right
@export var aim_deadzone_up: float = 0.2
@export var aim_deadzone_down: float = 0.2

var camera_tween:Tween
enum cameraalign{LEFT=-1,RIGHT=1,CENTER=0}
var current_camera_align:cameraalign = cameraalign.RIGHT

var base_position_y: float = 0.0
var action_offset_y: float = 0.0
var offset_tween: Tween

var action_pitch: float = 0.0
var pitch_tween: Tween

var base_spring_length: float = 0.0
var action_spring_length: float = 0.0
var spring_tween: Tween

func set_action_offset_y(target_offset: float, duration: float) -> void:
	if offset_tween:
		offset_tween.kill()
	offset_tween = get_tree().create_tween()
	offset_tween.tween_property(self, "action_offset_y", target_offset, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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

@onready var defaut_edge_spring_arm_length: float = edge_spring_arm.spring_length
@onready var defaut_rear_spring_arm_length: float = rear_spring_arm.spring_length
@onready var defaut_camera_fov:float = camera.fov



func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_position_y = position.y
	base_spring_length = defaut_rear_spring_arm_length
	
	# Remove camera collision with NPCs/Enemies by restricting it to only the Environment layer (Layer 1)
	if edge_spring_arm:
		edge_spring_arm.collision_mask = 1
	if rear_spring_arm:
		rear_spring_arm.collision_mask = 1

func _process(delta: float) -> void:
	if character and not character.is_aimming:
		aim_offset = aim_offset.lerp(Vector2.ZERO, delta * 15.0)
		
	# Smoothly apply the deadzone excess rotation for a heavier, cinematic feel
	if pending_camera_rotation.length_squared() > 0.000001:
		var applied = pending_camera_rotation * min(delta * 15.0, 1.0)
		target_camera_rotation += applied
		target_camera_rotation.y = clamp(target_camera_rotation.y, -max_look_up, max_look_down)
		pending_camera_rotation -= applied
		
	# Add inertia/smoothing to general camera movement
	camera_rotation = camera_rotation.lerp(target_camera_rotation, delta * camera_smoothing_speed)
	_apply_camera_rotation()
	
	if rear_spring_arm:
		rear_spring_arm.spring_length = base_spring_length + action_spring_length

func _input(event: InputEvent)-> void:
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
		enter_aim()
	if event.is_action_released("aim"):
		exit_aim()

func camera_look(mouse_movement: Vector2)-> void:
	if character.is_aimming:
		aim_offset += mouse_movement
		
		var excess_vector = Vector2.ZERO
		
		# Asymmetrical X boundaries
		if aim_offset.x > aim_deadzone_right:
			excess_vector.x = aim_offset.x - aim_deadzone_right
			aim_offset.x = aim_deadzone_right
		elif aim_offset.x < -aim_deadzone_left:
			excess_vector.x = aim_offset.x + aim_deadzone_left
			aim_offset.x = -aim_deadzone_left
			
		# Asymmetrical Y boundaries
		if aim_offset.y > aim_deadzone_down:
			excess_vector.y = aim_offset.y - aim_deadzone_down
			aim_offset.y = aim_deadzone_down
		elif aim_offset.y < -aim_deadzone_up:
			excess_vector.y = aim_offset.y + aim_deadzone_up
			aim_offset.y = -aim_deadzone_up
			
		pending_camera_rotation += excess_vector
	else:
		target_camera_rotation += mouse_movement
		target_camera_rotation.y = clamp(target_camera_rotation.y, -max_look_up, max_look_down)
		
func _apply_camera_rotation() -> void:
	camera_rotation.y = clamp(camera_rotation.y, -max_look_up, max_look_down)
	
	transform.basis = Basis()
	
	if not character.is_quick_turn:
		character.transform.basis = Basis()
		character.rotate_object_local(Vector3(0,1,0),-camera_rotation.x)
		
	rotate_object_local(Vector3(1,0,0), -camera_rotation.y + action_pitch)	
	
	# Dynamically push the camera's pivot UP when looking up or down to prevent the body from blocking the view!
	if camera_rotation.y < 0.0: # Looking UP
		position.y = base_position_y + action_offset_y + (abs(camera_rotation.y) * look_up_lift_amount)
	else: # Looking DOWN
		position.y = base_position_y + action_offset_y + (abs(camera_rotation.y) * look_down_lift_amount)

func swap_camera_align()-> void:
	match current_camera_align:
		cameraalign.LEFT:
			set_camera_alignment(cameraalign.RIGHT)
		cameraalign.RIGHT:
			set_camera_alignment(cameraalign.LEFT)
		cameraalign.CENTER:	
			return	
	var new_pos:float = defaut_edge_spring_arm_length * current_camera_align
	set_rear_spring_pos(new_pos,camera_align_speed)
	
func set_camera_alignment(alignment: cameraalign)-> void:
	current_camera_align = alignment
	
func set_rear_spring_pos(pos: float, speed: float)-> void:
	if camera_tween:
		camera_tween.kill()
		
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)	
	camera_tween = get_tree().create_tween()
	camera_tween.tween_property(edge_spring_arm,"spring_length",pos,speed)
	
func enter_aim()-> void:
	if camera_tween:
		camera_tween.kill()
	character.is_aimming = true	
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",aim_fov,aim_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",aim_edge_spring_arm_length*current_camera_align,aim_speed)
	camera_tween.tween_property(self,"base_spring_length",aim_rear_spring_arm_length,aim_speed)
func exit_aim()-> void:
	if camera_tween:
		camera_tween.kill()
	character.is_aimming = false		
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",defaut_camera_fov,aim_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",defaut_edge_spring_arm_length*current_camera_align,aim_speed)
	camera_tween.tween_property(self,"base_spring_length",defaut_rear_spring_arm_length,aim_speed)
	
func enter_sprint()-> void:
	if camera_tween:
		camera_tween.kill()
	
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",sprint_fov,sprint_tween_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",defaut_edge_spring_arm_length*current_camera_align,aim_speed)
	camera_tween.tween_property(self,"base_spring_length",defaut_rear_spring_arm_length,aim_speed)
func exit_sprint()-> void:
	if camera_tween:
		camera_tween.kill()
		
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",defaut_camera_fov,aim_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",defaut_edge_spring_arm_length*current_camera_align,aim_speed)
	camera_tween.tween_property(self,"base_spring_length",defaut_rear_spring_arm_length,aim_speed)
	
