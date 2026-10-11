@tool
class_name PCGBuildingInstance
extends Node3D

## Component attached to each building placed by BuildingPathPCG.
## Allows toggling front and back iron gates (e.g. IronGate v1, IronGate v2, 2panelGate)
## both via the procedural generator and directly in the Inspector.

@export_group("Iron Gate Controls")
## When closed (true), the front iron gate is visible and solid.
## When open (false), the gate is hidden and collision disabled, allowing entry.
@export var front_iron_gate_closed: bool = true:
	set(value):
		front_iron_gate_closed = value
		_update_gates()

## Toggles back / service iron gates if present.
@export var back_iron_gate_closed: bool = true:
	set(value):
		back_iron_gate_closed = value
		_update_gates()

func _ready() -> void:
	_update_gates()

func set_front_gate(closed: bool) -> void:
	front_iron_gate_closed = closed

func set_back_gate(closed: bool) -> void:
	back_iron_gate_closed = closed

func _is_gate_node(node: Node) -> bool:
	var n: String = node.name.to_lower()
	return n.contains("irongate") or n.contains("iron_gate") or n.contains("panelgate")

func _is_back_gate(node: Node) -> bool:
	var n: String = node.name.to_lower()
	return n.contains("back") or n.contains("rear")

func _update_gates() -> void:
	_apply_to_node_recursive(self)

func _apply_to_node_recursive(node: Node) -> void:
	for child in node.get_children():
		if _is_gate_node(child):
			var is_back: bool = _is_back_gate(child)
			var is_closed: bool = back_iron_gate_closed if is_back else front_iron_gate_closed
			_set_gate_active(child, is_closed)
		else:
			_apply_to_node_recursive(child)

func _set_gate_active(gate_node: Node, active: bool) -> void:
	if gate_node is Node3D:
		gate_node.visible = active
	
	# Disable or enable collision shapes inside or under this gate node
	var collision_shapes: Array[Node] = gate_node.find_children("*", "CollisionShape3D", true, false)
	for col in collision_shapes:
		if col is CollisionShape3D:
			col.disabled = not active
	
	# Also toggle any StaticBody3D collision layers if present
	var static_bodies: Array[Node] = gate_node.find_children("*", "StaticBody3D", true, false)
	for body in static_bodies:
		if body is StaticBody3D:
			body.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

## Returns true if this building scene contains any front gate node
func has_front_gate() -> bool:
	return _check_has_front_gate(self)

func _check_has_front_gate(node: Node) -> bool:
	for child in node.get_children():
		if _is_gate_node(child) and not _is_back_gate(child):
			return true
		if _check_has_front_gate(child):
			return true
	return false
