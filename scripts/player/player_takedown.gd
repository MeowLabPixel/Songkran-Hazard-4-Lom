extends State
#temp can do when idle,run,sprint
var anim_name = "TD/Take down anim"

@export_group("Hold & Release Timing")
@export var enable_hold_and_release: bool = true                     ## Enable dramatic slow windup hold before explosive kick release
@export_range(0.05, 0.6, 0.05) var start_hold_speed: float = 0.23     ## Initial slow-motion speed factor at start of windup (e.g. 0.23 = 23% speed)
@export_range(0.8, 2.0, 0.05) var release_speed_scale: float = 1.25   ## Explosive release speed scale when kick strikes
@export_range(1.0, 3.0, 0.1) var acceleration_curve: float = 1.4     ## Exponential acceleration curve during windup

@export_group("Hit Stop Settings")
@export var enable_hit_stop: bool = true
@export var enable_domino_hit_stop: bool = true
@export_range(0.02, 0.30, 0.01) var domino_delay: float = 0.07        ## Time delay between standard domino zombie hits (seconds)
@export_range(0.02, 0.30, 0.01) var domino_fatal_delay: float = 0.14  ## Time delay when domino zombie is defeated/killed (seconds)



@export var hitbox_enable_time: float = 0.28                         ## Keyframe position when takedown attack hitbox activates (seconds)
@export var hitbox_disable_time: float = 0.47                        ## Keyframe position when takedown attack hitbox deactivates (seconds)

@export_range(0.0, 0.5, 0.01) var anim_slow_duration: float = 0.08    ## Duration player & hit zombie move slow on impact (seconds)


@export_range(0.0, 0.2, 0.005) var anim_slow_speed: float = 0.02     ## Slow-motion speed scale on impact (e.g. 0.02 = 2% speed, 0.05 = 5% speed)
@export_range(0.0, 0.3, 0.01) var primary_time_stop_duration: float = 0.12 ## Engine time freeze duration for 0 HP fatal kill (seconds)
@export_range(0.0, 0.2, 0.01) var primary_time_stop_scale: float = 0.03   ## Engine time scale during 0 HP fatal kill
@export_range(0.0, 0.2, 0.01) var splash_time_stop_duration: float = 0.06  ## Engine time freeze duration for 0 HP splash kill (seconds)
@export_range(0.0, 0.2, 0.01) var splash_time_stop_scale: float = 0.10    ## Engine time scale during 0 HP splash kill
@export_range(0.01, 0.1, 0.005) var time_stop_ease_out_time: float = 0.04 ## Smooth easing recovery back to 1.0 time scale (seconds)

var splash_area: Area3D = null
var _hit_primary: bool = false
var _hit_enemies: Array[Node] = []
var _queued_enemies: Array[Node] = []
var _pending_domino_hits: Array[Dictionary] = []
var _domino_timer: float = 0.0
var _domino_combo_count: int = 0
var _anim_slow_timer: SceneTreeTimer = null
var _anim_slow_remaining: float = 0.0
var _enemy_prev_speed_scales: Dictionary = {}
var _target_player_rot_y: float = 0.0
var _is_aligning_player_rot: bool = false
var _hit_stop_tween: Tween = null
var _is_hit_stopping: bool = false
var _prev_capsule_transform: Transform3D = Transform3D.IDENTITY
var _has_valid_prev_ray: bool = false

var _state_timer: float = 0.0
var _anim_timeline_pos: float = 0.0
var _has_released_kick: bool = false
const TAKEDOWN_TIMEOUT_FALLBACK: float = 3.5


func _get_player_camera() -> Node:
	var cams = get_tree().get_nodes_in_group("player_camera") if get_tree() else []
	if cams.size() > 0:
		return cams[0]
	return null

func _enter() -> void:
	_state_timer = 0.0
	_anim_timeline_pos = 0.0
	_has_released_kick = false
	_hit_primary = false
	_hit_enemies.clear()
	_queued_enemies.clear()
	_pending_domino_hits.clear()
	_domino_timer = 0.0
	_has_valid_prev_ray = false

	_is_aligning_player_rot = false
	
	if enable_hold_and_release and is_instance_valid(owner) and "anim" in owner and owner.anim:
		owner.anim.set("parameters/Main/Takedown/TD_Take down anim/TimeScale/scale", 1.2 * start_hold_speed)
	
	# Cancel active aiming so camera offsets don't interfere
	if is_instance_valid(owner) and owner.has_method("cancel_aim"):
		owner.cancel_aim()
		
	# Calculate target facing direction using Godot native looking_at() transform
	var target_enemy = owner.takedown_target if is_instance_valid(owner) and "takedown_target" in owner else null
	var dynamic_blend_duration: float = 0.35
	
	if is_instance_valid(target_enemy):
		var target_pos = target_enemy.global_position
		target_pos.y = owner.global_position.y
		if target_pos.distance_squared_to(owner.global_position) > 0.01:
			var look_trans = owner.global_transform.looking_at(target_pos, Vector3.UP)
			_target_player_rot_y = look_trans.basis.get_euler().y
			
			# Dynamic blend duration based on rotation distance: min 0.35s (0°), max 0.45s (180°)
			var rot_delta: float = absf(angle_difference(owner.rotation.y, _target_player_rot_y))
			var rot_factor: float = clamp(rot_delta / PI, 0.0, 1.0)
			dynamic_blend_duration = lerp(0.35, 0.45, rot_factor)
			
			var cam_node = _get_player_camera()
			if cam_node:
				var desired_cam_yaw = -_target_player_rot_y
				
				# Smoothly blend character mesh rotation towards target
				if is_instance_valid(owner):
					var player_target_rot = owner.rotation.y + angle_difference(owner.rotation.y, _target_player_rot_y)
					var rot_tween := create_tween()
					rot_tween.set_trans(Tween.TRANS_SINE)
					rot_tween.set_ease(Tween.EASE_IN_OUT)
					rot_tween.tween_property(owner, "rotation:y", player_target_rot, dynamic_blend_duration)
					
				# Trigger hybrid additive takedown camera sweep (starts at 0.0, sweeps to target_diff, accepts mouse look additively)
				if cam_node.has_method("trigger_hybrid_takedown_yaw_sweep") and "camera_rotation" in cam_node:
					var cur_cam_rot = cam_node.camera_rotation.x
					var target_diff = angle_difference(cur_cam_rot, desired_cam_yaw)
					cam_node.trigger_hybrid_takedown_yaw_sweep(target_diff, dynamic_blend_duration)





	# Trigger dynamic cinematic takedown camera transition
	var cam = _get_player_camera()
	if cam:
		if cam.has_method("start_takedown_windup_zoom_in"):
			cam.start_takedown_windup_zoom_in(dynamic_blend_duration)
		elif cam.has_method("start_takedown_camera_transition"):
			cam.start_takedown_camera_transition()


	# Play Rookie Lee attack sound effects
	if randf() < 0.15:
		SoundManager.play_3d("vo_leon_attack", owner)
	else:
		SoundManager.play_3d("vo_leon_quickattack", owner)
		
	SoundManager.play_3d("leon_takedown", owner)
	SoundManager.play_3d("Region_PlayerTakedownAttackStart", owner)
		
	owner.aim_bone_on(false)
	stop_moving()
	owner.anim.get(owner.anim_playback).travel("Takedown")
	if not owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.connect(anim_done)
	owner.hitboxF.monitoring = false
	owner.hitboxB.monitoring = false
	# Reference the pre-configured takedown hitbox in the scene (Keep disabled during windup phase)
	splash_area = owner.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox")
	if splash_area:
		splash_area.monitoring = false
		if not splash_area.area_entered.is_connected(_on_splash_area_entered):
			splash_area.area_entered.connect(_on_splash_area_entered)
	else:
		push_warning("[PlayerTakedown] TakedownHitbox not found at path Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox")


func _update(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= TAKEDOWN_TIMEOUT_FALLBACK:
		push_warning("[PlayerTakedown] Safety timeout reached, transitioning to Idle.")
		finished.emit("Idle")
		return
		
	# Track animation timeline position & handle gradual windup acceleration
	if enable_hold_and_release and not _has_released_kick:
		var progress: float = clamp(_anim_timeline_pos / hitbox_enable_time, 0.0, 1.0)
		var current_speed: float = lerp(start_hold_speed, release_speed_scale, pow(progress, acceleration_curve))
		_anim_timeline_pos += delta * current_speed
		
		if is_instance_valid(owner) and "anim" in owner and owner.anim:
			owner.anim.set("parameters/Main/Takedown/TD_Take down anim/TimeScale/scale", 1.2 * current_speed)
			
		if _anim_timeline_pos >= hitbox_enable_time:
			_has_released_kick = true
			if is_instance_valid(splash_area):
				splash_area.monitoring = true # Enable attack hitbox now that windup phase has ended
			if is_instance_valid(owner) and "anim" in owner and owner.anim:
				owner.anim.set("parameters/Main/Takedown/TD_Take down anim/TimeScale/scale", 1.2 * release_speed_scale)
			
			# Trigger quick release zoom OUT on camera
			var cam = _get_player_camera()
			if cam and cam.has_method("trigger_takedown_release_zoom_out"):
				cam.trigger_takedown_release_zoom_out()
	else:
		_anim_timeline_pos += delta * (release_speed_scale if enable_hold_and_release else 1.0)
		if not enable_hold_and_release and _anim_timeline_pos >= hitbox_enable_time:
			_has_released_kick = true
			if is_instance_valid(splash_area) and not splash_area.monitoring and _anim_timeline_pos <= hitbox_disable_time:
				splash_area.monitoring = true

	# Process hit detection strictly within active release window (hitbox_enable_time to hitbox_disable_time)
	if _anim_timeline_pos >= hitbox_enable_time and _anim_timeline_pos <= hitbox_disable_time:
		if is_instance_valid(splash_area) and not splash_area.monitoring:
			splash_area.monitoring = true
		_check_overlapping_splash()
		
		# Process precise TakedownAttackBox shapecast and timed spatial proximity window
		_process_capsule_swept_shapecast()
	elif _anim_timeline_pos > hitbox_disable_time:
		if is_instance_valid(splash_area) and splash_area.monitoring:
			splash_area.monitoring = false
		_has_valid_prev_ray = false

		
	# Process domino hit stop queue with staggered delay (0.07s standard vs 0.14s fatal defeat kill)
	if enable_domino_hit_stop and not _pending_domino_hits.is_empty():
		_domino_timer -= delta
		if _domino_timer <= 0.0:
			var hit_info = _pending_domino_hits.pop_front()
			var enemy = hit_info.get("enemy") as Node
			var is_fatal: bool = false
			if is_instance_valid(enemy):
				if "current_hp" in enemy:
					is_fatal = (enemy.current_hp <= 1.33 or enemy.current_hp <= 0)
				if not is_fatal and ("is_takedown_defeat" in enemy or "is_defeated" in enemy):
					is_fatal = (enemy.get("is_takedown_defeat") == true or enemy.get("is_defeated") == true)
			_domino_timer = domino_fatal_delay if is_fatal else domino_delay
			_execute_domino_hit(hit_info)


func _process_capsule_swept_shapecast() -> void:
	var attack_box_node = owner.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox/TakedownAttackBox")
	if not is_instance_valid(attack_box_node) or not is_inside_tree():
		return
		
	var shape_resource: Shape3D = null
	if attack_box_node is CollisionShape3D:
		shape_resource = attack_box_node.shape
	elif attack_box_node is CollisionObject3D:
		for child in attack_box_node.get_children():
			if child is CollisionShape3D:
				shape_resource = child.shape
				break
				
	var curr_transform: Transform3D = attack_box_node.global_transform
	var is_first_frame: bool = false
	if not _has_valid_prev_ray:
		_prev_capsule_transform = curr_transform
		_has_valid_prev_ray = true
		is_first_frame = true
		
	var space_state = owner.get_world_3d().direct_space_state
	if not space_state:
		return
		
	if shape_resource:
		var exclude_rids: Array[RID] = [owner.get_rid()]
		var num_steps: int = 1 if is_first_frame else 6
		var player_pos: Vector3 = owner.global_position
		
		var rel_prev: Vector3 = _prev_capsule_transform.origin - player_pos
		var rel_curr: Vector3 = curr_transform.origin - player_pos
		var r_prev: float = rel_prev.length()
		var r_curr: float = rel_curr.length()
		var angle_prev: float = atan2(rel_prev.x, rel_prev.z)
		var angle_curr: float = angle_prev + angle_difference(angle_prev, atan2(rel_curr.x, rel_curr.z))
		
		var q_prev: Quaternion = _prev_capsule_transform.basis.get_rotation_quaternion()
		var q_curr: Quaternion = curr_transform.basis.get_rotation_quaternion()
		
		for step in range(num_steps + 1):
			var t: float = float(step) / float(num_steps)
			
			# Arc origin interpolation around player center Y-axis (preserves 1.5m radius)
			var radius: float = lerp(r_prev, r_curr, t)
			var angle: float = lerp(angle_prev, angle_curr, t)
			var step_y: float = lerp(_prev_capsule_transform.origin.y, curr_transform.origin.y, t)
			var step_origin: Vector3 = Vector3(player_pos.x + sin(angle) * radius, step_y, player_pos.z + cos(angle) * radius)
			
			# Quaternion slerp for un-warped basis rotation
			var step_basis: Basis = Basis(q_prev.slerp(q_curr, t))
			var step_transform: Transform3D = Transform3D(step_basis, step_origin)
			
			var query = PhysicsShapeQueryParameters3D.new()
			query.shape = shape_resource
			query.transform = step_transform
			query.collide_with_areas = true
			query.collide_with_bodies = true
			query.collision_mask = 8198 # Layer 2 hitboxes, Layer 3 enemies, Layer 14 hitboxes
			query.exclude = exclude_rids
			
			var results = space_state.intersect_shape(query, 32)
			for res in results:
				var collider = res.get("collider")
				if is_instance_valid(collider):
					if collider is RID:
						exclude_rids.append(collider)
					else:
						exclude_rids.append(collider.get_rid())
						var enemy = _find_enemy_from_node(collider)
						if enemy and not enemy.is_defeated:
							_register_enemy_takedown_hit(enemy, collider)

	_prev_capsule_transform = curr_transform

func _is_enemy_takedown_protected(enemy: Node) -> bool:
	if not is_instance_valid(enemy):
		return true
	var sm = enemy.get_node_or_null("EnemyStateMachine")
	if not sm or not is_instance_valid(sm.current_state):
		return false
	var state_name: String = sm.current_state.name
	if state_name == "StateGetUp":
		return true
	if state_name == "StateKnockdown":
		var kd = sm.current_state as StateKnockdown
		if kd and kd._phase in [StateKnockdown.Phase.ACT4, StateKnockdown.Phase.ACT5]:
			return true
	return false

func _register_enemy_takedown_hit(enemy: Node, hit_node: Node = null) -> void:
	if not is_instance_valid(enemy) or enemy.is_defeated or _is_enemy_takedown_protected(enemy):
		return
		
	if enemy in _hit_enemies or enemy in _queued_enemies:
		return
		
	# First enemy hit receives primary takedown hit (give priority to owner.takedown_target if assigned)
	if not _hit_primary:
		if is_instance_valid(owner) and "takedown_target" in owner and is_instance_valid(owner.takedown_target) and not owner.takedown_target.is_defeated:
			if enemy == owner.takedown_target or _hit_enemies.is_empty():
				_execute_primary_hit(enemy)
				return
		else:
			_execute_primary_hit(enemy)
			return
		
	var zone_name := "body"
	if is_instance_valid(hit_node):
		if hit_node is HitboxZone:
			zone_name = hit_node.zone_name
		elif hit_node.has_node("HitboxZone"):
			var hz = hit_node.get_node("HitboxZone")
			if hz is HitboxZone:
				zone_name = hz.zone_name
				
	var hit_info = {
		"enemy": enemy,
		"area": hit_node if hit_node is Area3D else null,
		"zone_name": zone_name
	}
	
	if enable_domino_hit_stop:
		_queued_enemies.append(enemy)
		_pending_domino_hits.append(hit_info)
		_sort_pending_domino_hits()
		if _pending_domino_hits.size() == 1:
			var is_fatal: bool = false
			if "current_hp" in enemy:
				is_fatal = (enemy.current_hp <= 1.33 or enemy.current_hp <= 0)
			if not is_fatal and ("is_takedown_defeat" in enemy or "is_defeated" in enemy):
				is_fatal = (enemy.get("is_takedown_defeat") == true or enemy.get("is_defeated") == true)
			_domino_timer = domino_fatal_delay if is_fatal else domino_delay
	else:
		_execute_splash_hit(hit_info)



func _sort_pending_domino_hits() -> void:
	if _pending_domino_hits.size() <= 1 or not is_instance_valid(owner):
		return
	var player_pos: Vector3 = owner.global_position
	var player_fwd: Vector3 = -owner.global_transform.basis.z
	var fwd_angle: float = atan2(player_fwd.x, player_fwd.z)
	
	_pending_domino_hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var enemy_a = a.get("enemy") as Node
		var enemy_b = b.get("enemy") as Node
		if not is_instance_valid(enemy_a) or not is_instance_valid(enemy_b):
			return false
		var pos_a: Vector3 = enemy_a.global_position - player_pos
		var pos_b: Vector3 = enemy_b.global_position - player_pos
		var ang_a: float = wrapf(atan2(pos_a.x, pos_a.z) - fwd_angle, -PI, PI)
		var ang_b: float = wrapf(atan2(pos_b.x, pos_b.z) - fwd_angle, -PI, PI)
		return ang_a < ang_b
	)



func _find_enemy_from_node(node: Node) -> EnemyBase:
	var curr = node
	while curr:
		if curr is EnemyBase:
			return curr
		curr = curr.get_parent()
	return null

func _exit() -> void:
	_has_valid_prev_ray = false
	# Ensure hit stop tween is killed and engine time scale is restored
	_reset_hit_stop()
	
	# Smoothly restore standard gameplay camera view
	var cam = _get_player_camera()
	if cam and cam.has_method("exit_takedown_camera_transition"):
		cam.exit_takedown_camera_transition()
	
	if is_instance_valid(owner):
		if "anim" in owner and owner.anim:
			owner.anim.set("parameters/Main/Takedown/TD_Take down anim/TimeScale/scale", 1.2)
			if owner.anim.animation_finished.is_connected(anim_done):
				owner.anim.animation_finished.disconnect(anim_done)
		if owner.stun_detect:
			owner.stun_detect.monitorable = false
		if owner.hitboxF:
			owner.hitboxF.monitoring = true
		if owner.hitboxB:
			owner.hitboxB.monitoring = true
	
	if is_instance_valid(splash_area):
		splash_area.monitoring = false
		if splash_area.area_entered.is_connected(_on_splash_area_entered):
			splash_area.area_entered.disconnect(_on_splash_area_entered)
			
	# Flush any remaining queued domino hits before exiting state
	while not _pending_domino_hits.is_empty():
		var hit_info = _pending_domino_hits.pop_front()
		_execute_domino_hit(hit_info)

	splash_area = null
	_hit_primary = false
	_domino_combo_count = 0
	_reset_anim_slow()
	_hit_enemies.clear()
	_queued_enemies.clear()
	_pending_domino_hits.clear()



func anim_done(namee: String):
	if namee == anim_name:
		finished.emit("Idle")

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)

func _check_overlapping_splash() -> void:
	if not is_instance_valid(splash_area) or not splash_area.monitoring:
		return
	# Query overlapping Area3D hitboxes (HitboxZones)
	for a in splash_area.get_overlapping_areas():
		_process_splash_hit(a)
	# Query overlapping CharacterBody3D physics bodies (EnemyBase)
	for b in splash_area.get_overlapping_bodies():
		_process_splash_hit(b)

func _on_splash_area_entered(area: Area3D) -> void:
	_process_splash_hit(area)

func _process_splash_hit(node: Node) -> void:
	if _anim_timeline_pos < hitbox_enable_time or _anim_timeline_pos > hitbox_disable_time:
		return
		
	var enemy = _find_enemy_from_node(node)
	if enemy:
		_register_enemy_takedown_hit(enemy, node)


func _execute_primary_hit(enemy: Node) -> void:
	if not is_instance_valid(enemy) or enemy.is_defeated or enemy in _hit_enemies:
		return
		
	_hit_primary = true
	_hit_enemies.append(enemy)
	_domino_combo_count = 1


	if enemy.has_method("trigger_takedown"):
		enemy.trigger_takedown()
	else:
		var sm = enemy.get_node_or_null("EnemyStateMachine")
		if sm:
			var td = sm.get_node_or_null("StateTakedownable")
			if td:
				td.trigger_takedown()
	
	var hit_dir = (enemy.global_position - owner.global_position).normalized()
	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()
	if enemy.has_method("take_hit"):
		enemy.take_hit({
			"damage": 1.33,
			"hit_zone": "body",
			"hit_type": "takedown",
			"hit_direction": hit_dir,
			"source": owner
		})
	
	# 1. ALWAYS slow down player and zombie animations briefly to convey physical impact
	_trigger_anim_slow(enemy, anim_slow_duration, anim_slow_speed)
	
	# 2. Trigger engine TIME STOP ONLY if zombie is reduced to 0 HP (fatal kill)
	var is_fatal: bool = false
	if "current_hp" in enemy:
		is_fatal = (enemy.current_hp <= 0)
	if not is_fatal and ("is_takedown_defeat" in enemy or "is_defeated" in enemy):
		is_fatal = (enemy.get("is_takedown_defeat") == true or enemy.get("is_defeated") == true)
	
	if is_fatal:
		_trigger_time_stop(primary_time_stop_duration, primary_time_stop_scale)
	
	# Trigger takedown screen shake & FOV impact punch on player camera
	var cam = _get_player_camera()
	if cam:
		if cam.has_method("trigger_takedown_impact_fov_kick"):
			cam.trigger_takedown_impact_fov_kick()
		if cam.has_method("trigger_takedown_shake"):
			cam.trigger_takedown_shake()
			
	# Trigger stylized UI takedown shockwave at impact position
	var ui = get_tree().get_first_node_in_group("player_ui") if get_tree() else null
	if ui and ui.has_method("spawn_takedown_shockwave"):
		ui.spawn_takedown_shockwave(enemy.global_position)


func _execute_domino_hit(hit_info: Dictionary) -> void:
	var enemy = hit_info.get("enemy") as Node
	if not is_instance_valid(enemy) or enemy.is_defeated:
		return
		
	_domino_combo_count += 1
	var pitch_multiplier: float = clamp(1.0 + (_domino_combo_count - 1) * 0.08, 1.0, 1.35)
	var raw_pitch = enemy.get("custom_pitch_scale") if "custom_pitch_scale" in enemy else null
	var base_pitch: float = 1.0
	if raw_pitch != null and typeof(raw_pitch) in [TYPE_FLOAT, TYPE_INT] and float(raw_pitch) > 0.0:
		base_pitch = float(raw_pitch)

	# Trigger dedicated domino impact SFX & pain voiceline with escalating pitch
	SoundManager.play_3d("zombie_melee_hit", enemy, 0.0, -1.0, pitch_multiplier)
	var event_name = "vo_zombie_m_melee_gethit" if ("voice_character" in enemy and enemy.voice_character == "Zombie Male") else "vo_zombie_f_melee_gethit"
	SoundManager.play_3d(event_name, enemy, 0.0, -1.0, base_pitch * pitch_multiplier)

	# Trigger stylized UI shockwave at domino zombie 3D position with growing scale
	var ui = get_tree().get_first_node_in_group("player_ui") if get_tree() else null
	if ui and ui.has_method("spawn_takedown_shockwave"):
		var shock_scale: float = clamp(1.0 + (_domino_combo_count - 1) * 0.25, 1.0, 2.0)
		ui.spawn_takedown_shockwave(enemy.global_position, shock_scale)

	_execute_splash_hit(hit_info)


func _execute_splash_hit(hit_info: Dictionary) -> void:
	var enemy = hit_info.get("enemy") as Node
	if not is_instance_valid(enemy) or enemy.is_defeated:
		return
		
	if enemy in _hit_enemies:
		return
	_hit_enemies.append(enemy)
	
	var zone_name = hit_info.get("zone_name", "body")
	var hit_dir = (enemy.global_position - owner.global_position).normalized()
	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()
	
	enemy.take_hit({
		"damage": 1.33,
		"hit_zone": zone_name,
		"hit_type": "takedown_splash",
		"hit_direction": hit_dir,
		"source": owner
	})
	
	# 1. Trigger domino animation micro slow-down
	_trigger_anim_slow(enemy, anim_slow_duration, anim_slow_speed)
	
	# 2. Trigger engine TIME STOP ONLY if collateral splash hit resulted in 0 HP (fatal kill)
	var is_fatal_splash: bool = false
	if "current_hp" in enemy:
		is_fatal_splash = (enemy.current_hp <= 0)
	if not is_fatal_splash and ("is_takedown_defeat" in enemy or "is_defeated" in enemy):
		is_fatal_splash = (enemy.get("is_takedown_defeat") == true or enemy.get("is_defeated") == true)
		
	if is_fatal_splash:
		_trigger_time_stop(splash_time_stop_duration, splash_time_stop_scale)
		
	# Trigger camera micro shake for domino splash hit
	var cams = get_tree().get_nodes_in_group("player_camera") if get_tree() else []
	for cam in cams:
		if cam.has_method("trigger_takedown_shake"):
			cam.trigger_takedown_shake()

func _trigger_anim_slow(enemy: Node, duration: float, slow_speed_factor: float) -> void:
	if not enable_hit_stop or duration <= 0.0:
		return
	# Avoid applying extreme slowdown if animation is past active hitbox window
	if _anim_timeline_pos > (hitbox_disable_time + 0.5):
		return
		
	# 1. Set player takedown AnimationTree TimeScale parameter relative to default 1.2 scale
	if is_instance_valid(owner) and "anim" in owner and owner.anim:
		owner.anim.set("parameters/Main/Takedown/TD_Take down anim/TimeScale/scale", 1.2 * slow_speed_factor)
		
	# 2. Set enemy AnimationPlayer speed_scale for zombie slow-mo
	var e_ap: AnimationPlayer = null
	if is_instance_valid(enemy):
		if "anim_player" in enemy and enemy.anim_player and enemy.anim_player is AnimationPlayer:
			e_ap = enemy.anim_player
		elif "anim_tree" in enemy and enemy.anim_tree and enemy.anim_tree is AnimationTree:
			e_ap = enemy.anim_tree.get_node_or_null(enemy.anim_tree.anim_player) as AnimationPlayer
			
	if e_ap:
		if not _enemy_prev_speed_scales.has(e_ap):
			_enemy_prev_speed_scales[e_ap] = e_ap.speed_scale
		e_ap.speed_scale = slow_speed_factor
		
	# 3. Additive stacking timer duration
	_anim_slow_remaining = clamp(_anim_slow_remaining + duration, 0.0, 0.30)
	
	var tree = get_tree()
	if not tree:
		return
		
	if _anim_slow_timer == null:
		_run_anim_slow_timer(tree, e_ap)

func _run_anim_slow_timer(tree: SceneTree, e_ap: AnimationPlayer) -> void:
	if _anim_slow_remaining <= 0.0:
		_reset_anim_slow(e_ap)
		return
		
	var step_duration: float = min(_anim_slow_remaining, 0.03)
	_anim_slow_remaining -= step_duration
	
	_anim_slow_timer = tree.create_timer(step_duration, true, false, true)
	_anim_slow_timer.timeout.connect(func():
		if _anim_slow_remaining > 0.0:
			_run_anim_slow_timer(tree, e_ap)
		else:
			_reset_anim_slow(e_ap)
	)

func _reset_anim_slow(e_ap: AnimationPlayer = null) -> void:
	_anim_slow_remaining = 0.0
	_anim_slow_timer = null
	if is_instance_valid(owner) and "anim" in owner and owner.anim:
		owner.anim.set("parameters/Main/Takedown/TD_Take down anim/TimeScale/scale", 1.2)
	if is_instance_valid(e_ap):
		var prev_scale: float = _enemy_prev_speed_scales.get(e_ap, 1.0)
		_enemy_prev_speed_scales.erase(e_ap)
		e_ap.speed_scale = prev_scale



func _trigger_time_stop(duration: float, time_scale: float) -> void:
	if not enable_hit_stop or duration <= 0.0:
		return
		
	if _hit_stop_tween and _hit_stop_tween.is_valid():
		_hit_stop_tween.kill()
		_hit_stop_tween = null
		
	_is_hit_stopping = true
	Engine.time_scale = time_scale
	
	var tree = get_tree()
	if not tree:
		Engine.time_scale = 1.0
		_is_hit_stopping = false
		return
		
	var timer = tree.create_timer(duration, true, false, true)
	timer.timeout.connect(func():
		if not is_inside_tree():
			Engine.time_scale = 1.0
			_is_hit_stopping = false
			return
			
		_hit_stop_tween = create_tween()
		if _hit_stop_tween:
			_hit_stop_tween.tween_property(Engine, "time_scale", 1.0, time_stop_ease_out_time)\
				.set_trans(Tween.TRANS_CUBIC)\
				.set_ease(Tween.EASE_OUT)
			_hit_stop_tween.finished.connect(func():
				Engine.time_scale = 1.0
				_is_hit_stopping = false
			)
		else:
			Engine.time_scale = 1.0
			_is_hit_stopping = false
	)

func _reset_hit_stop() -> void:
	if _hit_stop_tween and _hit_stop_tween.is_valid():
		_hit_stop_tween.kill()
		_hit_stop_tween = null
	Engine.time_scale = 1.0
	_is_hit_stopping = false

func _find_enemy_from_area(area: Area3D) -> Node:
	var node = area
	while node:
		if node is EnemyBase:
			return node
		node = node.get_parent()
	return null
