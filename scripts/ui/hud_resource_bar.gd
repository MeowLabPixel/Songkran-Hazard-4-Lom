@tool
## Horizontal trapezoid resource bar drawn with _draw().
## Renders a stylised bar with tapered left edge, fill, border, and label text.
## Used for both the water gauge and the air gauge.
## Fully tinker-ready with live preview in the Godot editor.
class_name HudResourceBar
extends Control

@export_group("Values")
## The maximum resource value (e.g. 200 for water, 100 for air).
@export var max_value: float = 100.0:
	set(v):
		max_value = v
		queue_redraw()

## The current resource value (preview in editor, driven by player/gun at runtime).
@export var current_value: float = 75.0:
	set(v):
		current_value = v
		if Engine.is_editor_hint():
			_display_value = v
		queue_redraw()

## Interpolation speed for smooth animated transitions at runtime.
@export var smooth_speed: float = 8.0

@export_group("Fill Direction")
## If true, the bar fills from right to left (outward from the portrait).
## If false, fills from left to right.
@export var fill_from_right: bool = true:
	set(v):
		fill_from_right = v
		queue_redraw()

@export_group("Shape & Colors")
## Color of the filled resource bar.
@export var fill_color: Color = Color("4fc3f7"):
	set(v):
		fill_color = v
		queue_redraw()

## Background fill color of the unfilled portion.
@export var bg_color: Color = Color(0.06, 0.08, 0.12, 0.88):
	set(v):
		bg_color = v
		queue_redraw()

## Border outline color.
@export var border_color: Color = Color("00bcd4"):
	set(v):
		border_color = v
		queue_redraw()

## Left-edge taper slant as a fraction of bar height (e.g. 0.45).
@export var taper_ratio: float = 0.45:
	set(v):
		taper_ratio = v
		queue_redraw()

## Thickness of the border outline in pixels.
@export var border_thickness: float = 1.5:
	set(v):
		border_thickness = v
		queue_redraw()

@export_group("Label")
## Text drawn inside the bar (e.g. "250", "100%").
@export var label_text: String = "100":
	set(v):
		label_text = v
		queue_redraw()

## Font used for the label.
@export var label_font: Font:
	set(v):
		label_font = v
		queue_redraw()

## Font size of the label in pixels.
@export var label_font_size: int = 18:
	set(v):
		label_font_size = v
		queue_redraw()

## Text color of the label.
@export var label_color: Color = Color.WHITE:
	set(v):
		label_color = v
		queue_redraw()

## Outline color of the label text.
@export var label_outline_color: Color = Color.BLACK:
	set(v):
		label_outline_color = v
		queue_redraw()

## Outline size of the label text in pixels.
@export var label_outline_size: int = 4:
	set(v):
		label_outline_size = v
		queue_redraw()

## Internal smoothed display value
var _display_value: float = 75.0


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
	var w := size.x
	var h := size.y
	var tp := h * taper_ratio
	var val := current_value if Engine.is_editor_hint() else _display_value
	var ratio := clampf(val / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0

	# ── Background trapezoid ──
	var bg_pts := PackedVector2Array([
		Vector2(tp, 0.0), Vector2(w, 0.0),
		Vector2(w, h),    Vector2(0.0, h),
	])
	draw_colored_polygon(bg_pts, bg_color)

	# ── Fill trapezoid ──
	if ratio > 0.001:
		if fill_from_right:
			var t_start := 1.0 - ratio
			var fill_pts := PackedVector2Array([
				Vector2(lerpf(tp, w, t_start), 0.0),
				Vector2(w, 0.0),
				Vector2(w, h),
				Vector2(lerpf(0.0, w, t_start), h),
			])
			draw_colored_polygon(fill_pts, fill_color)
		else:
			var fill_pts := PackedVector2Array([
				Vector2(tp, 0.0),
				Vector2(lerpf(tp, w, ratio), 0.0),
				Vector2(lerpf(0.0, w, ratio), h),
				Vector2(0.0, h),
			])
			draw_colored_polygon(fill_pts, fill_color)

	# ── Border lines ──
	if border_thickness > 0.0:
		var aa := border_thickness >= 1.0
		for i in range(bg_pts.size()):
			var from_pt := bg_pts[i]
			var to_pt := bg_pts[(i + 1) % bg_pts.size()]
			draw_line(from_pt, to_pt, border_color, border_thickness, aa)

	# ── Label text ──
	if label_text == "":
		return

	var active_font := label_font
	if active_font == null:
		active_font = ThemeDB.fallback_font

	if active_font != null:
		var ts := active_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size)
		var tx := (tp + w) * 0.5 - ts.x * 0.5
		var ty := h * 0.5 + ts.y * 0.3

		# Outline then foreground
		if label_outline_size > 0:
			draw_string_outline(active_font, Vector2(tx, ty), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size,
				label_outline_size, label_outline_color)
		draw_string(active_font, Vector2(tx, ty), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, label_color)
