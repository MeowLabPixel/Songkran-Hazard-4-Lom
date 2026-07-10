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

func _process(delta):
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

func can_shoot() -> bool:
	var has_water = water_tank.current_water >= water_consumption if water_tank else false
	var has_air = air >= air_consumption
	return shoot_timer <= 0.0 and has_water and has_air

func shoot():
	if not can_shoot():
		return
		
	# Play watergun shoot sounds
	var shoot_pos = spawn_point.global_position if spawn_point else global_position
	
	# Always play standard firing sound
	SoundManager.play_3d("watergun_pistol_shoot", shoot_pos)
	
	# Layer the Superpump shoot addition sound in parallel if super is active
	if is_super_active:
		SoundManager.play_3d("watergun_pistol_Superpump_Shoot_Add", shoot_pos)

	# Consume resources normally (super pump unlimited air/water time removed)
	if water_tank:
		water_tank.current_water -= water_consumption
		water_tank.current_water = max(water_tank.current_water, 0.0)
	
	air -= air_consumption
	air = max(air, 0.0)

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
		# Play watergun hit SFX
		var alt = false
		if is_super_active:
			alt = true
		else:
			var collider = result.get("collider")
			if collider is Area3D:
				var hz = collider.get_node_or_null("HitboxZone")
				if hz and hz.zone_name == "head":
					alt = true
		SoundManager.play_3d("watergun_hit", result.position, 0.0, -1.0, 1.0, alt)
		
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
	var tree := get_tree()
	var player = tree.get_first_node_in_group("player") if tree else null
	if player and player.has_method("get_damage_multiplier"):
		final_damage = damage * player.get_damage_multiplier()

	# ✅ Case 1: Hit an Area3D (hitbox)
	if collider is Area3D and not collider.is_in_group("player_hitbox"):
		# Better: search for HitboxZone
		var hitbox_zone: HitboxZone = collider.get_node_or_null("HitboxZone")
		
		if hitbox_zone:
			var enemy = hitbox_zone._enemy
			var anchalee = hitbox_zone.get("_anchalee")
			var target = enemy if enemy else anchalee
			
			if target:
				target.take_hit({
					"damage": final_damage,
					"hit_zone": hitbox_zone.zone_name,
					"position": result.position
				})
				return

	# ✅ Fallback (direct hit)
	var node = collider
	while node and not node.has_method("take_hit"):
		node = node.get_parent()

	if node:
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

func _update_player_exclude_cache() -> void:
	var tree := get_tree()
	if not tree:
		return
	var player = tree.get_first_node_in_group("player")
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
