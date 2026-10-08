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

## If true, flips the trapezoid shape vertically (tapers bottom instead of top).
@export var flip_vertical: bool = false:
	set(v):
		flip_vertical = v
		queue_redraw()

## Thickness of the border outline in pixels.
@export var border_thickness: float = 1.5:
	set(v):
		border_thickness = v
		queue_redraw()

@export_group("Corner Rounding")
## Master corner rounding radius in pixels for all 4 corners (0 = sharp corners).
@export_range(0.0, 50.0, 0.5) var corner_radius: float = 0.0:
	set(v):
		corner_radius = maxf(0.0, 0.0 if v == null else v)
		queue_redraw()

## Top-left corner radius in pixels (-1 = inherit master corner_radius).
@export_range(-1.0, 50.0, 0.5) var corner_radius_top_left: float = -1.0:
	set(v):
		corner_radius_top_left = -1.0 if v == null else v
		queue_redraw()

## Top-right corner radius in pixels (-1 = inherit master corner_radius).
@export_range(-1.0, 50.0, 0.5) var corner_radius_top_right: float = -1.0:
	set(v):
		corner_radius_top_right = -1.0 if v == null else v
		queue_redraw()

## Bottom-right corner radius in pixels (-1 = inherit master corner_radius).
@export_range(-1.0, 50.0, 0.5) var corner_radius_bottom_right: float = -1.0:
	set(v):
		corner_radius_bottom_right = -1.0 if v == null else v
		queue_redraw()

## Bottom-left corner radius in pixels (-1 = inherit master corner_radius).
@export_range(-1.0, 50.0, 0.5) var corner_radius_bottom_left: float = -1.0:
	set(v):
		corner_radius_bottom_left = -1.0 if v == null else v
		queue_redraw()

## Number of line segments per rounded corner arc (higher = smoother curve).
@export_range(1, 16) var corner_detail: int = 6:
	set(v):
		corner_detail = clampi(1 if v == null else v, 1, 16)
		queue_redraw()

## Corner radius for individual segments when segmented_mode is active (-1 = inherit corner_radius).
@export_range(-1.0, 30.0, 0.5) var segment_corner_radius: float = -1.0:
	set(v):
		segment_corner_radius = -1.0 if v == null else v
		queue_redraw()

## Rounding mode for segmented bars:
## - "All Segments": Rounds all 4 corners of every segment into rounded pill tiles.
## - "Outer Only": Rounds only the outer corners of the first and last segments, keeping inner dividers straight.
## - "None": Keeps all segments with sharp corners.
@export_enum("All Segments", "Outer Only", "None") var segment_rounding_mode: String = "All Segments":
	set(v):
		segment_rounding_mode = "All Segments" if v == null or v == "" else v
		queue_redraw()

@export_group("Bar Shadow")
## If true, renders a drop shadow behind the resource bar / gauge.
@export var bar_shadow_enabled: bool = false:
	set(v):
		bar_shadow_enabled = false if v == null else v
		queue_redraw()

## Color of the bar drop shadow (including opacity/alpha).
@export var bar_shadow_color: Color = Color(0.0, 0.0, 0.0, 0.45):
	set(v):
		bar_shadow_color = Color(0.0, 0.0, 0.0, 0.45) if v == null else v
		queue_redraw()

## Positional offset in pixels for the bar shadow (X and Y).
@export var bar_shadow_offset: Vector2 = Vector2(0.0, 4.0):
	set(v):
		bar_shadow_offset = Vector2.ZERO if v == null else v
		queue_redraw()

## Expansion / outset margin in pixels around the bar shadow (positive = larger shadow, negative = tighter shadow).
@export_range(-10.0, 20.0, 0.5) var bar_shadow_spread: float = 0.0:
	set(v):
		bar_shadow_spread = 0.0 if v == null else v
		queue_redraw()

## Blur / softness factor for the bar shadow (0 = crisp 1-pass shadow, 1-4 = multi-sample soft shadow).
@export_range(0, 4) var bar_shadow_blur: int = 0:
	set(v):
		bar_shadow_blur = clampi(0 if v == null else v, 0, 4)
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

## Positional offset for the label text in pixels.
@export var label_offset: Vector2 = Vector2.ZERO:
	set(v):
		label_offset = Vector2.ZERO if v == null else v
		queue_redraw()

## Rotation angle of the label text in degrees.
@export_range(-360.0, 360.0, 0.5) var label_rotation_degrees: float = 0.0:
	set(v):
		label_rotation_degrees = 0.0 if v == null else v
		queue_redraw()

## If true, flips the label text horizontally.
@export var label_flip_h: bool = false:
	set(v):
		label_flip_h = false if v == null else v
		queue_redraw()

## If true, flips the label text vertically.
@export var label_flip_v: bool = false:
	set(v):
		label_flip_v = false if v == null else v
		queue_redraw()

@export_subgroup("Shadow", "label_shadow_")
## If true, renders a drop shadow behind the label text.
@export var label_shadow_enabled: bool = false:
	set(v):
		label_shadow_enabled = false if v == null else v
		queue_redraw()

## Color of the label text shadow (including opacity/alpha).
@export var label_shadow_color: Color = Color(0.0, 0.0, 0.0, 0.65):
	set(v):
		label_shadow_color = Color(0.0, 0.0, 0.0, 0.65) if v == null else v
		queue_redraw()

## Positional offset in pixels for the text shadow (X and Y).
@export var label_shadow_offset: Vector2 = Vector2(2.0, 2.0):
	set(v):
		label_shadow_offset = Vector2.ZERO if v == null else v
		queue_redraw()

## Additional outline thickness in pixels for the text shadow (bolder/fuller backing shadow).
@export_range(0, 16) var label_shadow_outline_size: int = 0:
	set(v):
		label_shadow_outline_size = maxi(0, 0 if v == null else v)
		queue_redraw()

## Blur / softness factor for the text shadow (0 = crisp 1-pass shadow, 1-4 = multi-sample soft shadow).
@export_range(0, 4) var label_shadow_blur: int = 0:
	set(v):
		label_shadow_blur = clampi(0 if v == null else v, 0, 4)
		queue_redraw()

## Scale multiplier applied to label text during reload QTE (e.g. 1.5 for 50% larger).
@export var reload_qte_label_scale: float = 1.5:
	set(v):
		reload_qte_label_scale = maxf(0.1, 1.5 if v == null else v)
		queue_redraw()

## Additional positional offset in pixels applied to the label text specifically during reload QTE.
@export var reload_qte_label_offset: Vector2 = Vector2.ZERO:
	set(v):
		reload_qte_label_offset = Vector2.ZERO if v == null else v
		queue_redraw()

## If true, disables label position changes during QTE (keeps label anchored at its rest position while the bar extends).
@export var reload_qte_disable_label_shift: bool = false:
	set(v):
		reload_qte_disable_label_shift = false if v == null else v
		queue_redraw()

## Horizontal bar extension offset in pixels applied during reload QTE (negative values stretch outward).
@export var reload_qte_bar_offset: float = -150.0:
	set(v):
		reload_qte_bar_offset = -150.0 if v == null else v
		queue_redraw()

## Click in the inspector to test the reload QTE bar extension and label scaling (works live in editor).
@export var test_reload_qte_scale: bool = false:
	set(v):
		test_reload_qte_scale = v
		set_reload_qte(v)

@export_group("Chunk Layers")
## If true, renders a lingering chunk/ghost layer showing recently lost/consumed resource.
@export var enable_lost_chunk: bool = true:
	set(v):
		enable_lost_chunk = v
		queue_redraw()

## Color of the lingering lost resource chunk (damage / consumption).
@export var lost_chunk_color: Color = Color(1.0, 0.35, 0.2, 0.85):
	set(v):
		lost_chunk_color = v
		queue_redraw()

## Delay in seconds before the lost chunk begins smoothly decaying away.
@export var lost_chunk_delay: float = 0.35:
	set(v):
		lost_chunk_delay = maxf(0.0, v)

## Decay speed multiplier when the lost chunk drains towards the current value.
@export var lost_chunk_speed: float = 3.0:
	set(v):
		lost_chunk_speed = maxf(0.1, v)

## Click in the inspector to test the lost chunk reaction (works live in editor).
@export var test_lost_chunk: bool = false:
	set(v):
		if v:
			trigger_lost_chunk_test()

## If true, renders an advance preview chunk showing newly gained / refilled resource.
@export var enable_gain_chunk: bool = true:
	set(v):
		enable_gain_chunk = v
		queue_redraw()

## Color of the newly gained/refilled resource chunk (refill / pump).
@export var gain_chunk_color: Color = Color(0.3, 0.95, 0.7, 0.85):
	set(v):
		gain_chunk_color = v
		queue_redraw()

## Click in the inspector to test the gain chunk reaction (works live in editor).
@export var test_gain_chunk: bool = false:
	set(v):
		if v:
			trigger_gain_chunk_test()

@export_group("Segmented Slots")
## If true, renders the bar as distinct increment slots instead of a continuous fill.
@export var segmented_mode: bool = false:
	set(v):
		segmented_mode = false if v == null else v
		queue_redraw()

## Percentage value represented by each increment slot (default 5.0% -> 20 slots for 100%).
@export var segment_pct: float = 5.0:
	set(v):
		segment_pct = maxf(0.5, 5.0 if v == null else v)
		queue_redraw()

## Pixel spacing gap between adjacent slots.
@export var segment_gap: float = 2.0:
	set(v):
		segment_gap = maxf(0.0, 2.0 if v == null else v)
		queue_redraw()

## If true, draws unfilled background slot boxes for empty slots.
@export var draw_empty_slots: bool = true:
	set(v):
		draw_empty_slots = true if v == null else v
		queue_redraw()

## Color for unfilled empty slots.
@export var slot_empty_color: Color = Color(0.06, 0.08, 0.12, 0.88):
	set(v):
		slot_empty_color = v
		queue_redraw()

## Optional outline border thickness for individual slots. Set to 0.0 to disable.
@export var slot_border_thickness: float = 0.0:
	set(v):
		slot_border_thickness = maxf(0.0, 0.0 if v == null else v)
		queue_redraw()

## Optional outline border color for individual slots.
@export var slot_border_color: Color = Color("00bcd4"):
	set(v):
		slot_border_color = v
		queue_redraw()

@export_group("Juice & Shake Settings")
## If true, enables punchy scale kick, shake, and flash effects on shot and reload.
@export var enable_juice: bool = true

## If true, enables positional trauma vibration shake on QTE prompt hits.
@export var enable_shake: bool = true

## Click in the inspector to test the shot kick reaction (works live in editor).
@export var test_shot_reaction: bool = false:
	set(v):
		if v:
			trigger_shot_reaction()

## Click in the inspector to test the reload pulse reaction (works live in editor).
@export var test_reload_reaction: bool = false:
	set(v):
		if v:
			trigger_reload_pulse()

## Positional recoil kick offset in pixels applied to the reduction edge on shot fired.
@export var shot_kick_offset_px: float = 6.0

## Vertical thickness scale kick multiplier applied when a shot is fired.
@export var shot_kick_v_scale: float = 1.12

## Direction in which the vertical thickness kick/swell expands:
## - "Upward": Anchors the bottom edge so it pulses upward.
## - "Downward": Anchors the top edge so it pulses downward.
## - "Center": Anchors the center line so it expands symmetrically.
@export_enum("Upward", "Downward", "Center") var shot_kick_v_direction: String = "Upward":
	set(v):
		shot_kick_v_direction = "Upward" if v == null or v == "" else v
		queue_redraw()

## Flash color overlay on shot fired.
@export var shot_flash_color: Color = Color(1.0, 1.0, 1.0, 0.45)

## Positional recoil/expansion kick offset in pixels applied on reload/pump (negative values expand outward).
@export var reload_kick_offset_px: float = -6.0

## Vertical thickness scale swell multiplier applied when reloading or pumping.
@export var reload_pulse_v_scale: float = 1.08

## Flash color overlay on reload / pump.
@export var reload_flash_color: Color = Color(1.0, 1.0, 1.0, 0.55)

@export_group("QTE Reactions & Flashes")
## Positional shake intensity in pixels applied when a QTE prompt is missed or failed (empty zone hit).
@export var qte_fail_shake_intensity: float = 7.5

## Flash color overlay when player mistimes or fails a QTE prompt (empty zone hit).
@export var qte_fail_red_flash_color: Color = Color(1.0, 0.2, 0.2, 0.90)

## Flash fade duration in seconds when player mistimes or fails a QTE prompt.
@export var qte_fail_flash_duration: float = 0.45

## Click in the inspector to test the QTE Fail Shake & Red Flash reaction (works live in editor).
@export var test_qte_fail_reaction: bool = false:
	set(v):
		if v:
			trigger_qte_fail_reaction()

## Vertical scale compression factor during the initial squash phase of a QTE squish (e.g. 0.25).
@export var qte_squish_compress_scale: float = 0.25

## Vertical thickness scale squish multiplier applied when a QTE prompt is hit or on standard 100% complete.
@export var qte_hit_v_scale: float = 1.35

## Vertical thickness scale squish multiplier applied on perfect QTE completion (springs bigger).
@export var qte_perfect_v_scale: float = 1.50

## Direction in which the QTE squish thickness expands:
## - "Center": Anchors the center line so it squishes symmetrically from both above and below.
## - "Upward": Anchors the bottom edge so it pulses upward.
## - "Downward": Anchors the top edge so it pulses downward.
@export_enum("Center", "Upward", "Downward") var qte_hit_v_direction: String = "Center":
	set(v):
		qte_hit_v_direction = "Center" if v == null or v == "" else v
		queue_redraw()

## Flash color overlay when a QTE prompt is hit.
@export var qte_hit_flash_color: Color = Color(1.0, 1.0, 1.0, 0.65)

## Flash fade duration in seconds when a QTE prompt is hit.
@export var qte_hit_flash_duration: float = 0.22

## Click in the inspector to test the satisfying QTE Hit Squish & Flash reaction (works live in editor).
@export var test_qte_hit_squish: bool = false:
	set(v):
		if v:
			trigger_qte_hit_reaction()

## Click in the inspector to test the QTE Hit Shake & Punch reaction (works live in editor).
@export var test_qte_hit_shake: bool = false:
	set(v):
		if v:
			trigger_qte_hit_reaction()

## Flash color overlay when air reaches 100% on normal/partial QTE completion.
@export var qte_complete_white_flash_color: Color = Color(1.0, 1.0, 1.0, 0.95)

## Flash fade duration in seconds when air reaches 100% on normal/partial QTE completion.
@export var qte_complete_flash_duration: float = 0.85

## Click in the inspector to test the 100% Air White Flash reaction (works live in editor).
@export var test_qte_complete_white_flash: bool = false:
	set(v):
		if v:
			trigger_qte_full_air_flash()

## Flash color overlay when all QTE prompts are perfected.
@export var qte_perfect_green_flash_color: Color = Color(0.2, 1.0, 0.4, 0.95)

## Flash fade duration in seconds when all QTE prompts are perfected.
@export var qte_perfect_flash_duration: float = 1.10

## Click in the inspector to test the Perfect QTE Green Flash reaction (works live in editor).
@export var test_qte_perfect_green_flash: bool = false:
	set(v):
		if v:
			trigger_qte_perfect_flash()

## Internal smoothed display value
var _display_value: float = 75.0

## Internal lost chunk tracking variables
var _last_tracked_value: float = -1.0
var _lost_chunk_value: float = 75.0
var _lost_chunk_timer: float = 0.0

## Internal juice reaction edge kick, vertical scale, and flash
var _juice_edge_kick: float = 0.0
var _juice_scale_y: float = 1.0
var _active_v_direction: String = ""
var _juice_flash_alpha: float = 0.0
var _juice_flash_color: Color = Color.WHITE
var _juice_tween: Tween = null
var _flash_tween: Tween = null

## Internal trauma shake tracking
var _shake_trauma: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

## Internal QTE completion flash lock
var _is_qte_completion_flash_active: bool = false

## Internal reload QTE state and blend factor (0.0 = normal, 1.0 = in reload QTE)
var _is_reload_qte_active: bool = false
var _label_qte_blend: float = 0.0:
	set(v):
		_label_qte_blend = v
		queue_redraw()
var _label_scale_tween: Tween = null


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
	trigger_shot_reaction()
	queue_redraw()


func trigger_gain_chunk_test(amount: float = 25.0) -> void:
	var start_val := current_value
	_display_value = start_val
	current_value = minf(max_value, start_val + amount)
	_lost_chunk_value = current_value
	_lost_chunk_timer = 0.0
	trigger_reload_pulse()
	queue_redraw()


func set_reload_qte(active: bool) -> void:
	if _is_reload_qte_active == active and _label_scale_tween != null and _label_scale_tween.is_valid():
		return
	if _is_reload_qte_active == active and (_label_qte_blend == (1.0 if active else 0.0)):
		return
	_is_reload_qte_active = active
	if _label_scale_tween and _label_scale_tween.is_valid():
		_label_scale_tween.kill()
	var target := 1.0 if active else 0.0
	if not is_inside_tree() or Engine.is_editor_hint():
		_label_qte_blend = target
		queue_redraw()
		return
	_label_scale_tween = create_tween()
	_label_scale_tween.tween_property(self, "_label_qte_blend", target, 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_label_scale_tween.tween_callback(queue_redraw)


func trigger_shot_reaction(include_offset: bool = true) -> void:
	if not enable_juice:
		return
	if is_inside_tree() and _juice_tween and _juice_tween.is_valid():
		_juice_tween.kill()
	if not _is_qte_completion_flash_active:
		if is_inside_tree() and _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()

	_active_v_direction = shot_kick_v_direction
	if include_offset:
		var kick_dir: float = 1.0 if fill_from_right else -1.0
		_juice_edge_kick = kick_dir * shot_kick_offset_px
	_juice_scale_y = shot_kick_v_scale
	if not _is_qte_completion_flash_active:
		_juice_flash_alpha = 1.0
		_juice_flash_color = shot_flash_color
	queue_redraw()

	if not is_inside_tree():
		return

	_juice_tween = create_tween().set_parallel(true)
	if include_offset:
		_juice_tween.tween_property(self, "_juice_edge_kick", 0.0, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_juice_tween.tween_property(self, "_juice_scale_y", 1.0, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_juice_tween.chain().tween_callback(queue_redraw)

	if not _is_qte_completion_flash_active:
		_flash_tween = create_tween()
		_flash_tween.tween_property(self, "_juice_flash_alpha", 0.0, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func trigger_qte_hit_reaction() -> void:
	if not enable_juice:
		return
	if is_inside_tree() and _juice_tween and _juice_tween.is_valid():
		_juice_tween.kill()
	if not _is_qte_completion_flash_active:
		if is_inside_tree() and _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()

	_active_v_direction = qte_hit_v_direction
	if not _is_qte_completion_flash_active:
		_juice_flash_alpha = 1.0
		_juice_flash_color = qte_hit_flash_color
	queue_redraw()

	if not is_inside_tree():
		_juice_scale_y = qte_hit_v_scale
		return

	_juice_tween = create_tween()
	# Phase 1: Rapid squash compress down (0.25)
	_juice_tween.tween_property(self, "_juice_scale_y", qte_squish_compress_scale, 0.04) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Phase 2: Explosive spring overshoot up to 1.35x
	_juice_tween.tween_property(self, "_juice_scale_y", qte_hit_v_scale, 0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Phase 3: Satisfying elastic bounce back to 1.0
	_juice_tween.tween_property(self, "_juice_scale_y", 1.0, 0.24) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_juice_tween.tween_callback(queue_redraw)

	if not _is_qte_completion_flash_active:
		_flash_tween = create_tween()
		_flash_tween.tween_property(self, "_juice_flash_alpha", 0.0, qte_hit_flash_duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func trigger_qte_fail_reaction() -> void:
	if not enable_juice:
		return
	if is_inside_tree() and _juice_tween and _juice_tween.is_valid():
		_juice_tween.kill()
	if not _is_qte_completion_flash_active:
		if is_inside_tree() and _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()

	_active_v_direction = qte_hit_v_direction
	if enable_shake:
		_shake_trauma = 1.0

	if not _is_qte_completion_flash_active:
		_juice_flash_alpha = 1.0
		_juice_flash_color = qte_fail_red_flash_color
	queue_redraw()

	if not is_inside_tree():
		return

	if not _is_qte_completion_flash_active:
		_flash_tween = create_tween()
		_flash_tween.tween_property(self, "_juice_flash_alpha", 0.0, qte_fail_flash_duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func trigger_reload_pulse() -> void:
	if not enable_juice:
		return
	if is_inside_tree() and _juice_tween and _juice_tween.is_valid():
		_juice_tween.kill()
	if not _is_qte_completion_flash_active:
		if is_inside_tree() and _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()

	_active_v_direction = shot_kick_v_direction
	var kick_dir: float = 1.0 if fill_from_right else -1.0
	var target_kick := kick_dir * reload_kick_offset_px
	var target_scale_y := reload_pulse_v_scale

	if not _is_qte_completion_flash_active:
		_juice_flash_alpha = 1.0
		_juice_flash_color = reload_flash_color
	queue_redraw()

	if not is_inside_tree():
		return

	_juice_tween = create_tween()
	# Phase 1: Smoothly surge/expand outward to peak
	var tween_out := _juice_tween.parallel()
	tween_out.tween_property(self, "_juice_edge_kick", target_kick, 0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween_out.tween_property(self, "_juice_scale_y", target_scale_y, 0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Phase 2: Elastic bounce back to rest position
	var tween_back := _juice_tween.chain().parallel()
	tween_back.tween_property(self, "_juice_edge_kick", 0.0, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween_back.tween_property(self, "_juice_scale_y", 1.0, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_juice_tween.chain().tween_callback(queue_redraw)

	if not _is_qte_completion_flash_active:
		_flash_tween = create_tween()
		_flash_tween.tween_property(self, "_juice_flash_alpha", 0.0, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func trigger_qte_full_air_flash() -> void:
	if not enable_juice:
		return
	if is_inside_tree() and _juice_tween and _juice_tween.is_valid():
		_juice_tween.kill()
	if is_inside_tree() and _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	_active_v_direction = qte_hit_v_direction
	_is_qte_completion_flash_active = true
	_juice_flash_alpha = 1.0
	_juice_flash_color = qte_complete_white_flash_color
	queue_redraw()

	if not is_inside_tree():
		return

	_juice_tween = create_tween()
	# Phase 1: Rapid squash compress down (0.25)
	_juice_tween.tween_property(self, "_juice_scale_y", qte_squish_compress_scale, 0.04) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Phase 2: Explosive spring overshoot up to 1.35x
	_juice_tween.tween_property(self, "_juice_scale_y", qte_hit_v_scale, 0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Phase 3: Satisfying elastic bounce back to 1.0
	_juice_tween.tween_property(self, "_juice_scale_y", 1.0, 0.24) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_juice_tween.chain().tween_callback(queue_redraw)

	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "_juice_flash_alpha", 0.0, qte_complete_flash_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.chain().tween_callback(func(): _is_qte_completion_flash_active = false)


func trigger_qte_perfect_flash() -> void:
	if not enable_juice:
		return
	if is_inside_tree() and _juice_tween and _juice_tween.is_valid():
		_juice_tween.kill()
	if is_inside_tree() and _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	_active_v_direction = qte_hit_v_direction
	_is_qte_completion_flash_active = true
	_juice_flash_alpha = 1.0
	_juice_flash_color = qte_perfect_green_flash_color
	queue_redraw()

	if not is_inside_tree():
		return

	_juice_tween = create_tween()
	# Phase 1: Rapid squash compress down (0.25)
	_juice_tween.tween_property(self, "_juice_scale_y", qte_squish_compress_scale, 0.04) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Phase 2: Explosive spring overshoot BIGGER to 1.50x
	_juice_tween.tween_property(self, "_juice_scale_y", qte_perfect_v_scale, 0.09) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Phase 3: Satisfying elastic bounce back to 1.0
	_juice_tween.tween_property(self, "_juice_scale_y", 1.0, 0.28) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_juice_tween.chain().tween_callback(queue_redraw)

	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "_juice_flash_alpha", 0.0, qte_perfect_flash_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.chain().tween_callback(func(): _is_qte_completion_flash_active = false)


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

	# ── Trauma shake calculation ──
	if enable_shake and _shake_trauma > 0.0:
		_shake_trauma = maxf(0.0, _shake_trauma - delta * 4.5)
		var intensity := qte_fail_shake_intensity if qte_fail_shake_intensity > 0.0 else 7.5
		var amt := _shake_trauma * _shake_trauma * intensity
		_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amt
		queue_redraw()
	else:
		if _shake_offset != Vector2.ZERO:
			_shake_offset = Vector2.ZERO
			queue_redraw()

	if Engine.is_editor_hint():
		_display_value = target
		queue_redraw()
		return

	_display_value = lerpf(_display_value, target, delta * smooth_speed)
	queue_redraw()


## Builds a rounded polygon from a 4-point convex quad (TL, TR, BR, BL in clockwise order).
## Rounds corners using tangent circular arcs clamped so adjacent corners never overlap.
func _build_rounded_quad(pts: PackedVector2Array, r_tl: float, r_tr: float, r_br: float, r_bl: float, detail: int) -> PackedVector2Array:
	var radii := [r_tl, r_tr, r_br, r_bl]
	var max_r := maxf(maxf(r_tl, r_tr), maxf(r_br, r_bl))
	if max_r <= 0.001 or pts.size() != 4:
		return pts

	var result := PackedVector2Array()
	var n := 4
	for i in range(n):
		var vi := pts[i]
		var r: float = radii[i]
		if r <= 0.001:
			result.append(vi)
			continue

		var v_prev := pts[(i + n - 1) % n]
		var v_next := pts[(i + 1) % n]

		var e1 := v_prev - vi
		var e2 := v_next - vi
		var l1 := e1.length()
		var l2 := e2.length()
		if l1 < 0.001 or l2 < 0.001:
			result.append(vi)
			continue

		var u1 := e1 / l1
		var u2 := e2 / l2

		var dot_val := clampf(u1.dot(u2), -1.0, 1.0)
		var theta := acos(dot_val)
		if theta < 0.01 or theta > 3.13:
			result.append(vi)
			continue

		var half_theta := theta * 0.5
		var tan_half := tan(half_theta)
		var sin_half := sin(half_theta)
		if tan_half < 0.0001 or sin_half < 0.0001:
			result.append(vi)
			continue

		var d := r / tan_half
		var d_max := minf(l1 * 0.48, l2 * 0.48)
		if d > d_max:
			d = d_max
		var r_eff := d * tan_half

		var t1 := vi + u1 * d
		var t2 := vi + u2 * d

		var b := u1 + u2
		var lb := b.length()
		if lb < 0.0001:
			result.append(vi)
			continue
		var b_hat := b / lb
		var center := vi + b_hat * (r_eff / sin_half)

		var ang1 := atan2((t1 - center).y, (t1 - center).x)
		var ang2 := atan2((t2 - center).y, (t2 - center).x)

		var diff := ang2 - ang1
		while diff < 0.0:
			diff += TAU
		while diff > TAU:
			diff -= TAU

		if diff > PI:
			diff -= TAU

		var num_steps := maxi(1, detail)
		for s in range(num_steps + 1):
			var t := float(s) / float(num_steps)
			var a := ang1 + diff * t
			var arc_pt := center + Vector2(cos(a), sin(a)) * r_eff
			if result.size() == 0 or result[result.size() - 1].distance_squared_to(arc_pt) > 0.01:
				result.append(arc_pt)

	return result


## Draws a slice polygon clipped against a rounded boundary polygon using Geometry2D.
func _draw_clipped_polygon(clip_target: PackedVector2Array, slice_quad: PackedVector2Array, color: Color) -> void:
	if slice_quad.size() < 3:
		return
	if clip_target.size() <= 4:
		draw_colored_polygon(slice_quad, color)
		return
	var polys := Geometry2D.intersect_polygons(clip_target, slice_quad)
	for poly in polys:
		draw_colored_polygon(poly, color)


## Draws the bar / gauge drop shadow before backgrounds, fills, and borders.
func _draw_bar_shadow(bg_pts: PackedVector2Array, tl_x: float, bl_x: float, r_top_x: float, r_bot_x: float, h: float, eff_tl: float, eff_tr: float, eff_br: float, eff_bl: float) -> void:
	var base_off := bar_shadow_offset if bar_shadow_offset != null else Vector2.ZERO
	if segmented_mode:
		var num_slots := maxi(1, int(round(100.0 / segment_pct)))
		var half_gap := segment_gap * 0.5
		var seg_r := segment_corner_radius if segment_corner_radius >= 0.0 else corner_radius

		for i in range(num_slots):
			var t_0 := float(i) / float(num_slots)
			var t_1 := float(i + 1) / float(num_slots)

			var slot_tl_x := lerpf(tl_x, r_top_x, t_0) + (half_gap if i > 0 else 0.0)
			var slot_tr_x := lerpf(tl_x, r_top_x, t_1) - (half_gap if i < num_slots - 1 else 0.0)
			var slot_bl_x := lerpf(bl_x, r_bot_x, t_0) + (half_gap if i > 0 else 0.0)
			var slot_br_x := lerpf(bl_x, r_bot_x, t_1) - (half_gap if i < num_slots - 1 else 0.0)

			var slot_base_pts := PackedVector2Array([
				Vector2(slot_tl_x, 0.0), Vector2(slot_tr_x, 0.0),
				Vector2(slot_br_x, h),   Vector2(slot_bl_x, h),
			])

			var s_tl := 0.0
			var s_tr := 0.0
			var s_br := 0.0
			var s_bl := 0.0
			match segment_rounding_mode:
				"All Segments":
					s_tl = seg_r
					s_tr = seg_r
					s_br = seg_r
					s_bl = seg_r
				"Outer Only":
					if i == 0:
						s_tl = eff_tl
						s_bl = eff_bl
					if i == num_slots - 1:
						s_tr = eff_tr
						s_br = eff_br
				"None":
					pass

			var slot_pts := _build_rounded_quad(slot_base_pts, s_tl, s_tr, s_br, s_bl, corner_detail)
			_draw_polygon_shadow(slot_pts, base_off)
	else:
		_draw_polygon_shadow(bg_pts, base_off)


func _draw_polygon_shadow(poly_pts: PackedVector2Array, base_off: Vector2) -> void:
	if poly_pts.size() < 3:
		return

	var target_poly := poly_pts
	if absf(bar_shadow_spread) > 0.01:
		var offset_polys := Geometry2D.offset_polygon(poly_pts, bar_shadow_spread, Geometry2D.JOIN_ROUND)
		if offset_polys.size() > 0:
			target_poly = offset_polys[0]

	if bar_shadow_blur <= 0:
		var shadow_poly := PackedVector2Array()
		for pt in target_poly:
			shadow_poly.append(pt + base_off)
		draw_colored_polygon(shadow_poly, bar_shadow_color)
	else:
		var samples := [
			Vector2(0, 0),
			Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
		]
		var step_dist := float(bar_shadow_blur) * 1.0
		var sample_alpha := bar_shadow_color.a / float(samples.size() * 0.5 + 0.5)
		var pass_col := Color(bar_shadow_color.r, bar_shadow_color.g, bar_shadow_color.b, clampf(sample_alpha, 0.0, 1.0))
		for s_idx in range(samples.size()):
			var smp: Vector2 = samples[s_idx]
			var off := base_off + smp * step_dist
			var shadow_poly := PackedVector2Array()
			for pt in target_poly:
				shadow_poly.append(pt + off)
			draw_colored_polygon(shadow_poly, pass_col)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var tp := h * taper_ratio
	var val := current_value if Engine.is_editor_hint() else _display_value
	var ratio := clampf(val / maxf(max_value, 0.001), 0.0, 1.0) if max_value > 0.0 else 0.0
	var target_val := current_value
	var gain_ratio := clampf(target_val / maxf(max_value, 0.001), 0.0, 1.0) if max_value > 0.0 else 0.0

	var show_lost_chunk := enable_lost_chunk and (_lost_chunk_value > val + 0.001)
	var chunk_ratio := clampf(_lost_chunk_value / maxf(max_value, 0.001), 0.0, 1.0) if max_value > 0.0 else 0.0

	var show_gain_chunk := enable_gain_chunk and (target_val > val + 0.001)

	var edge_kick := _juice_edge_kick if enable_juice else 0.0
	var qte_ext := (reload_qte_bar_offset if reload_qte_bar_offset != null else 0.0) * _label_qte_blend

	var tl_x: float
	var bl_x: float
	var r_top_x: float = w
	var r_bot_x: float = w

	if fill_from_right:
		# Pinned strictly at right (w), left edge is tapered and receives juice kick + persistent QTE extension
		tl_x = (0.0 if flip_vertical else tp) + edge_kick + qte_ext
		bl_x = (tp if flip_vertical else 0.0) + edge_kick + qte_ext
		r_top_x = w
		r_bot_x = w
	else:
		# Pinned strictly at left (0), right edge receives juice kick + persistent QTE extension
		tl_x = 0.0 if flip_vertical else tp
		bl_x = tp if flip_vertical else 0.0
		r_top_x = w + edge_kick - qte_ext
		r_bot_x = w + edge_kick - qte_ext

	# ── Transform matrix calculation (Shake + Vertical juice) ──
	var sy := _juice_scale_y if enable_juice else 1.0
	var has_v_scale := absf(sy - 1.0) > 0.001
	var has_shake := _shake_offset.length_squared() > 0.0001
	var bar_xform := Transform2D.IDENTITY

	if has_shake:
		bar_xform = Transform2D(0.0, _shake_offset)

	if has_v_scale:
		var pivot_y: float = h * 0.5
		var dir := _active_v_direction if _active_v_direction != "" else (qte_hit_v_direction if _is_reload_qte_active else shot_kick_v_direction)
		match dir:
			"Upward":
				pivot_y = h
			"Downward":
				pivot_y = 0.0
			_:
				pivot_y = h * 0.5
		var v_scale_xform := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, sy), Vector2(0.0, pivot_y * (1.0 - sy)))
		bar_xform = bar_xform * v_scale_xform

	if has_shake or has_v_scale:
		draw_set_transform_matrix(bar_xform)

	# ── Background and Fill Rendering ──
	var base_bg_pts := PackedVector2Array([
		Vector2(tl_x, 0.0),    Vector2(r_top_x, 0.0),
		Vector2(r_bot_x, h),   Vector2(bl_x, h),
	])

	var eff_tl := corner_radius_top_left if corner_radius_top_left >= 0.0 else corner_radius
	var eff_tr := corner_radius_top_right if corner_radius_top_right >= 0.0 else corner_radius
	var eff_br := corner_radius_bottom_right if corner_radius_bottom_right >= 0.0 else corner_radius
	var eff_bl := corner_radius_bottom_left if corner_radius_bottom_left >= 0.0 else corner_radius

	var bg_pts := _build_rounded_quad(base_bg_pts, eff_tl, eff_tr, eff_br, eff_bl, corner_detail)

	# ── Bar Drop Shadow Rendering ──
	if bar_shadow_enabled and bar_shadow_color.a > 0.001:
		_draw_bar_shadow(bg_pts, tl_x, bl_x, r_top_x, r_bot_x, h, eff_tl, eff_tr, eff_br, eff_bl)

	if segmented_mode:
		var num_slots := maxi(1, int(round(100.0 / segment_pct)))
		var half_gap := segment_gap * 0.5
		var flash_col := _juice_flash_color if _juice_flash_color != null else Color.WHITE
		var flash_active := (_juice_flash_alpha > 0.001)
		var seg_r := segment_corner_radius if segment_corner_radius >= 0.0 else corner_radius

		for i in range(num_slots):
			var t_0 := float(i) / float(num_slots)
			var t_1 := float(i + 1) / float(num_slots)

			var slot_tl_x := lerpf(tl_x, r_top_x, t_0) + (half_gap if i > 0 else 0.0)
			var slot_tr_x := lerpf(tl_x, r_top_x, t_1) - (half_gap if i < num_slots - 1 else 0.0)
			var slot_bl_x := lerpf(bl_x, r_bot_x, t_0) + (half_gap if i > 0 else 0.0)
			var slot_br_x := lerpf(bl_x, r_bot_x, t_1) - (half_gap if i < num_slots - 1 else 0.0)

			var slot_base_pts := PackedVector2Array([
				Vector2(slot_tl_x, 0.0), Vector2(slot_tr_x, 0.0),
				Vector2(slot_br_x, h),   Vector2(slot_bl_x, h),
			])

			var s_tl := 0.0
			var s_tr := 0.0
			var s_br := 0.0
			var s_bl := 0.0
			match segment_rounding_mode:
				"All Segments":
					s_tl = seg_r
					s_tr = seg_r
					s_br = seg_r
					s_bl = seg_r
				"Outer Only":
					if i == 0:
						s_tl = eff_tl
						s_bl = eff_bl
					if i == num_slots - 1:
						s_tr = eff_tr
						s_br = eff_br
				"None":
					pass

			var slot_pts := _build_rounded_quad(slot_base_pts, s_tl, s_tr, s_br, s_bl, corner_detail)

			# 1. Empty slot background
			if draw_empty_slots:
				var empty_col := slot_empty_color if slot_empty_color != null else bg_color
				draw_colored_polygon(slot_pts, empty_col)

			# 2. Slot range
			var s_min: float
			var s_max: float
			if fill_from_right:
				var k := num_slots - 1 - i
				s_min = float(k) / float(num_slots)
				s_max = float(k + 1) / float(num_slots)
			else:
				s_min = float(i) / float(num_slots)
				s_max = float(i + 1) / float(num_slots)

			# 3. Lost chunk layer per slot (Damage/consumption)
			if show_lost_chunk:
				var f_chunk := clampf((chunk_ratio - s_min) / maxf(s_max - s_min, 0.0001), 0.0, 1.0)
				if f_chunk >= 0.999:
					draw_colored_polygon(slot_pts, lost_chunk_color)
				elif f_chunk > 0.001:
					var chunk_part_pts: PackedVector2Array
					if fill_from_right:
						var c_fill_tl := lerpf(slot_tr_x, slot_tl_x, f_chunk)
						var c_fill_bl := lerpf(slot_br_x, slot_bl_x, f_chunk)
						chunk_part_pts = PackedVector2Array([
							Vector2(c_fill_tl, 0.0), Vector2(slot_tr_x, 0.0),
							Vector2(slot_br_x, h),   Vector2(c_fill_bl, h),
						])
					else:
						var c_fill_tr := lerpf(slot_tl_x, slot_tr_x, f_chunk)
						var c_fill_br := lerpf(slot_bl_x, slot_br_x, f_chunk)
						chunk_part_pts = PackedVector2Array([
							Vector2(slot_tl_x, 0.0), Vector2(c_fill_tr, 0.0),
							Vector2(c_fill_br, h),   Vector2(slot_bl_x, h),
						])
					_draw_clipped_polygon(slot_pts, chunk_part_pts, lost_chunk_color)

			# 4. Gain chunk layer per slot (Refill/pump)
			if show_gain_chunk:
				var f_gain := clampf((gain_ratio - s_min) / maxf(s_max - s_min, 0.0001), 0.0, 1.0)
				if f_gain >= 0.999:
					draw_colored_polygon(slot_pts, gain_chunk_color)
				elif f_gain > 0.001:
					var gain_part_pts: PackedVector2Array
					if fill_from_right:
						var g_fill_tl := lerpf(slot_tr_x, slot_tl_x, f_gain)
						var g_fill_bl := lerpf(slot_br_x, slot_bl_x, f_gain)
						gain_part_pts = PackedVector2Array([
							Vector2(g_fill_tl, 0.0), Vector2(slot_tr_x, 0.0),
							Vector2(slot_br_x, h),   Vector2(g_fill_bl, h),
						])
					else:
						var g_fill_tr := lerpf(slot_tl_x, slot_tr_x, f_gain)
						var g_fill_br := lerpf(slot_bl_x, slot_br_x, f_gain)
						gain_part_pts = PackedVector2Array([
							Vector2(slot_tl_x, 0.0), Vector2(g_fill_tr, 0.0),
							Vector2(g_fill_br, h),   Vector2(slot_bl_x, h),
						])
					_draw_clipped_polygon(slot_pts, gain_part_pts, gain_chunk_color)

			# 5. Fill calculation per slot
			var f := clampf((ratio - s_min) / maxf(s_max - s_min, 0.0001), 0.0, 1.0)
			if f >= 0.999:
				draw_colored_polygon(slot_pts, fill_color)
				if flash_active:
					draw_colored_polygon(slot_pts, Color(flash_col.r, flash_col.g, flash_col.b, flash_col.a * _juice_flash_alpha))
			elif f > 0.001:
				var part_pts: PackedVector2Array
				if fill_from_right:
					var fill_tl := lerpf(slot_tr_x, slot_tl_x, f)
					var fill_bl := lerpf(slot_br_x, slot_bl_x, f)
					part_pts = PackedVector2Array([
						Vector2(fill_tl, 0.0), Vector2(slot_tr_x, 0.0),
						Vector2(slot_br_x, h),  Vector2(fill_bl, h),
					])
				else:
					var fill_tr := lerpf(slot_tl_x, slot_tr_x, f)
					var fill_br := lerpf(slot_bl_x, slot_br_x, f)
					part_pts = PackedVector2Array([
						Vector2(slot_tl_x, 0.0), Vector2(fill_tr, 0.0),
						Vector2(fill_br, h),     Vector2(slot_bl_x, h),
					])
				_draw_clipped_polygon(slot_pts, part_pts, fill_color)
				if flash_active:
					_draw_clipped_polygon(slot_pts, part_pts, Color(flash_col.r, flash_col.g, flash_col.b, flash_col.a * _juice_flash_alpha))

			# 6. Optional slot individual border
			if slot_border_thickness > 0.0:
				if slot_pts.size() > 4:
					var closed_slot := slot_pts.duplicate()
					closed_slot.append(slot_pts[0])
					draw_polyline(closed_slot, slot_border_color, slot_border_thickness, true)
				else:
					for j in range(4):
						draw_line(slot_pts[j], slot_pts[(j + 1) % 4], slot_border_color, slot_border_thickness, true)
	else:
		# Continuous mode
		draw_colored_polygon(bg_pts, bg_color)

		# Lost chunk layer (Damage / consumption)
		if show_lost_chunk and chunk_ratio > 0.001:
			var chunk_pts := PackedVector2Array()
			if fill_from_right:
				var t_start_chunk := 1.0 - chunk_ratio
				chunk_pts = PackedVector2Array([
					Vector2(lerpf(tl_x, r_top_x, t_start_chunk), 0.0),
					Vector2(r_top_x, 0.0),
					Vector2(r_bot_x, h),
					Vector2(lerpf(bl_x, r_bot_x, t_start_chunk), h),
				])
			else:
				chunk_pts = PackedVector2Array([
					Vector2(tl_x, 0.0),
					Vector2(lerpf(tl_x, r_top_x, chunk_ratio), 0.0),
					Vector2(lerpf(bl_x, r_bot_x, chunk_ratio), h),
					Vector2(bl_x, h),
				])
			_draw_clipped_polygon(bg_pts, chunk_pts, lost_chunk_color)

		# Gain chunk layer (Refill / pump)
		if show_gain_chunk and gain_ratio > 0.001:
			var gain_pts := PackedVector2Array()
			if fill_from_right:
				var t_start_gain := 1.0 - gain_ratio
				gain_pts = PackedVector2Array([
					Vector2(lerpf(tl_x, r_top_x, t_start_gain), 0.0),
					Vector2(r_top_x, 0.0),
					Vector2(r_bot_x, h),
					Vector2(lerpf(bl_x, r_bot_x, t_start_gain), h),
				])
			else:
				gain_pts = PackedVector2Array([
					Vector2(tl_x, 0.0),
					Vector2(lerpf(tl_x, r_top_x, gain_ratio), 0.0),
					Vector2(lerpf(bl_x, r_bot_x, gain_ratio), h),
					Vector2(bl_x, h),
				])
			_draw_clipped_polygon(bg_pts, gain_pts, gain_chunk_color)

		# Active fill layer
		var fill_pts := PackedVector2Array()
		if ratio > 0.001:
			if ratio >= 0.999:
				draw_colored_polygon(bg_pts, fill_color)
			else:
				if fill_from_right:
					var t_start := 1.0 - ratio
					fill_pts = PackedVector2Array([
						Vector2(lerpf(tl_x, r_top_x, t_start), 0.0),
						Vector2(r_top_x, 0.0),
						Vector2(r_bot_x, h),
						Vector2(lerpf(bl_x, r_bot_x, t_start), h),
					])
				else:
					fill_pts = PackedVector2Array([
						Vector2(tl_x, 0.0),
						Vector2(lerpf(tl_x, r_top_x, ratio), 0.0),
						Vector2(lerpf(bl_x, r_bot_x, ratio), h),
						Vector2(bl_x, h),
					])
				_draw_clipped_polygon(bg_pts, fill_pts, fill_color)

		# Flash highlight overlay
		if _juice_flash_alpha > 0.001 and ratio > 0.001:
			var flash_col := _juice_flash_color if _juice_flash_color != null else Color.WHITE
			flash_col.a *= _juice_flash_alpha
			if ratio >= 0.999:
				draw_colored_polygon(bg_pts, flash_col)
			elif fill_pts.size() > 0:
				_draw_clipped_polygon(bg_pts, fill_pts, flash_col)

	# ── Border lines ──
	if border_thickness > 0.0:
		var aa := border_thickness >= 1.0
		var border_col := border_color
		if _juice_flash_alpha > 0.001:
			var flash_col := _juice_flash_color if _juice_flash_color != null else Color.WHITE
			border_col = border_col.lerp(flash_col, _juice_flash_alpha * 0.7)
		if bg_pts.size() > 4:
			var closed_pts := bg_pts.duplicate()
			closed_pts.append(bg_pts[0])
			draw_polyline(closed_pts, border_col, border_thickness, aa)
		else:
			for i in range(bg_pts.size()):
				var from_pt := bg_pts[i]
				var to_pt := bg_pts[(i + 1) % bg_pts.size()]
				draw_line(from_pt, to_pt, border_col, border_thickness, aa)

	# ── Label text ──
	if label_text == "":
		if has_shake or has_v_scale:
			draw_set_transform_matrix(Transform2D.IDENTITY)
		return

	var active_font := label_font
	if active_font == null:
		active_font = ThemeDB.fallback_font

	if active_font != null:
		var base_off: Vector2 = label_offset if label_offset != null else Vector2.ZERO
		var qte_off: Vector2 = (reload_qte_label_offset if reload_qte_label_offset != null else Vector2.ZERO) * _label_qte_blend
		var off: Vector2 = base_off + qte_off
		var rot_deg: float = label_rotation_degrees if label_rotation_degrees != null else 0.0
		var flip_h: bool = label_flip_h if label_flip_h != null else false
		var flip_v: bool = label_flip_v if label_flip_v != null else false

		var effective_scale: float = lerpf(1.0, reload_qte_label_scale, _label_qte_blend)
		var effective_font_size: int = maxi(1, int(round(float(label_font_size) * effective_scale)))
		var ts := active_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, effective_font_size)
		var text_center_x: float
		var text_center_y: float
		if reload_qte_disable_label_shift:
			var rest_tl_x := 0.0 if flip_vertical else tp
			var rest_bl_x := tp if flip_vertical else 0.0
			var rest_r_top_x := w
			var rest_r_bot_x := w
			text_center_x = ((rest_tl_x + rest_bl_x) * 0.5 + (rest_r_top_x + rest_r_bot_x) * 0.5) * 0.5 + base_off.x + (edge_kick * 0.5)
			text_center_y = h * 0.5 + base_off.y
		else:
			var label_qte_shift: float = (qte_ext * 0.5) if fill_from_right else (-qte_ext * 0.5)
			text_center_x = ((tl_x + bl_x) * 0.5 + (r_top_x + r_bot_x) * 0.5) * 0.5 + off.x + (edge_kick * 0.5) + label_qte_shift
			text_center_y = h * 0.5 + off.y
		var pivot := Vector2(text_center_x, text_center_y)

		var sx: float = -1.0 if flip_h else 1.0
		var sy_label: float = -1.0 if flip_v else 1.0
		var rot_rad := deg_to_rad(rot_deg)

		# Apply 2D centered transform for rotation and mirroring compounded with bar shake/vertical juice transform
		var label_local_xform := Transform2D().translated(pivot).rotated(rot_rad).scaled(Vector2(sx, sy_label))
		if has_shake or has_v_scale:
			draw_set_transform_matrix(bar_xform * label_local_xform)
		else:
			draw_set_transform_matrix(label_local_xform)

		# Draw centered around the local origin (0, 0)
		var local_text_pos := Vector2(-ts.x * 0.5, ts.y * 0.3)

		# Drop shadow layer
		if label_shadow_enabled and label_shadow_color.a > 0.001:
			var base_shadow_off := (label_shadow_offset if label_shadow_offset != null else Vector2.ZERO) * effective_scale
			var eff_shadow_outline := maxi(0, label_outline_size + label_shadow_outline_size)
			if label_shadow_blur <= 0:
				var shadow_pos := local_text_pos + base_shadow_off
				if eff_shadow_outline > 0:
					draw_string_outline(active_font, shadow_pos, label_text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size,
						eff_shadow_outline, label_shadow_color)
				draw_string(active_font, shadow_pos, label_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size, label_shadow_color)
			else:
				var samples := [
					Vector2(0, 0),
					Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
					Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
				]
				var step_dist := float(label_shadow_blur) * 0.85
				var sample_alpha := label_shadow_color.a / float(samples.size() * 0.5 + 0.5)
				var pass_col := Color(label_shadow_color.r, label_shadow_color.g, label_shadow_color.b, clampf(sample_alpha, 0.0, 1.0))
				for s_idx in range(samples.size()):
					var smp: Vector2 = samples[s_idx]
					var shadow_pos := local_text_pos + base_shadow_off + smp * step_dist
					if eff_shadow_outline > 0:
						draw_string_outline(active_font, shadow_pos, label_text,
							HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size,
							eff_shadow_outline, pass_col)
					draw_string(active_font, shadow_pos, label_text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size, pass_col)

		# Outline then foreground
		if label_outline_size > 0:
			draw_string_outline(active_font, local_text_pos, label_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size,
				label_outline_size, label_outline_color)
		draw_string(active_font, local_text_pos, label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, effective_font_size, label_color)

	# Reset transform matrix
	draw_set_transform_matrix(Transform2D.IDENTITY)
