extends SkeletonModifier3D
class_name EnemyLeanModifier

@export var max_tilt_angle: float = 5.0
@export var tilt_speed: float = 6.0

var current_tilt_x: float = 0.0
var current_tilt_z: float = 0.0

var enemy: CharacterBody3D

func _process_modification() -> void:
	if not enemy or not enemy.is_inside_tree(): return
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton: return
	
	var delta = get_process_delta_time()
	if delta <= 0.0: delta = 0.016
	
	var local_vel = enemy.global_transform.basis.inverse() * enemy.velocity
	
	# Only lean at meaningful speeds (move_speed is 2.0)
	var speed_factor = clamp((local_vel.length() - 0.8) / 2.0, 0.0, 1.0)
	
	# Only apply lean during active movement states (Hunt walking, Defeated walking)
	# Disable for all stationary states to prevent residual velocity causing a forward lean
	var lean_multiplier = 1.0
	if "state_machine" in enemy and enemy.state_machine != null:
		var sm = enemy.state_machine
		if sm.current_state:
			var state_name = sm.current_state.name
			if state_name == "StateTakedownable":
				lean_multiplier = 2.0 # Exaggerated lean during stumble
			elif state_name not in ["StateHunt", "StateDefeated"]:
				speed_factor = 0.0
	
	# Ignore residual velocities from the avoidance move_toward smoothing
	var dir = local_vel.normalized() if local_vel.length() > 0.8 else Vector3.ZERO
	
	# local_vel.z is negative when moving forward
	var target_tilt_x = deg_to_rad(-dir.z * max_tilt_angle * speed_factor * lean_multiplier)
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
