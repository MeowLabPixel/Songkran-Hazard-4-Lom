## HitboxZone: attach to an Area3D inside a BoneAttachment3D on the enemy.
## Automatically finds EnemyBase, connects body_entered, and fires take_hit()
## with the correct zone name when a player projectile or player body enters.
##
## Scene structure per zone:
##   BoneAttachment3D  (bone_name set in inspector to the correct skeleton bone)
##   └── Area3D  (collision_layer=2, collision_mask=4)
##       ├── CollisionShape3D
##       └── HitboxZone  <── this script
##
## Valid zone_name values: "head" | "foot" | "right_arm" | "left_arm" | "body"
class_name HitboxZone
extends Node

@export var zone_name: String = "body"
@export var base_damage: int = 5

var _enemy: EnemyBase = null

func _ready() -> void:
	var parent_name = get_parent().name
	if parent_name in ["HitboxLeftThigh", "HitboxLeftShin"]:
		zone_name = "left_leg"
	elif parent_name in ["HitboxRightThigh", "HitboxRightShin"]:
		zone_name = "right_leg"

	# Walk up the full tree, crossing sub-scene boundaries, to find EnemyBase.
	# The hitboxes live inside the ZombieModel sub-scene (zombie_animated.tscn),
	# so we must continue past that Node3D boundary to reach the CharacterBody3D
	# root of enemy.tscn where EnemyBase lives.
	var node: Node = get_parent()
	while node != null:
		if node is EnemyBase:
			_enemy = node
			break
		node = node.get_parent()

	if not _enemy:
		push_error("[HitboxZone] No EnemyBase found above zone '%s' - hitbox must be inside enemy.tscn" % zone_name)
		return

	var area := get_parent() as Area3D
	if area:
		area.body_entered.connect(_on_body_entered)
		area.add_to_group("enemy")
	else:
		push_error("[HitboxZone] Parent must be Area3D (zone '%s')" % zone_name)

func _on_body_entered(body: Node3D) -> void:
	if not (body.is_in_group("player_projectile") or body.is_in_group("bullet") or body.is_in_group("player_attack")):
		return
	_enemy.take_hit({
		"damage": base_damage,
		"hit_zone": zone_name,
		"source": body,
	})
