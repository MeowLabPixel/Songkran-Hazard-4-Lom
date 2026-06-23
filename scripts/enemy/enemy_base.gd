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
var attack_blocked: bool = false  # Set true to prevent this zombie from entering attack state
var last_attack_time: float = -100.0

# ─── Drop Table ────────────────────────────────────────────────────────────
@export var drop_table: Array[Dictionary] = [
	{"item_type": "coin", "value": 1, "count_min": 2, "count_max": 4}
]

# ─── References ────────────────────────────────────────────────────────────
@onready var state_machine: EnemyStateMachine = $EnemyStateMachine
@export var anim_set: ZombieAnimSet
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null

var next_idle_offset: float = -1.0
var guaranteed_grab_next_attack: bool = false

# ─── Procedural Animation Properties ───────────────────────────────────────
var last_y_rotation: float = 0.0
var _smoothed_turn_speed: float = 0.0
var _smoothed_angular_velocity: float = 0.0
@export var rotation_tilt_sensitivity: float = 2.0
@export var max_roll_angle: float = 15.0
@export var tilt_speed: float = 5.0

# ─── Hit Reaction Properties ───────────────────────────────────────────────
@export_group("Hit Reaction Stiffness")
@export var head_reaction_stiffness: float = 260.0
@export var body_reaction_stiffness: float = 260.0
@export var arms_reaction_stiffness: float = 220.0
@export var legs_reaction_stiffness: float = 240.0

@export_group("Hit Reaction Damping")
@export var head_reaction_damping: float = 18.0
@export var body_reaction_damping: float = 18.0
@export var arms_reaction_damping: float = 16.0
@export var legs_reaction_damping: float = 18.0

@export var head_reaction_force: float = 26.0
@export var body_reaction_force: float = -6.0
@export var arms_reaction_force: float = -14.0
@export var legs_reaction_force: float = -10.0
@export var legs_knockdown_dampening: float = 0.5

@export_group("Hit Reaction Randomness")
@export var force_randomness_min: float = 0.8
@export var force_randomness_max: float = 1.2
@export var side_offset_min: float = 0.3
@export var side_offset_max: float = 0.6

@export_group("Flipflop Eat Leg Feature")
@export var flipflop_slide_height: float = 0.38
@export var flipflop_slide_speed: float = 2.0
@export var flipflop_rot_x: float = 85.0
@export var flipflop_rot_z: float = 35.0
@export var flipflop_slide_duration: float = 1.0
@export var flipflop_blend_duration: float = 0.4
@export var flipflop_slide_depth: float = 0.06
@export var flipflop_min_height: float = 0.28
@export var flipflop_blend_min_height: float = 0.00
@export var flipflop_blend_min_depth: float = 0.00
@export var flipflop_blend_height_speed: float = 1.0
@export var flipflop_blend_depth_speed: float = 1.0
@export var flipflop_blend_rot_speed: float = 1.0
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
	add_to_group("enemies")
	current_hp = MAX_HP
	if not anim_set:
		anim_set = ZombieAnimSet.new()
		push_warning("[EnemyBase] anim_set not assigned in Inspector — using defaults")
	anim_player = _find_anim_player()
	anim_tree = get_node_or_null("ZombieModel/AnimationTree") as AnimationTree
	
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
		nav.radius = 0.5
		nav.neighbor_distance = 10.0
		nav.max_neighbors = 10
		nav.max_speed = 3.0
		nav.time_horizon_agents = 2.0 # They look 2 seconds ahead to steer earlier and smoother
		nav.avoidance_enabled = true
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

		var hit_react = EnemyHitReactionModifier.new()
		hit_react.enemy = self
		hit_react.name = "EnemyHitReactionModifier"
		
		# Copy inspector adjustable settings
		hit_react.head_stiffness = head_reaction_stiffness
		hit_react.head_damping = head_reaction_damping
		hit_react.head_force = head_reaction_force
		
		hit_react.body_stiffness = body_reaction_stiffness
		hit_react.body_damping = body_reaction_damping
		hit_react.body_force = body_reaction_force
		
		hit_react.arms_stiffness = arms_reaction_stiffness
		hit_react.arms_damping = arms_reaction_damping
		hit_react.arms_force = arms_reaction_force
		
		hit_react.legs_stiffness = legs_reaction_stiffness
		hit_react.legs_damping = legs_reaction_damping
		hit_react.legs_force = legs_reaction_force
		hit_react.legs_knockdown_dampening = legs_knockdown_dampening
		
		# Copy randomness settings
		hit_react.force_randomness_min = force_randomness_min
		hit_react.force_randomness_max = force_randomness_max
		hit_react.side_offset_min = side_offset_min
		hit_react.side_offset_max = side_offset_max
		
		# Copy flip-flop settings
		hit_react.flipflop_slide_height = flipflop_slide_height
		hit_react.flipflop_slide_speed = flipflop_slide_speed
		hit_react.flipflop_rot_x = flipflop_rot_x
		hit_react.flipflop_rot_z = flipflop_rot_z
		hit_react.flipflop_blend_duration = flipflop_blend_duration
		hit_react.flipflop_slide_duration = flipflop_slide_duration
		hit_react.flipflop_slide_depth = flipflop_slide_depth
		hit_react.flipflop_min_height = flipflop_min_height
		hit_react.flipflop_blend_min_height = flipflop_blend_min_height
		hit_react.flipflop_blend_min_depth = flipflop_blend_min_depth
		hit_react.flipflop_blend_height_speed = flipflop_blend_height_speed
		hit_react.flipflop_blend_depth_speed = flipflop_blend_depth_speed
		hit_react.flipflop_blend_rot_speed = flipflop_blend_rot_speed
		
		skel.add_child(hit_react)
	
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

# --- Animation Event Hooks ---
# Call these from AnimationPlayer Method Tracks on the root node

func open_hitboxes() -> void:
	if state_machine.has_method("open_hitboxes"):
		state_machine.open_hitboxes()

func close_hitboxes() -> void:
	if state_machine.has_method("close_hitboxes"):
		state_machine.close_hitboxes()

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
	# Only apply avoidance velocity when the zombie is actively hunting.
	# All other states manage their own velocity and move_and_slide() calls.
	if not state_machine or not state_machine.current_state:
		return
	if state_machine.current_state.name != "StateHunt":
		return
	
	var current_y = velocity.y
	velocity = velocity.move_toward(safe_velocity, 0.25)
	velocity.y = current_y
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
