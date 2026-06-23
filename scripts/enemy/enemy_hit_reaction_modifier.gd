extends SkeletonModifier3D
class_name EnemyHitReactionModifier

# Default spring parameters (fallback)
@export var default_stiffness: float = 240.0
@export var default_damping: float = 18.0
@export var default_force: float = -18.0

@export var reaction_multiplier: float = 1.0

@export_group("Head Reaction")
@export var head_stiffness: float = 260.0
@export var head_damping: float = 18.0
@export var head_force: float = 26.0

@export_group("Body Reaction")
@export var body_stiffness: float = 260.0
@export var body_damping: float = 18.0
@export var body_force: float = -6.0

@export_group("Arms Reaction")
@export var arms_stiffness: float = 220.0
@export var arms_damping: float = 16.0
@export var arms_force: float = -14.0

@export_group("Legs Reaction")
@export var legs_stiffness: float = 240.0
@export var legs_damping: float = 18.0
@export var legs_force: float = -10.0
@export var legs_knockdown_dampening: float = 0.5

@export_group("Randomness & Offsets")
@export var force_randomness_min: float = 0.8
@export var force_randomness_max: float = 1.2
@export var side_offset_min: float = 0.3
@export var side_offset_max: float = 0.6

@export_group("Flipflop Eat Leg Feature")
@export var flipflop_slide_height: float = 0.38
@export var flipflop_slide_speed: float = 2.0
@export var flipflop_rot_x: float = 85.0
@export var flipflop_rot_z: float = 35.0
@export var flipflop_blend_duration: float = 0.4
@export var flipflop_slide_duration: float = 1.0
@export var flipflop_slide_depth: float = 0.06
@export var flipflop_min_height: float = 0.28
@export var flipflop_blend_min_height: float = 0.00
@export var flipflop_blend_min_depth: float = 0.00
@export var flipflop_blend_height_speed: float = 1.0
@export var flipflop_blend_depth_speed: float = 1.0
@export var flipflop_blend_rot_speed: float = 1.0

# Keep track of the active slide flip-flop state
var _slid_flipflop: String = "" # "", "left", "right"
var _flipflop_offset: float = 0.0
var _flipflop_target_offset: float = 0.0
var _return_time_elapsed: float = 0.0

var _left_mesh: MeshInstance3D = null
var _right_mesh: MeshInstance3D = null
var _left_flipflop_shin_relative_transform: Transform3D = Transform3D.IDENTITY
var _right_flipflop_shin_relative_transform: Transform3D = Transform3D.IDENTITY
var _attachments_setup: bool = false

var _left_original_skin: Skin = null
var _left_original_skeleton: NodePath = NodePath("")
var _left_original_transform: Transform3D = Transform3D.IDENTITY

var _right_original_skin: Skin = null
var _right_original_skeleton: NodePath = NodePath("")
var _right_original_transform: Transform3D = Transform3D.IDENTITY

var enemy: CharacterBody3D

class ActiveReaction:
	var bone_name: String
	var axis: Vector3
	var angle: float = 0.0
	var velocity: float = 0.0
	var stiffness: float = 240.0
	var damping: float = 18.0

# Map of bone_name -> ActiveReaction
var _active_reactions: Dictionary = {}

func _ready() -> void:
	if not enemy:
		var node: Node = get_parent()
		while node != null:
			if node is EnemyBase:
				enemy = node
				break
			node = node.get_parent()
			
	if enemy:
		if not enemy.enemy_hit.is_connected(_on_enemy_hit):
			enemy.enemy_hit.connect(_on_enemy_hit)
			
	var skeleton = get_skeleton()
	if skeleton:
		call_deferred("_setup_attachments", skeleton)

func _on_enemy_hit(hit_data: Dictionary) -> void:
	var skeleton = get_skeleton()
	if not skeleton: return

	var zone = hit_data.get("hit_zone", "body")
	var hit_dir = hit_data.get("hit_direction", Vector3.ZERO)
	
	if hit_dir == Vector3.ZERO:
		var players = enemy.get_tree().get_nodes_in_group("player")
		var player = players[0] if players.size() > 0 else null
		if player:
			var hit_pos = hit_data.get("position", enemy.global_position)
			hit_dir = (hit_pos - player.global_position).normalized()
		else:
			hit_dir = -enemy.global_transform.basis.z
			
	var local_hit_dir = enemy.global_transform.basis.inverse() * hit_dir
	local_hit_dir = local_hit_dir.normalized()
	
	# Determine axis of rotation in skeleton local space.
	var axis = local_hit_dir.cross(Vector3.UP).normalized()
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
		
	# Add horizontal/vertical force offset (diagonal roll/yaw)
	# yaw (rotation around Vector3.UP) twists the body left/right.
	# roll (rotation around local_hit_dir) tilts the body sideways.
	var side_sign = 1.0 if randf() > 0.5 else -1.0
	var side_amount = randf_range(side_offset_min, side_offset_max) * side_sign
	
	# perturbed_axis combines:
	# - axis: pitch (forward/backward)
	# - Vector3.UP * side_amount: yaw (twist left/right)
	# - local_hit_dir * (side_amount * 0.5): roll (side tilt)
	var perturbed_axis = (axis + Vector3.UP * side_amount + local_hit_dir * (side_amount * 0.5)).normalized()
	
	# Randomize force by 0% - 20% (varying from min to max multiplier)
	var force_mult = randf_range(force_randomness_min, force_randomness_max)
		
	# Determine bone-specific spring parameters
	var stiffness_val: float = default_stiffness
	var damping_val: float = default_damping
	var force_val: float = default_force
	var target_bones = []
	
	var is_knocked_down = false
	if enemy and "state_machine" in enemy and enemy.state_machine != null:
		var sm = enemy.state_machine
		if sm.current_state and sm.current_state.name == "StateKnockdown":
			is_knocked_down = true

	match zone:
		"head":
			stiffness_val = head_stiffness
			damping_val = head_damping  
			force_val = head_force
			target_bones = ["DEF-spine.006"]
			
			# Shooting head also add body reaction force in positive value (only head feature)
			var body_force_positive = abs(body_force) * force_mult
			for b in ["DEF-spine.002", "DEF-spine.003"]:
				_trigger_reaction(skeleton, b, perturbed_axis, body_stiffness, body_damping, body_force_positive)
		"left_arm", "left_hand":
			stiffness_val = arms_stiffness
			damping_val = arms_damping  
			force_val = arms_force   
			target_bones = ["DEF-upper_arm.L", "DEF-forearm.L"]
		"right_arm", "right_hand":
			stiffness_val = arms_stiffness
			damping_val = arms_damping  
			force_val = arms_force   
			target_bones = ["DEF-upper_arm.R", "DEF-forearm.R"]
		"left_leg", "left_foot":
			stiffness_val = legs_stiffness
			damping_val = legs_damping  
			force_val = legs_force
			if is_knocked_down:
				force_val = abs(legs_force) * legs_knockdown_dampening
			target_bones = ["DEF-thigh.L", "DEF-shin.L"]
		"right_leg", "right_foot":
			stiffness_val = legs_stiffness
			damping_val = legs_damping  
			force_val = legs_force
			if is_knocked_down:
				force_val = abs(legs_force) * legs_knockdown_dampening
			target_bones = ["DEF-thigh.R", "DEF-shin.R"]
		_: # body, chest, etc.
			stiffness_val = body_stiffness 
			damping_val = body_damping    
			force_val = body_force      
			target_bones = ["DEF-spine.002", "DEF-spine.003"]
			
	print("[EnemyHitReactionModifier] Hit registered on '%s' of '%s'. Hit dir: %s, Local hit: %s, perturbed_axis: %s, force_mult: %f" % [
		zone, enemy.name, hit_dir, local_hit_dir, perturbed_axis, force_mult
	])
	
	for bone_name in target_bones:
		_trigger_reaction(skeleton, bone_name, perturbed_axis, stiffness_val, damping_val, force_val * force_mult)

func _trigger_reaction(skeleton: Skeleton3D, bone_name: String, axis: Vector3, stiffness_val: float, damping_val: float, force_val: float) -> void:
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx == -1: return
	
	var react = _active_reactions.get(bone_name)
	if not react:
		react = ActiveReaction.new()
		react.bone_name = bone_name
		_active_reactions[bone_name] = react
		
	react.axis = axis
	react.stiffness = stiffness_val
	react.damping = damping_val
	react.velocity += force_val * reaction_multiplier

func _find_flipflop_mesh(skeleton: Skeleton3D, is_left: bool) -> MeshInstance3D:
	var prefix = "left" if is_left else "right"
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			var cname = child.name.to_lower()
			if prefix in cname and "flipflop" in cname:
				return child
	return null

func _get_bone_global_rest(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var t = skeleton.get_bone_rest(bone_idx)
	var parent = skeleton.get_bone_parent(bone_idx)
	while parent != -1:
		t = skeleton.get_bone_rest(parent) * t
		parent = skeleton.get_bone_parent(parent)
	return t

func _setup_attachments(skeleton: Skeleton3D) -> void:
	if _attachments_setup: return
	
	var left_foot_idx = skeleton.find_bone("DEF-foot.L")
	var left_shin_idx = skeleton.find_bone("DEF-shin.L")
	var right_foot_idx = skeleton.find_bone("DEF-foot.R")
	var right_shin_idx = skeleton.find_bone("DEF-shin.R")
	
	if left_foot_idx != -1 and left_shin_idx != -1:
		_left_mesh = _find_flipflop_mesh(skeleton, true)
		if _left_mesh:
			_left_original_skin = _left_mesh.skin
			_left_original_skeleton = _left_mesh.skeleton
			_left_original_transform = _left_mesh.transform
			_left_flipflop_shin_relative_transform = _get_bone_global_rest(skeleton, left_shin_idx).inverse()
			
	if right_foot_idx != -1 and right_shin_idx != -1:
		_right_mesh = _find_flipflop_mesh(skeleton, false)
		if _right_mesh:
			_right_original_skin = _right_mesh.skin
			_right_original_skeleton = _right_mesh.skeleton
			_right_original_transform = _right_mesh.transform
			_right_flipflop_shin_relative_transform = _get_bone_global_rest(skeleton, right_shin_idx).inverse()
			
	_attachments_setup = true

func _detach_flipflop(side: String, skeleton: Skeleton3D) -> void:
	if side == "left":
		if _left_mesh:
			_left_mesh.skin = null
			_left_mesh.skeleton = NodePath("")
	elif side == "right":
		if _right_mesh:
			_right_mesh.skin = null
			_right_mesh.skeleton = NodePath("")

func _restore_flipflop(side: String, skeleton: Skeleton3D) -> void:
	if side == "left":
		if _left_mesh:
			_left_mesh.skin = _left_original_skin
			_left_mesh.skeleton = _left_original_skeleton
			_left_mesh.transform = _left_original_transform
	elif side == "right":
		if _right_mesh:
			_right_mesh.skin = _right_original_skin
			_right_mesh.skeleton = _right_original_skeleton
			_right_mesh.transform = _right_original_transform

func _process_modification() -> void:
	if not enemy or not enemy.is_inside_tree(): return
	var skeleton = get_skeleton()
	if not skeleton: return
	if not _attachments_setup: return
	
	var delta = get_process_delta_time()
	if delta <= 0.0: delta = 0.016
	
	# --- Slide Flip-flop Processing ---
	var current_state_name = ""
	var current_state = null
	if enemy and "state_machine" in enemy and enemy.state_machine != null:
		current_state = enemy.state_machine.current_state
		if current_state:
			current_state_name = current_state.name

	var in_return_phase = false
	var return_duration = 0.0
	
	# Reset _slid_flipflop when returning to normal state (not takedownable or knockdown)
	if current_state_name not in ["StateTakedownable", "StateKnockdown"]:
		if _slid_flipflop != "":
			_restore_flipflop(_slid_flipflop, skeleton)
			_slid_flipflop = ""
			_flipflop_target_offset = 0.0
			_return_time_elapsed = 0.0
	else:
		# We are in a stun/knockdown sequence!
		# 1. Determine which foot was shot (first trigger)
		if _slid_flipflop == "":
			var new_slid = ""
			if current_state_name == "StateTakedownable":
				var stun = current_state.stun_type
				if stun == "left_foot":
					new_slid = "left"
				elif stun == "right_foot":
					new_slid = "right"
			elif current_state_name == "StateKnockdown":
				var mode = current_state.knockdown_mode
				if mode == "SPECIAL_LEG_SHOT":
					var side = current_state.special_side
					if side == "L":
						new_slid = "left"
					elif side == "R":
						new_slid = "right"
			
			if new_slid != "":
				_slid_flipflop = new_slid
				_detach_flipflop(_slid_flipflop, skeleton)

		# 2. Determine if we are in a gradual return phase
		if _slid_flipflop != "":
			if current_state_name == "StateTakedownable" and not current_state._in_act1:
				in_return_phase = true
				return_duration = current_state.takedown_window
			elif current_state_name == "StateKnockdown" and current_state._phase >= 2: # ACT 4 & ACT 5
				in_return_phase = true
				return_duration = current_state.knockdown_duration

	# Calculate animation offsets and blend weights
	var rot_progress = 1.0
	var blend_weight = 0.0
	
	if _slid_flipflop != "":
		var current_depth = flipflop_slide_depth
		
		if in_return_phase:
			_return_time_elapsed += delta
			
			if _return_time_elapsed <= flipflop_slide_duration:
				# 1. Shin Slide (Act 1): slide height from flipflop_slide_height to flipflop_min_height
				var slide_progress = _return_time_elapsed / flipflop_slide_duration if flipflop_slide_duration > 0.0 else 1.0
				_flipflop_offset = flipflop_min_height + (1.0 - slide_progress) * (flipflop_slide_height - flipflop_min_height)
				current_depth = flipflop_slide_depth
				rot_progress = 1.0
				blend_weight = 0.0
			elif _return_time_elapsed <= flipflop_slide_duration + flipflop_blend_duration:
				# 2. Final Shin Blend (Act 2): slide down, return depth, straighten rotation, and blend to foot bone
				var blend_elapsed = _return_time_elapsed - flipflop_slide_duration
				if flipflop_blend_duration > 0.0:
					blend_weight = clamp(blend_elapsed / flipflop_blend_duration, 0.0, 1.0)
				else:
					blend_weight = 1.0
				
				# Calculate individual adjustable speed weights using exponents
				var h_weight = pow(blend_weight, flipflop_blend_height_speed)
				var d_weight = pow(blend_weight, flipflop_blend_depth_speed)
				var r_weight = pow(blend_weight, flipflop_blend_rot_speed)
				
				# Slide values from min_height/depth to blend targets during the final blend
				_flipflop_offset = flipflop_blend_min_height + (1.0 - h_weight) * (flipflop_min_height - flipflop_blend_min_height)
				current_depth = flipflop_blend_min_depth + (1.0 - d_weight) * (flipflop_slide_depth - flipflop_blend_min_depth)
				rot_progress = 1.0 - r_weight
				
				# Use rotation weight to blend the space transition
				blend_weight = r_weight
			else:
				# 3. Completed (Act 3 target): remain at target pose and fully skinned
				_flipflop_offset = flipflop_blend_min_height
				current_depth = flipflop_blend_min_depth
				rot_progress = 0.0
				blend_weight = 1.0
		else:
			# Not in return phase (sliding up in Act 1 or Act 3)
			_return_time_elapsed = 0.0
			_flipflop_offset = flipflop_slide_height
			current_depth = flipflop_slide_depth
			rot_progress = 1.0
			blend_weight = 0.0

		# Apply local/global transforms and blending
		var left_foot_idx = skeleton.find_bone("DEF-foot.L")
		var left_shin_idx = skeleton.find_bone("DEF-shin.L")
		var right_foot_idx = skeleton.find_bone("DEF-foot.R")
		var right_shin_idx = skeleton.find_bone("DEF-shin.R")

		if _slid_flipflop == "left" and _left_mesh and left_foot_idx != -1 and left_shin_idx != -1:
			var target_pose = skeleton.get_bone_global_pose(left_foot_idx) * _get_bone_global_rest(skeleton, left_foot_idx).inverse()
			var slide_trans = Transform3D(Basis.IDENTITY, Vector3(0, _flipflop_offset, current_depth))
			var rot_basis = Basis.from_euler(Vector3(deg_to_rad(rot_progress * flipflop_rot_x), 0, deg_to_rad(rot_progress * -flipflop_rot_z)))
			var shin_pose = skeleton.get_bone_global_pose(left_shin_idx) * _left_flipflop_shin_relative_transform
			var source_pose = shin_pose * slide_trans * Transform3D(rot_basis, Vector3.ZERO)
			
			# Interpolate in foot local space to wrap around the ankle rotation arc
			var source_local_to_foot = target_pose.inverse() * source_pose
			var local_to_foot = source_local_to_foot.interpolate_with(Transform3D.IDENTITY, blend_weight)
			_left_mesh.transform = target_pose * local_to_foot
			
		elif _slid_flipflop == "right" and _right_mesh and right_foot_idx != -1 and right_shin_idx != -1:
			var target_pose = skeleton.get_bone_global_pose(right_foot_idx) * _get_bone_global_rest(skeleton, right_foot_idx).inverse()
			var slide_trans = Transform3D(Basis.IDENTITY, Vector3(0, _flipflop_offset, current_depth))
			var rot_basis = Basis.from_euler(Vector3(deg_to_rad(rot_progress * flipflop_rot_x), 0, deg_to_rad(rot_progress * flipflop_rot_z)))
			var shin_pose = skeleton.get_bone_global_pose(right_shin_idx) * _right_flipflop_shin_relative_transform
			var source_pose = shin_pose * slide_trans * Transform3D(rot_basis, Vector3.ZERO)
			
			# Interpolate in foot local space to wrap around the ankle rotation arc
			var source_local_to_foot = target_pose.inverse() * source_pose
			var local_to_foot = source_local_to_foot.interpolate_with(Transform3D.IDENTITY, blend_weight)
			_right_mesh.transform = target_pose * local_to_foot

	# --- Spring Simulation Processing ---
	var to_remove = []
	for bone_name in _active_reactions.keys():
		var react = _active_reactions[bone_name]
		
		var force = -react.stiffness * react.angle - react.damping * react.velocity
		react.velocity += force * delta
		react.angle += react.velocity * delta
		
		if abs(react.angle) < 0.001 and abs(react.velocity) < 0.01:
			to_remove.append(bone_name)
			continue
			
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx != -1:
			var pose = skeleton.get_bone_pose(bone_idx)
			var bone_global_basis = skeleton.get_bone_global_pose(bone_idx).basis
			
			# Transform skeleton space axis of rotation to the bone's own local coordinate system
			var local_axis = bone_global_basis.inverse() * react.axis
			local_axis = local_axis.normalized()
			
			# Create local rotation and right-multiply to apply it in the bone's own space
			var local_rot = Basis(local_axis, react.angle)
			pose.basis = pose.basis * local_rot
			skeleton.set_bone_pose(bone_idx, pose)
			
	for bone_name in to_remove:
		_active_reactions.erase(bone_name)
