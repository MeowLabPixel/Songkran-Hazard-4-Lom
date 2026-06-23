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
class_name PlayerHitboxZone
extends Node

@export var zone_name: String = "body"
@export var base_damage: int = 5


signal Grabbed(area: Area3D)
signal Attacked

var _player: Player = null

func _ready() -> void:
	var node: Node = get_parent()
	while node != null:
		if node is Player:
			_player = node
			break
		node = node.get_parent()

	if not _player:
		push_error("[PlayerHitboxZone] No Player found above zone '%s'" % zone_name)
		return

	var area := get_parent() as Area3D
	if not area:
		push_error("[PlayerHitboxZone] Parent must be Area3D (zone '%s')" % zone_name)
		return

	# Register this Area3D in the player_hitbox group so enemy _hand_touches_player()
	# can find it via get_overlapping_areas().
	if not area.is_in_group("player_hitbox"):
		area.add_to_group("player_hitbox")

	# Layer 4 (value 8):  player hitboxes — what enemy attack hitboxes scan for.
	# Layer 5 (value 16): enemy attack hitboxes — what we scan for via area_entered.
	area.collision_layer = 8   # layer 4: we exist on this layer
	area.collision_mask  = 16  # layer 5: we detect enemy AttackHitbox areas
	area.monitorable     = true
	area.monitoring      = true

	area.area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("enemy_attack"):
		return

	var attack_type := "attack"

	if area is AttackHitbox:
		attack_type = area.attack_type

	match attack_type:
		"grab":
			print("Player grabbed!")
			# Emit the area that caused the grab so the player can identify the grabber
			Grabbed.emit(area)
		"attack":
			print("Player attacked!")
			Attacked.emit()
			# DO NOT call _player.take_damage here! 
			# The enemy's state_attack.gd script already detects the hit and calls _player.take_damage(attack_damage)
			# If we call it here too, the player takes double damage (or 1 extra damage per hitbox touched)!
			# _player.take_damage(base_damage)
