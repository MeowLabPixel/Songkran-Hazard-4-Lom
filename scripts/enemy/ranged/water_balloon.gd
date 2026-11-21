@tool
extends RigidBody3D
class_name WaterBalloon

@export_group("Physics & Fuze")
@export var fuze_time: float = 1.2
@export var max_horizontal_speed: float = 9.0
@export_range(0.0, 1.0) var impact_horizontal_keep: float = 0.3
@export var post_impact_linear_damp: float = 3.0
@export var post_impact_angular_damp: float = 2.5
@export var ground_normal_min_y: float = 0.3
@export var max_air_time: float = 8.0
@export var throw_spin_speed: float = 6.0

@export_group("Squish & Fuze Pop")
@export_range(0.0, 0.75) var bounce_squash_strength: float = 0.38
@export var bounce_min_speed: float = 1.5
@export var bounce_squash_recovery: float = 12.0
@export_range(0, 20) var fuze_tick_count: int = 16
@export_range(1.0, 4.0) var tick_accel_power: float = 2.2
@export var tick_pop_peak_scale: float = 1.35
@export var max_pre_swell_scale: float = 1.45
@export var tick_pop_recovery: float = 16.0
@export var final_pop_scale: float = 10.0
@export var final_swell_duration: float = 0.22
@export var tick_shake_intensity: float = 0.045
@export var tick_shake_decay: float = 14.0
@export_range(0.0, 1.0) var tick_flash_alpha: float = 0.9
@export var tick_flash_decay: float = 12.0
@export var tick_flash_color: Color = Color(1.5, 1.5, 1.5, 1.0)

@export_group("VFX")
@export var trail_spawn_point: Node3D
@export var trail_particles: GPUParticles3D
@export var extra_trail_particles: Array[GPUParticles3D] = []
@export var splash_particles: GPUParticles3D  # assign Bomb GPUParticles3D child in inspector
@export var extra_splash_particles: Array[GPUParticles3D] = []
@export var throw_vfx_root: Node3D
@export var tick_flashes_particles: GPUParticles3D

var _start: Vector3
var _target: Vector3
var _damage: float
var _radius: float
var _arc_height: float
var _travel_time: float
var _elapsed: float = 0.0
var _fuze_total: float = 1.2
var _fuze_remaining: float = 0.0
var _fuze_elapsed: float = 0.0
var _fuze_started: bool = false
var _ticks_fired: int = 0
var _in_final_swell: bool = false
var _final_swell_start_scale: float = 1.0
var _squash_scale: Vector3 = Vector3.ONE
var _tick_scale: float = 1.0
var _tick_baseline_scale: float = 1.0
var _shake_amount: float = 0.0
var _flash_alpha: float = 0.0
var _flash_overlay_mat: StandardMaterial3D
var _bounce_squash_cooldown: float = 0.0
var _prev_linear_velocity: Vector3 = Vector3.ZERO
var _balloon_mesh: Node3D
var _balloon_visual_meshes: Array[GeometryInstance3D] = []
var _balloon_base_scale: Vector3 = Vector3.ONE
var _balloon_base_position: Vector3 = Vector3.ZERO
var _balloon_transform_cached: bool = false
var _active: bool = false
var _splashing: bool = false
var _splash_serial: int = 0
var _default_collision_layer: int = 1
var _default_collision_mask: int = 1
var _collision_cached: bool = false
var is_pooled: bool = false
var on_splash_callback: Callable = Callable()

func _ready() -> void:
	_cache_collision_settings()
	_resolve_vfx_nodes()
	if not Engine.is_editor_hint():
		continuous_cd = true
		contact_monitor = true
		max_contacts_reported = maxi(max_contacts_reported, 4)
		linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	if not _active:
		freeze = true
		_set_collision_enabled(false)
		_stop_all_particles()

func launch(target: Vector3, damage: float, radius: float,
		arc_height: float = 3.0, travel_time: float = 1.2, thrower: Node = null) -> void:
	_resolve_vfx_nodes()
	_splash_serial += 1
	_start          = global_position
	_target         = target
	_damage         = damage
	_radius         = radius
	_arc_height     = arc_height
	_travel_time    = travel_time
	_elapsed        = 0.0
	_fuze_total     = maxf(fuze_time, 0.05)
	_fuze_remaining = _fuze_total
	_fuze_elapsed   = 0.0
	_fuze_started   = false
	_ticks_fired    = 0
	_in_final_swell = false
	_final_swell_start_scale = 1.0
	_squash_scale   = Vector3.ONE
	_tick_scale     = 1.0
	_tick_baseline_scale = 1.0
	_shake_amount   = 0.0
	_flash_alpha    = 0.0
	_bounce_squash_cooldown = 0.0
	_prev_linear_velocity = Vector3.ZERO
	_active         = true
	_splashing      = false

	_apply_balloon_visuals()
	_set_balloon_mesh_visible(true)
	global_basis = Basis.IDENTITY
	_clear_thrower_exceptions()
	if thrower is PhysicsBody3D:
		add_collision_exception_with(thrower)

	_stop_splash_particles()
	_stop_tick_flashes()
	_trigger_throw_vfx(_start)

	if not Engine.is_editor_hint():
		_set_collision_enabled(true)
		continuous_cd = true
		linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		linear_damp = 0.0
		angular_damp = 0.0
		var init_vel := _compute_ballistic_velocity(_start, target, arc_height, travel_time)
		var init_spin := _random_spin_velocity()
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		freeze = false
		sleeping = false
		linear_velocity = init_vel
		angular_velocity = init_spin
		_prev_linear_velocity = init_vel
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, init_vel)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, init_spin)
		_sync_trail_to_tip(init_vel)
	else:
		_sync_trail_to_tip(target - _start)

	_start_trail_particles()

func launch_pooled(target: Vector3, damage: float, radius: float,
		arc_height: float = 3.0, travel_time: float = 1.2, callback: Callable = Callable(), thrower: Node = null) -> void:
	_resolve_vfx_nodes()
	is_pooled = true
	on_splash_callback = callback
	visible = true
	if is_instance_valid(throw_vfx_root):
		throw_vfx_root.top_level = false
		throw_vfx_root.transform = Transform3D.IDENTITY
	launch(target, damage, radius, arc_height, travel_time, thrower)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint() or not _active or _splashing:
		return
	var contact_count := state.get_contact_count()
	if contact_count > 0:
		if _bounce_squash_cooldown <= 0.0:
			var best_impact_speed := 0.0
			var best_normal := Vector3.UP
			for i in range(contact_count):
				var n := state.get_contact_local_normal(i)
				var impact_speed := absf(_prev_linear_velocity.dot(n))
				if impact_speed > best_impact_speed:
					best_impact_speed = impact_speed
					best_normal = n
			if best_impact_speed >= bounce_min_speed:
				_trigger_bounce_squash(best_normal, best_impact_speed)
				_bounce_squash_cooldown = 0.08

		if not _fuze_started:
			var hit_ground := state.linear_velocity.length_squared() < 0.04
			if not hit_ground:
				for i in range(contact_count):
					if state.get_contact_local_normal(i).y >= ground_normal_min_y:
						hit_ground = true
						break
			if hit_ground:
				_fuze_started = true
				_start_tick_flashes()
				state.linear_velocity = Vector3(
					state.linear_velocity.x * impact_horizontal_keep,
					state.linear_velocity.y,
					state.linear_velocity.z * impact_horizontal_keep
				)
				linear_damp = post_impact_linear_damp
				angular_damp = post_impact_angular_damp

	_prev_linear_velocity = state.linear_velocity

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active or _splashing:
		return

	_elapsed += delta
	_bounce_squash_cooldown = maxf(0.0, _bounce_squash_cooldown - delta)

	if _fuze_started:
		_fuze_elapsed += delta
		_fuze_remaining -= delta
		_update_fuze_pop(delta)
		if _fuze_remaining <= 0.0:
			_tick_scale = maxf(final_pop_scale, 1.0)
			_apply_balloon_visuals()
			_splash()
			return
	elif max_air_time > 0.0 and _elapsed >= max_air_time:
		_splash()
		return

	_update_balloon_visuals(delta)
	_sync_trail_to_tip(linear_velocity)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or not _active or _splashing:
		return
	var prev_pos := global_position
	_elapsed += delta
	var t: float = clamp(_elapsed / maxf(_travel_time, 0.05), 0.0, 1.0)

	var flat: Vector3 = _start.lerp(_target, t)
	var height: float = _arc_height * 4.0 * t * (1.0 - t)
	global_position = Vector3(flat.x, flat.y + height, flat.z)

	_sync_trail_to_tip(global_position - prev_pos)

	if t >= 1.0:
		_splash()

func _splash() -> void:
	if _splashing:
		return
	_splashing = true
	_active = false
	var current_serial := _splash_serial

	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_set_collision_enabled(false, true)
	_clear_thrower_exceptions()

	_set_balloon_mesh_visible(false)
	_squash_scale = Vector3.ONE
	_tick_scale = 1.0
	_tick_baseline_scale = 1.0
	_shake_amount = 0.0
	_flash_alpha = 0.0
	_apply_balloon_visuals()
	global_basis = Basis.IDENTITY
	_stop_trail_particles()
	_stop_tick_flashes()
	var splash_lifetime := _trigger_splash_particles()

	if on_splash_callback.is_valid():
		on_splash_callback.call(global_position)

	var tree := get_tree()
	if not tree:
		queue_free()
		return

	if _damage > 0.0:
		for player in tree.get_nodes_in_group("player"):
			if player.global_position.distance_to(global_position) <= _radius:
				player.take_damage(int(_damage), false, self)
				print("[WaterBalloon] Splash hit player for %d" % int(_damage))

	var wait_time := maxf(splash_lifetime, 0.1)
	if is_pooled:
		tree.create_timer(wait_time).timeout.connect(func():
			if is_instance_valid(self) and is_pooled and _splash_serial == current_serial:
				_splashing = false
				visible = false
				if is_instance_valid(throw_vfx_root):
					throw_vfx_root.top_level = false
					throw_vfx_root.transform = Transform3D.IDENTITY
		)
	else:
		tree.create_timer(wait_time).timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)

# ─── Physics & Collision Helpers ──────────────────────────────────────────────

func _compute_ballistic_velocity(start_pos: Vector3, target_pos: Vector3, arc_height: float, travel_time: float) -> Vector3:
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	if gravity_mag <= 0.001:
		return (target_pos - start_pos) / maxf(travel_time, 0.1)

	var peak_y: float = maxf(start_pos.y, target_pos.y) + maxf(arc_height, 0.25)
	var vy_arc: float = sqrt(2.0 * gravity_mag * maxf(0.05, peak_y - start_pos.y))
	var t_up: float = vy_arc / gravity_mag
	var t_down: float = sqrt(2.0 * gravity_mag * maxf(0.0, peak_y - target_pos.y)) / gravity_mag
	var arc_time: float = maxf(t_up + t_down, 0.1)

	var delta_xz := Vector3(target_pos.x - start_pos.x, 0.0, target_pos.z - start_pos.z)
	var min_time_by_speed := 0.0
	if max_horizontal_speed > 0.0:
		min_time_by_speed = delta_xz.length() / maxf(max_horizontal_speed, 0.5)

	var total_time: float = maxf(arc_time, min_time_by_speed)
	var horiz_vel: Vector3 = delta_xz / total_time
	var delta_y: float = target_pos.y - start_pos.y
	var vy: float = (delta_y + 0.5 * gravity_mag * total_time * total_time) / total_time
	return Vector3(horiz_vel.x, vy, horiz_vel.z)

func _random_spin_velocity() -> Vector3:
	if throw_spin_speed <= 0.0:
		return Vector3.ZERO
	return Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.5, 0.5),
		randf_range(-1.0, 1.0)
	).normalized() * throw_spin_speed

func _cache_collision_settings() -> void:
	if _collision_cached:
		return
	_collision_cached = true
	_default_collision_layer = collision_layer if collision_layer != 0 else 1
	_default_collision_mask = collision_mask if collision_mask != 0 else 1

func _set_collision_enabled(enabled: bool, _deferred: bool = false) -> void:
	_cache_collision_settings()
	if enabled:
		collision_layer = _default_collision_layer
		collision_mask = _default_collision_mask
		for child in get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				child.disabled = false
				child.set_deferred("disabled", false)
	else:
		collision_layer = 0
		collision_mask = 0

func _clear_thrower_exceptions() -> void:
	for body in get_collision_exceptions():
		if is_instance_valid(body):
			remove_collision_exception_with(body)

# ─── VFX & Visual Helpers ─────────────────────────────────────────────────────

func _resolve_vfx_nodes() -> void:
	if not is_instance_valid(trail_spawn_point):
		trail_spawn_point = get_node_or_null("Balloon/Balloon2") as Node3D

	if not is_instance_valid(trail_particles):
		trail_particles = get_node_or_null("Water") as GPUParticles3D
	if extra_trail_particles.is_empty():
		var bubble := get_node_or_null("Bubble") as GPUParticles3D
		if is_instance_valid(bubble) and bubble != trail_particles:
			extra_trail_particles.append(bubble)

	if not Engine.is_editor_hint():
		for p in _get_trail_nodes():
			if p.process_material is ParticleProcessMaterial:
				(p.process_material as ParticleProcessMaterial).emission_shape_offset = Vector3.ZERO

	if not is_instance_valid(splash_particles):
		splash_particles = get_node_or_null("Bomb") as GPUParticles3D
	for splash_name in ["Bubble_Small", "Flashes_01"]:
		var extra_p := get_node_or_null(splash_name) as GPUParticles3D
		if is_instance_valid(extra_p) and extra_p != splash_particles and not extra_splash_particles.has(extra_p):
			extra_splash_particles.append(extra_p)

	if not is_instance_valid(throw_vfx_root):
		throw_vfx_root = get_node_or_null("Throw") as Node3D

	if not is_instance_valid(tick_flashes_particles):
		tick_flashes_particles = get_node_or_null("Tick_Flashes") as GPUParticles3D

func _get_balloon_mesh() -> Node3D:
	if not is_instance_valid(_balloon_mesh):
		_balloon_mesh = get_node_or_null("Balloon") as Node3D
		if not _balloon_mesh:
			_balloon_mesh = get_node_or_null("MeshInstance3D") as Node3D
		if _balloon_mesh:
			if not _balloon_transform_cached:
				_balloon_base_scale = _balloon_mesh.scale
				_balloon_base_position = _balloon_mesh.position
				_balloon_transform_cached = true
			_balloon_visual_meshes.clear()
			if _balloon_mesh is GeometryInstance3D:
				_balloon_visual_meshes.append(_balloon_mesh as GeometryInstance3D)
			for child in _balloon_mesh.find_children("*", "GeometryInstance3D", true, false):
				var gi := child as GeometryInstance3D
				if gi and not _balloon_visual_meshes.has(gi):
					_balloon_visual_meshes.append(gi)
	return _balloon_mesh

func _set_balloon_mesh_visible(is_vis: bool) -> void:
	var mesh := _get_balloon_mesh()
	if mesh:
		mesh.visible = is_vis

func _trigger_bounce_squash(world_normal: Vector3, impact_speed: float) -> void:
	var mesh := _get_balloon_mesh()
	if not mesh or bounce_squash_strength <= 0.0:
		return
	var strength := clampf(impact_speed / 8.0, 0.35, 1.0) * clampf(bounce_squash_strength, 0.0, 0.75)
	var squash := clampf(1.0 - strength, 0.25, 1.0)
	var stretch := 1.0 / sqrt(squash)
	var local_n := (mesh.global_basis.inverse() * world_normal).normalized()
	if local_n.length_squared() <= 0.0001:
		local_n = Vector3.UP
	_squash_scale = Vector3(
		lerpf(stretch, squash, local_n.x * local_n.x),
		lerpf(stretch, squash, local_n.y * local_n.y),
		lerpf(stretch, squash, local_n.z * local_n.z)
	)
	_apply_balloon_visuals()

func _update_fuze_pop(delta: float) -> void:
	var safe_final_pop := maxf(final_pop_scale, 1.0)
	var safe_pre_swell := maxf(max_pre_swell_scale, 1.0)
	var safe_accel := maxf(tick_accel_power, 1.0)
	var safe_recovery := maxf(tick_pop_recovery, 1.0)
	var swell_dur := minf(final_swell_duration, _fuze_total * 0.45)

	if swell_dur > 0.001 and _fuze_remaining <= swell_dur:
		if not _in_final_swell:
			_in_final_swell = true
			_final_swell_start_scale = _tick_scale
		var swell_t := clampf(1.0 - (_fuze_remaining / swell_dur), 0.0, 1.0)
		_tick_scale = lerpf(_final_swell_start_scale, safe_final_pop, swell_t * swell_t)
		_shake_amount = maxf(_shake_amount, tick_shake_intensity * lerpf(0.8, 1.4, swell_t))
		_flash_alpha = maxf(_flash_alpha, lerpf(tick_flash_alpha * 0.65, 1.0, swell_t))
		if is_instance_valid(tick_flashes_particles):
			tick_flashes_particles.amount_ratio = 1.0
		return

	var tick_window := _fuze_total - swell_dur
	if fuze_tick_count > 0 and tick_window > 0.05:
		while _ticks_fired < fuze_tick_count:
			var u := float(_ticks_fired) / float(fuze_tick_count)
			var next_tick_time := tick_window * (1.0 - pow(1.0 - u, safe_accel))
			if _fuze_elapsed < next_tick_time:
				break
			_ticks_fired += 1
			var progress := float(_ticks_fired) / float(fuze_tick_count)
			_tick_baseline_scale = lerpf(1.0, safe_pre_swell, progress)
			var pop_boost := maxf(tick_pop_peak_scale, 1.0) - 1.0
			_tick_scale = maxf(_tick_scale, _tick_baseline_scale + pop_boost)
			_shake_amount = maxf(_shake_amount, tick_shake_intensity * lerpf(0.4, 1.0, progress))
			_flash_alpha = tick_flash_alpha

	if is_instance_valid(tick_flashes_particles):
		tick_flashes_particles.amount_ratio = clampf(_fuze_elapsed / maxf(tick_window, 0.05), 0.0, 1.0)

	_tick_scale = lerpf(_tick_scale, _tick_baseline_scale, minf(1.0, safe_recovery * delta))

func _update_balloon_visuals(delta: float) -> void:
	_squash_scale = _squash_scale.lerp(Vector3.ONE, minf(1.0, bounce_squash_recovery * delta))
	_shake_amount = lerpf(_shake_amount, 0.0, minf(1.0, tick_shake_decay * delta))
	_flash_alpha = lerpf(_flash_alpha, 0.0, minf(1.0, tick_flash_decay * delta))
	_apply_balloon_visuals()

func _apply_balloon_visuals() -> void:
	var mesh := _get_balloon_mesh()
	if mesh:
		mesh.scale = _balloon_base_scale * _squash_scale * _tick_scale
		if _shake_amount > 0.0001:
			mesh.position = _balloon_base_position + Vector3(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)
			) * _shake_amount
		else:
			mesh.position = _balloon_base_position

	if Engine.is_editor_hint():
		return

	if _flash_alpha > 0.005:
		if not _flash_overlay_mat:
			_flash_overlay_mat = StandardMaterial3D.new()
			_flash_overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_flash_overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_overlay_mat.albedo_color = Color(
			tick_flash_color.r,
			tick_flash_color.g,
			tick_flash_color.b,
			clampf(_flash_alpha, 0.0, 1.0)
		)
		for gi in _balloon_visual_meshes:
			if is_instance_valid(gi) and gi.material_overlay != _flash_overlay_mat:
				gi.material_overlay = _flash_overlay_mat
	else:
		for gi in _balloon_visual_meshes:
			if is_instance_valid(gi) and gi.material_overlay != null:
				gi.material_overlay = null

func _get_trail_nodes() -> Array[GPUParticles3D]:
	var nodes: Array[GPUParticles3D] = []
	if is_instance_valid(trail_particles):
		nodes.append(trail_particles)
	for p in extra_trail_particles:
		if is_instance_valid(p) and not nodes.has(p):
			nodes.append(p)
	return nodes

func _get_splash_nodes() -> Array[GPUParticles3D]:
	var nodes: Array[GPUParticles3D] = []
	if is_instance_valid(splash_particles):
		nodes.append(splash_particles)
	for p in extra_splash_particles:
		if is_instance_valid(p) and not nodes.has(p):
			nodes.append(p)
	return nodes

func _start_trail_particles() -> void:
	for p in _get_trail_nodes():
		p.restart()
		p.emitting = true

func _stop_trail_particles() -> void:
	for p in _get_trail_nodes():
		p.emitting = false

func _stop_splash_particles() -> void:
	for p in _get_splash_nodes():
		p.emitting = false

func _stop_all_particles() -> void:
	for child in find_children("*", "GPUParticles3D", true, false):
		var p := child as GPUParticles3D
		if p:
			p.emitting = false
	if is_instance_valid(tick_flashes_particles):
		tick_flashes_particles.amount_ratio = 0.0

func _start_tick_flashes() -> void:
	if is_instance_valid(tick_flashes_particles):
		tick_flashes_particles.amount_ratio = 0.0
		tick_flashes_particles.restart()
		tick_flashes_particles.emitting = true

func _stop_tick_flashes() -> void:
	if is_instance_valid(tick_flashes_particles):
		tick_flashes_particles.emitting = false
		tick_flashes_particles.amount_ratio = 0.0

func _sync_trail_to_tip(move_dir: Vector3 = Vector3.ZERO) -> void:
	if not is_instance_valid(trail_spawn_point):
		return
	var tip_pos := trail_spawn_point.global_position
	var has_dir := move_dir.length_squared() > 0.0001
	var backward := -move_dir.normalized() if has_dir else Vector3.ZERO
	var up_vec := Vector3.UP if (not has_dir or (not backward.is_equal_approx(Vector3.UP) and not backward.is_equal_approx(Vector3.DOWN))) else Vector3.FORWARD
	for p in _get_trail_nodes():
		p.global_position = tip_pos
		if has_dir:
			p.look_at(tip_pos + backward, up_vec)

func _trigger_throw_vfx(spawn_pos: Vector3) -> void:
	if not is_instance_valid(throw_vfx_root):
		return
	throw_vfx_root.top_level = true
	throw_vfx_root.global_transform = Transform3D(Basis.IDENTITY, spawn_pos)
	for child in throw_vfx_root.find_children("*", "GPUParticles3D", true, false):
		var p := child as GPUParticles3D
		if p:
			p.restart()
			p.emitting = true

func _trigger_splash_particles() -> float:
	var max_lifetime := 0.0
	for p in _get_splash_nodes():
		p.restart()
		p.emitting = true
		var effective_life := p.lifetime / maxf(p.speed_scale, 0.01)
		max_lifetime = maxf(max_lifetime, effective_life)
	return max_lifetime
