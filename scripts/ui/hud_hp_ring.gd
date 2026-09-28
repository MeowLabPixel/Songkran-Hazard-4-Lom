@tool
## Circular HP ring drawn with _draw(). Renders a background circle,
## a full "damaged" ring, a partial "healthy" ring on top, and border arcs.
## Used for both the player and follower portrait rings.
## Fully tinker-ready with live preview in the Godot editor.
class_name HudHPRing
extends Control

@export_group("Values")
## The maximum HP value (e.g. 150).
@export var max_value: float = 150.0:
	set(v):
		max_value = v
		queue_redraw()

## The current HP value (preview in editor, driven by player at runtime).
@export var current_value: float = 120.0:
	set(v):
		current_value = v
		if Engine.is_editor_hint():
			_display_value = v
		queue_redraw()

## Interpolation speed for smooth animated transitions at runtime.
@export var smooth_speed: float = 8.0

@export_group("Visuals")
## Width of the health / damage circular ring band in pixels.
@export var ring_width: float = 7.0:
	set(v):
		ring_width = v
		queue_redraw()

## Width of the inner and outer border outlines in pixels.
@export var border_width: float = 2.0:
	set(v):
		border_width = v
		queue_redraw()

## Color for remaining HP (dryness).
@export var healthy_color: Color = Color("00e676"):
	set(v):
		healthy_color = v
		queue_redraw()

## Color for lost HP (wetness).
@export var damaged_color: Color = Color("1565c0"):
	set(v):
		damaged_color = v
		queue_redraw()

## Color for the inner and outer outline borders.
@export var border_color: Color = Color("00bcd4"):
	set(v):
		border_color = v
		queue_redraw()

## Color for the background disk sitting behind the 3D portrait.
@export var portrait_bg_color: Color = Color(0.04, 0.05, 0.08, 0.95):
	set(v):
		portrait_bg_color = v
		queue_redraw()

## Starting angle of the health arc in degrees (-90 = 12 o'clock top).
@export var start_angle_deg: float = -90.0:
	set(v):
		start_angle_deg = v
		queue_redraw()

@export_group("Chunk Layers")
## If true, renders a lingering chunk/ghost layer showing recently lost HP/damage.
@export var enable_lost_chunk: bool = true:
	set(v):
		enable_lost_chunk = v
		queue_redraw()

## Color of the lingering lost HP chunk (damage).
@export var lost_chunk_color: Color = Color(1.0, 0.25, 0.25, 0.85):
	set(v):
		lost_chunk_color = v
		queue_redraw()

## Delay in seconds before the lost chunk begins smoothly decaying away.
@export var lost_chunk_delay: float = 0.35:
	set(v):
		lost_chunk_delay = maxf(0.0, v)

## Decay speed multiplier when the lost chunk drains towards current HP.
@export var lost_chunk_speed: float = 3.0:
	set(v):
		lost_chunk_speed = maxf(0.1, v)

## Click in the inspector to test the lost chunk reaction (works live in editor).
@export var test_lost_chunk: bool = false:
	set(v):
		if v:
			trigger_lost_chunk_test()

## If true, renders an advance preview chunk showing newly gained / healed HP.
@export var enable_gain_chunk: bool = true:
	set(v):
		enable_gain_chunk = v
		queue_redraw()

## Color of the newly gained/healed HP chunk (heal / regen).
@export var gain_chunk_color: Color = Color(0.2, 1.0, 0.5, 0.85):
	set(v):
		gain_chunk_color = v
		queue_redraw()

## Click in the inspector to test the gain chunk reaction (works live in editor).
@export var test_gain_chunk: bool = false:
	set(v):
		if v:
			trigger_gain_chunk_test()

@export_group("Juice & Reactions")
## If true, enables shake, damage flash, and grab struggle effects.
@export var enable_juice: bool = true

## Maximum shake displacement in pixels when taking damage.
@export var hit_shake_intensity: float = 7.0

## Flash color overlay when taking damage.
@export var hit_flash_color: Color = Color(1.0, 0.15, 0.15, 0.85)

## Danger aura color when grabbed / struggling.
@export var grab_pulse_color: Color = Color(1.0, 0.35, 0.0, 0.85)

## Internal smoothed display value
var _display_value: float = 120.0

## Internal lost chunk tracking variables
var _last_tracked_value: float = -1.0
var _lost_chunk_value: float = 120.0
var _lost_chunk_timer: float = 0.0

## Internal juice state variables
var _shake_trauma: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _flash_alpha: float = 0.0
var _flash_tween: Tween = null
var _is_grabbed: bool = false
var _grab_pulse_time: float = 0.0
var _hit_ripple_active: bool = false
var _hit_ripple_radius: float = 0.0
var _hit_ripple_alpha: float = 0.0


func _ready() -> void:
	_display_value = current_value
	_lost_chunk_value = current_value
	_last_tracked_value = current_value


func trigger_lost_chunk_test(amount: float = 25.0) -> void:
	var start_val := current_value
	_lost_chunk_value = start_val
	_lost_chunk_timer = lost_chunk_delay
	current_value = maxf(0.0, start_val - amount)
	if Engine.is_editor_hint():
		_display_value = current_value
	trigger_hit_reaction(1.0)
	queue_redraw()


func trigger_gain_chunk_test(amount: float = 25.0) -> void:
	var start_val := current_value
	_display_value = start_val
	current_value = minf(max_value, start_val + amount)
	_lost_chunk_value = current_value
	_lost_chunk_timer = 0.0
	queue_redraw()


func trigger_hit_reaction(intensity: float = 1.0) -> void:
	if not enable_juice or not is_inside_tree():
		return

	_shake_trauma = clampf(_shake_trauma + 0.8 * intensity, 0.0, 1.5)
	_flash_alpha = 1.0

	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "_flash_alpha", 0.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_hit_ripple_active = true
	_hit_ripple_radius = minf(size.x, size.y) * 0.5 - border_width
	_hit_ripple_alpha = 1.0

	var rip_tw := create_tween().set_parallel(true)
	rip_tw.tween_property(self, "_hit_ripple_radius", minf(size.x, size.y) * 0.72, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rip_tw.tween_property(self, "_hit_ripple_alpha", 0.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rip_tw.finished.connect(func(): _hit_ripple_active = false)

	queue_redraw()


func set_grabbed(grabbed: bool) -> void:
	_is_grabbed = grabbed
	if not grabbed:
		_grab_pulse_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	var target := clampf(current_value, 0.0, max_value)

	if _last_tracked_value < 0.0:
		_last_tracked_value = current_value
		_lost_chunk_value = current_value

	# Track sudden drop or rise in current value
	if current_value < _last_tracked_value - 0.001:
		_lost_chunk_value = maxf(_lost_chunk_value, _last_tracked_value)
		_lost_chunk_timer = lost_chunk_delay
	elif current_value > _last_tracked_value + 0.001:
		_lost_chunk_value = maxf(_lost_chunk_value, current_value)
		_lost_chunk_timer = 0.0
	_last_tracked_value = current_value

	# Ensure lost chunk never sits below current target
	if _lost_chunk_value < target:
		_lost_chunk_value = target

	# Handle lost chunk delay timer and decay lerp
	if _lost_chunk_timer > 0.0:
		_lost_chunk_timer = maxf(0.0, _lost_chunk_timer - delta)
	elif _lost_chunk_value > target:
		var decay_target := maxf(_display_value, target)
		_lost_chunk_value = lerpf(_lost_chunk_value, decay_target, clampf(delta * lost_chunk_speed, 0.0, 1.0))
		if absf(_lost_chunk_value - decay_target) < 0.05:
			_lost_chunk_value = decay_target
		queue_redraw()

	if Engine.is_editor_hint():
		_display_value = target
		queue_redraw()
		return

	_display_value = lerpf(_display_value, target, delta * smooth_speed)

	# ── Trauma shake calculation ──
	if _shake_trauma > 0.0:
		_shake_trauma = maxf(0.0, _shake_trauma - delta * 3.5)
		var shake_amount := _shake_trauma * _shake_trauma * hit_shake_intensity
		_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amount
	elif _is_grabbed:
		_shake_offset = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	else:
		_shake_offset = Vector2.ZERO

	if _is_grabbed:
		_grab_pulse_time += delta * 6.0

	queue_redraw()


func _draw() -> void:
	var center := size * 0.5 + _shake_offset
	var half := minf(size.x, size.y) * 0.5

	# ── Radius calculations ──
	var outer_r := half - border_width * 0.5
	var ring_r := half - border_width - ring_width * 0.5
	var inner_r := half - border_width - ring_width - border_width * 0.5
	var bg_r := inner_r - border_width * 0.5

	var val := current_value if Engine.is_editor_hint() else _display_value
	var ratio := clampf(val / maxf(max_value, 0.001), 0.0, 1.0) if max_value > 0.0 else 0.0
	var target_val := current_value
	var gain_ratio := clampf(target_val / maxf(max_value, 0.001), 0.0, 1.0) if max_value > 0.0 else 0.0

	var show_lost_chunk := enable_lost_chunk and (_lost_chunk_value > val + 0.001)
	var chunk_ratio := clampf(_lost_chunk_value / maxf(max_value, 0.001), 0.0, 1.0) if max_value > 0.0 else 0.0

	var show_gain_chunk := enable_gain_chunk and (target_val > val + 0.001)

	# Dynamic juice colors
	var cur_border_col := border_color
	var cur_damaged_col := damaged_color
	var cur_healthy_col := healthy_color

	if _flash_alpha > 0.001:
		cur_border_col = cur_border_col.lerp(hit_flash_color, _flash_alpha)
		cur_damaged_col = cur_damaged_col.lerp(hit_flash_color, _flash_alpha * 0.8)

	if _is_grabbed:
		var grab_glow := (sin(_grab_pulse_time) * 0.5 + 0.5)
		cur_border_col = cur_border_col.lerp(grab_pulse_color, 0.5 + grab_glow * 0.5)

	# 1 ─ Portrait background circle (visible behind the 3D portrait)
	draw_circle(center, bg_r, portrait_bg_color)

	# 2 ─ Damaged ring (full circle — shows where healthy/chunk doesn't cover)
	var ring_aa := ring_width >= 1.0
	draw_arc(center, ring_r, 0.0, TAU, 64, cur_damaged_col, ring_width, ring_aa)

	var start_rad := deg_to_rad(start_angle_deg)

	# 3 ─ Lost HP Chunk arc (lingering damage before decaying away)
	if show_lost_chunk and chunk_ratio > 0.001:
		var chunk_sweep := chunk_ratio * TAU
		var chunk_segments := maxi(int(64.0 * chunk_ratio), 8)
		draw_arc(center, ring_r, start_rad, start_rad + chunk_sweep, chunk_segments, lost_chunk_color, ring_width, ring_aa)

	# 4 ─ Gain HP Chunk arc (advance preview of healing before smooth catchup)
	if show_gain_chunk and gain_ratio > 0.001:
		var gain_sweep := gain_ratio * TAU
		var gain_segments := maxi(int(64.0 * gain_ratio), 8)
		draw_arc(center, ring_r, start_rad, start_rad + gain_sweep, gain_segments, gain_chunk_color, ring_width, ring_aa)

	# 5 ─ Healthy ring (clockwise from start_angle)
	if ratio > 0.001:
		var sweep := ratio * TAU
		var segments := maxi(int(64.0 * ratio), 8)
		draw_arc(center, ring_r, start_rad, start_rad + sweep, segments, cur_healthy_col, ring_width, ring_aa)

	# 6 ─ Border arcs
	if border_width > 0.0:
		var w := maxf(1.0, border_width)
		draw_arc(center, outer_r, 0.0, TAU, 64, cur_border_col, w, true)
		draw_arc(center, inner_r, 0.0, TAU, 64, cur_border_col, w, true)

	# 7 ─ Grab struggle danger aura
	if _is_grabbed:
		var grab_r := outer_r + 3.0 + sin(_grab_pulse_time) * 2.0
		var grab_a := 0.4 + sin(_grab_pulse_time) * 0.3
		draw_arc(center, grab_r, 0.0, TAU, 48, Color(grab_pulse_color.r, grab_pulse_color.g, grab_pulse_color.b, grab_a), 2.5, true)

	# 8 ─ Hit expanding ripple wave
	if _hit_ripple_active and _hit_ripple_alpha > 0.001:
		var rip_col := Color(hit_flash_color.r, hit_flash_color.g, hit_flash_color.b, _hit_ripple_alpha * 0.75)
		draw_arc(center, _hit_ripple_radius, 0.0, TAU, 48, rip_col, 2.0, true)
