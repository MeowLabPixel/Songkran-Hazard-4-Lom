@tool
extends GPUParticles3D
class_name ParticleBunchingFix

@export var enabled: bool = true

var is_active: bool = false:
	set(val):
		if is_active != val:
			is_active = val
			_has_old_transform = false
			if not Engine.is_editor_hint():
				set_process(is_active and enabled)

var old_transform: Transform3D
var old_transform_time: int = 0
var last_emitted: int = 0
var _has_old_transform: bool = false

func _ready() -> void:
	if not Engine.is_editor_hint():
		emitting = false # Silence Godot's native ticks so only interpolated sub-frame particles are emitted
		set_process(is_active and enabled) # Disable _process entirely when idle to save CPU

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not enabled or not is_active:
		return

	var current_time: int = Time.get_ticks_usec()

	# First frame of active attack prep: anchor initial transform to current hand location
	if not _has_old_transform:
		_has_old_transform = true
		old_transform = global_transform
		old_transform_time = current_time
		last_emitted = current_time
		return

	# Calculate microsecond interval per particle
	var effective_speed_scale: float = maxf(speed_scale, 0.001)
	var real_lifetime: float = lifetime / effective_speed_scale
	var emit_interval_usec: int = int((real_lifetime * 1_000_000.0) / maxf(float(amount), 1.0))
	if emit_interval_usec <= 0:
		emit_interval_usec = 10_000

	# Sub-frame interpolation along the motion path
	var max_iterations: int = 15 # Cap catch-up iterations to avoid CPU frame hitches
	var iterations: int = 0
	var time_diff: float = float(current_time - old_transform_time)
	
	if time_diff > 0.0:
		while (last_emitted + emit_interval_usec <= current_time) and (iterations < max_iterations):
			last_emitted += emit_interval_usec
			iterations += 1
			var w: float = clampf(float(last_emitted - old_transform_time) / time_diff, 0.0, 1.0)
			var interp_transform: Transform3D = old_transform.interpolate_with(global_transform, w)
			emit_particle(interp_transform, Vector3.ZERO, Color.WHITE, Color.WHITE, EMIT_FLAG_POSITION | EMIT_FLAG_ROTATION_SCALE)
	else:
		last_emitted = current_time

	old_transform = global_transform
	old_transform_time = current_time
