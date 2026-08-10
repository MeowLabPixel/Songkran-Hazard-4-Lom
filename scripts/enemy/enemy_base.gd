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
var last_hit_zone: String = "body"
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

@export_group("Voice Config")
@export_enum("Zombie Male", "Zombie Female") var voice_character: String = "Zombie Male"
@export var face_controller: ZombieFaceController
var custom_pitch_scale: float = 1.0
var _last_voice_gethit_time: float = -100.0
var _last_takedown_hit_time: float = -100.0

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
var _walk_markers: Array[float] = [0.5, 1.0]
var _enemy_meshes: Array[MeshInstance3D] = []
var _takedown_aura_alpha: float = 0.0
var _left_hand_aura_alpha: float = 0.0
var _right_hand_aura_alpha: float = 0.0
var _aura_fade_speed: float = 4.0

var _takedown_aura_material: ShaderMaterial = null
var _left_hand_aura_material: ShaderMaterial = null
var _right_hand_aura_material: ShaderMaterial = null
var _takedown_last_mask_dir: int = 0
var current_attack_type: String = ""
var _dead_walk_markers: Array[float] = [0.5, 1.0]
var _last_norm_pos: float = -1.0
var _last_step_time: int = 0

# ─── Act 3 Game Juice Variables ────────────────────────────────────────────
var _model_juice_tween: Tween = null
var _model_juice_shake_timer: float = 0.0
var _model_juice_shake_duration: float = 0.0
var _model_juice_shake_amp: float = 0.0
var _model_juice_shake_freq: float = 24.0
var _model_original_pos: Vector3 = Vector3.ZERO
var _model_original_scale: Vector3 = Vector3.ONE
var _has_stored_model_baseline: bool = false


func _get_footstep_markers(anim_player: AnimationPlayer, anim_name: String) -> Array[float]:
	var result: Array[float] = [0.5, 1.0]
	if not anim_player or not anim_player.has_animation(anim_name):
		return result
	var anim_res = anim_player.get_animation(anim_name)
	if not anim_res:
		return result
		
	var markers = anim_res.get_marker_names()
	if markers.size() > 0:
		var temp: Array[float] = []
		var length = anim_res.length
		if length <= 0.0:
			length = 1.0
		for m_name in markers:
			if "step" in String(m_name).to_lower():
				var t = anim_res.get_marker_time(m_name)
				temp.append(fmod(t / length, 1.0))
		if temp.size() > 0:
			temp.sort()
			result = temp
	return result

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
	if not face_controller:
		face_controller = get_node_or_null("ZombieFaceController") as ZombieFaceController
		if not face_controller:
			face_controller = find_child("ZombieFaceController", true, false) as ZombieFaceController
	# Choose a persistent randomized pitch modifier for this zombie instance's voice
	const PITCH_INCREMENTS = [1.0, 1.05, 1.10, 1.15]
	custom_pitch_scale = PITCH_INCREMENTS.pick_random()
	
	add_to_group("enemies")
	MAX_HP = float(randi_range(10, 12))
	current_hp = MAX_HP
	is_takedown_defeat = false
	if not anim_set:
		anim_set = ZombieAnimSet.new()
		push_warning("[EnemyBase] anim_set not assigned in Inspector — using defaults")
	anim_player = _find_anim_player()
	if anim_player:
		_walk_markers = _get_footstep_markers(anim_player, anim_set.walk_anim)
		_dead_walk_markers = _get_footstep_markers(anim_player, anim_set.dead_walk)
	anim_tree = get_node_or_null("ZombieModel/AnimationTree") as AnimationTree
	
	if anim_player and show_debug_label:
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

	# Cache all MeshInstance3Ds for shader effects
	_find_meshes_recursive(self, _enemy_meshes)

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
		
	var time_now = Time.get_ticks_msec() / 1000.0
	var hit_type_check: String = hit_data.get("hit_type", "")
	if hit_type_check in ["takedown", "takedown_splash"]:
		if time_now - _last_takedown_hit_time < 0.5:
			return
		_last_takedown_hit_time = time_now

	# Play pain voiceline and hit SFX for non-takedown hits (takedowns use dedicated ZombieGetHitTakedown SFX)
	if time_now - _last_voice_gethit_time >= 0.05:
		_last_voice_gethit_time = time_now
		if hit_type_check not in ["takedown", "takedown_splash"]:
			play_takedown_launch_voiceline()
			SoundManager.play_3d("zombie_melee_hit", self)


	if show_debug_label:
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

	if face_controller:
		var hit_z = String(hit_data.get("hit_zone", "")).to_lower()
		var hit_t = String(hit_data.get("hit_type", "")).to_lower()
		var duration = 1.0
		if hit_t in ["takedown", "takedown_splash"] or is_takedown:
			duration = 2.5
		elif hit_z == "head":
			duration = 2.0
		face_controller.notify_hit(duration)

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
	last_hit_zone = zone

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
	if show_debug_label:
		print("[EnemyBase] Second chance triggered!")

func _trigger_defeat() -> void:
	is_defeated = true
	custom_pitch_scale = 1.0
	state_machine.transition_to("StateDefeated")
	enemy_defeated.emit()
	
	var is_game_over = false
	if get_tree().root.has_node("GameManager"):
		is_game_over = get_tree().root.get_node("GameManager").is_game_ended
		
	if not is_game_over:
		_spawn_drops()
		_check_stop_combat_music()
		if is_inside_tree():
			var ui = get_tree().get_first_node_in_group("player_ui")
			var spawn_pos = _get_zone_bone_position(last_hit_zone)
			if ui:
				if ui.has_method("spawn_defeat_shockwave"):
					ui.spawn_defeat_shockwave(spawn_pos)
				if ui.has_method("spawn_kill_projectile"):
					ui.spawn_kill_projectile(spawn_pos)
			if get_tree().root.has_node("GameManager"):
				get_tree().root.get_node("GameManager").register_kill(is_takedown_defeat)
	else:
		_check_stop_combat_music()

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
		return current_state.is_takedown_window_active() if current_state.has_method("is_takedown_window_active") else true
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
			if show_debug_label:
				print("[EnemyBase debug] Resetting parameter: %s to %s" % [param, anim_tree.get(param)])

func _on_state_changed(old_state: String, new_state: String) -> void:
	if show_debug_label:
		print("[EnemyBase] State: %s → %s  |  HP: %d/%d" % [old_state, new_state, current_hp, MAX_HP])
	if debug_label:
		debug_label.text = "State: %s\n(%s → %s)" % [new_state, old_state, new_state]

	if new_state == "StateTakedownable":
		# Do not spawn takedown indicator shockwave if we were just hit by a takedown attack (e.g. splash/domino hit)
		var time_now = Time.get_ticks_msec() / 1000.0
		var time_since_takedown = time_now - _last_takedown_hit_time
		if time_since_takedown > 0.5 and not is_takedown_defeat:
			var ui = get_tree().get_first_node_in_group("player_ui")
			if ui and ui.has_method("spawn_takedown_shockwave"):
				var stun_bone = "DEF-spine.006" # Default to head
				if state_machine:
					var td = state_machine._states.get("StateTakedownable")
					if td:
						if td.stun_type == "left_foot":
							stun_bone = "DEF-foot.L"
						elif td.stun_type == "right_foot":
							stun_bone = "DEF-foot.R"
							
				var spawn_pos = global_position
				var skeleton = _find_skeleton(self)
				if skeleton:
					var bone_idx = skeleton.find_bone(stun_bone)
					if bone_idx != -1:
						spawn_pos = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx).origin
						
				ui.spawn_takedown_shockwave(spawn_pos)

func _find_meshes_recursive(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, meshes)

func _update_aura_overlays(delta: float) -> void:
	# 1. Update targets based on current state
	var target_takedown = 0.0
	if state_machine:
		var td = state_machine._states.get("StateTakedownable")
		if td and state_machine.current_state == td:
			target_takedown = 1.0
			if td.stun_type == "head":
				_takedown_last_mask_dir = 1 # Upper half only
			else:
				_takedown_last_mask_dir = 2 # Lower half only (foot/leg shots)
	
	var active_attack = get_active_attack_type()
	var target_left = 1.0 if (active_attack == "attack_2" or active_attack == "attack_grab") else 0.0
	var target_right = 1.0 if (active_attack == "attack_1" or active_attack == "attack_grab") else 0.0
	
	# 2. Interpolate alphas
	_takedown_aura_alpha = move_toward(_takedown_aura_alpha, target_takedown, delta * _aura_fade_speed)
	_left_hand_aura_alpha = move_toward(_left_hand_aura_alpha, target_left, delta * _aura_fade_speed)
	_right_hand_aura_alpha = move_toward(_right_hand_aura_alpha, target_right, delta * _aura_fade_speed)
	
	# 3. Create materials on demand
	var shader = null
	if _takedown_aura_alpha > 0.0 and not _takedown_aura_material:
		shader = load("res://shaders/takedown_aura.gdshader")
		if shader:
			_takedown_aura_material = ShaderMaterial.new()
			_takedown_aura_material.shader = shader
			_takedown_aura_material.set_shader_parameter("pink_color", Color(1.0, 1.0, 1.0, 1.0))
			_takedown_aura_material.set_shader_parameter("blue_color", Color(0.8, 0.85, 0.95, 1.0))
			# Make it a little bit smaller (user requested)
			_takedown_aura_material.set_shader_parameter("aura_scale", 0.025)
	if _left_hand_aura_alpha > 0.0 and not _left_hand_aura_material:
		if not shader:
			shader = load("res://shaders/takedown_aura.gdshader")
		if shader:
			_left_hand_aura_material = ShaderMaterial.new()
			_left_hand_aura_material.shader = shader
			_left_hand_aura_material.set_shader_parameter("pink_color", Color(1.0, 0.07, 0.57, 1.0))
			_left_hand_aura_material.set_shader_parameter("blue_color", Color(0.0, 0.75, 1.0, 1.0))
	if _right_hand_aura_alpha > 0.0 and not _right_hand_aura_material:
		if not shader:
			shader = load("res://shaders/takedown_aura.gdshader")
		if shader:
			_right_hand_aura_material = ShaderMaterial.new()
			_right_hand_aura_material.shader = shader
			_right_hand_aura_material.set_shader_parameter("pink_color", Color(1.0, 0.07, 0.57, 1.0))
			_right_hand_aura_material.set_shader_parameter("blue_color", Color(0.0, 0.75, 1.0, 1.0))
			
	# Update Shader uniform alpha values
	if _takedown_aura_material:
		_takedown_aura_material.set_shader_parameter("alpha_val", _takedown_aura_alpha)
		_takedown_aura_material.set_shader_parameter("mask_direction", _takedown_last_mask_dir)
	if _left_hand_aura_material:
		_left_hand_aura_material.set_shader_parameter("alpha_val", _left_hand_aura_alpha)
	if _right_hand_aura_material:
		_right_hand_aura_material.set_shader_parameter("alpha_val", _right_hand_aura_alpha)
		
	# 4. Assign overlays based on priorities
	for mesh in _enemy_meshes:
		if not is_instance_valid(mesh):
			continue
			
		var is_left = _is_left_hand_mesh(mesh)
		var is_right = _is_right_hand_mesh(mesh)
		
		if is_left:
			if _takedown_aura_alpha > 0.0:
				mesh.material_overlay = _takedown_aura_material
			elif _left_hand_aura_alpha > 0.0:
				mesh.material_overlay = _left_hand_aura_material
			else:
				mesh.material_overlay = null
		elif is_right:
			if _takedown_aura_alpha > 0.0:
				mesh.material_overlay = _takedown_aura_material
			elif _right_hand_aura_alpha > 0.0:
				mesh.material_overlay = _right_hand_aura_material
			else:
				mesh.material_overlay = null
		else:
			# Non-hand body parts
			if _takedown_aura_alpha > 0.0:
				mesh.material_overlay = _takedown_aura_material
			else:
				mesh.material_overlay = null

func get_active_attack_type() -> String:
	# If in StateAttack, check current_attack_type
	if state_machine and state_machine.current_state and state_machine.current_state.name == "StateAttack":
		return current_attack_type
	
	# If preparing (has token in StateHunt)
	var token_manager = get_node_or_null("/root/AttackTokenManager")
	if token_manager:
		if token_manager.has_grab_token(self):
			return "attack_grab"
		if token_manager.has_token(self):
			return selected_attack_type
		
	return ""

func _is_left_hand_mesh(mesh: MeshInstance3D) -> bool:
	var name_lower = mesh.name.to_lower()
	return "left_hand" in name_lower or "left_ hand" in name_lower

func _is_right_hand_mesh(mesh: MeshInstance3D) -> bool:
	var name_lower = mesh.name.to_lower()
	return "right_hand" in name_lower or "right_ hand" in name_lower

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
	_update_act3_mesh_juice(delta)
	_update_aura_overlays(delta)
	_update_skeleton_tilt(delta)

	
	target_update_timer -= delta
	if target_update_timer <= 0.0:
		target_update_timer = randf_range(1.0, 2.0)
		_update_target()

	# Process footstep sound logic based on animation play position and loaded markers
	if not is_defeated:
		if anim_tree and anim_tree.active:
			var pb = anim_tree.get("parameters/playback")
			if pb:
				var current_node = pb.get_current_node()
				if current_node == anim_set.walk_anim or current_node == anim_set.dead_walk:
					var is_moving = Vector2(velocity.x, velocity.z).length_squared() > 0.05
					if is_moving:
						var length = 1.0 # Walk and DeadWalk animations are 1.0s cycles
						var play_pos = pb.get_current_play_position()
						var norm_pos = fmod(play_pos / length, 1.0)
						
						var active_markers = _dead_walk_markers if current_node == anim_set.dead_walk else _walk_markers
						
						# Check crossings for each marker
						if _last_norm_pos >= 0.0:
							for marker_ratio in active_markers:
								if _last_norm_pos > norm_pos: # Wrap around!
									if _last_norm_pos < marker_ratio or norm_pos >= marker_ratio:
										var now = Time.get_ticks_msec()
										if now - _last_step_time > 220:
											_last_step_time = now
											SoundManager.play_3d("zombie_footstep", self, 0.0, -1.0, custom_pitch_scale)
										break
								else:
									if _last_norm_pos < marker_ratio and norm_pos >= marker_ratio:
										var now = Time.get_ticks_msec()
										if now - _last_step_time > 220:
											_last_step_time = now
											SoundManager.play_3d("zombie_footstep", self, 0.0, -1.0, custom_pitch_scale)
										break
						_last_norm_pos = norm_pos
					else:
						if _last_norm_pos >= 0.0:
							var now = Time.get_ticks_msec()
							if now - _last_step_time > 220:
								_last_step_time = now
								SoundManager.play_3d("zombie_footstep", self, 0.0, -1.0, custom_pitch_scale)
						_last_norm_pos = -1.0
				else:
					if _last_norm_pos >= 0.0:
						var now = Time.get_ticks_msec()
						if now - _last_step_time > 220:
							_last_step_time = now
							SoundManager.play_3d("zombie_footstep", self, 0.0, -1.0, custom_pitch_scale)
					_last_norm_pos = -1.0
			else:
				_last_norm_pos = -1.0
		else:
			_last_norm_pos = -1.0
	else:
		_last_norm_pos = -1.0


func _update_skeleton_tilt(delta: float) -> void:
	if not rig: return
	# Enforce clean X and Z rotations on the root body
	rotation.x = 0.0
	rotation.z = 0.0
	
	var current_y_rot = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	var rotation_delta = angle_difference(last_y_rotation, current_y_rot)
	last_y_rotation = current_y_rot
	
	# Determine if we should suppress tilt during rapid/instant rotations
	var suppress_tilt = false
	if state_machine and state_machine.current_state:
		var state_name = state_machine.current_state.name
		if state_name in ["StateTurnBack", "StateKnockdown"]:
			suppress_tilt = true
			
	# Also suppress on huge single-frame rotation snaps (e.g. grab alignment)
	if abs(rotation_delta) > deg_to_rad(15.0):
		suppress_tilt = true
		
	if suppress_tilt:
		# Smoothly relax existing tilt back to zero
		rig.rotation.z = lerp_angle(rig.rotation.z, 0.0, delta * tilt_speed)
		# Reset tracking variables to prevent spikes upon exiting suppression
		_smoothed_turn_speed = 0.0
		_smoothed_angular_velocity = 0.0
		return
		
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
	var tree = get_tree()
	if not tree or not is_instance_valid(tree) or not tree.current_scene:
		return
	var any_in_combat = false
	var enemies = tree.get_nodes_in_group("enemies")
	for other in enemies:
		if is_instance_valid(other) and other != self and not other.is_defeated and other.is_inside_tree():
			var sm = other.get_node_or_null("EnemyStateMachine")
			if sm and sm.current_state:
				var state_name = sm.current_state.name
				if state_name != "StateIdle" and state_name != "StateDefeated":
					any_in_combat = true
					break
	if not any_in_combat:
		SoundManager.play_music_non_combat()
		if show_debug_label:
			print("No enemies left in combat. Transitioning to non-combat music.")


func step_1() -> void:
	if not is_defeated:
		SoundManager.play_3d("zombie_footstep", self, 0.0, -1.0, custom_pitch_scale)


func step_2() -> void:
	if not is_defeated:
		SoundManager.play_3d("zombie_footstep", self, 0.0, -1.0, custom_pitch_scale)


func _get_zone_bone_position(zone: String) -> Vector3:
	var skeleton = _find_skeleton(self)
	if not skeleton:
		return global_position
		
	var target_bone = ""
	match zone:
		"head":
			target_bone = "DEF-spine.006"
		"left_foot":
			target_bone = "DEF-foot.L"
		"right_foot":
			target_bone = "DEF-foot.R"
		"left_leg":
			target_bone = "DEF-shin.L.001"
		"right_leg":
			target_bone = "DEF-shin.R.001"
		"left_arm":
			target_bone = "DEF-hand.L"
		"right_arm":
			target_bone = "DEF-hand.R"
		"body":
			target_bone = "DEF-spine.003"
		_:
			target_bone = "DEF-spine.003"
			
	var bone_idx = skeleton.find_bone(target_bone)
	# Alternate bone fallbacks if specific bones don't exist in the skeleton
	if bone_idx == -1:
		if "left_leg" in zone:
			bone_idx = skeleton.find_bone("DEF-thigh.L.001")
		elif "right_leg" in zone:
			bone_idx = skeleton.find_bone("DEF-thigh.R.001")
		elif "left_arm" in zone:
			bone_idx = skeleton.find_bone("DEF-forearm.L.001")
		elif "right_arm" in zone:
			bone_idx = skeleton.find_bone("DEF-forearm.R.001")
		elif "body" in zone or target_bone == "DEF-spine.003":
			bone_idx = skeleton.find_bone("DEF-spine.001")
			if bone_idx == -1:
				bone_idx = skeleton.find_bone("DEF-spine")
			if bone_idx == -1:
				bone_idx = skeleton.find_bone("Hips")
				
	if bone_idx != -1:
		return skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx).origin
	return global_position


# ─── Act 3 Visual Mesh Juice Helpers ──────────────────────────────────────────
func _get_visual_model_node() -> Node3D:
	for path in ["ZombieModel", "Re4Lom Base Rig", "All zombie fix", "rig"]:
		var node = get_node_or_null(path)
		if node and node is Node3D:
			return node
	var skel = _find_skeleton(self)
	if skel and skel.get_parent() is Node3D and skel.get_parent() != self:
		return skel.get_parent() as Node3D
	elif skel:
		return skel
	return self


func trigger_act2_anticipation_juice(hit_direction: Vector3, duration: float, mesh_pop_scale: float = 1.30, stretch_factor: float = 1.35, shake_amp: float = 0.06, shake_freq: float = 30.0) -> void:
	var model_node = _get_visual_model_node()
	if not is_instance_valid(model_node):
		return
		
	if not _has_stored_model_baseline:
		_model_original_pos = model_node.position
		_model_original_scale = model_node.scale
		_has_stored_model_baseline = true

	if _model_juice_tween and _model_juice_tween.is_running():
		_model_juice_tween.kill()

	# Combine Frame-1 Mesh Pop (mesh_pop_scale) + Directional Squash & Stretch (stretch_factor)
	var stretch_y = 1.0 / sqrt(clamp(stretch_factor, 1.0, 2.0))
	var stretch_xz = clamp(stretch_factor, 1.0, 2.0)
	var pop = clamp(mesh_pop_scale, 1.0, 2.0)

	var target_scale = Vector3(
		_model_original_scale.x * stretch_xz * pop,
		_model_original_scale.y * stretch_y * pop,
		_model_original_scale.z * stretch_xz * pop
	)

	model_node.scale = target_scale

	_model_juice_shake_timer = duration
	_model_juice_shake_duration = max(duration, 0.01)
	_model_juice_shake_amp = shake_amp
	_model_juice_shake_freq = shake_freq

	# Create elastic rebound back to baseline scale as transition to Act 3 launch occurs
	_model_juice_tween = create_tween()
	_model_juice_tween.set_trans(Tween.TRANS_ELASTIC)
	_model_juice_tween.set_ease(Tween.EASE_OUT)
	_model_juice_tween.tween_property(model_node, "scale", _model_original_scale, max(duration * 1.8, 0.35)).set_delay(duration * 0.7)


func trigger_act3_mesh_juice(hit_direction: Vector3, windup_duration: float, stretch_factor: float = 1.35, shake_amp: float = 0.06, shake_freq: float = 24.0) -> void:
	trigger_act2_anticipation_juice(hit_direction, windup_duration, 1.15, stretch_factor, shake_amp, shake_freq)


func _update_act3_mesh_juice(delta: float) -> void:
	if _model_juice_shake_timer > 0.0:
		_model_juice_shake_timer -= delta
		var model_node = _get_visual_model_node()
		if is_instance_valid(model_node):
			if _model_juice_shake_timer > 0.0:
				var decay = _model_juice_shake_timer / _model_juice_shake_duration
				var offset_x = sin(_model_juice_shake_timer * _model_juice_shake_freq * TAU) * _model_juice_shake_amp * decay
				var offset_z = cos(_model_juice_shake_timer * _model_juice_shake_freq * TAU * 1.25) * _model_juice_shake_amp * decay
				model_node.position = _model_original_pos + Vector3(offset_x, 0.0, offset_z)
			else:
				model_node.position = _model_original_pos


func play_takedown_launch_voiceline() -> void:
	if not is_defeated:
		var event_name = "vo_zombie_m_melee_gethit" if voice_character == "Zombie Male" else "vo_zombie_f_melee_gethit"
		SoundManager.play_3d(event_name, self, 0.0, -1.0, custom_pitch_scale)
