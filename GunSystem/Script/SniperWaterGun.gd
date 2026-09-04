extends Gun
class_name SniperWaterGun

func _ready():
	gun_name = "Water sniper"
	recoil_pitch = 4.2
	recoil_yaw = 0.4
	camera_fov_kick = 3.6
	camera_shake = 0.10
	mesh_kick_z = 0.22
	mesh_kick_pitch = 0.28
	shoulder_kick_z = 0.22
	shoulder_kick_pitch = 0.26

func play_shoot_sound(shoot_pos: Vector3) -> void:
	var pitch = randf_range(0.95, 1.05) if (SoundManager and SoundManager.enable_pitch_randomization) else 1.0
	if is_super_active:
		SoundManager.play_3d("Region_Rifle_SuperShot", shoot_pos, 0.0, -1.0, pitch)
		SoundManager.play_3d("watergun_pistol_Superpump_Shoot_Add", shoot_pos, 0.0, -1.0, pitch)
	else:
		SoundManager.play_3d("watergun_pistol_shoot", shoot_pos, 0.0, -1.0, pitch)

func fire_projectiles():
	if is_super_active:
		fire_sniper_super_shot()
		# Immediately reset air and end super after this powerful shot
		air = 0.0
		is_super_active = false
	else:
		fire_pellet()

func fire_sniper_super_shot():
	var tree := get_tree()
	if not tree:
		return
	var pc = _get_player_camera()
	var ray_origin: Vector3
	var ray_dir: Vector3
	if pc and ("camera" in pc) and pc.camera:
		var vp = pc.camera.get_viewport()
		var screen_size = vp.get_visible_rect().size if vp else Vector2(1280, 720)
		var screen_center = screen_size * 0.5
		var crosshair_speed = screen_size.y * 1.25
		var offset_pixels = Vector2(pc.aim_offset.x, pc.aim_offset.y) * crosshair_speed if ("aim_offset" in pc) else Vector2.ZERO
		var crosshair_center = screen_center + offset_pixels
		ray_origin = pc.camera.project_ray_origin(crosshair_center)
		ray_dir = pc.camera.project_ray_normal(crosshair_center)
	elif camera:
		ray_origin = camera.global_transform.origin
		ray_dir = -camera.global_transform.basis.z
	else:
		ray_origin = global_transform.origin
		ray_dir = -global_transform.basis.z

	var ray_start: Vector3 = ray_origin
	var to: Vector3 = ray_origin + ray_dir * 1000.0
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = spawn_point.global_transform.origin if spawn_point else ray_origin
	var exclude: Array[RID] = []
	var max_penetration: int = 10
	var final_pos: Vector3 = to

	# Build exclusions using cached player RIDs
	var exclude_nodes: Array = []
	var node: Node = self
	while node:
		if node is CollisionObject3D:
			exclude_nodes.append(node.get_rid())
		node = node.get_parent()
	_update_player_exclude_cache()
	exclude_nodes.append_array(_cached_player_rids)
	exclude.append_array(exclude_nodes)

	var current_from = ray_start
	for i in range(max_penetration):
		var query = PhysicsRayQueryParameters3D.create(current_from, to, 1 | 2 | 8192, exclude) # Detect Layer 1 (World), Layer 2 (Weakpoints), and Layer 14 (Hitboxes). Excludes Layer 3 CharacterBody3D
		query.collide_with_areas = true   # ← required to hit Area3D hitboxes
		query.collide_with_bodies = true
		query.hit_from_inside = true
		var result = space_state.intersect_ray(query)
		if not result:
			break

		# Apply damage to whatever was hit
		var hit_info = _apply_damage_to_result(result)
		var is_crit = hit_info.get("is_crit", false) if typeof(hit_info) == TYPE_DICTIONARY else false
		var is_weakpoint = hit_info.get("is_weakpoint", false) if typeof(hit_info) == TYPE_DICTIONARY else false
		# Play hit sound on penetration impact
		play_hit_sound(result)

		# Spawn hit VFX
		if hit_vfx_scene:
			var hit_vfx: Node3D = hit_vfx_scene.instantiate()
			var tree_vfx := get_tree()
			if tree_vfx and tree_vfx.current_scene:
				tree_vfx.current_scene.add_child(hit_vfx)
				var normal = result.normal
				if normal.length_squared() < 0.01:
					normal = Vector3.UP
				hit_vfx.global_position = result.position + (normal * 0.01)

				var up_dir = Vector3.UP
				if abs(normal.dot(Vector3.UP)) > 0.999:
					up_dir = Vector3.FORWARD
				hit_vfx.look_at(hit_vfx.global_position + normal, up_dir)
				hit_vfx.position += hit_vfx.global_transform.basis * impact_offset
				hit_vfx.scale = impact_scale
				_trigger_vfx_node(hit_vfx, impact_animation_name, is_crit, is_weakpoint)
				tree_vfx.create_timer(3.0).timeout.connect(func():
					if is_instance_valid(hit_vfx):
						hit_vfx.queue_free()
				)
			else:
				hit_vfx.queue_free()

		exclude.append(result.rid)
		final_pos = result.position

	if shot_vfx_scene:
		var shot_vfx = _get_pooled_shot_vfx()
		if shot_vfx and shot_vfx.has_method("set_line"):
			shot_vfx.set_line(start_pos, final_pos)

	_draw_debug_raycast(start_pos, final_pos, final_pos != to)

func on_super_end():
	air = 0.0
