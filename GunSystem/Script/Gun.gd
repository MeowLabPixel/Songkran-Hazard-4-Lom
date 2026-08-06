extends Node3D
class_name Gun

@export var gun_name: String = "Water pistol"
@export var camera: Camera3D
@export var spawn_point: Node3D
@export var shot_vfx_scene: PackedScene
@export var hit_vfx_scene: PackedScene
@export var muzzle_vfx_scene: PackedScene

@export_group("VFX Customization")
@export var muzzle_scale: Vector3 = Vector3.ONE
@export var muzzle_offset: Vector3 = Vector3.ZERO
@export var impact_scale: Vector3 = Vector3.ONE
@export var impact_offset: Vector3 = Vector3.ZERO
@export var muzzle_animation_name: String = ""
@export var impact_animation_name: String = ""

@export_group("Recoil & Juice Settings")
@export var enable_arm_recoil: bool = true
@export var recoil_pitch: float = 1.6
@export var recoil_yaw: float = 0.5
@export var camera_fov_kick: float = 1.8
@export var camera_shake: float = 0.04
@export var crosshair_shot_kick: float = 9.0
@export var mesh_kick_z: float = 0.10
@export var mesh_kick_x: float = 0.012
@export var mesh_kick_y: float = 0.015
@export var mesh_kick_pitch: float = 0.14
@export var mesh_kick_yaw: float = 0.025
@export var mesh_kick_roll: float = 0.035
@export var mesh_recoil_recovery_speed: float = 14.0

@export_group("Procedural Shoulder Recoil")
@export var shoulder_kick_z: float = 0.08
@export var shoulder_kick_pitch: float = 0.12

var mesh_offset_z: float = 0.0
var mesh_offset_x: float = 0.0
var mesh_offset_y: float = 0.0
var mesh_offset_pitch: float = 0.0
var mesh_offset_yaw: float = 0.0
var mesh_offset_roll: float = 0.0

var mesh_container: Node3D = null
var initial_mesh_pos: Vector3 = Vector3.ZERO
var initial_mesh_rot: Vector3 = Vector3.ZERO
var is_mesh_init: bool = false

var water_tank: GunController

@export_group("Gun Stats")
@export var damage: float = 10.0
@export var water_consumption: float = 2.0
@export var air_consumption: float = 10.0
@export var shoot_interval: float = 0.3
@export var pump_air_gain: float = 10.0
@export var max_air: float = 100.0
@export var super_threshold: float = 120.0

# Air
var air: float = 0.0

# Interval
var shoot_timer: float = 0.0

# Super shot
var is_super_ready: bool = false
var is_super_active: bool = false
var super_shot_time: float = 5.0
var super_timer: float = 0.0

# Accuracy
@export var min_spread: float = 0.5
@export var max_spread: float = 8.0
var current_spread: float = 0.0

# Object Pooling & Exclude Cache
var _shot_vfx_pool: Array[Node] = []
var _cached_player_rids: Array = []
var _cached_player_node: Node = null

static var _last_hit_frame: int = -1
static var _hits_in_current_frame: int = 0

func _get_mesh_container() -> Node3D:
	if mesh_container and is_instance_valid(mesh_container):
		return mesh_container
	for child in get_children():
		if child is Node3D and child.name != "SpawnPoint":
			mesh_container = child
			return mesh_container
	return null

func _process(delta):
	var target_mesh = _get_mesh_container()
	if target_mesh:
		if not is_mesh_init:
			initial_mesh_pos = target_mesh.transform.origin
			initial_mesh_rot = target_mesh.rotation
			is_mesh_init = true
		
	# Smoothly return weapon mesh recoil offsets to rest position
	mesh_offset_z = lerpf(mesh_offset_z, 0.0, delta * mesh_recoil_recovery_speed)
	mesh_offset_x = lerpf(mesh_offset_x, 0.0, delta * mesh_recoil_recovery_speed)
	mesh_offset_y = lerpf(mesh_offset_y, 0.0, delta * mesh_recoil_recovery_speed)
	mesh_offset_pitch = lerpf(mesh_offset_pitch, 0.0, delta * mesh_recoil_recovery_speed)
	mesh_offset_yaw = lerpf(mesh_offset_yaw, 0.0, delta * mesh_recoil_recovery_speed)
	mesh_offset_roll = lerpf(mesh_offset_roll, 0.0, delta * mesh_recoil_recovery_speed)

	# Apply recoil transform to child mesh container
	if target_mesh:
		target_mesh.transform.origin = initial_mesh_pos + Vector3(mesh_offset_x, mesh_offset_y, mesh_offset_z)
		target_mesh.rotation = initial_mesh_rot + Vector3(-mesh_offset_pitch, mesh_offset_yaw, mesh_offset_roll)

	if shoot_timer > 0.0:
		shoot_timer -= delta

	if is_super_active:
		super_timer -= delta
		if super_timer <= 0.0:
			is_super_active = false
			on_super_end()
			
			# Play Superpump duration end sound
			SoundManager.play_2d("Superpump_Duration_End")
			
	update_accuracy()

func get_gun_name() -> String:
	return gun_name

func on_super_end():
	pass

func get_air_consumption() -> float:
	var base_consumption = air_consumption
	if get_tree().root.has_node("GameManager") and GameManager.difficulty == GameManager.Difficulty.CASUAL:
		return base_consumption * 0.5
	return base_consumption

func can_shoot() -> bool:
	var has_water = water_tank.current_water >= water_consumption if water_tank else false
	var has_air = air >= get_air_consumption()
	return shoot_timer <= 0.0 and has_water and has_air

func play_shoot_sound(shoot_pos: Vector3) -> void:
	var pitch = randf_range(0.95, 1.05) if (SoundManager and SoundManager.enable_pitch_randomization) else 1.0
	SoundManager.play_3d("watergun_pistol_shoot", shoot_pos, 0.0, -1.0, pitch)
	if is_super_active:
		SoundManager.play_3d("watergun_pistol_Superpump_Shoot_Add", shoot_pos, 0.0, -1.0, pitch)

func _is_result_enemy(result: Dictionary) -> bool:
	var collider = result.get("collider")
	if collider == null:
		return false
	if collider is Area3D:
		var hz: HitboxZone = collider.get_node_or_null("HitboxZone")
		if hz and (hz._enemy != null or hz.get("_anchalee") != null):
			return true
	var node: Node = collider
	while node:
		if node.is_in_group("enemy") or node.has_method("take_hit") or ("Enemy" in node.name) or ("Zombie" in node.name):
			if not node.is_in_group("player"):
				return true
		node = node.get_parent()
	return false

func play_hit_sound(result: Dictionary) -> void:
	if not result:
		return
	var current_frame = Engine.get_process_frames()
	if _last_hit_frame != current_frame:
		_last_hit_frame = current_frame
		_hits_in_current_frame = 0
	
	_hits_in_current_frame += 1
	if _hits_in_current_frame <= 2:
		var is_enemy = _is_result_enemy(result)
		var pitch = randf_range(0.92, 1.08) if (SoundManager and SoundManager.enable_pitch_randomization) else 1.0
		SoundManager.play_3d("watergun_hit", result.position, 0.0, -1.0, pitch, is_enemy)

func shoot():
	if not can_shoot():
		return
		
	# Register shot fired in GameManager
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_shot_fired(water_consumption)

	# Play watergun shoot sounds
	var shoot_pos = spawn_point.global_position if spawn_point else global_position
	play_shoot_sound(shoot_pos)

	# Consume resources normally (super pump unlimited air/water time removed)
	if water_tank:
		water_tank.current_water -= water_consumption
		water_tank.current_water = max(water_tank.current_water, 0.0)
	
	air -= get_air_consumption()
	air = max(air, 0.0)

	# Apply procedural arm recoil kick (independent from camera recoil)
	var gm = get_tree().root.get_node_or_null("GameManager") if get_tree() and get_tree().root.has_node("GameManager") else null
	var is_arm_enabled = enable_arm_recoil and (not gm or not ("enable_arm_recoil" in gm) or gm.enable_arm_recoil)
	
	if is_arm_enabled:
		mesh_offset_z += mesh_kick_z
		mesh_offset_pitch += mesh_kick_pitch
		mesh_offset_x += randf_range(-mesh_kick_x, mesh_kick_x)
		mesh_offset_y += randf_range(mesh_kick_y * 0.5, mesh_kick_y)
		mesh_offset_yaw += randf_range(-mesh_kick_yaw, mesh_kick_yaw)
		mesh_offset_roll += randf_range(-mesh_kick_roll, mesh_kick_roll)
		
		var player_node = _get_player_ref()
		if player_node and player_node.has_method("trigger_shoulder_recoil"):
			player_node.trigger_shoulder_recoil(shoulder_kick_z, shoulder_kick_pitch)
	
	var is_weakpoint_hit = _check_weakpoint_aim()
	var pc = _get_player_camera()
	if pc:
		var yaw_sign = 1.0 if randf() > 0.5 else -1.0
		pc.add_recoil(recoil_pitch, recoil_yaw * yaw_sign, camera_fov_kick, camera_shake, is_weakpoint_hit)
		
	var crosshairs = get_tree().get_nodes_in_group("crosshair")
	for ch in crosshairs:
		if ch.has_method("trigger_shot_kick"):
			ch.trigger_shot_kick(crosshair_shot_kick)

	fire_projectiles()
	shoot_timer = shoot_interval

func fire_projectiles():
	fire_pellet()

func _add_collision_objects_recursive(node: Node, exclude_array: Array):
	if node is CollisionObject3D:
		exclude_array.append(node.get_rid())
	for child in node.get_children():
		_add_collision_objects_recursive(child, exclude_array)

func fire_pellet():
	var horizontal_spread: float = deg_to_rad(randf_range(-current_spread, current_spread))
	var vertical_spread: float = deg_to_rad(randf_range(-current_spread, current_spread))
	
	var from: Vector3 = camera.global_transform.origin
	var direction: Vector3 = -camera.global_transform.basis.z
	
	var tree := get_tree()
	if not tree:
		return
	var player = tree.get_first_node_in_group("player")
	if player and "true_aim_position" in player:
		direction = (player.true_aim_position - from).normalized()
		
	direction = direction.rotated(Vector3.UP, horizontal_spread)
	direction = direction.rotated(camera.global_transform.basis.x, vertical_spread)

	# Raycast
	var to: Vector3 = from + direction * 1000.0	

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 8192 # Detect Layer 1 (World) and Layer 14 (Hitboxes), ignore root body shapes
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var exclude_nodes: Array = []
	var node: Node = self
	while node:
		if node is CollisionObject3D:
			exclude_nodes.append(node.get_rid())
		node = node.get_parent()
	
	_update_player_exclude_cache()
	exclude_nodes.append_array(_cached_player_rids)
	
	query.exclude = exclude_nodes
	
	var result: Dictionary = space_state.intersect_ray(query)
	
	var start_pos: Vector3 = spawn_point.global_transform.origin if spawn_point else from
	var end_pos: Vector3 = to
	
	if result:
		end_pos = result.position
		# Apply damage to any enemy hit by the raycast
		_apply_damage_to_result(result)
		# Play watergun hit SFX
		play_hit_sound(result)

	# Muzzle Flash
	if muzzle_vfx_scene and spawn_point:
		var muzzle_vfx: Node3D = muzzle_vfx_scene.instantiate()
		if tree.current_scene:
			tree.current_scene.add_child(muzzle_vfx)
			muzzle_vfx.global_transform = spawn_point.global_transform
			muzzle_vfx.position += spawn_point.global_transform.basis * muzzle_offset
			muzzle_vfx.scale = muzzle_scale
			
			# Play Animation
			if muzzle_vfx is GPUParticles3D:
				muzzle_vfx.emitting = true
			
			var anim_player = muzzle_vfx.get_node_or_null("AnimationPlayer")
			if anim_player and anim_player is AnimationPlayer:
				if muzzle_animation_name != "" and anim_player.has_animation(muzzle_animation_name):
					anim_player.play(muzzle_animation_name)
				else:
					anim_player.play(anim_player.get_animation_list()[0])
			
			tree.create_timer(0.5).timeout.connect(func():
				if is_instance_valid(muzzle_vfx):
					muzzle_vfx.queue_free()
			)
		else:
			muzzle_vfx.queue_free()

	if shot_vfx_scene:
		var shot_vfx = _get_pooled_shot_vfx()
		if shot_vfx and shot_vfx.has_method("set_line"):
			shot_vfx.set_line(start_pos, end_pos)

	if result and hit_vfx_scene:
		var hit_vfx: Node3D = hit_vfx_scene.instantiate()
		if tree.current_scene:
			tree.current_scene.add_child(hit_vfx)
			
			# Position and Align with Normal
			var normal = result.normal
			if normal.length_squared() < 0.01:
				normal = Vector3.UP
			hit_vfx.global_position = result.position + (normal * 0.01) # Slight offset to prevent clipping

			var up_dir = Vector3.UP
			if abs(normal.dot(Vector3.UP)) > 0.999:
				up_dir = Vector3.FORWARD
			hit_vfx.look_at(hit_vfx.global_position + normal, up_dir)
			
			# Apply custom offset (local to the hit orientation) and scale
			hit_vfx.position += hit_vfx.global_transform.basis * impact_offset
			hit_vfx.scale = impact_scale
			
			# Play Animation
			if hit_vfx is GPUParticles3D:
				hit_vfx.emitting = true
				
			var anim_player = hit_vfx.get_node_or_null("AnimationPlayer")
			if anim_player and anim_player is AnimationPlayer:
				if impact_animation_name != "" and anim_player.has_animation(impact_animation_name):
					anim_player.play(impact_animation_name)
				else:
					anim_player.play(anim_player.get_animation_list()[0])
			
			tree.create_timer(3.0).timeout.connect(func():
				if is_instance_valid(hit_vfx):
					hit_vfx.queue_free()
			)
		else:
			hit_vfx.queue_free()


func update_accuracy():
	pass

func _apply_damage_to_result(result: Dictionary) -> void:
	var collider = result.get("collider")
	if collider == null:
		return

	var final_damage = damage
	if get_tree().root.has_node("GameManager") and GameManager.difficulty == GameManager.Difficulty.CASUAL:
		final_damage = final_damage * 1.25
	var tree := get_tree()
	var player = tree.get_first_node_in_group("player") if tree else null
	if player and player.has_method("get_damage_multiplier"):
		final_damage = final_damage * player.get_damage_multiplier()

	# ✅ Case 1: Hit an Area3D (hitbox)
	if collider is Area3D and not collider.is_in_group("player_hitbox"):
		# Better: search for HitboxZone
		var hitbox_zone: HitboxZone = collider.get_node_or_null("HitboxZone")
		
		if hitbox_zone:
			var enemy = hitbox_zone._enemy
			var anchalee = hitbox_zone.get("_anchalee")
			var target = enemy if enemy else anchalee
			
			if target:
				if enemy and get_tree().root.has_node("GameManager"):
					get_tree().root.get_node("GameManager").register_shot_hit()
				target.take_hit({
					"damage": final_damage,
					"hit_zone": hitbox_zone.zone_name,
					"position": result.position
				})
				
				# On confirmed weakpoint hit impact, trigger camera shake ONLY if mode is WEAKPOINT_ONLY
				# (If mode is ENABLED, shot fire already triggered camera shake on pull-trigger!)
				var pc = _get_player_camera()
				if pc and ("camera_shake_mode" in pc) and pc.camera_shake_mode == pc.CameraShakeMode.WEAKPOINT_ONLY:
					var zn = str(hitbox_zone.zone_name).to_lower()
					var is_weak = zn == "head" or zn == "weakpoint" or zn == "weak" or ("head" in zn) or ("weak" in zn) or ("foot" in zn) or ("feet" in zn) or ("leg" in zn)
					if is_weak and pc.has_method("trigger_weakpoint_shake"):
						pc.trigger_weakpoint_shake()
				return

	# ✅ Fallback (direct hit)
	var node = collider
	while node and not node.has_method("take_hit"):
		node = node.get_parent()

	if node:
		if get_tree().root.has_node("GameManager"):
			if not node.is_in_group("player") and not node.is_in_group("anchalee") and not ("Anchalee" in node.name):
				get_tree().root.get_node("GameManager").register_shot_hit()
		node.take_hit({
			"damage": final_damage,
			"hit_zone": "body",
			"position": result.position
		})

func pump_air():
	if is_super_active:
		return

	var _old_air = air
	pump_air_gain = max_air / 5.0 # 5 pumps must fill to 100% air
	
	# Determine and play pump sound based on current air level before pumping
	if _old_air >= max_air:
		# Pumping the special transition from 100 to 120 air
		SoundManager.play_2d("watergun_pistol_reload_Superpump")
	else:
		# Pumping standard air from 0 to 100
		SoundManager.play_2d("watergun_pistol_reload")

	if air < max_air:
		air += pump_air_gain
		if air >= max_air:
			air = max_air
			# Just reached 100% air! Play notification chime
			SoundManager.play_2d("Superpump_Ready_FullAir")
	else:
		# Already at or above max_air, pumping goes toward super_threshold
		air += pump_air_gain
		if air >= super_threshold:
			air = super_threshold
			is_super_ready = false
			is_super_active = true
			super_timer = 5.0 # Super pump last for 5.0 sec

	update_accuracy()

func reload_water(water_gain):
	if water_tank:
		water_tank.current_water += water_gain
		water_tank.current_water = clamp(water_tank.current_water, 0.0, water_tank.max_water)

func _get_player_ref() -> Node:
	if _cached_player_node and is_instance_valid(_cached_player_node):
		return _cached_player_node
	var tree := get_tree()
	if tree:
		_cached_player_node = tree.get_first_node_in_group("player")
		if _cached_player_node:
			return _cached_player_node
	var p: Node = self
	while p:
		if p.has_method("trigger_arm_recoil") or p.is_in_group("player") or p.name == "Player":
			_cached_player_node = p
			return _cached_player_node
		p = p.get_parent()
	return null

func _get_player_camera() -> Node:
	if camera and camera.has_method("add_recoil"):
		return camera
	if camera:
		var p: Node = camera
		while p:
			if p.has_method("add_recoil"):
				return p
			p = p.get_parent()
	var player_node = _get_player_ref()
	if player_node and ("camera" in player_node) and is_instance_valid(player_node.camera) and player_node.camera.has_method("add_recoil"):
		return player_node.camera
	var tree := get_tree()
	if tree:
		var cams = tree.get_nodes_in_group("player_camera")
		if cams.size() > 0:
			return cams[0]
	return null

func _check_weakpoint_aim() -> bool:
	if not camera:
		return false
	var from: Vector3 = camera.global_transform.origin
	var direction: Vector3 = -camera.global_transform.basis.z
	var to: Vector3 = from + direction * 100.0
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2 | 4 | 14 | 8192
	query.collide_with_areas = true
	query.collide_with_bodies = true
	_update_player_exclude_cache()
	if not _cached_player_rids.is_empty():
		query.exclude = _cached_player_rids
		
	var result: Dictionary = space_state.intersect_ray(query)
	if result and result.has("collider") and is_instance_valid(result.collider):
		var col: Node = result.collider
		# Search up and down the collider node tree for HitboxZone
		var curr: Node = col
		while curr and curr != get_tree().root:
			if curr.has_node("HitboxZone"):
				var hz = curr.get_node("HitboxZone")
				if "zone_name" in hz:
					var zn = str(hz.zone_name).to_lower()
					if "head" in zn or "weak" in zn or "foot" in zn or "feet" in zn or "leg" in zn:
						return true
			if "zone_name" in curr:
				var zn = str(curr.zone_name).to_lower()
				if "head" in zn or "weak" in zn or "foot" in zn or "feet" in zn or "leg" in zn:
					return true
			for child in curr.get_children():
				if "zone_name" in child:
					var zn = str(child.zone_name).to_lower()
					if "head" in zn or "weak" in zn or "foot" in zn or "feet" in zn or "leg" in zn:
						return true
			curr = curr.get_parent()
	return false

func _update_player_exclude_cache() -> void:
	var tree := get_tree()
	if not tree:
		return
	var player = _get_player_ref()
	if player != _cached_player_node or _cached_player_rids.is_empty() or not is_instance_valid(_cached_player_node):
		_cached_player_node = player
		_cached_player_rids.clear()
		if player:
			var exclude_nodes: Array = []
			_add_collision_objects_recursive(player, exclude_nodes)
			_cached_player_rids = exclude_nodes

func _get_pooled_shot_vfx() -> Node:
	var i = _shot_vfx_pool.size() - 1
	while i >= 0:
		if not is_instance_valid(_shot_vfx_pool[i]):
			_shot_vfx_pool.remove_at(i)
		i -= 1

	for vfx in _shot_vfx_pool:
		if is_instance_valid(vfx) and not vfx.visible:
			return vfx
			
	if shot_vfx_scene:
		var vfx = shot_vfx_scene.instantiate()
		var tree := get_tree()
		if tree and tree.current_scene:
			tree.current_scene.add_child(vfx)
			_shot_vfx_pool.append(vfx)
			return vfx
		else:
			vfx.queue_free()
	return null
