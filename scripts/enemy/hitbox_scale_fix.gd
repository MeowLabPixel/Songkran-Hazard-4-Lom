## Resets scale to uniform (1,1,1) every physics frame.
## Attached to hitbox Area3D nodes whose BoneAttachment3D parents inherit
## non-uniform scale from Blender's armature export, causing Jolt Physics errors.
extends Area3D

func _ready() -> void:
	_sanitize_scale()

func _notification(what: int) -> void:
	if what == Node3D.NOTIFICATION_LOCAL_TRANSFORM_CHANGED or what == Node3D.NOTIFICATION_TRANSFORM_CHANGED:
		_sanitize_scale()

func _physics_process(_delta: float) -> void:
	_sanitize_scale()

func _sanitize_scale() -> void:
	if not is_inside_tree():
		return
	top_level = true
	var p := get_parent() as Node3D
	if p:
		var t := p.global_transform
		t.basis = t.basis.orthonormalized()
		global_transform = t
	else:
		var t := global_transform
		t.basis = t.basis.orthonormalized()
		global_transform = t
