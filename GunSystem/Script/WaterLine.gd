@tool
extends Node3D

@export var life_time: float = 0.03

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var _life_remaining: float = 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		visible = false
		set_process(false)


func set_line(spawn_pos: Vector3, target_pos: Vector3) -> void:
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_instance:
		return

	var to_target = target_pos - spawn_pos
	var distance := to_target.length()
	if distance < 0.05:
		visible = false
		set_process(false)
		return

	global_position = spawn_pos
	var fwd = to_target.normalized()
	var up = Vector3.UP
	if abs(fwd.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	look_at(spawn_pos + fwd, up)
	
	mesh_instance.scale.z = distance
	mesh_instance.position = Vector3(0, 0, -distance * 0.5)
	
	_life_remaining = maxf(life_time, 0.001)
	visible = true
	set_process(true)
