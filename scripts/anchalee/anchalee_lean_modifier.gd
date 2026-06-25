extends SkeletonModifier3D
class_name AnchaleeLeanModifier

@export var max_tilt_angle: float = 6.0
@export var tilt_speed: float = 8.0
@export var forward_lean_factor: float = 0.4 # reduce forward lean (multiplier)

var current_tilt_x: float = 0.0
var current_tilt_z: float = 0.0

var anchalee: CharacterBody3D

func _process_modification() -> void:
	if not anchalee or not anchalee.is_inside_tree(): return
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton: return
	
	var delta = get_process_delta_time()
	if delta <= 0.0: delta = 0.016
	
	var local_vel = anchalee.global_transform.basis.inverse() * anchalee.velocity
	
	# Only lean at meaningful speeds (anchalee walk speed is ~2.8-3.5)
	var speed_factor = clamp((local_vel.length() - 0.5) / 3.0, 0.0, 1.0)
	
	# Only apply lean during active movement states (Walk state)
	# Disable for all stationary states to prevent residual velocity causing a forward lean
	var lean_multiplier = 1.0
	if "state_machine" in anchalee and anchalee.state_machine != null:
		var sm = anchalee.state_machine
		if sm.current_state:
			var state_name = sm.current_state.name
			if state_name != "AnchaleeStateWalk":
				speed_factor = 0.0
	
	# Ignore residual velocities from the avoidance move_toward smoothing
	var dir = local_vel.normalized() if local_vel.length() > 0.5 else Vector3.ZERO
	
	# local_vel.z is negative when moving forward
	var forward_factor = 1.0
	if dir.z < 0.0:
		forward_factor = forward_lean_factor
		
	var target_tilt_x = deg_to_rad(-dir.z * max_tilt_angle * speed_factor * lean_multiplier * forward_factor)
	var target_tilt_z = deg_to_rad(dir.x * max_tilt_angle * speed_factor * lean_multiplier)
	
	current_tilt_x = lerp_angle(current_tilt_x, target_tilt_x, delta * tilt_speed)
	current_tilt_z = lerp_angle(current_tilt_z, target_tilt_z, delta * tilt_speed)
	
	var group_tilt_basis = Basis.from_euler(Vector3(current_tilt_x, 0.0, current_tilt_z))
	
	var bones = ["DEF-spine", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]
	for bone_name in bones:
		var b_idx = skeleton.find_bone(bone_name)
		if b_idx != -1:
			var pose = skeleton.get_bone_pose(b_idx)
			var parent_idx = skeleton.get_bone_parent(b_idx)
			var local_tilt_basis: Basis
			if parent_idx == -1:
				local_tilt_basis = group_tilt_basis
			else:
				var p_pose = skeleton.get_bone_global_pose(parent_idx)
				local_tilt_basis = p_pose.basis.inverse() * group_tilt_basis * p_pose.basis
			
			pose.basis = local_tilt_basis * pose.basis
			skeleton.set_bone_pose(b_idx, pose)
