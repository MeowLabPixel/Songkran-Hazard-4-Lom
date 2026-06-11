extends SkeletonModifier3D
class_name PlayerLeanModifier

@export var pivot_bone: String = "DEF-spine"

@export var max_tilt_angle: float = 6.0 # in degrees
@export var tilt_speed: float = 10.0
@export var sprint_tilt_multiplier: float = 1.5 # extra tilt multiplier when sprinting

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
var current_tilt_x: float = 0.0
var current_tilt_z: float = 0.0
var _debug_non_zero_printed: bool = false

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
	if is_sprinting:
		active_max_tilt *= sprint_tilt_multiplier

	var target_tilt_x = deg_to_rad(-input_dir.y * active_max_tilt)
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

	# 1. Apply tilt to the spine bones
	_apply_tilt_to_group(skeleton, spine_bones, current_tilt_x * spine_tilt_multiplier, current_tilt_z * spine_tilt_multiplier)

	# 2. Apply tilt to the chest bones (LookAt target bones)
	_apply_tilt_to_group(skeleton, chest_bones, current_tilt_x * chest_tilt_multiplier, current_tilt_z * chest_tilt_multiplier)

	# 3. Apply tilt to the head bones
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

		var extra_shift = Vector3(shift_x, 0.0, shift_z)

		var pose = skeleton.get_bone_pose(bone_idx)
		var offset = pose.origin - pivot_pos
		var rotated_offset = arm_tilt_basis * offset
		pose.origin = pivot_pos + rotated_offset + extra_shift
		pose.basis = arm_tilt_basis * pose.basis
		skeleton.set_bone_pose(bone_idx, pose)

	# 5. Apply translation shift to the actual shoulder bones to prevent clipping
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

		pose.origin.x += shift_x
		pose.origin.z += shift_z
		skeleton.set_bone_pose(bone_idx, pose)


func _apply_tilt_to_group(skeleton: Skeleton3D, bone_group: Array[String], tilt_x: float, tilt_z: float) -> void:
	var group_tilt_basis = Basis.from_euler(Vector3(tilt_x, 0.0, tilt_z))
	for bone_name in bone_group:
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
			local_tilt_basis = parent_global_pose.basis.inverse() * group_tilt_basis * parent_global_pose.basis

		pose.basis = local_tilt_basis * pose.basis
		skeleton.set_bone_pose(bone_idx, pose)
