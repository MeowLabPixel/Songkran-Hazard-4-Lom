extends SkeletonModifier3D
class_name PlayerLeanModifier

@export var pivot_bone: String = "DEF-spine"

@export var max_tilt_angle: float = 3.0 # in degrees
@export var max_backward_tilt_angle: float = 5.0 # in degrees
@export var tilt_speed: float = 10.0
@export var sprint_tilt_multiplier: float = 1.5 # extra tilt multiplier when sprinting

@export_group("Body Bobbing")
@export var bobbing_amount: float = 0.015
@export var bobbing_sway_amount: float = 0.0075
@export var bobbing_speed: float = 8.0
@export var arm_bob_multiplier: float = 1.5 # How much more the arms bounce compared to the body
@export var arm_sway_multiplier: float = 3.0 # How much the chest twists to create left/right weapon sway
@export var sprint_bobbing_speed_multiplier: float = 1.3
@export var sprint_bobbing_amount_multiplier: float = 1.5

@export_group("Spine Lean Multipliers")
@export var spine_tilt_multiplier: float = 1.0
@export var chest_tilt_multiplier: float = 0.5 # keep lower to prevent shoulder clipping
@export var head_tilt_multiplier: float = 0.5

@export_group("Arm Exaggeration Settings")
@export var arm_tilt_multiplier: float = 1.0 # make arms tilt faster than body

@export_subgroup("Left Arm Offsets")
@export var left_arm_inward_x_offset: float = 0.1 # when leaning right (moving left)
@export var left_arm_outward_x_offset: float = -0.3 # when leaning left (moving right)
@export var left_arm_extra_z_offset: float = -0.3

@export_subgroup("Right Arm Offsets")
@export var right_arm_inward_x_offset: float = 0.5 # when leaning left (moving right)
@export var right_arm_outward_x_offset: float = -0.3 # when leaning right (moving left)
@export var right_arm_extra_z_offset: float = -0.3

var input_dir: Vector2 = Vector2.ZERO
var is_sprinting: bool = false
var is_aiming: bool = false
var is_reloading: bool = false
var is_rotating_in_place: bool = false
var is_grab: bool = false
var rotating_in_place_speed: float = 0.0
var current_tilt_x: float = 0.0
var current_tilt_z: float = 0.0
var _debug_non_zero_printed: bool = false
var _bob_time: float = 0.0
var _current_bob_weight: float = 0.0
@export_group("Procedural Shoulder Recoil")
@export var enable_shoulder_recoil: bool = true
@export var shoulder_recoil_multiplier: float = 1.0
@export var shoulder_kick_z: float = 0.08
@export var shoulder_kick_pitch: float = 0.12
@export var shoulder_recoil_recovery_speed: float = 14.0

@export_group("Procedural Shoulder Aim Sway")
@export var enable_shoulder_aim_sway: bool = true
@export var arm_crosshair_coupling: float = 0.003
@export var body_sway_coupling: float = 0.0008

@export_group("Procedural Body Recoil (DEF-spine.003)")
@export var enable_body_recoil: bool = true
@export var body_kick_pitch: float = 0.04
@export var body_recoil_recovery_speed: float = 10.0

var shoulder_recoil_pos: Vector3 = Vector3.ZERO
var shoulder_recoil_rot: Vector3 = Vector3.ZERO
var body_recoil_rot: float = 0.0

func trigger_shoulder_recoil(kick_z: float = 0.08, kick_pitch: float = 0.12) -> void:
	if not enable_shoulder_recoil:
		return
	shoulder_recoil_pos.z += kick_z * shoulder_recoil_multiplier
	shoulder_recoil_rot.x += kick_pitch * shoulder_recoil_multiplier
	# Body gets a small sympathetic knockback on every shot
	if enable_body_recoil:
		body_recoil_rot += body_kick_pitch * shoulder_recoil_multiplier

var current_global_bob_offset: Vector3 = Vector3.ZERO
var current_bob_x: float = 0.0
var current_bob_y: float = 0.0

# Bone names categorized by group
var spine_bones: Array[String] = ["DEF-spine", "ORG-spine"]
var chest_bones: Array[String] = ["DEF-spine.003", "ORG-spine.003"]
var head_bones: Array[String] = ["DEF-spine.006"]
var ik_parent_bones: Array[String] = [
	"MCH-hand_ik.parent.L",
	"MCH-hand_ik.parent.R",
	"MCH-upper_arm_ik_target.parent.L",
	"MCH-upper_arm_ik_target.parent.R"
]

func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton:
		return

	var pivot_idx = skeleton.find_bone(pivot_bone)
	if pivot_idx == -1:
		return

	var delta = get_process_delta_time()
	if delta <= 0.0:
		delta = get_physics_process_delta_time()
	if delta <= 0.0:
		delta = 0.016 # fallback

	# Calculate base tilts based on input
	var active_max_tilt = max_tilt_angle
	var active_backward_tilt = max_backward_tilt_angle
	if is_sprinting:
		active_max_tilt *= sprint_tilt_multiplier
		active_backward_tilt *= sprint_tilt_multiplier

	var target_tilt_x = 0.0
	if input_dir.y < 0.0:
		target_tilt_x = deg_to_rad(-input_dir.y * active_max_tilt)
	elif input_dir.y > 0.0:
		target_tilt_x = deg_to_rad(-input_dir.y * active_backward_tilt)
		
	var target_tilt_z = deg_to_rad(input_dir.x * active_max_tilt)
	
	if is_aiming:
		target_tilt_x = 0.0
		target_tilt_z = 0.0

	# Smoothly interpolate the tilts
	current_tilt_x = lerp_angle(current_tilt_x, target_tilt_x, delta * tilt_speed)
	current_tilt_z = lerp_angle(current_tilt_z, target_tilt_z, delta * tilt_speed)

	if not _debug_non_zero_printed and input_dir != Vector2.ZERO:
		_debug_non_zero_printed = true
		print("[SpineLeanModifier] First non-zero input: ", input_dir)
		print("  Pivot: ", pivot_bone, " idx: ", pivot_idx)

	var pivot_pos = skeleton.get_bone_global_pose(pivot_idx).origin

	# Calculate and apply body bobbing
	# Bob when moving or when rotating in place.
	# No bobbing when aiming, reloading, or grabbed (during grab loop QTE)
	var should_bob = (input_dir != Vector2.ZERO or is_rotating_in_place) and not is_aiming and not is_reloading and not is_grab
	var target_bob_weight = 1.0 if should_bob else 0.0
	_current_bob_weight = lerpf(_current_bob_weight, target_bob_weight, delta * 10.0)

	var active_bob_speed = bobbing_speed
	var active_bob_amount = bobbing_amount
	var active_sway_amount = bobbing_sway_amount
	if is_sprinting:
		active_bob_speed *= sprint_bobbing_speed_multiplier
		active_bob_amount *= sprint_bobbing_amount_multiplier
		active_sway_amount *= sprint_bobbing_amount_multiplier
	elif is_rotating_in_place:
		# Sync bobbing speed with the step system of the turn-in-place animation.
		# The turn-in-place animation (walk_side) has a length of 1.06 seconds, consisting of 2 steps.
		# A full cycle of bobbing (2 steps) corresponds to 2 * PI radians.
		# We scale the speed by 0.75 to make it slightly faster (3/4 of the step speed) and reduce the amplitude to 0.7 for a slightly subtler but noticeable look.
		active_bob_speed = (2.0 * PI / 1.06) * rotating_in_place_speed * 0.75
		active_bob_amount *= 0.7
		active_sway_amount *= 0.7

	# Only advance bob time when the weight is meaningfully active.
	# Do NOT hard-snap bob_time to 0 — let the weight fade to 0 smoothly to avoid pops.
	if _current_bob_weight > 0.001:
		_bob_time += delta * active_bob_speed

	var bob_y = abs(sin(_bob_time)) * active_bob_amount * _current_bob_weight
	var bob_x = sin(_bob_time) * active_sway_amount * _current_bob_weight
	
	# Expose pure values for camera-based aiming offsets (reversed to create weapon lag)
	current_bob_x = -bob_x
	current_bob_y = -bob_y
	
	var pivot_pose = skeleton.get_bone_pose(pivot_idx)
	
	# Calculate the true UP and RIGHT vectors in the parent bone's local space
	var parent_idx = skeleton.get_bone_parent(pivot_idx)
	var up_dir_local = Vector3(0, 1, 0)
	var right_dir_local = Vector3(1, 0, 0)
	if parent_idx != -1:
		var parent_global_pose = skeleton.get_bone_global_pose(parent_idx)
		up_dir_local = parent_global_pose.basis.inverse() * Vector3(0, 1, 0)
		right_dir_local = parent_global_pose.basis.inverse() * Vector3(1, 0, 0)
		
	pivot_pose.origin += up_dir_local.normalized() * bob_y
	pivot_pose.origin += right_dir_local.normalized() * bob_x
	skeleton.set_bone_pose(pivot_idx, pivot_pose)
	
	# Create a global offset vector to apply to the detached IK arms (and aim target)
	current_global_bob_offset = Vector3(bob_x, bob_y, 0) * arm_bob_multiplier

	# 1. Apply tilt to the spine bones (add Yaw for weapon sway!)
	_apply_tilt_to_group(skeleton, spine_bones, current_tilt_x * spine_tilt_multiplier, current_tilt_z * spine_tilt_multiplier, current_bob_x * arm_sway_multiplier)
	
	# 2. Apply tilt to the chest bones
	_apply_tilt_to_group(skeleton, chest_bones, current_tilt_x * chest_tilt_multiplier, current_tilt_z * chest_tilt_multiplier, current_bob_x * arm_sway_multiplier)

	# 3. Apply tilt to the head bones (only when NOT aiming so HeadLookAt has full control without modifier conflict)
	if not is_aiming:
		_apply_tilt_to_group(skeleton, head_bones, current_tilt_x * head_tilt_multiplier, current_tilt_z * head_tilt_multiplier)

	# 4. Apply exaggerated tilt and translation shift to the arm/hand IK parent bones
	var arm_tilt_x = current_tilt_x * arm_tilt_multiplier
	var arm_tilt_z = current_tilt_z * arm_tilt_multiplier
	var arm_tilt_basis = Basis.from_euler(Vector3(arm_tilt_x, 0.0, arm_tilt_z))

	for bone_name in ik_parent_bones:
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue

		var shift_x = 0.0
		var shift_z = 0.0
		if bone_name.ends_with(".L"):
			if current_tilt_z < 0.0:
				shift_x = -current_tilt_z * left_arm_inward_x_offset
			else:
				shift_x = current_tilt_z * left_arm_outward_x_offset
			shift_z = -current_tilt_x * left_arm_extra_z_offset
		elif bone_name.ends_with(".R"):
			if current_tilt_z > 0.0:
				shift_x = -current_tilt_z * right_arm_inward_x_offset
			else:
				shift_x = current_tilt_z * right_arm_outward_x_offset
			shift_z = -current_tilt_x * right_arm_extra_z_offset

		# Add the global bobbing offset so the IK hands bounce with the body
		var extra_shift = Vector3(shift_x, 0.0, shift_z) + current_global_bob_offset

		var pose = skeleton.get_bone_pose(bone_idx)
		var offset = pose.origin - pivot_pos
		var rotated_offset = arm_tilt_basis * offset
		pose.origin = pivot_pos + rotated_offset + extra_shift
		pose.basis = (arm_tilt_basis * pose.basis).orthonormalized()
		skeleton.set_bone_pose(bone_idx, pose)

	# Smoothly decay procedural shoulder recoil
	shoulder_recoil_pos = shoulder_recoil_pos.lerp(Vector3.ZERO, delta * shoulder_recoil_recovery_speed)
	shoulder_recoil_rot = shoulder_recoil_rot.lerp(Vector3.ZERO, delta * shoulder_recoil_recovery_speed)
	body_recoil_rot = lerpf(body_recoil_rot, 0.0, delta * body_recoil_recovery_speed)

	# 1:1 Synchronized coupling: read 2D crosshair sway_offset to drive 3D shoulder bone sway
	var sway_pitch_offset = 0.0
	var sway_yaw_offset = 0.0
	var body_sway_pitch = 0.0
	var body_sway_yaw = 0.0
	if is_aiming and enable_shoulder_aim_sway:
		var crosshairs = get_tree().get_nodes_in_group("crosshair")
		if crosshairs.size() > 0 and is_instance_valid(crosshairs[0]):
			var ch = crosshairs[0]
			if "sway_offset" in ch:
				sway_pitch_offset = ch.sway_offset.y * arm_crosshair_coupling
				sway_yaw_offset = -ch.sway_offset.x * arm_crosshair_coupling
				# Body moves subtly with the arms (smaller fraction)
				body_sway_pitch = ch.sway_offset.y * body_sway_coupling
				body_sway_yaw = -ch.sway_offset.x * body_sway_coupling

	# Apply aim body sway + shoot knockback to DEF-spine.003
	var chest_idx = skeleton.find_bone("DEF-spine.003")
	if chest_idx != -1:
		var chest_pose = skeleton.get_bone_pose(chest_idx)
		var total_body_pitch = body_sway_pitch - body_recoil_rot
		if abs(total_body_pitch) > 0.0001 or abs(body_sway_yaw) > 0.0001:
			var body_basis = Basis.from_euler(Vector3(total_body_pitch, body_sway_yaw, 0.0))
			var chest_parent_idx = skeleton.get_bone_parent(chest_idx)
			if chest_parent_idx != -1:
				var parent_global = skeleton.get_bone_global_pose(chest_parent_idx)
				var local_body_basis = parent_global.basis.inverse() * body_basis * parent_global.basis
				chest_pose.basis = (local_body_basis * chest_pose.basis).orthonormalized()
			else:
				chest_pose.basis = (body_basis * chest_pose.basis).orthonormalized()
		skeleton.set_bone_pose(chest_idx, chest_pose)

	# 5. Apply translation shift, procedural recoil, and aim breathing sway to the actual shoulder bones
	for bone_name in ["ORG-shoulder.L", "ORG-shoulder.R"]:
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue

		var pose = skeleton.get_bone_pose(bone_idx)
		
		var shift_x = 0.0
		var shift_z = 0.0
		if bone_name.ends_with(".L"):
			if current_tilt_z < 0.0:
				shift_x = -current_tilt_z * left_arm_inward_x_offset
			else:
				shift_x = current_tilt_z * left_arm_outward_x_offset
			shift_z = -current_tilt_x * left_arm_extra_z_offset
		elif bone_name.ends_with(".R"):
			if current_tilt_z > 0.0:
				shift_x = -current_tilt_z * right_arm_inward_x_offset
			else:
				shift_x = current_tilt_z * right_arm_outward_x_offset
			shift_z = -current_tilt_x * right_arm_extra_z_offset
			
			# Add procedural shoulder recoil (-Z backward knockback & pitch rotation)
			shift_z -= shoulder_recoil_pos.z
			if abs(shoulder_recoil_rot.x) > 0.0001:
				var recoil_basis = Basis.from_euler(Vector3(shoulder_recoil_rot.x, 0.0, 0.0))
				pose.basis = (recoil_basis * pose.basis).orthonormalized()

		# Apply organic arm aim breathing sway to shoulder bones
		if is_aiming and enable_shoulder_aim_sway:
			var arm_sway_basis = Basis.from_euler(Vector3(sway_pitch_offset, sway_yaw_offset, 0.0))
			pose.basis = (arm_sway_basis * pose.basis).orthonormalized()

		pose.origin.x += shift_x
		pose.origin.z += shift_z
		skeleton.set_bone_pose(bone_idx, pose)


func _apply_tilt_to_group(skeleton: Skeleton3D, bone_names: Array[String], tilt_x: float, tilt_z: float, tilt_y: float = 0.0) -> void:
	# Create the tilt rotation in global space (Pitch, Yaw, Roll)
	var group_tilt_basis = Basis.from_euler(Vector3(tilt_x, tilt_y, tilt_z))
	for bone_name in bone_names:
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue

		var pose = skeleton.get_bone_pose(bone_idx)
		var parent_idx = skeleton.get_bone_parent(bone_idx)
		
		var local_tilt_basis: Basis
		if parent_idx == -1:
			local_tilt_basis = group_tilt_basis
		else:
			var parent_global_pose = skeleton.get_bone_global_pose(parent_idx)
			# Convert the global tilt rotation into the bone's local space
			local_tilt_basis = parent_global_pose.basis.inverse() * group_tilt_basis * parent_global_pose.basis

		pose.basis = (local_tilt_basis * pose.basis).orthonormalized()
		skeleton.set_bone_pose(bone_idx, pose)
