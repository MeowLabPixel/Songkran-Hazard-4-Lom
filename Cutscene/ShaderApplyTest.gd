extends Node3D

const CELL_MATERIAL = preload("res://shaders/cell_shade_material.tres")

func _ready():
	# Just use the pre-made material
	for node in get_tree().get_nodes_in_group("cell_shaded"):
		if node is MeshInstance3D:
			node.material_override = CELL_MATERIAL
