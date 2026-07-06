# AttackHitbox.gd
class_name AttackHitbox
extends Area3D

var attack_type: String = "attack"  # "attack" or "grab"

func _physics_process(_delta: float) -> void:
	if not global_basis.get_scale().is_equal_approx(Vector3.ONE):
		var t := global_transform
		t.basis = t.basis.orthonormalized()
		global_transform = t
