extends Node3D
class_name WaterBalloon

var _start: Vector3
var _target: Vector3
var _damage: float
var _radius: float
var _arc_height: float
var _travel_time: float
var _elapsed: float = 0.0
var _active: bool = false

@export var trail_particles: GPUParticles3D
@export var splash_particles: GPUParticles3D  # assign a GPUParticles3D child in inspector

func launch(target: Vector3, damage: float, radius: float,
		arc_height: float = 3.0, travel_time: float = 1.2) -> void:
	_start       = global_position
	_target      = target
	_damage      = damage
	_radius      = radius
	_arc_height  = arc_height
	_travel_time = travel_time
	_elapsed     = 0.0
	_active      = true

func _process(delta: float) -> void:
	if not _active:
		return
	var prev_pos: Vector3 = global_position
	_elapsed += delta
	var t: float = clamp(_elapsed / _travel_time, 0.0, 1.0)

	var flat: Vector3 = _start.lerp(_target, t)
	var height: float = _arc_height * 4.0 * t * (1.0 - t)
	global_position = Vector3(flat.x, flat.y + height, flat.z)

	if trail_particles:
		var move_dir: Vector3 = global_position - prev_pos
		if move_dir.length() > 0.001:
			var backward: Vector3 = -move_dir.normalized()
			if not backward.is_equal_approx(Vector3.UP) and not backward.is_equal_approx(Vector3.DOWN):
				trail_particles.look_at(trail_particles.global_position + backward, Vector3.UP)
			else:
				trail_particles.look_at(trail_particles.global_position + backward, Vector3.FORWARD)

	if t >= 1.0:
		_splash()

func _splash() -> void:
	_active = false

	# Detach and trigger splash particles in world space before freeing
	if splash_particles:
		var current_scene = get_tree().current_scene
		if is_instance_valid(current_scene):
			splash_particles.reparent(current_scene)
			splash_particles.emitting = true
			get_tree().create_timer(splash_particles.lifetime).timeout.connect(splash_particles.queue_free)
		else:
			splash_particles.queue_free()

	if _damage > 0.0:
		for player in get_tree().get_nodes_in_group("player"):
			if player.global_position.distance_to(global_position) <= _radius:
				player.take_damage(int(_damage))
				print("[WaterBalloon] Splash hit player for %d" % int(_damage))

	queue_free()
