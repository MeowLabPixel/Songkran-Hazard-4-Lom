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
@tool
class_name HitboxZone
extends Node

@export var zone_name: String = "body"
@export var base_damage: int = 5

var _enemy: EnemyBase = null
var _anchalee: AnchaleeBase = null
var _attachment: BoneAttachment3D = null

func _ready() -> void:
	var parent_name = get_parent().name
	if parent_name == "HitboxLeftThigh":
		zone_name = "left_leg"
	elif parent_name == "HitboxLeftShin":
		zone_name = "left_foot"
	elif parent_name == "HitboxRightThigh":
		zone_name = "right_leg"
	elif parent_name == "HitboxRightShin":
		zone_name = "right_foot"

	# Walk up the full tree, crossing sub-scene boundaries, to find EnemyBase or AnchaleeBase.
	var node: Node = get_parent()
	while node != null:
		if node is EnemyBase:
			_enemy = node
			break
		elif node is AnchaleeBase:
			_anchalee = node
			break
		node = node.get_parent()

	if not _enemy and not _anchalee:
		push_error("[HitboxZone] No EnemyBase or AnchaleeBase found above zone '%s'" % zone_name)
		return

	var area := get_parent() as Area3D
	if area:
		_sanitize_scale(area)
		
		# Find the Skeleton3D and the corresponding BoneAttachment3D node
		var skeleton: Skeleton3D = null
		var root_node = _enemy if _enemy else _anchalee
		if root_node:
			var s_nodes = [root_node]
			while s_nodes.size() > 0:
				var curr = s_nodes.pop_back()
				if curr is Skeleton3D:
					skeleton = curr
					break
				s_nodes.append_array(curr.get_children())
			
		if skeleton:
			var suffix = parent_name.replace("Hitbox", "")
			if parent_name == "HitboxRightArm":
				suffix = "RightForeArm"
			elif parent_name == "HitboxLeftArm":
				suffix = "LeftForeArm"
			elif parent_name == "HitboxUpperRightArm":
				suffix = "RightUpperArm"
			elif parent_name == "HitboxUpperLeftArm":
				suffix = "LeftUpperArm"
			
			var attach_name = "HitboxAttach" + suffix
			_attachment = skeleton.get_node_or_null(attach_name)
			# Also search recursively for Anchalee-style rigs where the attachment
			# lives under RetargetModifier3D/OriginalSkeleton
			if not _attachment:
				_attachment = skeleton.find_child(attach_name, true, false)
		
		area.body_entered.connect(_on_body_entered)
		if _enemy:
			area.add_to_group("enemy")
		elif _anchalee:
			area.add_to_group("anchalee_hitbox")
			
		# Reparent to BoneAttachment3D at runtime to eliminate one-frame lag
		if not Engine.is_editor_hint() and _attachment and area.get_parent() != _attachment:
			_reparent_to_attachment.call_deferred(area, _attachment)
	else:
		push_error("[HitboxZone] Parent must be Area3D (zone '%s')" % zone_name)

func _notification(what: int) -> void:
	if what == Node3D.NOTIFICATION_LOCAL_TRANSFORM_CHANGED or what == Node3D.NOTIFICATION_TRANSFORM_CHANGED:
		var area := get_parent() as Area3D
		_sanitize_scale(area)

func _process(_delta: float) -> void:
	var area := get_parent() as Area3D
	_sanitize_scale(area)

func _physics_process(_delta: float) -> void:
	var area := get_parent() as Area3D
	_sanitize_scale(area)

func _sanitize_scale(area: Area3D) -> void:
	if not area or not area.is_inside_tree():
		return
	area.top_level = true
	var source: Node3D = _attachment if is_instance_valid(_attachment) else (area.get_parent() as Node3D)
	if source:
		var t := source.global_transform
		t.basis = t.basis.orthonormalized()
		area.global_transform = t
	else:
		var t := area.global_transform
		t.basis = t.basis.orthonormalized()
		area.global_transform = t

func _on_body_entered(body: Node3D) -> void:
	if not (body.is_in_group("player_projectile") or body.is_in_group("bullet") or body.is_in_group("player_attack")):
		return
	
	var hit_dir: Vector3 = Vector3.ZERO
	var target = _enemy if _enemy else _anchalee
	if "velocity" in body:
		hit_dir = body.velocity.normalized()
	elif "linear_velocity" in body:
		hit_dir = body.linear_velocity.normalized()
	else:
		if target:
			hit_dir = (target.global_position - body.global_position).normalized()
	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()

	if target:
		target.take_hit({
			"damage": base_damage,
			"hit_zone": zone_name,
			"source": body,
			"hit_direction": hit_dir,
		})

func _reparent_to_attachment(area: Area3D, attachment: BoneAttachment3D) -> void:
	if not is_instance_valid(area) or not is_instance_valid(attachment):
		return
	var old_global_trans = area.global_transform
	var old_parent = area.get_parent()
	if old_parent:
		old_parent.remove_child(area)
	attachment.add_child(area)
	area.global_transform = old_global_trans
