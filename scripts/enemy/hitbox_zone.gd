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
var _merchant: Merchant = null
var _attachment: BoneAttachment3D = null
var _target_entity: Node = null
var _area: Area3D = null

func get_target() -> Node:
	if _enemy: return _enemy
	if _anchalee: return _anchalee
	if _merchant: return _merchant
	if _target_entity: return _target_entity
	return null

func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(false)
		return
	var parent_name = get_parent().name
	if parent_name == "HitboxLeftThigh":
		zone_name = "left_leg"
	elif parent_name == "HitboxLeftShin" or parent_name == "HitboxLeftFoot":
		zone_name = "left_foot"
	elif parent_name == "HitboxRightThigh":
		zone_name = "right_leg"
	elif parent_name == "HitboxRightShin" or parent_name == "HitboxRightFoot":
		zone_name = "right_foot"
	elif parent_name in ["HitboxUpperLeftArm", "HitboxLeftArm", "HitboxLeftHand"]:
		zone_name = "left_arm"
	elif parent_name in ["HitboxUpperRightArm", "HitboxRightArm", "HitboxRightHand"]:
		zone_name = "right_arm"
	elif parent_name == "HitboxHead":
		zone_name = "head"
	elif parent_name in ["HitboxChest", "HitboxWaist", "HitboxPelvis"]:
		zone_name = "body"

	# Walk up the full tree, crossing sub-scene boundaries, to find EnemyBase, AnchaleeBase, Merchant, or any entity with take_hit.
	var node: Node = get_parent()
	while node != null:
		if node is EnemyBase:
			_enemy = node
			break
		elif node is AnchaleeBase:
			_anchalee = node
			break
		elif node is Merchant:
			_merchant = node
			break
		elif node.has_method("take_hit"):
			_target_entity = node
			break
		elif node is CharacterBody3D and (node.name.begins_with("Crowd") or node.name.begins_with("Male") or node.name.begins_with("Female")):
			_target_entity = node
			break
		node = node.get_parent()

	var area := get_parent() as Area3D
	if not area:
		push_error("[HitboxZone] Parent must be Area3D (zone '%s')" % zone_name)
		return
	_area = area

	_sanitize_scale(area)
	
	# Find the Skeleton3D and the corresponding BoneAttachment3D node
	var skeleton: Skeleton3D = null
	var root_node = get_target()
	if not root_node:
		root_node = owner if owner else (area.get_parent().get_parent() if area.get_parent() else null)

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
	
	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)
	var is_standard_entity = (_enemy != null or _anchalee != null or _merchant != null)
	if _enemy:
		area.add_to_group("enemy")
	elif _anchalee:
		area.add_to_group("anchalee_hitbox")
	elif _merchant:
		area.add_to_group("merchant_hitbox")
	else:
		area.add_to_group("crowd_hitbox")
		area.monitoring = false
		if not Engine.is_editor_hint():
			set_physics_process(false)
		
	# Reparent to BoneAttachment3D at runtime to eliminate one-frame lag only for standard enemies/Anchalee/Merchant (never reparent crowd members)
	if not Engine.is_editor_hint() and _attachment and area.get_parent() != _attachment and is_standard_entity:
		_reparent_to_attachment.call_deferred(area, _attachment)

	if not Engine.is_editor_hint() and not get_target() and is_standard_entity:
		push_warning("[HitboxZone] No EnemyBase, AnchaleeBase, Merchant, or target with take_hit found above zone '%s'" % zone_name)

func sync_now() -> void:
	var area := _area if is_instance_valid(_area) else (get_parent() as Area3D)
	_sanitize_scale(area)

func _resolve_attachment_if_needed() -> void:
	if is_instance_valid(_attachment):
		return
	var area := get_parent() as Area3D
	if not area:
		return
	var root_node = get_target()
	if not root_node:
		root_node = owner if owner else (area.get_parent().get_parent() if area.get_parent() else null)
	if not root_node:
		return
	var skeleton: Skeleton3D = null
	var s_nodes = [root_node]
	while s_nodes.size() > 0:
		var curr = s_nodes.pop_back()
		if curr is Skeleton3D:
			skeleton = curr
			break
		s_nodes.append_array(curr.get_children())
	if skeleton:
		var parent_name = area.name
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
		if not _attachment:
			_attachment = skeleton.find_child(attach_name, true, false)

func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(_enemy) or is_instance_valid(_anchalee) or is_instance_valid(_merchant):
		if what == Node3D.NOTIFICATION_LOCAL_TRANSFORM_CHANGED or what == Node3D.NOTIFICATION_TRANSFORM_CHANGED:
			var area := _area if is_instance_valid(_area) else (get_parent() as Area3D)
			_sanitize_scale(area)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not (is_instance_valid(_enemy) or is_instance_valid(_anchalee) or is_instance_valid(_merchant)):
		set_physics_process(false)
		return
	var area := _area if is_instance_valid(_area) else (get_parent() as Area3D)
	_sanitize_scale(area)

func _sanitize_scale(area: Area3D) -> void:
	if not area or not area.is_inside_tree():
		return
	if not is_instance_valid(_attachment):
		_resolve_attachment_if_needed()
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
	var target = get_target()
	if "velocity" in body:
		hit_dir = body.velocity.normalized()
	elif "linear_velocity" in body:
		hit_dir = body.linear_velocity.normalized()
	else:
		if target and target is Node3D:
			hit_dir = (target.global_position - body.global_position).normalized()
	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()

	if target and target.has_method("take_hit"):
		target.take_hit({
			"damage": base_damage,
			"hit_zone": zone_name,
			"source": body,
			"hit_direction": hit_dir,
		})
		
		# Trigger camera shake on confirmed weakpoint hit ONLY if mode is WEAKPOINT_ONLY
		var zn = str(zone_name).to_lower()
		if zn == "head" or zn == "weakpoint" or zn == "weak" or ("head" in zn) or ("weak" in zn) or ("foot" in zn) or ("feet" in zn) or ("leg" in zn):
			var cams = get_tree().get_nodes_in_group("player_camera") if get_tree() else []
			for cam in cams:
				if ("camera_shake_mode" in cam) and cam.camera_shake_mode == cam.CameraShakeMode.WEAKPOINT_ONLY:
					if cam.has_method("trigger_weakpoint_shake"):
						cam.trigger_weakpoint_shake()

func _reparent_to_attachment(area: Area3D, attachment: BoneAttachment3D) -> void:
	if not is_instance_valid(area) or not is_instance_valid(attachment):
		return
	var old_global_trans = area.global_transform
	var old_parent = area.get_parent()
	if old_parent == attachment:
		return
	if old_parent:
		old_parent.remove_child(area)
	attachment.add_child(area)
	area.global_transform = old_global_trans
	_sanitize_scale(area)
