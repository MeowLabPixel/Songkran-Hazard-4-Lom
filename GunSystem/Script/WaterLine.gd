extends Node3D

@export var life_time: float = 0.03

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func set_line(spawn_pos: Vector3, target_pos: Vector3) -> void:
	global_position = spawn_pos
	look_at(target_pos, Vector3.UP)
	
	var distance := spawn_pos.distance_to(target_pos)
	
	mesh_instance.scale.z = distance
	mesh_instance.position = Vector3(0, 0, -distance * 0.5)

	get_tree().create_timer(life_time).timeout.connect(queue_free)
