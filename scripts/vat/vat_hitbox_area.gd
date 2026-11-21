class_name VATHitboxArea
extends Area3D
## Lightweight capsule hitbox for Full VAT crowd instances.
## Supports both physics projectile body_entered (HitboxZone groups) and direct take_hit() calls.

var spawner: Node = null
var instance_idx: int = -1
var variant_id: int = 0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 4
	monitoring = false
	monitorable = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not (body.is_in_group("player_projectile") or body.is_in_group("bullet") or body.is_in_group("player_attack")):
		return

	var hit_dir := Vector3.ZERO
	if "velocity" in body:
		hit_dir = body.velocity
	elif "linear_velocity" in body:
		hit_dir = body.linear_velocity
	else:
		hit_dir = global_position - body.global_position

	hit_dir.y = 0.0
	if hit_dir.length_squared() > 0.0001:
		hit_dir = hit_dir.normalized()
	else:
		hit_dir = Vector3.BACK

	var local_hit := to_local(body.global_position)
	_dispatch_hit(hit_dir, local_hit)


func take_hit(hit_data: Dictionary) -> void:
	var hit_dir: Vector3 = hit_data.get("hit_direction", Vector3.BACK)
	var local_hit := Vector3(0.0, 1.0, 0.0)
	if hit_data.has("position") and hit_data["position"] is Vector3:
		local_hit = to_local(hit_data["position"])
	_dispatch_hit(hit_dir, local_hit)


func _dispatch_hit(hit_dir: Vector3, local_hit: Vector3) -> void:
	if is_instance_valid(spawner) and instance_idx >= 0:
		spawner.trigger_hit(instance_idx, hit_dir, local_hit, variant_id)
