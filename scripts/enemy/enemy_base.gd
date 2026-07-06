## EnemyBase: root script for a Songkran Hazard 4 enemy (zombie).
class_name EnemyBase
extends CharacterBody3D

# ─── Signals ───────────────────────────────────────────────────────────────
signal health_changed(current_hp: float, max_hp: float)
signal enemy_defeated()
signal enemy_hit(hit_data: Dictionary)

# ─── HP ────────────────────────────────────────────────────────────────────
var MAX_HP: float = 25.0
var current_hp: float = MAX_HP
var _second_chance_used: bool = false
var is_defeated: bool = false
var is_takedown_defeat: bool = false
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
var debug_label: Label3D = null
@export var show_debug_label: bool = false

var next_idle_offset: float = -1.0
var guaranteed_grab_next_attack: bool = false
var selected_attack_type: String = ""
var last_normal_attack: String = ""

var current_target: Node3D = null
var target_update_timer: float = 0.0

# ─── Procedural Animation Properties ───────────────────────────────────────
var last_y_rotation: float = 0.0
var _smoothed_turn_speed: float = 0.0
var _smoothed_angular_velocity: float = 0.0
@export var rotation_tilt_sensitivity: float = 2.0
@export var max_roll_angle: float = 15.0
@export var tilt_speed: float = 5.0

# ─── Hit Reaction Properties ───────────────────────────────────────────────
@export_group("Hit Reaction Stiffness")
@export var head_reaction_stiffness: float = 220.0
@export var body_reaction_stiffness: float = 260.0
@export var arms_reaction_stiffness: float = 220.0
@export var legs_reaction_stiffness: float = 260.0

@export_group("Hit Reaction Damping")
@export var head_reaction_damping: float = 10.0
@export var body_reaction_damping: float = 18.0
@export var arms_reaction_damping: float = 16.0
@export var legs_reaction_damping: float = 18.0

@export var head_reaction_force: float = 26.0
@export var body_reaction_force: float = -7.0
@export var arms_reaction_force: float = -14.0
@export var legs_reaction_force: float = -10.0
@export var legs_knockdown_dampening: float = 0.5

@export_group("Hit Reaction Randomness")
@export var force_randomness_min: float = 0.8
@export var force_randomness_max: float = 1.2
@export var side_offset_min: float = 0.3
@export var side_offset_max: float = 0.6

@export_group("Flipflop Eat Leg Feature")
@export var flipflop_slide_height: float = 0.35
@export var flipflop_slide_speed: float = 1.0
@export var flipflop_rot_x: float = 85.0
@export var flipflop_rot_z: float = 35.0
@export var flipflop_slide_duration: float = 0.8
@export var flipflop_blend_duration: float = 0.6
@export var flipflop_slide_depth: float = 0.06
@export var flipflop_min_height: float = 0.28
@export var flipflop_blend_min_height: float = 0.23
@export var flipflop_blend_min_depth: float = 0.03
@export var flipflop_blend_height_speed: float = 10.0
@export var flipflop_blend_depth_speed: float = 10.0
@export var flipflop_blend_rot_speed: float = 10.0
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
	MAX_HP = float(randi_range(10, 12))
	current_hp = MAX_HP
	is_takedown_defeat = false
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
	# Ensure the root CharacterBody3D is ONLY on Layer 3 (Enemies).
	# Specifically, we clear other layers (like Layer 14 / Hitboxes and Layer 1 / World) 
	# so the weapon raycast passes through the root body capsule to hit the actual hitbox areas.
	collision_layer = 0
	set_collision_layer_value(3, true)
	set_collision_mask_value(3, true)
	# Set Mask 2 (value 2) to ensure zombies collide with the player
	set_collision_mask_value(2, true)
	# Set Mask 5 (value 16) to ensure zombies collide with Anchalee (Follower)
	set_collision_mask_value(5, true)
	# Set Mask 1 (value 1) to ensure zombies collide with the environment/floor
	set_collision_mask_value(1, true)


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
	
	# Create debug label for state display
	if show_debug_label:
		debug_label = Label3D.new()
		debug_label.name = "DebugStateLabel"
		debug_label.position = Vector3(0, 2.3, 0) # Adjust height above the head
		debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		debug_label.no_depth_test = true # Visible through walls for debugging
		debug_label.font_size = 40
		debug_label.outline_size = 10
		debug_label.modulate = Color.YELLOW
		debug_label.outline_modulate = Color.BLACK
		add_child(debug_label)
	
	# Attach scale fix programmatically to GrabHitbox nodes to prevent Jolt Physics warnings
	var scale_fix_script = load("res://scripts/enemy/hitbox_scale_fix.gd")
	for path in [
		"ZombieModel/rig_002/GeneralSkeleton/HitboxAttachChest/GrabHitbox",
		"ZombieModel/rig/GeneralSkeleton/HitboxAttachChest/GrabHitbox",
		"ZombieModel/rig_001/Skeleton3D/HitboxAttachChest/GrabHitbox",
		"All zombie fix/rig_001/Skeleton3D/HitboxAttachChest/GrabHitbox"
	]:
		var node = get_node_or_null(path)
		if node and node is Area3D:
			node.set_script(scale_fix_script)
			node.set_physics_process(true)

	state_machine.initialize("StateIdle")
	state_machine.state_changed.connect(_on_state_changed)
	if debug_label:
		debug_label.text = "State: %s" % state_machine.get_current_state_name()

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
	if is_defeated or is_takedown_defeat:
		return
	print("[EnemyBase] take_hit — zone:'%s' dmg:%d state:%s hp:%d" % [
		hit_data.get("hit_zone", "?"),
		hit_data.get("damage", 0),
		state_machine.get_current_state_name(),
		current_hp
	])
	
	# Trigger procedural hit impact sway
	var is_takedown = (hit_data.get("hit_type") == "takedown_splash" or 
					   (state_machine and state_machine.current_state and state_machine.current_state.name == "StateTakedownable"))
	trigger_impact_sway(is_takedown)

	# Set hit_getup to true if hit during vulnerable getup block
	var is_vulnerable_getup = false
	if state_machine:
		var hunt = state_machine._states.get("StateHunt")
		if hunt and state_machine.current_state == hunt and hunt.has_method("is_in_vulnerable_getup") and hunt.is_in_vulnerable_getup():
			is_vulnerable_getup = true
	
	if is_vulnerable_getup and anim_tree:
		if "parameters/hit/Getup_End/conditions/hit_getup" in anim_tree:
			anim_tree.set("parameters/hit/Getup_End/conditions/hit_getup", true)
		if "parameters/hit/hit_takedown/conditions/hit_getup" in anim_tree:
			anim_tree.set("parameters/hit/hit_takedown/conditions/hit_getup", true)

	var dmg: float = float(hit_data.get("damage", 1.0))
	var zone: String = hit_data.get("hit_zone", "body")
	var hit_type: String = hit_data.get("hit_type", "")

	# Apply zone multiplier only for gunshots
	if hit_type != "takedown" and hit_type != "takedown_splash" and hit_type != "push":
		if zone == "head":
			dmg *= 1.2
		else:
			dmg *= 1.0

	var new_hp: float = current_hp - dmg

	if new_hp <= 0 and not _second_chance_used:
		new_hp = 1.0
		_second_chance_used = true
		_on_second_chance_triggered()

	current_hp = clampf(new_hp, 0.0, MAX_HP)
	health_changed.emit(current_hp, MAX_HP)
	enemy_hit.emit(hit_data)
	state_machine.handle_hit(hit_data)

	if current_hp <= 0:
		var playing_special_takedown = false
		if state_machine and state_machine.current_state:
			var curr = state_machine.current_state
			if curr.name == "StateKnockdown" and curr.has_method("is_playing_special_act3") and curr.is_playing_special_act3():
				playing_special_takedown = true
				
		if hit_type == "takedown" or hit_type == "takedown_splash" or playing_special_takedown:
			is_takedown_defeat = true
		else:
			_trigger_defeat()

func _on_second_chance_triggered() -> void:
	print("[EnemyBase] Second chance triggered!")

func _trigger_defeat() -> void:
	is_defeated = true
	state_machine.transition_to("StateDefeated")
	enemy_defeated.emit()
	_spawn_drops()
	_check_stop_combat_music()
	if is_inside_tree() and get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_kill()

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

	# Randomly drop a bottle (30% chance)
	if randf() < 0.30:
		ItemPickup.instantiate_drop(parent, global_position, "bottle", 1)

func is_takedownable() -> bool:
	if is_defeated:
		return false
	if not state_machine:
		return false
	var current_state = state_machine.current_state
	if current_state == state_machine._states.get("StateTakedownable"):
		return true
	# Also takedownable during the vulnerable getup recovery phase
	var hunt = state_machine._states.get("StateHunt")
	if hunt and current_state == hunt and hunt.has_method("is_in_vulnerable_getup") and hunt.is_in_vulnerable_getup():
		return true
	return false

func trigger_takedown() -> void:
	if not state_machine:
		return
	var td = state_machine._states.get("StateTakedownable")
	if td:
		td.trigger_takedown()

func reset_getup_conditions() -> void:
	if not anim_tree:
		return
	for param in [
		"parameters/hit/Getup_End/conditions/act2_skip",
		"parameters/hit/Getup_End/conditions/hit_getup",
		"parameters/hit/hit_takedown/conditions/hit_getup",
		"parameters/hit/Getup_End/conditions/idle_block"
	]:
		if param in anim_tree:
			anim_tree.set(param, false)
			print("[EnemyBase debug] Resetting parameter: %s to %s" % [param, anim_tree.get(param)])

func _on_state_changed(old_state: String, new_state: String) -> void:
	print("[EnemyBase] State: %s → %s  |  HP: %d/%d" % [old_state, new_state, current_hp, MAX_HP])
	if debug_label:
		debug_label.text = "State: %s\n(%s → %s)" % [new_state, old_state, new_state]

# ─── Navigation ────────────────────────────────────────────────────────────
func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	# Only apply avoidance velocity when the zombie is actively hunting.
	# All other states manage their own velocity and move_and_slide() calls.
	if not state_machine or not state_machine.current_state:
		return
	if state_machine.current_state.name != "StateHunt":
		return
	if state_machine.current_state.is_movement_blocked():
		return
	
	var current_y = velocity.y
	
	# Restrict physical movement strictly to the forward/backward direction they are currently facing
	var forward_dir = -global_transform.basis.z.normalized()
	
	# Determine if we are backing up/fleeing
	var is_fleeing = false
	var current_state = state_machine.current_state
	if current_state.get("_is_fleeing") or current_state.get("_is_fleeing_grab"):
		is_fleeing = true
		
	var move_vector = forward_dir
	if is_fleeing:
		move_vector = -forward_dir
		
	# Project safe_velocity onto the allowed movement vector
	var move_speed = safe_velocity.dot(move_vector)
	var target_vel = move_vector * max(0.0, move_speed)
	
	velocity = velocity.move_toward(target_vel, 8.0)
	velocity.y = current_y
	move_and_slide()

# ─── Procedural Animation ──────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_update_skeleton_tilt(delta)
	
	target_update_timer -= delta
	if target_update_timer <= 0.0:
		target_update_timer = randf_range(1.0, 2.0)
		_update_target()

func _update_skeleton_tilt(delta: float) -> void:
	if not rig: return
	# Enforce clean X and Z rotations on the root body
	rotation.x = 0.0
	rotation.z = 0.0
	
	var current_y_rot = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	var rotation_delta = angle_difference(last_y_rotation, current_y_rot)
	last_y_rotation = current_y_rot
	
	var angular_velocity = 0.0
	if delta > 0.0:
		angular_velocity = rotation_delta / delta
		
	# Clamp angular velocity to reasonable maximum to prevent single-frame spikes
	angular_velocity = clampf(angular_velocity, -PI * 2.0, PI * 2.0)
	
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

func trigger_impact_sway(is_takedown: bool) -> void:
	var skeleton = _find_skeleton(self)
	if skeleton:
		var lean = skeleton.get_node_or_null("EnemyLeanModifier")
		if lean and lean.has_method("trigger_impact_sway"):
			lean.trigger_impact_sway(is_takedown)

func get_current_target() -> Node3D:
	if current_target == null:
		_update_target()
	return current_target

func _update_target() -> void:
	var player = null
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		
	if player == null or player.HP <= 0:
		current_target = null
		return
		
	current_target = player

func _exit_tree() -> void:
	_check_stop_combat_music()

func _check_stop_combat_music() -> void:
	if not is_inside_tree():
		return
	var any_in_combat = false
	var enemies = get_tree().get_nodes_in_group("enemies")
	for other in enemies:
		if is_instance_valid(other) and other != self and not other.is_defeated and other.is_inside_tree():
			var sm = other.get_node_or_null("EnemyStateMachine")
			if sm and sm.current_state:
				var state_name = sm.current_state.name
				if state_name != "StateIdle" and state_name != "StateDefeated":
					any_in_combat = true
					break
	if not any_in_combat:
		var music = get_tree().current_scene.get_node_or_null("MusicPlayer2D")
		if not music:
			music = get_tree().current_scene.get_node_or_null("AudioStreamPlayer2D")
		if music and music is AudioStreamPlayer2D and music.playing:
			music.stop()
			print("No enemies left in combat. Stopping combat music.")
