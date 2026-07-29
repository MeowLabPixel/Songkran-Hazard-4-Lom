extends Gun
class_name SniperWaterGun

func _ready():
	gun_name = "Water sniper"

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
	var direction: Vector3 = -camera.global_transform.basis.z
	var from: Vector3 = camera.global_transform.origin
	var to: Vector3 = from + direction * 1000.0
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = spawn_point.global_transform.origin if spawn_point else from
	var exclude: Array[RID] = []
	var max_penetration: int = 10
	var final_pos: Vector3 = to

	# Build player exclusions the same way fire_pellet() does
	var exclude_nodes: Array = []
	var node: Node = self
	while node:
		if node is CollisionObject3D:
			exclude_nodes.append(node)
		node = node.get_parent()
	var tree := get_tree()
	if not tree:
		return
	for player_node in tree.get_nodes_in_group("player"):
		_add_collision_objects_recursive(player_node, exclude_nodes)
	for n in exclude_nodes:
		exclude.append(n.get_rid())

	for i in range(max_penetration):
		var query = PhysicsRayQueryParameters3D.create(from, to, 1 | 8192, exclude) # Detect Layer 1 (World) and Layer 14 (Hitboxes), ignore root body shapes
		query.collide_with_areas = true   # ← required to hit Area3D hitboxes
		query.collide_with_bodies = true
		var result = space_state.intersect_ray(query)
		if not result:
			break

		# Apply damage to whatever was hit
		_apply_damage_to_result(result)
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
				hit_vfx.scale = impact_scale
				if hit_vfx is GPUParticles3D:
					hit_vfx.emitting = true
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

func on_super_end():
	air = 0.0
