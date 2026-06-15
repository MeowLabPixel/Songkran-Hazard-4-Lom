## EnemyBase: root script for a Songkran Hazard 4 enemy (zombie).
class_name EnemyBase
extends CharacterBody3D

# ─── Signals ───────────────────────────────────────────────────────────────
signal health_changed(current_hp: int, max_hp: int)
signal enemy_defeated()
signal enemy_hit(hit_data: Dictionary)

# ─── HP ────────────────────────────────────────────────────────────────────
const MAX_HP: int = 25
var current_hp: int = MAX_HP
var _second_chance_used: bool = false
var is_defeated: bool = false

# ─── Drop Table ────────────────────────────────────────────────────────────
@export var drop_table: Array[Dictionary] = [
	{"item_type": "coin", "value": 1, "count_min": 2, "count_max": 4}
]

# ─── References ────────────────────────────────────────────────────────────
@onready var state_machine: EnemyStateMachine = $EnemyStateMachine
@export var anim_set: ZombieAnimSet
var anim_player: AnimationPlayer = null

# ─── Procedural Animation Properties ───────────────────────────────────────
var last_y_rotation: float = 0.0
var _smoothed_turn_speed: float = 0.0
var _smoothed_angular_velocity: float = 0.0
@export var rotation_tilt_sensitivity: float = 2.0
@export var max_roll_angle: float = 15.0
@export var tilt_speed: float = 5.0
var rig: Node3D

func _find_anim_player() -> AnimationPlayer:
	var model := get_node_or_null("ZombieModel")
	if not model:
		push_error("[EnemyBase] ZombieModel node not found")
		return null
	# Check direct child first, then search whole subtree
	var ap := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		return ap
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not ap:
		push_error("[EnemyBase] No AnimationPlayer found under ZombieModel")
	return ap

# ─── Ready ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	current_hp = MAX_HP
	if not anim_set:
		anim_set = ZombieAnimSet.new()
		push_warning("[EnemyBase] anim_set not assigned in Inspector — using defaults")
	anim_player = _find_anim_player()
	if anim_player:
		print("[EnemyBase] AnimationPlayer found: %s" % anim_player.get_path())
		print("[EnemyBase] %d animations available" % anim_player.get_animation_list().size())
	_disable_attack_hitboxes()
	
	# ── Collision Setup ────────────────────────────────────────────────────────
	# Set Layer 3 (value 4) and Mask 3 (value 4) to ensure zombies collide with each other
	set_collision_layer_value(3, true)
	set_collision_mask_value(3, true)

	# ── Navigation Avoidance Setup ─────────────────────────────────────────────
	var nav = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav:
		nav.avoidance_enabled = true
		nav.radius = 0.4
		nav.neighbor_distance = 5.0
		nav.max_neighbors = 10
		nav.max_speed = 5.0
		nav.velocity_computed.connect(_on_nav_velocity_computed)
		
	# ── Procedural Animation Modifiers Setup ───────────────────────────────────
	var skel = _find_skeleton(self)
	if skel:
		rig = skel.get_parent()
		var lean = EnemyLeanModifier.new()
		lean.enemy = self
		lean.name = "EnemyLeanModifier"
		skel.add_child(lean)
		
		var head = EnemyHeadLookAt.new()
		head.enemy = self
		head.name = "EnemyHeadLookAt"
		skel.add_child(head)
	
	state_machine.initialize("StateIdle")
	state_machine.state_changed.connect(_on_state_changed)

func _disable_attack_hitboxes() -> void:
	for skel_base in [
		"ZombieModel/rig_002/GeneralSkeleton",
		"ZombieModel/rig_002/GeneralSkeleton",
		"ZombieModel/rig_002/GeneralSkeleton"
	]:
		for suffix in [
			"/HitboxAttachLeftHand/AttackHitbox",
			"/HitboxAttachRightHand/AttackHitbox",
		]:
			var hitbox := get_node_or_null(skel_base + suffix)
			if hitbox:
				hitbox.monitoring  = false
				hitbox.monitorable = false

# ─── HP / Damage ───────────────────────────────────────────────────────────
func take_hit(hit_data: Dictionary) -> void:
	if is_defeated:
		return
	print("[EnemyBase] take_hit — zone:'%s' dmg:%d state:%s hp:%d" % [
		hit_data.get("hit_zone", "?"),
		hit_data.get("damage", 0),
		state_machine.get_current_state_name(),
		current_hp
	])

	var dmg: int = hit_data.get("damage", 1)
	var new_hp: int = current_hp - dmg

	if new_hp <= 0 and not _second_chance_used:
		new_hp = 1
		_second_chance_used = true
		_on_second_chance_triggered()

	current_hp = clampi(new_hp, 0, MAX_HP)
	health_changed.emit(current_hp, MAX_HP)
	enemy_hit.emit(hit_data)
	state_machine.handle_hit(hit_data)

	if current_hp <= 0:
		_trigger_defeat()

func _on_second_chance_triggered() -> void:
	print("[EnemyBase] Second chance triggered!")

func _trigger_defeat() -> void:
	is_defeated = true
	state_machine.transition_to("StateDefeated")
	enemy_defeated.emit()
	_spawn_drops()

func _spawn_drops() -> void:
	var parent: Node = get_tree().current_scene
	for entry in drop_table:
		var item_type: String = entry.get("item_type", "coin")
		var value: int = entry.get("value", 1)
		var count: int = randi_range(entry.get("count_min", 1), entry.get("count_max", 1))
		for i in count:
			ItemPickup.instantiate_drop(parent, global_position, item_type, value)

func _on_state_changed(old_state: String, new_state: String) -> void:
	print("[EnemyBase] State: %s → %s  |  HP: %d/%d" % [old_state, new_state, current_hp, MAX_HP])

# ─── Navigation ────────────────────────────────────────────────────────────
func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

# ─── Procedural Animation ──────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_update_skeleton_tilt(delta)

func _update_skeleton_tilt(delta: float) -> void:
	if not rig: return
	var current_y_rot = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	var rotation_delta = angle_difference(last_y_rotation, current_y_rot)
	last_y_rotation = current_y_rot
	
	var angular_velocity = 0.0
	if delta > 0.0:
		angular_velocity = rotation_delta / delta
		
	var raw_speed = abs(angular_velocity)
	if raw_speed > _smoothed_turn_speed:
		_smoothed_turn_speed = lerp(_smoothed_turn_speed, raw_speed, delta * 25.0)
	else:
		_smoothed_turn_speed = lerp(_smoothed_turn_speed, raw_speed, delta * 18.0)
		
	_smoothed_angular_velocity = lerp(_smoothed_angular_velocity, angular_velocity, delta * 15.0)
	
	var turn_tilt_deg = -_smoothed_angular_velocity * rotation_tilt_sensitivity
	var turn_tilt_rad = deg_to_rad(turn_tilt_deg)
	
	var target_z = clamp(turn_tilt_rad, deg_to_rad(-max_roll_angle), deg_to_rad(max_roll_angle))
	
	rig.rotation.z = lerp_angle(rig.rotation.z, target_z, delta * tilt_speed)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result: return result
	return null
