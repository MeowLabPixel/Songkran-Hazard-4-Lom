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
var mouse_sensitivity: float = 0.002
var max_y_rot:float= 0.5

var camera_tween:Tween
enum cameraalign{LEFT=-1,RIGHT=1,CENTER=0}
var current_camera_align: int = cameraalign.RIGHT

@onready var defaut_edge_spring_arm_length: float = edge_spring_arm.spring_length
@onready var defaut_rear_spring_arm_length: float = rear_spring_arm.spring_length
@onready var defaut_camera_fov:float = camera.fov



func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
	camera_rotation += mouse_movement
	transform.basis = Basis()
	character.transform.basis = Basis()
	if not character.is_quick_turn:
		character.rotate_object_local(Vector3(0,1,0),-camera_rotation.x)
	rotate_object_local(Vector3(1,0,0),-camera_rotation.y)	
	
	camera_rotation.y = clamp(camera_rotation.y,-max_y_rot,max_y_rot)

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
	camera_tween.tween_property(rear_spring_arm,"spring_length",aim_rear_spring_arm_length,aim_speed)
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
	camera_tween.tween_property(rear_spring_arm,"spring_length",defaut_rear_spring_arm_length,aim_speed)
	
func enter_sprint()-> void:
	if camera_tween:
		camera_tween.kill()
	
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",sprint_fov,sprint_tween_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",defaut_edge_spring_arm_length*current_camera_align,aim_speed)
	camera_tween.tween_property(rear_spring_arm,"spring_length",defaut_rear_spring_arm_length,aim_speed)
func exit_sprint()-> void:
	if camera_tween:
		camera_tween.kill()
		
	camera_tween = get_tree().create_tween()
	camera_tween.set_parallel()
	camera_tween.set_trans(Tween.TRANS_EXPO)
	camera_tween.set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(camera,"fov",defaut_camera_fov,aim_speed)
	camera_tween.tween_property(edge_spring_arm,"spring_length",defaut_edge_spring_arm_length*current_camera_align,aim_speed)
	camera_tween.tween_property(rear_spring_arm,"spring_length",defaut_rear_spring_arm_length,aim_speed)
	
