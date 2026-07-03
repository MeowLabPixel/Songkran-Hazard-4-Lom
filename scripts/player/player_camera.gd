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
	collision_target_length = defaut_rear_spring_arm_length
	collision_smoothed_target = defaut_rear_spring_arm_length
	collision_current_length = defaut_rear_spring_arm_length
	
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
		
	var space_state = get_world_3d().direct_space_state
	var right_dir = character.global_transform.basis.x
	var origin = character.global_position + Vector3(0, 1.0, 0) # Chest height
	var target_pos = origin + right_dir * auto_swap_wall_distance
	
	var query = PhysicsRayQueryParameters3D.create(origin, target_pos, 1) # Layer 1
	query.exclude = [character.get_rid()]
	var result = space_state.intersect_ray(query)
	
	if result:
		# Wall detected on the right
		if current_camera_align == cameraalign.RIGHT:
			auto_swapped_to_left = true
			swap_camera_align()
	else:
		# No wall on the right
		if auto_swapped_to_left and current_camera_align == cameraalign.LEFT:
			auto_swapped_to_left = false
			swap_camera_align()

func _process(delta: float) -> void:
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
	camera_rotation = camera_rotation.lerp(target_camera_rotation, delta * camera_smoothing_speed)
	_apply_camera_rotation()
	
	if rear_spring_arm:
		var desired_rear_length = base_spring_length + action_spring_length
		var raw_hit_length = desired_rear_length
		
		var hit_wall = false
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
			if character:
				shape_query.exclude = [character.get_rid()]
				
			var result = space_state.cast_motion(shape_query)
			if result.size() > 0 and result[0] < 1.0:
				raw_hit_length = desired_rear_length * result[0]
				hit_wall = true
				
		# Only apply max limit if we are actively hitting a wall. 
		# This prevents the max zoom limit from capping normal gameplay distance.
		if hit_wall:
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
		if not character.aim_blocked_until_release:
			enter_aim()
	if event.is_action_released("aim"):
		# Always clear the block when aim is released so re-press works
		character.aim_blocked_until_release = false
		exit_aim()

func camera_look(mouse_movement: Vector2)-> void:
	if character.is_aimming:
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
		if character and not character.is_aimming:
			rear_spring_arm.shape.radius = rear_collision_radius_center
		else:
			match current_camera_align:
				cameraalign.CENTER:
					rear_spring_arm.shape.radius = rear_collision_radius_center
				cameraalign.RIGHT:
					rear_spring_arm.shape.radius = rear_collision_radius_right
				cameraalign.LEFT:
					rear_spring_arm.shape.radius = rear_collision_radius_left
	
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
	update_collision_radius()
			
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",aim_fov,aim_speed)
	
	camera_tween.tween_property(edge_spring_arm,"spring_length",get_target_edge_length(),aim_speed)
	camera_tween.tween_property(self,"base_spring_length",aim_rear_spring_arm_length,aim_speed)
func exit_aim()-> void:
	if camera_tween:
		camera_tween.kill()
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
	
