extends Gun
class_name SniperWaterGun

func _ready():
	gun_name = "Water sniper"

func fire_projectiles():
	if is_super_active:
		fire_sniper_super_shot()
		# Immediately reset air and end super after this powerful shot
		air = 0.0
		is_super_active = false
		print("Sniper Super Shot Fired! Air Reset to 0.")
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
	for player_node in get_tree().get_nodes_in_group("player"):
		_add_collision_objects_recursive(player_node, exclude_nodes)
	for n in exclude_nodes:
		exclude.append(n.get_rid())

	for i in range(max_penetration):
		var query = PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
		query.collide_with_areas = true   # ← required to hit Area3D hitboxes
		query.collide_with_bodies = true
		var result = space_state.intersect_ray(query)
		if not result:
			break

		# Apply damage to whatever was hit
		_apply_damage_to_result(result)

		# Spawn hit VFX
		if hit_vfx_scene:
			var hit_vfx: Node3D = hit_vfx_scene.instantiate()
			get_tree().current_scene.add_child(hit_vfx)
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
			get_tree().create_timer(10).timeout.connect(hit_vfx.queue_free)

		exclude.append(result.rid)
		final_pos = result.position

	if shot_vfx_scene:
		var shot_vfx: Node = shot_vfx_scene.instantiate()
		get_tree().current_scene.add_child(shot_vfx)
		if shot_vfx.has_method("set_line"):
			shot_vfx.set_line(start_pos, final_pos)

func on_super_end():
	air = 0.0
	print("Sniper Air Reset to 0 after Super.")
