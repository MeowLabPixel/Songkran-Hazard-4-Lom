# AttackHitbox.gd
class_name AttackHitbox
extends Area3D

var attack_type: String = "attack"  # "attack" or "grab"

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
