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

## Internal smoothed display value
var _display_value: float = 120.0


func _ready() -> void:
	_display_value = current_value


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_display_value = clampf(current_value, 0.0, max_value)
		queue_redraw()
		return

	var target := clampf(current_value, 0.0, max_value)
	_display_value = lerpf(_display_value, target, delta * smooth_speed)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var half := minf(size.x, size.y) * 0.5

	# ── Radius calculations ──
	# From outside inward: outer_border | ring_band | inner_border | portrait_bg
	var outer_r := half - border_width * 0.5
	var ring_r := half - border_width - ring_width * 0.5
	var inner_r := half - border_width - ring_width - border_width * 0.5
	var bg_r := inner_r - border_width * 0.5

	var ratio := clampf(_display_value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0

	# 1 ─ Portrait background circle (visible behind the 3D portrait)
	draw_circle(center, bg_r, portrait_bg_color)

	# 2 ─ Damaged ring (full circle — shows where healthy doesn't cover)
	var ring_aa := ring_width >= 1.0
	draw_arc(center, ring_r, 0.0, TAU, 64, damaged_color, ring_width, ring_aa)

	# 3 ─ Healthy ring (clockwise from start_angle)
	if ratio > 0.001:
		var start_rad := deg_to_rad(start_angle_deg)
		var sweep := ratio * TAU
		var segments := maxi(int(64.0 * ratio), 8)
		draw_arc(center, ring_r, start_rad, start_rad + sweep, segments, healthy_color, ring_width, ring_aa)

	# 4 ─ Border arcs (thin cyan outlines)
	if border_width > 0.0:
		var w := maxf(1.0, border_width)
		draw_arc(center, outer_r, 0.0, TAU, 64, border_color, w, true)
		draw_arc(center, inner_r, 0.0, TAU, 64, border_color, w, true)
