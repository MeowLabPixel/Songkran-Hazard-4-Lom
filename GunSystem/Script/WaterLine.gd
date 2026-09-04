extends Node3D

@export var life_time: float = 0.03

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func set_line(spawn_pos: Vector3, target_pos: Vector3) -> void:
	var to_target = target_pos - spawn_pos
	var distance := to_target.length()
	if distance < 0.05:
		visible = false
		return

	global_position = spawn_pos
	var fwd = to_target.normalized()
	var up = Vector3.UP
	if abs(fwd.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	look_at(spawn_pos + fwd, up)
	
	mesh_instance.scale.z = distance
	mesh_instance.position = Vector3(0, 0, -distance * 0.5)
	
	visible = true

	var tree = get_tree()
	if tree:
		tree.create_timer(life_time).timeout.connect(func():
			if is_instance_valid(self):
				visible = false
		)
