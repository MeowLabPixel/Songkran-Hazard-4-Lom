extends Node3D
class_name Merchant

## Water Merchant Controller
## Handles procedural head tracking (LookAtModifier3D IK) towards Player, Follower, and Zombies,
## and provides extensible hooks for water gun selling and tinkering.

@export_group("Head Look-At IK")
@export var enable_head_look: bool = true
@export var model_facing_direction: Vector3 = Vector3(0, 0, 1) ## Local facing vector (+Z for Merchant model towards bucket)
@export var look_distance: float = 8.0 ## Max detection distance to look at an entity
@export var exit_distance: float = 10.5 ## Distance hysteresis before disengaging target gaze
@export var customer_priority_distance: float = 5.0 ## Priority range where Player is favored as customer
@export var threat_priority_distance: float = 4.0 ## Danger range where close Zombies get immediate attention
@export var max_look_angle_deg: float = 70.0 ## Max horizontal glance angle (prevents unnatural neck snaps)
@export var max_pitch_down_deg: float = 5.0 ## Max downward glance angle (tight clamp prevents straw hat brim from hiding eyes)
@export var max_pitch_up_deg: float = 25.0 ## Max upward glance angle
@export var glance_pitch_up_deg: float = 15.0 ## Upward tilt angle added when tracking a target (lifts hat brim to reveal eyes)
@export var head_turn_speed: float = 5.0 ## Tracking speed when moving head to target
@export var return_speed: float = 3.0 ## Smooth return speed when relaxing back to forward gaze

signal enemy_hit(hit_data: Dictionary)

@export_group("Skeleton & Bone Configuration")
@export var head_bone_name: String = "DEF-spine.006" ## Deform head bone (Head, Ear, Mask, Straw Hat)
@export var skeleton_path: NodePath = NodePath("water merchant anim/rig/Skeleton3D")

@export_group("Hit Reaction (Spring Physics)")
@export var enable_hit_reaction: bool = true
@export var invert_hit_reaction_pitch: bool = true ## Inverts hit reaction pitch axis to match +Z model facing (+Z forward)
@export var hit_reaction_multiplier: float = 1.0 ## Master multiplier to increase or reduce merchant hit reaction intensity
@export var leg_hit_spine_reaction_multiplier: float = 1.0 ## Intensity of spine tilt down when shot in leg or foot
@export var head_reaction_stiffness: float = 220.0
@export var head_reaction_damping: float = 10.0
@export var head_reaction_force: float = 26.0

@export var body_reaction_stiffness: float = 260.0
@export var body_reaction_damping: float = 18.0
@export var body_reaction_force: float = -7.0

@export var arms_reaction_stiffness: float = 220.0
@export var arms_reaction_damping: float = 16.0
@export var arms_reaction_force: float = -14.0

@export var legs_reaction_stiffness: float = 260.0
@export var legs_reaction_damping: float = 18.0
@export var legs_reaction_force: float = -10.0

@export_group("Shop & Tinkering")
@export var shop_trigger_area: Area3D = null
@export var shop_camera: Node3D = null
@export var shop_camera_lerp_duration: float = 0.8
@export var shop_close_anim_delay: float = 0.5
@export var animation_tree_path: NodePath = NodePath("AnimationTree")
@export var interaction_radius: float = 1.1
@export var max_interaction_distance: float = 1.7
@export var min_interaction_facing_dot: float = 0.2
@export var min_merchant_front_dot: float = 0.25
@export var shop_menu_scene: PackedScene = preload("res://scenes/ui/merchant_shop_menu.tscn")

# Internal Node References
var skeleton: Skeleton3D = null
var head_lookat: LookAtModifier3D = null
var aim_target_marker: Marker3D = null
var hit_reaction_modifier: EnemyHitReactionModifier = null
var animation_tree: AnimationTree = null
var anim_state_machine: AnimationNodeStateMachinePlayback = null
var shop_menu: MerchantShopMenu = null
var nearby_player: CharacterBody3D = null
var is_player_in_range: bool = false
var _prompt_ui: CanvasLayer = null
var _prompt_label: Label = null

# Runtime Tracking State
var current_glance_pos: Vector3 = Vector3.ZERO
var active_target: Node3D = null
var current_influence: float = 0.0
var current_player: CharacterBody3D = null
var is_in_interaction: bool = false
var current_voice_player: AudioStreamPlayer3D = null

func _ready() -> void:
	_setup_head_lookat_ik()
	_setup_hit_reaction_modifier()
	_setup_fabric_hitboxes()
	_setup_shop_trigger()
	_setup_shop_bucket()
	_setup_animation_tree()

func _setup_animation_tree() -> void:
	animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	if not animation_tree:
		animation_tree = find_child("AnimationTree", true, false) as AnimationTree
	if animation_tree:
		animation_tree.active = true
		anim_state_machine = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

func _setup_shop_bucket() -> void:
	var cam = get_shop_camera()
	if cam:
		cam.current = false
	var water_mesh = find_child("Water Mesh", true, false) as MeshInstance3D
	if water_mesh and not water_mesh.material_override:
		var water_mat = load("res://shaders/bucket_water_material.tres") as Material
		if water_mat:
			water_mesh.material_override = water_mat

func _process(delta: float) -> void:
	_update_player_stun_interaction()

	if not enable_head_look:
		if head_lookat:
			head_lookat.influence = 0.0
		return

	_update_head_tracking(delta)

# ─── Head Look-At IK Initialization ──────────────────────────────────────────

func _setup_head_lookat_ik() -> void:
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not skeleton:
		skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	
	if not skeleton:
		push_warning("[Merchant] Skeleton3D not found at path: %s" % str(skeleton_path))
		return

	# 1. Aim Target Marker (Parented to Skeleton3D for clean local coordinates)
	aim_target_marker = skeleton.get_node_or_null("Aim_target_head") as Marker3D
	if not aim_target_marker:
		aim_target_marker = Marker3D.new()
		aim_target_marker.name = "Aim_target_head"
		# Pre-position forward along model facing in skeleton space
		aim_target_marker.position = Vector3(0.0, 1.46, 10.0 * model_facing_direction.z)
		skeleton.add_child(aim_target_marker)

	# 2. LookAtModifier3D on Primary Deform Bone (DEF-spine.006)
	var b_idx = skeleton.find_bone(head_bone_name)
	if b_idx != -1:
		head_lookat = skeleton.get_node_or_null("HeadLookAt") as LookAtModifier3D
		if not head_lookat:
			head_lookat = LookAtModifier3D.new()
			head_lookat.name = "HeadLookAt"
			head_lookat.bone_name = head_bone_name
			head_lookat.bone = b_idx
			head_lookat.primary_rotation_axis = Vector3.AXIS_X
			head_lookat.use_secondary_rotation = true
			head_lookat.use_angle_limitation = true
			head_lookat.symmetry_limitation = false
			head_lookat.primary_positive_limit_angle = deg_to_rad(max_pitch_up_deg)
			head_lookat.primary_negative_limit_angle = deg_to_rad(max_pitch_up_deg)
			head_lookat.primary_positive_damp_threshold = 1.0
			head_lookat.primary_negative_damp_threshold = 1.0
			head_lookat.secondary_positive_limit_angle = deg_to_rad(max_look_angle_deg)
			head_lookat.secondary_negative_limit_angle = deg_to_rad(max_look_angle_deg)
			head_lookat.secondary_positive_damp_threshold = 0.7
			head_lookat.secondary_negative_damp_threshold = 0.7
			head_lookat.influence = 0.0
			skeleton.add_child(head_lookat)
		else:
			head_lookat.primary_positive_limit_angle = deg_to_rad(max_pitch_up_deg)
			head_lookat.primary_negative_limit_angle = deg_to_rad(max_pitch_up_deg)
			head_lookat.secondary_positive_limit_angle = deg_to_rad(max_look_angle_deg)
			head_lookat.secondary_negative_limit_angle = deg_to_rad(max_look_angle_deg)
		head_lookat.target_node = head_lookat.get_path_to(aim_target_marker)

	# Clean up any legacy HeadCtrlLookAt modifier (Straw Hat & Mask are now attached to DEF-spine.006)
	var legacy_ctrl = skeleton.get_node_or_null("HeadCtrlLookAt")
	if legacy_ctrl:
		legacy_ctrl.queue_free()

# ─── Head Tracking Update Loop ───────────────────────────────────────────────

func _update_head_tracking(delta: float) -> void:
	if not skeleton or not aim_target_marker:
		return

	var m_head_pos = _get_merchant_head_pos()
	var fwd_dir = _get_forward_dir()
	var default_forward = m_head_pos + fwd_dir * 10.0

	var best_target = _select_best_target()
	active_target = best_target

	if is_instance_valid(active_target):
		var target_pos = _get_target_head_pos(active_target)
		var t_factor = minf(delta * head_turn_speed, 1.0)
		if current_glance_pos == Vector3.ZERO:
			current_glance_pos = target_pos
		else:
			current_glance_pos = current_glance_pos.lerp(target_pos, t_factor)
		current_influence = lerpf(current_influence, 1.0, t_factor)
	else:
		var r_factor = minf(delta * return_speed, 1.0)
		if current_glance_pos == Vector3.ZERO:
			current_glance_pos = default_forward
		else:
			current_glance_pos = current_glance_pos.lerp(default_forward, r_factor)
		current_influence = lerpf(current_influence, 0.0, r_factor)

	# Fixed-depth projection (1:1 with Player & Follower look-at system)
	# Eliminates perspective & distance distortions when target is close
	var to_target_vec = current_glance_pos - m_head_pos
	# Restrict vertical deviation so head never dips below eye level
	to_target_vec.y = clampf(to_target_vec.y, 0.0, 0.6)
	var aim_dir = fwd_dir if to_target_vec.length_squared() < 0.0001 else to_target_vec.normalized()
	var fixed_depth_global = m_head_pos + aim_dir * 10.0

	var target_local = skeleton.to_local(fixed_depth_global)
	if absf(target_local.x) < 0.001:
		target_local.x = 0.001

	# Subtly tilt head up when tracking an entity so hat brim lifts and eyes/mask are clearly visible
	if current_influence > 0.001 and glance_pitch_up_deg != 0.0:
		var pitch_up_offset = 10.0 * tan(deg_to_rad(glance_pitch_up_deg)) * current_influence
		target_local.y += pitch_up_offset

	aim_target_marker.position = target_local

	# Apply smooth influence to modifier
	if head_lookat:
		head_lookat.influence = current_influence

# ─── Multi-Target Selection & Priority ───────────────────────────────────────

func _select_best_target() -> Node3D:
	var m_head = _get_merchant_head_pos()
	var fwd = _get_forward_dir()
	# Generous forward FOV check: allows full forward and wide side view (up to ~100 degrees)
	var min_front_dot: float = -0.2

	# 1. Hysteresis Retention: Keep looking at existing active target if still valid & in range
	if is_instance_valid(active_target) and not active_target.is_queued_for_deletion():
		if _is_target_active(active_target):
			var cur_pos = _get_target_head_pos(active_target)
			var cur_dist = m_head.distance_to(cur_pos)
			var cur_dir = (cur_pos - m_head).normalized()
			if cur_dist <= exit_distance and fwd.dot(cur_dir) >= min_front_dot:
				# If active target is player and within customer proximity, firmly retain gaze
				if _is_player(active_target) and cur_dist <= customer_priority_distance:
					return active_target

	# 2. Customer Priority: If Player is near the counter/stall (< customer_priority_distance)
	var player = _find_player()
	if player and _is_target_active(player):
		var p_pos = _get_target_head_pos(player)
		var p_dist = m_head.distance_to(p_pos)
		var p_dir = (p_pos - m_head).normalized()
		if p_dist <= customer_priority_distance and fwd.dot(p_dir) >= min_front_dot:
			return player

	# 3. Danger Priority: If a Zombie gets very close (< threat_priority_distance)
	var zombies = _get_active_zombies()
	var closest_threat: Node3D = null
	var min_threat_dist: float = threat_priority_distance
	for z in zombies:
		var z_pos = _get_target_head_pos(z)
		var z_dist = m_head.distance_to(z_pos)
		var z_dir = (z_pos - m_head).normalized()
		if z_dist <= min_threat_dist and fwd.dot(z_dir) >= min_front_dot:
			min_threat_dist = z_dist
			closest_threat = z
	if closest_threat:
		return closest_threat

	# 4. Proximity Fallback: Closest valid entity among Player, Follower, and Zombies within look_distance
	var candidates: Array[Node3D] = []
	if player and _is_target_active(player):
		candidates.append(player)
	var follower = _find_follower()
	if follower and _is_target_active(follower):
		candidates.append(follower)
	candidates.append_array(zombies)

	var best_candidate: Node3D = null
	var best_dist: float = look_distance
	for c in candidates:
		if not is_instance_valid(c):
			continue
		var c_pos = _get_target_head_pos(c)
		var c_dist = m_head.distance_to(c_pos)
		var c_dir = (c_pos - m_head).normalized()
		if c_dist <= best_dist and fwd.dot(c_dir) >= min_front_dot:
			best_dist = c_dist
			best_candidate = c

	return best_candidate

# ─── Target Query Helpers ───────────────────────────────────────────────────

func _get_forward_dir() -> Vector3:
	return (global_transform.basis * model_facing_direction).normalized()

func _find_player() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			return p as Node3D
	var p_node = get_tree().root.find_child("Player", true, false)
	if not p_node:
		p_node = get_tree().root.find_child("player", true, false)
	if p_node and is_instance_valid(p_node) and not p_node.is_queued_for_deletion():
		return p_node as Node3D
	return null

func _find_follower() -> Node3D:
	var followers = get_tree().get_nodes_in_group("anchalee")
	if followers.is_empty():
		followers = get_tree().get_nodes_in_group("Anchalee")
	if followers.size() > 0:
		var f = followers[0]
		if is_instance_valid(f) and not f.is_queued_for_deletion():
			return f as Node3D
	return null

func _get_active_zombies() -> Array[Node3D]:
	var list: Array[Node3D] = []
	var zombies = get_tree().get_nodes_in_group("enemies")
	if zombies.is_empty():
		zombies = get_tree().get_nodes_in_group("enemy")
	for z in zombies:
		if is_instance_valid(z) and not z.is_queued_for_deletion() and z is Node3D:
			if _is_target_active(z):
				list.append(z)
	return list

func _is_target_active(node: Node3D) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false

	# 1. Safely check is_dead (method or property)
	if node.has_method("is_dead"):
		if node.is_dead():
			return false
	elif "is_dead" in node and bool(node.is_dead):
		return false

	# 2. Safely check is_defeated (method or property)
	if node.has_method("is_defeated"):
		if node.is_defeated():
			return false
	elif "is_defeated" in node and bool(node.is_defeated):
		return false

	# 3. Check health / HP values
	if "health" in node and node.health <= 0:
		return false
	if "HP" in node and node.HP <= 0:
		return false

	return true

func _is_player(node: Node3D) -> bool:
	if not is_instance_valid(node):
		return false
	return node.is_in_group("player") or node.name.to_lower() == "player"

func _get_merchant_head_pos() -> Vector3:
	if skeleton:
		var head_idx = skeleton.find_bone(head_bone_name)
		if head_idx != -1:
			return skeleton.to_global(skeleton.get_bone_global_pose(head_idx).origin)
	return global_position + Vector3(0.0, 1.46, 0.0)

func _get_target_head_pos(node: Node3D) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.ZERO
	# 1. Try explicit head attachments/bones if present
	var exact_head = node.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/Head")
	if exact_head and exact_head is Node3D:
		return exact_head.global_position
	# 2. Check Anchalee helper if available
	if node.has_method("_get_head_origin_global"):
		return node.call("_get_head_origin_global")
	# 3. Known height offsets
	if _is_player(node):
		return node.global_position + Vector3(0.0, 1.5, 0.0)
	if node.is_in_group("anchalee") or "anchalee" in node.name.to_lower():
		return node.global_position + Vector3(0.0, 1.4, 0.0)
	# 4. Default enemy / character head height
	return node.global_position + Vector3(0.0, 1.5, 0.0)

# ─── Shop & Water Gun Tinkering Interface (Hooks) ────────────────────────────

func get_shop_camera() -> Camera3D:
	if shop_camera and is_instance_valid(shop_camera) and shop_camera is Camera3D:
		return shop_camera as Camera3D
	var cam = get_node_or_null("Shop Bucket/ShopCamera") as Camera3D
	if not cam:
		cam = find_child("ShopCamera", true, false) as Camera3D
	if cam:
		shop_camera = cam
		cam.current = false
	return cam

func play_shop_open_anim() -> void:
	if not anim_state_machine and animation_tree:
		anim_state_machine = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if anim_state_machine:
		anim_state_machine.travel(&"OPEN")

func play_shop_close_anim() -> void:
	if not anim_state_machine and animation_tree:
		anim_state_machine = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if anim_state_machine:
		anim_state_machine.travel(&"Close")

func enter_interaction(player: CharacterBody3D, on_camera_ready: Callable = Callable()) -> void:
	current_player = player
	is_in_interaction = true
	# Lock gaze firmly on the customer during dialogue/shopping
	active_target = player

	# Trigger AnimationTree state machine: IDLE -> OPEN -> Open_Loop
	play_shop_open_anim()

	var target_cam = get_shop_camera()
	var cam_controller = player.get("camera") if player else null
	if cam_controller and target_cam and cam_controller.has_method("transition_to_shop_camera"):
		cam_controller.transition_to_shop_camera(target_cam, shop_camera_lerp_duration, on_camera_ready)
	else:
		if on_camera_ready.is_valid():
			on_camera_ready.call()

func exit_interaction(on_camera_exited: Callable = Callable()) -> void:
	# Delay transition to Close animation by shop_close_anim_delay (0.5s)
	if shop_close_anim_delay > 0.0:
		get_tree().create_timer(shop_close_anim_delay).timeout.connect(func():
			play_shop_close_anim()
		)
	else:
		play_shop_close_anim()

	var cam_controller = current_player.get("camera") if current_player else null
	if cam_controller and cam_controller.has_method("exit_shop_camera"):
		cam_controller.exit_shop_camera(shop_camera_lerp_duration, on_camera_exited)
	else:
		if on_camera_exited.is_valid():
			on_camera_exited.call()

	current_player = null
	is_in_interaction = false

func is_customer_present() -> bool:
	return is_in_interaction and is_instance_valid(current_player)

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_in_range or is_in_interaction:
		return
		
	if not _is_player_stun_overlapping(nearby_player):
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_E:
			if nearby_player:
				open_shop_menu(nearby_player)
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed("takedown"):
		if nearby_player:
			open_shop_menu(nearby_player)
			get_viewport().set_input_as_handled()

func open_shop_menu(player: CharacterBody3D) -> void:
	if not _is_player_stun_overlapping(player):
		return

	if not shop_menu or not is_instance_valid(shop_menu):
		if shop_menu_scene:
			shop_menu = shop_menu_scene.instantiate() as MerchantShopMenu
		else:
			shop_menu = MerchantShopMenu.new()
		add_child(shop_menu)
		shop_menu.shop_closed.connect(_on_shop_closed)
		
	_set_prompt_visible(false)
	shop_menu.open_shop(player, self)

func _on_shop_closed() -> void:
	if is_player_in_range and _is_player_stun_overlapping(nearby_player):
		_set_prompt_visible(true)

func stop_merchant_voice() -> void:
	if current_voice_player and is_instance_valid(current_voice_player):
		if current_voice_player.playing:
			current_voice_player.stop()
		current_voice_player.queue_free()
		current_voice_player = null

func play_merchant_voice(event_name: String) -> AudioStreamPlayer3D:
	stop_merchant_voice()
	if typeof(SoundManager) != TYPE_NIL and SoundManager.has_method("play_3d"):
		current_voice_player = SoundManager.play_3d(event_name, self)
		return current_voice_player
	return null

func _get_player_stun_detector(player: Node) -> Area3D:
	if not player or not is_instance_valid(player):
		return null
	var stun_area = player.get("stun_detect") as Area3D
	if not stun_area:
		stun_area = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/spine02/Stunned detect2") as Area3D
	if not stun_area:
		stun_area = player.find_child("Stunned detect2", true, false) as Area3D
	return stun_area

func _get_interaction_point() -> Vector3:
	if shop_trigger_area and is_instance_valid(shop_trigger_area):
		var col = shop_trigger_area.find_child("CollisionShape3D", true, false) as CollisionShape3D
		if col:
			return col.global_position
		return shop_trigger_area.global_position
	return to_global(Vector3(0.0, 1.0, 0.85))

func _is_player_stun_overlapping(player: Node) -> bool:
	if not player or not is_instance_valid(player):
		return false
	var stun_area = _get_player_stun_detector(player)
	if not stun_area or not is_instance_valid(stun_area):
		return false
	if not shop_trigger_area or not is_instance_valid(shop_trigger_area):
		return false

	# 1. Physics overlap validation with shop trigger area
	if not stun_area.overlaps_area(shop_trigger_area):
		return false

	# 2. Maximum global distance validation between player stun detector and counter
	var interact_pos = _get_interaction_point()
	var stun_pos = stun_area.global_position
	var dist = stun_pos.distance_to(interact_pos)
	if dist > max_interaction_distance:
		return false

	# 3. Orientation validation: Player must be facing towards merchant/bucket
	var player_fwd: Vector3 = -player.global_transform.basis.z.normalized()
	var to_merchant: Vector3 = (global_position - player.global_position)
	to_merchant.y = 0.0
	if to_merchant.length_squared() > 0.001:
		to_merchant = to_merchant.normalized()
		if player_fwd.dot(to_merchant) < min_interaction_facing_dot:
			return false

	# 4. Front hemisphere validation: Player must be in front of merchant (not behind back or walls)
	var merchant_fwd: Vector3 = _get_forward_dir()
	merchant_fwd.y = 0.0
	var to_player: Vector3 = (player.global_position - global_position)
	to_player.y = 0.0
	if to_player.length_squared() > 0.001 and merchant_fwd.length_squared() > 0.001:
		to_player = to_player.normalized()
		merchant_fwd = merchant_fwd.normalized()
		if merchant_fwd.dot(to_player) < min_merchant_front_dot:
			return false

	return true

func _update_player_stun_interaction() -> void:
	if is_in_interaction:
		if is_player_in_range:
			is_player_in_range = false
			_set_prompt_visible(false)
		return

	var player = _find_player() as CharacterBody3D
	var is_overlapping = _is_player_stun_overlapping(player)

	if is_overlapping:
		if not is_player_in_range or nearby_player != player:
			nearby_player = player
			is_player_in_range = true
			_set_prompt_visible(true)
	else:
		if is_player_in_range or nearby_player != null:
			nearby_player = null
			is_player_in_range = false
			_set_prompt_visible(false)

func _setup_shop_trigger() -> void:
	if not shop_trigger_area:
		shop_trigger_area = get_node_or_null("ShopTriggerArea") as Area3D
		if not shop_trigger_area:
			shop_trigger_area = Area3D.new()
			shop_trigger_area.name = "ShopTriggerArea"
			var col_shape = CollisionShape3D.new()
			var cyl = CylinderShape3D.new()
			cyl.radius = interaction_radius
			cyl.height = 2.0
			col_shape.shape = cyl
			col_shape.position = Vector3(0.0, 1.0, 0.85)
			shop_trigger_area.add_child(col_shape)
			add_child(shop_trigger_area)
			
	# Configure collision layer for player stun detection (Layer 14: 8192)
	shop_trigger_area.collision_layer = 8192
	shop_trigger_area.collision_mask = 0
		
	_setup_prompt_ui()

func _setup_prompt_ui() -> void:
	if _prompt_ui and is_instance_valid(_prompt_ui):
		return
	_prompt_ui = CanvasLayer.new()
	_prompt_ui.layer = 110
	_prompt_ui.name = "MerchantPromptUI"
	add_child(_prompt_ui)
	
	var margin_bottom = MarginContainer.new()
	margin_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_bottom.add_theme_constant_override("margin_bottom", 64)
	_prompt_ui.add_child(margin_bottom)
	
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_bottom.add_child(center)
	
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(220, 52)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.12, 0.88)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.35, 0.8, 1.0, 0.95)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.shadow_color = Color(0, 0.25, 0.5, 0.4)
	sb.shadow_size = 12
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	_prompt_label = Label.new()
	_prompt_label.text = "[E] Open Shop"
	var font_bold = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	_prompt_label.add_theme_font_override("font", font_bold)
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 6)
	margin.add_child(_prompt_label)
	
	_prompt_ui.visible = false

func _set_prompt_visible(vis: bool) -> void:
	if _prompt_ui and is_instance_valid(_prompt_ui):
		if vis and _prompt_label:
			var lang = "en"
			if get_tree().root.has_node("GameManager"):
				lang = GameManager.selected_language
			if lang == "th":
				_prompt_label.text = "[E] ร้านค้าปืนฉีดน้ำ"
			else:
				_prompt_label.text = "[E] Open Shop"
		_prompt_ui.visible = vis

func _on_shop_body_entered(_body: Node3D) -> void:
	pass

func _on_shop_body_exited(_body: Node3D) -> void:
	pass

func _on_shop_area_entered(_area: Area3D) -> void:
	pass

func _on_shop_area_exited(_area: Area3D) -> void:
	pass

# ─── Combat & Hit Reaction ───────────────────────────────────────────────────

func _setup_hit_reaction_modifier() -> void:
	if not skeleton or not enable_hit_reaction:
		return
	hit_reaction_modifier = skeleton.get_node_or_null("EnemyHitReactionModifier") as EnemyHitReactionModifier
	if not hit_reaction_modifier:
		hit_reaction_modifier = EnemyHitReactionModifier.new()
		hit_reaction_modifier.name = "EnemyHitReactionModifier"
		hit_reaction_modifier.enemy = self
		hit_reaction_modifier.reaction_multiplier = hit_reaction_multiplier
		
		hit_reaction_modifier.head_stiffness = head_reaction_stiffness
		hit_reaction_modifier.head_damping = head_reaction_damping
		hit_reaction_modifier.head_force = head_reaction_force
		
		hit_reaction_modifier.body_stiffness = body_reaction_stiffness
		hit_reaction_modifier.body_damping = body_reaction_damping
		hit_reaction_modifier.body_force = body_reaction_force
		
		hit_reaction_modifier.arms_stiffness = arms_reaction_stiffness
		hit_reaction_modifier.arms_damping = arms_reaction_damping
		hit_reaction_modifier.arms_force = arms_reaction_force
		
		hit_reaction_modifier.legs_stiffness = legs_reaction_stiffness
		hit_reaction_modifier.legs_damping = legs_reaction_damping
		hit_reaction_modifier.legs_force = legs_reaction_force
		
		skeleton.add_child(hit_reaction_modifier)
	else:
		hit_reaction_modifier.reaction_multiplier = hit_reaction_multiplier

func take_hit(hit_data: Dictionary) -> void:
	var zone: String = hit_data.get("hit_zone", "body")
	var hit_dir: Vector3 = hit_data.get("hit_direction", Vector3.ZERO)
	
	if hit_dir == Vector3.ZERO:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and is_instance_valid(players[0]):
			var hit_pos = hit_data.get("position", global_position)
			hit_dir = (hit_pos - players[0].global_position).normalized()
		else:
			hit_dir = -_get_forward_dir()
	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()
	hit_data["hit_direction"] = hit_dir

	# 1. Emit enemy_hit signal for EnemyHitReactionModifier (damped spring recoil)
	enemy_hit.emit(hit_data)

	# 2. Trigger Act 1 localized Bone Juice (Pop, Squash-and-Stretch, Shake)
	if hit_reaction_modifier and hit_reaction_modifier.has_method("trigger_bone_juice"):
		if zone in ["head", "left_foot", "left_leg", "right_foot", "right_leg"]:
			hit_reaction_modifier.trigger_bone_juice(zone, hit_dir, 0.35, 1.15, 1.175, 0.0, 30.0)

	# 3. Lock gaze on shooter if player
	var shooter = hit_data.get("source")
	if shooter and is_instance_valid(shooter) and shooter is Node3D:
		active_target = shooter
	else:
		var player = _find_player()
		if player:
			active_target = player

	# 4. Play hit sound effect if SoundManager exists
	if typeof(SoundManager) != TYPE_NIL:
		SoundManager.play_3d("zombie_melee_hit", self)

func _setup_fabric_hitboxes() -> void:
	if not skeleton:
		return
	for child in skeleton.get_children():
		if child is BoneAttachment3D and child.name.begins_with("FabricHitbox"):
			var b_name = child.bone_name
			if b_name.is_empty() and child.bone_idx != -1:
				b_name = skeleton.get_bone_name(child.bone_idx)
			
			var area = child.get_node_or_null("Area3D") as Area3D
			if not area:
				area = child.find_child("Area3D", false, false) as Area3D
			
			if area:
				# Configure collision layer for Hitboxes (Layer 14: 8192, Layer 3: 4 -> 8196) and mask to 4
				area.collision_layer = 8196
				area.collision_mask = 4
				if not area.is_in_group("merchant_hitbox"):
					area.add_to_group("merchant_hitbox")
				
				var hz = area.get_node_or_null("HitboxZone") as HitboxZone
				if not hz:
					hz = HitboxZone.new()
					hz.name = "HitboxZone"
					hz.zone_name = "fabric:" + b_name
					hz.base_damage = 0
					area.add_child(hz)
				else:
					hz.zone_name = "fabric:" + b_name
					hz.base_damage = 0
