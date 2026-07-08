@tool
@icon("images/acoustic_body.svg")
extends Node
class_name AcousticBody
## Attach as a child of any [CollisionObject3D] (e.g. [StaticBody3D],
## [RigidBody3D], [Area3D], [CharacterBody3D]) or [CSGShape3D] to give that surface acoustic properties.
##
## [b]Supported parent nodes:[/b]
## - [StaticBody3D]: For static level geometry (walls, floors, props)
## - [RigidBody3D]: For dynamic/movable objects (crates, doors, debris)
## - [CharacterBody3D]: For player or NPC bodies (rare, but possible)
## - [Area3D]: For trigger zones or volumes that affect sound
## - [CSGShape3D]: For CSG-based geometry (CSGBox3D, CSGSphere3D, etc.)
##
## The AcousticBody must be a [b]direct child[/b] of the parent node's collision object or CSG shape. It is not detected if placed deeper in the hierarchy.
##
## [b]Tip:[/b] In the Godot editor, the Spatial Audio plugin adds a button to CollisionShape3D and CSGShape3D nodes that lets you quickly add an AcousticBody as a child. This streamlines setup for acoustic surfaces.
##
## When [SpatialAudioPlayer3D] traces an occlusion ray and hits the parent
## body, it looks for an [AcousticBody] child to retrieve the
## [AcousticMaterial]. If none is found, the player's fallback transmission
## value is used instead.
## [br][br]
## [b]Usage:[/b]
## [codeblock]
## StaticBody3D (concrete wall)
## ├── CollisionShape3D
## ├── MeshInstance3D
## └── AcousticBody  ← assign an AcousticMaterial here
##
## RigidBody3D (movable crate)
## ├── CollisionShape3D
## └── AcousticBody
##
## Area3D (trigger volume)
## ├── CollisionShape3D
## └── AcousticBody
##
## CSGBox3D (use_collision = true)
## └── AcousticBody  ← also works on CSG shapes
## [/codeblock]

## The acoustic material that describes how this surface absorbs, scatters,
## and transmits sound energy.
@export var acoustic_material : AcousticMaterial : 
	set(value):
		acoustic_material = value
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []

	# Must be a child of a CollisionObject3D or CSGShape3D.
	var parent := get_parent()
	if parent != null and not (parent is CollisionObject3D) and not (parent is CSGShape3D):
		warnings.append("AcousticBody should be a direct child of a CollisionObject3D (e.g. StaticBody3D, RigidBody3D) or a CSGShape3D.")

	# Warn if the parent is a CSGShape3D without collision enabled.
	if parent != null and parent is CSGShape3D:
		if not parent.use_collision:
			warnings.append("The parent CSGShape3D does not have 'use_collision' enabled. Occlusion raycasts won't hit it.")

		# Warn if the parent CSGShape3D is inside a CSGCombiner.
		var grandparent := parent.get_parent()
		if grandparent != null and grandparent.get_class() == "CSGCombiner3D":
			warnings.append("AcousticBody is on a CSG shape inside a CSGCombiner3D. This setup may not work properly for raycasts or occlusion.")

	# Warn if there are multiple AcousticBody nodes on the same parent.
	if parent != null:
		var count := 0
		for child in parent.get_children():
			if child is AcousticBody:
				count += 1
		if count > 1:
			warnings.append("This node has %d AcousticBody children. Only the first one found will be used — remove the extras." % count)

	# Warn if no material is assigned.
	if acoustic_material == null:
		warnings.append("No AcousticMaterial assigned. The SpatialAudioPlayer3D will use its fallback transmission value for this surface.")

	return warnings


func _ready() -> void:
	if Engine.is_editor_hint():
		# Re-check warnings when siblings change.
		var parent := get_parent()
		if parent != null:
			if not parent.child_order_changed.is_connected(_on_siblings_changed):
				parent.child_order_changed.connect(_on_siblings_changed)


func _on_siblings_changed() -> void:
	update_configuration_warnings()


## Finds the [AcousticBody] child of the given node, if any.
## Returns [code]null[/code] when none exists.
static func find_on(node: Node) -> AcousticBody:
	if node == null:
		return null
	for child in node.get_children():
		if child is AcousticBody:
			return child
	return null


## Resolves the [AcousticBody] for a raycast collider.
## Checks the collider itself first, then walks up to handle CSG shapes
## whose internal [StaticBody3D] is what raycasts actually hit.
static func find_for_collider(collider: Node) -> AcousticBody:
	if collider == null:
		return null
	# Direct lookup (normal CollisionObject3D case).
	var result := find_on(collider)
	if result != null:
		return result
	# CSG shapes create an internal StaticBody3D child when use_collision is
	# enabled. The raycast hits that internal body, so we check the parent.
	var parent := collider.get_parent()
	if parent != null and parent is CSGShape3D:
		return find_on(parent)
	return null
