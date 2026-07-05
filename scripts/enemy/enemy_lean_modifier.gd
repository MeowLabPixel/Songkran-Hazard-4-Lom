extends SkeletonModifier3D
class_name EnemyLeanModifier

@export var max_tilt_angle: float = 2.5 # Halved from 5.0
@export var tilt_speed: float = 3.0 # Halved from 6.0 for smoother lingering lean transitions when turning

var current_tilt_x: float = 0.0
var current_tilt_z: float = 0.0

var enemy: CharacterBody3D

# Locomotion Sway variables (Drunk / Unbalanced motion)
var sway_time: float = 0.0
var sway_frequency: float = 3.5 # Matches walking speed frequency
var sway_amplitude: float = 4.0 # Halved from 8.0

# Hit Impact Sway variables
var impact_sway_z: float = 0.0
var target_impact_sway_z: float = 0.0
var impact_decay_rate: float = 0.5 # Slower decay rate (lasts ~0.8s to 1.0s) for high impact visibility
var last_sway_dir: float = 0.0 # Track direction of last shot's sway (alternating left/right)

func trigger_impact_sway(is_takedown: bool) -> void:
	if is_takedown:
		# Takedown: strictly sway to the left (negative roll), halved to 7.5 degrees
		target_impact_sway_z = -deg_to_rad(10)
		last_sway_dir = -1.0 # Align last direction to left
	else:
		# Normal hit: first shot sways randomly, subsequent shots alternate directions
		if last_sway_dir == 0.0:
			last_sway_dir = -1.0 if randf() > 0.5 else 1.0
		else:
			last_sway_dir = -last_sway_dir
			
		var random_offset = randf_range(-1.0, 2.0)
		target_impact_sway_z = last_sway_dir * deg_to_rad(6.25) + deg_to_rad(random_offset)

func _process_modification() -> void:
	if not enemy or not enemy.is_inside_tree(): return
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton: return
	
	var delta = get_process_delta_time()
	if delta <= 0.0: delta = 0.016
	
	# Process impact sway lerping and decay
	impact_sway_z = lerp(impact_sway_z, target_impact_sway_z, delta * 8.0) # Smooth transition to peak sway
	target_impact_sway_z = move_toward(target_impact_sway_z, 0.0, delta * impact_decay_rate)
	
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
	
	# Process locomotion sway accumulator based on movement
	if speed_factor > 0.01:
		sway_time += delta * sway_frequency
	else:
		sway_time = move_toward(sway_time, 0.0, delta * 5.0)
		
	# Locomotion sway (drunk tilt left/right)
	var movement_sway = 0.0
	if speed_factor > 0.01:
		movement_sway = sin(sway_time) * deg_to_rad(sway_amplitude) * speed_factor
	
	# Ignore residual velocities from the avoidance move_toward smoothing
	var dir = local_vel.normalized() if local_vel.length() > 0.8 else Vector3.ZERO
	
	# local_vel.z is negative when moving forward
	var target_tilt_x = deg_to_rad(-dir.z * max_tilt_angle * speed_factor * lean_multiplier)
	var target_tilt_z = 0.0
	
	current_tilt_x = lerp_angle(current_tilt_x, target_tilt_x, delta * tilt_speed)
	current_tilt_z = lerp_angle(current_tilt_z, target_tilt_z, delta * tilt_speed)
	
	# Blend lean, locomotion sway, and impact sway into the roll axis (Z) of the group
	var total_tilt_z = current_tilt_z + movement_sway + impact_sway_z
	var group_tilt_basis = Basis.from_euler(Vector3(current_tilt_x, 0.0, total_tilt_z))
	
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
