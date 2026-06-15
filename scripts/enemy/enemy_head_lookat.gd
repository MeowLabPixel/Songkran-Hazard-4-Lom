extends SkeletonModifier3D
class_name EnemyHeadLookAt

var enemy: CharacterBody3D
var player: Node3D
@export var head_bone_name: String = "DEF-spine.006"
@export var max_angle_deg: float = 65.0
@export var tracking_speed: float = 5.0

var current_yaw: float = 0.0
var current_pitch: float = 0.0

func _process_modification() -> void:
	if not enemy or not enemy.is_inside_tree(): return
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton: return
	
	if not player or not player.is_inside_tree():
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		else:
			_relax_head()
			return
			
	var head_idx = skeleton.find_bone(head_bone_name)
	if head_idx == -1: return
	
	# Look at chest/head level of the player
	var target_pos = player.global_position + Vector3(0, 1.4, 0)
	var my_head_pos = skeleton.to_global(skeleton.get_bone_global_pose(head_idx).origin)
	var dir_to_target = (target_pos - my_head_pos).normalized()
	
	var local_dir = enemy.global_transform.basis.inverse() * dir_to_target
	# local forward is -Z. Right is X. Up is Y.
	var target_yaw = atan2(-local_dir.x, -local_dir.z)
	var target_pitch = asin(local_dir.y)
	
	# Clamp angles to prevent snapping necks Exorcist-style
	target_yaw = clamp(target_yaw, deg_to_rad(-max_angle_deg), deg_to_rad(max_angle_deg))
	target_pitch = clamp(target_pitch, deg_to_rad(-max_angle_deg), deg_to_rad(max_angle_deg))
	
	var dist = enemy.global_position.distance_to(player.global_position)
	if dist > 15.0 or dist < 0.8:
		# Don't track if too far, or if too close (to avoid head twisting down unnaturally)
		target_yaw = 0.0
		target_pitch = 0.0
		
	var delta = get_process_delta_time()
	if delta <= 0.0: delta = 0.016
	
	current_yaw = lerp_angle(current_yaw, target_yaw, delta * tracking_speed)
	current_pitch = lerp_angle(current_pitch, target_pitch, delta * tracking_speed)
	
	var head_rot = Basis.from_euler(Vector3(current_pitch, current_yaw, 0.0))
	
	var pose = skeleton.get_bone_pose(head_idx)
	var parent_idx = skeleton.get_bone_parent(head_idx)
	var local_rot_basis: Basis
	
	if parent_idx == -1:
		local_rot_basis = head_rot
	else:
		var p_pose = skeleton.get_bone_global_pose(parent_idx)
		local_rot_basis = p_pose.basis.inverse() * head_rot * p_pose.basis
		
	pose.basis = local_rot_basis * pose.basis
	skeleton.set_bone_pose(head_idx, pose)

func _relax_head() -> void:
	current_yaw = lerp_angle(current_yaw, 0.0, 0.016 * tracking_speed)
	current_pitch = lerp_angle(current_pitch, 0.0, 0.016 * tracking_speed)
