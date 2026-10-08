@tool
## GrabQteHud: Controls the mouse-shake QTE UI within player_stat_hud.
##
## Usage:
##   var hud = get_tree().get_first_node_in_group("grab_qte_hud") as GrabQteHud
##   hud.escaped.connect(_on_player_escaped)
##   hud.caught.connect(_on_player_caught)
##   hud.start_qte(duration, shakes_needed)
##
## The node manages its own visibility and state without queue_free().
class_name GrabQteHud
extends Control

signal escaped   # player shook free in time
signal caught    # timer ran out or enough failures

# ---- Tunables ----
@export var duration: float        = 2.5   # seconds the player has to escape
@export var shakes_needed: int     = 10    # how many valid shake gestures break the grab (10 = 10% per shake)
@export var shake_threshold: float = 120.0 # px/s mouse speed that counts as a shake

# ---- Visual Customization: Grab Bar (StyleBoxFancy) ----
@export_group("Grab Bar (StyleBoxFancy)")
@export var max_fill_width: float = 280.0:
	set(v):
		max_fill_width = v
		if Engine.is_editor_hint() and is_inside_tree():
			_setup_editor_preview()

@export var bg_style: StyleBox:
	set(v):
		bg_style = v
		_wire_nodes()
		if is_inside_tree() and grab_bg:
			if v:
				grab_bg.add_theme_stylebox_override("panel", v)
			else:
				grab_bg.remove_theme_stylebox_override("panel")

@export var fill_style: StyleBox:
	set(v):
		fill_style = v
		_wire_nodes()
		if is_inside_tree() and grab_fill:
			if v:
				grab_fill.add_theme_stylebox_override("panel", v)
			else:
				grab_fill.remove_theme_stylebox_override("panel")

@export var bar_bg_color_override: Color = Color(0, 0, 0, 0):
	set(v):
		if v == null or bar_bg_color_override == v:
			return
		bar_bg_color_override = v
		_apply_bar_colors()

@export var bar_fill_color_override: Color = Color(0, 0, 0, 0):
	set(v):
		if v == null or bar_fill_color_override == v:
			return
		bar_fill_color_override = v
		_apply_bar_colors()

# ---- Visual Customization: Segmented Fill (10% Per Fill) ----
@export_group("Segmented Fill")
## If true, renders the bar partitioned into distinct segment slots.
@export var segmented_mode: bool = true:
	set(v):
		segmented_mode = v
		if Engine.is_editor_hint() and is_inside_tree():
			_setup_editor_preview()

## Percentage represented by each segment slot (default 10.0% -> 10 segments across the bar).
@export var segment_pct: float = 10.0:
	set(v):
		segment_pct = maxf(1.0, v)
		if Engine.is_editor_hint() and is_inside_tree():
			_setup_editor_preview()

## Pixel thickness of the dividers between segments.
@export var segment_gap: float = 2.0:
	set(v):
		segment_gap = maxf(0.5, v)
		if Engine.is_editor_hint() and is_inside_tree():
			_setup_editor_preview()

## Color for the slanted segment dividers.
@export var segment_divider_color: Color = Color(0.09803922, 0.08627451, 0.45490196, 1.0):
	set(v):
		segment_divider_color = v
		if grab_dividers:
			grab_dividers.queue_redraw()

## If true, fill progression snaps to clean discrete segment blocks (10% increments).
@export var snap_fill_to_segments: bool = true:
	set(v):
		snap_fill_to_segments = v
		if Engine.is_editor_hint() and is_inside_tree():
			_setup_editor_preview()

## Horizontal skew factor matching StyleBoxFancy slant (0.685).
@export var segment_skew: float = 0.685:
	set(v):
		segment_skew = v
		if grab_dividers:
			grab_dividers.queue_redraw()

# ---- Visual Customization: Shake Effect (Air Gauge Style) ----
@export_group("Shake Effect")
## If true, enables mouse-driven trauma vibration shake.
@export var enable_shake: bool = true

## Maximum shake displacement in pixels when shaking vigorously.
@export var shake_intensity: float = 8.0

## Rate at which trauma decays per second (matching air gauge).
@export var shake_decay: float = 4.5

## Click in the inspector to test the trauma shake live in editor.
@export var test_shake: bool = false:
	set(v):
		if v:
			trigger_shake(1.0)

# ---- Visual Customization: Pop Animation ----
@export_group("Pop Animation")
@export var enable_pop_animation: bool = true
@export var pop_in_duration: float = 0.25
@export var pop_out_duration: float = 0.2
@export var pop_in_curve: Curve
@export var pop_out_curve: Curve
@export var preview_trigger_pop_in: bool = false:
	set(v):
		if v and Engine.is_editor_hint() and is_inside_tree():
			play_pop_in()
@export var preview_trigger_pop_out: bool = false:
	set(v):
		if v and Engine.is_editor_hint() and is_inside_tree():
			play_pop_out()

# ---- Visual Customization: Typography & Feedback ----
@export_group("Typography & Feedback")
@export var prompt_text_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(v):
		if v == null or prompt_text_color == v:
			return
		prompt_text_color = v
		if is_inside_tree() and label_prompt:
			label_prompt.add_theme_color_override("font_color", v)

# ---- Visual Customization: Overlay ----
@export_group("Overlay")
@export var overlay_color: Color = Color(0, 0, 0, 0.0):
	set(v):
		if v == null or overlay_color == v:
			return
		overlay_color = v
		if is_inside_tree() and overlay:
			overlay.color = v

# ---- UI Node References (Customizable in Godot Editor) ----
@export_group("UI References")
@export var overlay: ColorRect
@export var root_panel: Control
@export var grab_bg: Panel
@export var grab_fill: Panel
@export var grab_dividers: Control
@export var label_prompt: Label

# ---- Internals ----
var _time_left: float        = 0.0
var _shake_count: int        = 0
var _last_mouse_vel: Vector2 = Vector2.ZERO
var _resolved: bool          = false
var _fill_tween: Tween       = null
var _pop_tween: Tween        = null

# Internal trauma shake tracking (Air Gauge physics)
var _shake_trauma: float     = 0.0
var _shake_offset: Vector2   = Vector2.ZERO
var _prev_shake_offset: Vector2 = Vector2.ZERO

func _init(p_duration: float = 2.5, p_shakes: int = 10) -> void:
	duration      = p_duration
	shakes_needed = p_shakes

func _ready() -> void:
	add_to_group("qte_hud")
	add_to_group("grab_qte_hud")
	_apply_visual_settings()
	if Engine.is_editor_hint():
		_setup_editor_preview()
		return
	visible = false
	set_process(false)

func _setup_editor_preview() -> void:
	_wire_nodes()
	_apply_visual_settings()
	_ensure_fill_setup()
	_reset_shake_offset()
	_set_pop_scale_x(1.0)
	visible = true
	if overlay:
		overlay.visible = true
	if root_panel:
		root_panel.modulate = Color.WHITE
		root_panel.visible = true
	if grab_bg:
		grab_bg.visible = true
	if grab_fill:
		grab_fill.visible = true
		var preview_pct: float = 0.60 if (segmented_mode and snap_fill_to_segments) else 0.65
		grab_fill.size.x = max_fill_width * preview_pct
	if grab_dividers:
		grab_dividers.visible = segmented_mode
		grab_dividers.queue_redraw()
	if label_prompt:
		label_prompt.visible = true
		label_prompt.text = "SHAKE MOUSE TO BREAK FREE"

func _wire_nodes() -> void:
	if not overlay:
		overlay = get_node_or_null("DimOverlay") as ColorRect
	if not root_panel:
		root_panel = get_node_or_null("GrabPanel") as Control
	if root_panel:
		if not grab_bg:
			grab_bg = root_panel.get_node_or_null("GrabBG") as Panel
		if grab_bg and not grab_fill:
			grab_fill = grab_bg.get_node_or_null("GrabFill") as Panel
		if not grab_fill:
			grab_fill = root_panel.get_node_or_null("GrabFill") as Panel
		if not grab_dividers:
			grab_dividers = root_panel.get_node_or_null("GrabDividers") as Control
		if not grab_dividers:
			grab_dividers = Control.new()
			grab_dividers.name = "GrabDividers"
			grab_dividers.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root_panel.add_child(grab_dividers)
		if not label_prompt:
			label_prompt = root_panel.get_node_or_null("PromptLabel") as Label

func _ensure_fill_setup() -> void:
	if not grab_fill:
		return
	grab_fill.scale.y = 1.0
	grab_fill.grow_horizontal = Control.GROW_DIRECTION_END
	grab_fill.custom_minimum_size.x = 0.0
	if grab_bg:
		grab_bg.scale.y = 1.0
		var h = grab_bg.size.y
		if h > 0.0:
			grab_fill.size.y = h
		if grab_fill.get_parent() == grab_bg.get_parent():
			grab_fill.offset_left = grab_bg.offset_left
			grab_fill.offset_top = grab_bg.offset_top
			grab_fill.offset_bottom = grab_bg.offset_bottom

		# Ensure pivots are centered on the bar for symmetrical pop-in/pop-out scaling
		var center_pivot = Vector2(max_fill_width * 0.5, h * 0.5)
		grab_bg.pivot_offset = center_pivot
		grab_fill.pivot_offset = center_pivot

		# Ensure grab dividers overlay matches grab_bg position, size, and pivot
		if grab_dividers:
			grab_dividers.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grab_dividers.position = grab_bg.position
			grab_dividers.size = Vector2(max_fill_width, h)
			grab_dividers.pivot_offset = center_pivot
			if not grab_dividers.draw.is_connected(_draw_dividers):
				grab_dividers.draw.connect(_draw_dividers)
			if root_panel and grab_dividers.get_parent() == root_panel:
				root_panel.move_child(grab_dividers, -1)
			grab_dividers.visible = segmented_mode
			grab_dividers.queue_redraw()

# ---------- Segmented Dividers Drawing ----------

func _draw_dividers() -> void:
	if not segmented_mode or not grab_dividers:
		return
	var num_slots := maxi(1, int(round(100.0 / segment_pct)))
	if num_slots <= 1:
		return
	var w := max_fill_width
	var h := grab_bg.size.y if grab_bg else 14.0
	for i in range(1, num_slots):
		var frac := float(i) / float(num_slots)
		var cx := frac * w
		# Slanted divider matching StyleBoxFancy skew angle:
		# Top is at cx + segment_skew * h * 0.5
		# Bottom is at cx - segment_skew * h * 0.5
		var p_top := Vector2(cx + segment_skew * h * 0.5, 0.0)
		var p_bot := Vector2(cx - segment_skew * h * 0.5, h)
		grab_dividers.draw_line(p_bot, p_top, segment_divider_color, segment_gap)

# ---------- Pop Animation (Curve / Fallbacks) ----------

func _sample_pop_curve(curve_res: Curve, t: float, is_pop_in: bool) -> float:
	if curve_res:
		return curve_res.sample_baked(clampf(t, 0.0, 1.0))

	# Built-in fallback curves if no custom curve is assigned:
	if is_pop_in:
		# Spring / back-out overshoot curve (overshoots slightly up to ~1.08, then settles at 1.0)
		var s: float = 1.70158
		var x: float = clampf(t, 0.0, 1.0) - 1.0
		return 1.0 + (s + 1.0) * pow(x, 3.0) + s * pow(x, 2.0)
	else:
		# Smooth quadratic ease-in collapse (1.0 down to 0.0)
		var x: float = clampf(t, 0.0, 1.0)
		return 1.0 - (x * x)

func _set_pop_scale_x(scale_val: float) -> void:
	if grab_bg:
		grab_bg.scale.x = scale_val
	if grab_fill:
		grab_fill.scale.x = scale_val
	if grab_dividers:
		grab_dividers.scale.x = scale_val

func play_pop_in() -> void:
	_wire_nodes()
	_ensure_fill_setup()
	if not enable_pop_animation:
		_set_pop_scale_x(1.0)
		return

	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()

	var start_s = _sample_pop_curve(pop_in_curve, 0.0, true)
	_set_pop_scale_x(start_s)

	_pop_tween = create_tween()
	_pop_tween.tween_method(
		func(t: float):
			var s = _sample_pop_curve(pop_in_curve, t, true)
			_set_pop_scale_x(s),
		0.0,
		1.0,
		pop_in_duration
	)

func play_pop_out() -> void:
	if not enable_pop_animation:
		_set_pop_scale_x(0.0)
		return

	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()

	_pop_tween = create_tween()
	_pop_tween.tween_method(
		func(t: float):
			var s = _sample_pop_curve(pop_out_curve, t, false)
			_set_pop_scale_x(s),
		0.0,
		1.0,
		pop_out_duration
	)
	await _pop_tween.finished

# ---------- Trauma Shake (Air Gauge Physics) ----------

func trigger_shake(amount: float = 1.0) -> void:
	if not enable_shake:
		return
	_shake_trauma = clampf(_shake_trauma + amount, 0.0, 1.0)

func _reset_shake_offset() -> void:
	if root_panel and _prev_shake_offset != Vector2.ZERO:
		root_panel.position -= _prev_shake_offset
		_prev_shake_offset = Vector2.ZERO
	_shake_offset = Vector2.ZERO
	_shake_trauma = 0.0

# ---------- Visual Styling ----------

func _apply_bar_colors() -> void:
	if not is_inside_tree():
		return
	if grab_bg and bar_bg_color_override.a > 0.0:
		var s = grab_bg.get_theme_stylebox("panel")
		if s and "color" in s:
			s.color = bar_bg_color_override
	if grab_fill and bar_fill_color_override.a > 0.0:
		var s = grab_fill.get_theme_stylebox("panel")
		if s and "color" in s:
			s.color = bar_fill_color_override

func _apply_visual_settings() -> void:
	_wire_nodes()
	_ensure_fill_setup()
	if overlay:
		overlay.color = overlay_color
	if grab_bg and bg_style:
		grab_bg.add_theme_stylebox_override("panel", bg_style)
	if grab_fill and fill_style:
		grab_fill.add_theme_stylebox_override("panel", fill_style)
	_apply_bar_colors()
	if grab_dividers:
		grab_dividers.queue_redraw()
	if label_prompt:
		label_prompt.add_theme_color_override("font_color", prompt_text_color)

# ---------- Activation & Lifecycle ----------

func start_qte(p_duration: float = 2.5, p_shakes: int = 10) -> void:
	duration      = p_duration
	shakes_needed = p_shakes
	_time_left    = duration
	_shake_count  = 0
	_last_mouse_vel = Vector2.ZERO
	_resolved     = false

	_wire_nodes()
	_apply_visual_settings()
	_ensure_fill_setup()
	_reset_shake_offset()

	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()

	if grab_fill:
		grab_fill.size.x = 0.0
		grab_fill.visible = true

	if grab_bg:
		grab_bg.visible = true

	if grab_dividers:
		grab_dividers.visible = segmented_mode
		grab_dividers.queue_redraw()

	var lang = "en"
	if get_tree() and get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	if label_prompt:
		label_prompt.text = "สลัดเมาส์เพื่อหลุดพ้น!" if lang == "th" else "SHAKE MOUSE TO BREAK FREE"
		label_prompt.visible = true

	var should_show := true
	if get_tree() and get_tree().root.has_node("GameManager"):
		should_show = GameManager.show_grab_qte and GameManager.show_gameplay_ui
	visible = should_show
	set_process(true)

	play_pop_in()

func cancel() -> void:
	_resolved = true
	set_process(false)
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()
	_reset_shake_offset()
	_set_pop_scale_x(1.0)
	visible = false

# ---------- Per-frame logic ----------

func _process(delta: float) -> void:
	if _resolved:
		return

	# --- Mouse shake detection & continuous velocity trauma ---
	var mouse_vel: Vector2 = Input.get_last_mouse_velocity()
	var speed: float       = mouse_vel.length()
	var dir_changed: bool  = _last_mouse_vel.length() > 10.0 and \
		mouse_vel.normalized().dot(_last_mouse_vel.normalized()) < -0.3

	# Mouse movement continuously feeds trauma
	if enable_shake and speed > 15.0:
		var speed_trauma = clampf(speed / (shake_threshold * 1.5), 0.0, 1.0)
		_shake_trauma = maxf(_shake_trauma, speed_trauma)

	# Valid shake gesture flip
	if speed > shake_threshold and dir_changed:
		_shake_count += 1
		_last_mouse_vel = mouse_vel
		if enable_shake:
			_shake_trauma = 1.0 # Peak trauma pulse on valid shake
		_update_fill()
		if _shake_count >= shakes_needed:
			_resolve(true)
			return
	elif speed > shake_threshold * 0.4:
		_last_mouse_vel = mouse_vel

	# --- Air Gauge Trauma Shake calculation ---
	if enable_shake and _shake_trauma > 0.0:
		_shake_trauma = maxf(0.0, _shake_trauma - delta * shake_decay)
		var intensity := shake_intensity if shake_intensity > 0.0 else 8.0
		var amt := _shake_trauma * _shake_trauma * intensity
		_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amt
	else:
		_shake_offset = Vector2.ZERO

	# Apply zero-drift relative displacement to root_panel
	if root_panel:
		root_panel.position = root_panel.position - _prev_shake_offset + _shake_offset
		_prev_shake_offset = _shake_offset

	# --- Timer (silent countdown, no bar visualization) ---
	_time_left -= delta
	if _time_left <= 0.0:
		_resolve(false)

func _update_fill() -> void:
	if not grab_fill:
		return
	_ensure_fill_setup()
	var progress: float = clampf(float(_shake_count) / float(shakes_needed), 0.0, 1.0)
	var target_progress: float = progress
	if segmented_mode and snap_fill_to_segments:
		var num_slots := maxi(1, int(round(100.0 / segment_pct)))
		target_progress = ceilf(progress * float(num_slots) - 0.0001) / float(num_slots) if progress > 0.0 else 0.0
	var target_width: float = target_progress * max_fill_width
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = create_tween()
	_fill_tween.tween_property(grab_fill, "size:x", target_width, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ---------- Resolution ----------

func _resolve(player_escaped: bool) -> void:
	if _resolved:
		return
	_resolved = true
	set_process(false)

	if label_prompt:
		label_prompt.visible = false

	_reset_shake_offset()

	if player_escaped:
		escaped.emit()
		# When GrabFill reaches 100%, start pop out immediately!
		if _fill_tween and _fill_tween.is_valid():
			await _fill_tween.finished
		elif grab_fill:
			grab_fill.size.x = max_fill_width
		await play_pop_out()
	else:
		caught.emit()
		await play_pop_out()

	visible = false
	_set_pop_scale_x(1.0)
