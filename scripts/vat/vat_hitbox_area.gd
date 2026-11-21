class_name VATHitboxArea
extends Area3D
## Lightweight capsule hitbox for both VAT dancer instances and rigged Gun/Balloon CrowdMembers.
## Supports both physics projectile body_entered (HitboxZone groups) and direct take_hit() calls.

var spawner: Node = null
var instance_idx: int = -1
var variant_id: int = 0
var target_member: Node = null


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
	_dispatch_hit(hit_dir, local_hit, body)


func take_hit(hit_data: Dictionary) -> void:
	var hit_dir: Vector3 = hit_data.get("hit_direction", Vector3.BACK)
	var local_hit := Vector3(0.0, 1.0, 0.0)
	if hit_data.has("position") and hit_data["position"] is Vector3:
		local_hit = to_local(hit_data["position"])
	_dispatch_hit(hit_dir, local_hit, hit_data.get("source"))


func _dispatch_hit(hit_dir: Vector3, local_hit: Vector3, source: Variant) -> void:
	if is_instance_valid(target_member):
		if is_instance_valid(spawner) and spawner.has_method("trigger_specialist_hit"):
			spawner.trigger_specialist_hit(target_member, hit_dir, to_global(local_hit))
		elif target_member.has_method("take_hit"):
			target_member.take_hit({
				"damage": 5,
				"hit_zone": _resolve_zone_name(local_hit),
				"source": source,
				"hit_direction": hit_dir,
				"position": to_global(local_hit),
			})
	elif is_instance_valid(spawner) and instance_idx >= 0:
		spawner.trigger_hit(instance_idx, hit_dir, local_hit, variant_id)


func _resolve_zone_name(local_hit: Vector3) -> String:
	if local_hit.y >= 1.35:
		return "head"
	if local_hit.y <= 0.45:
		return "left_foot" if local_hit.x < 0.0 else "right_foot"
	if local_hit.y <= 0.78:
		return "left_leg" if local_hit.x < 0.0 else "right_leg"
	if absf(local_hit.x) >= 0.22:
		return "left_arm" if local_hit.x < 0.0 else "right_arm"
	return "body"
