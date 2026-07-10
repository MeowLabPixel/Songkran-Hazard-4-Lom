## GrabQteHud: self-contained CanvasLayer that drives the mouse-shake QTE.
##
## Usage:
##   var hud = GrabQteHud.new(duration, shakes_needed)
##   hud.escaped.connect(_on_player_escaped)
##   hud.caught.connect(_on_player_caught)
##   get_tree().root.add_child(hud)
##
## The node removes itself when the QTE resolves.
class_name GrabQteHud
extends CanvasLayer

signal escaped   # player shook free in time
signal caught    # timer ran out or enough failures

# ---- tunables (set before add_child) ----
var duration: float        = 2.5   # seconds the player has to escape
var shakes_needed: int     = 5     # how many valid shake gestures break the grab
var shake_threshold: float = 120.0 # px/s mouse speed that counts as a shake

# ---- internals ----
var _time_left: float   = 0.0
var _shake_count: int   = 0
var _last_mouse_vel: Vector2 = Vector2.ZERO
var _resolved: bool     = false

# --- UI nodes (built in _ready, no scene file needed) ---
var _root_panel:   Control     = null
var _bar_bg:       ColorRect   = null
var _bar_fill:     ColorRect   = null
var _shake_dots:   HBoxContainer = null
var _label_prompt: Label       = null
var _label_result: Label       = null

func _init(p_duration: float = 2.5, p_shakes: int = 5) -> void:
	duration      = p_duration
	shakes_needed = p_shakes
	layer         = 128  # render on top of game world

func _ready() -> void:
	_time_left = duration
	_build_ui()

# ---------- UI construction ----------

func _build_ui() -> void:
	# Full-screen dim overlay (semi-transparent).
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Centred panel.
	_root_panel = Control.new()
	_root_panel.set_anchors_preset(Control.PRESET_CENTER)
	_root_panel.custom_minimum_size = Vector2(320, 180)
	_root_panel.position = Vector2(-160, -90)
	add_child(_root_panel)

	# Dark card background.
	var card := ColorRect.new()
	card.color = Color(0.08, 0.08, 0.08, 0.9)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_panel.add_child(card)

	# Red border highlight.
	var border := ColorRect.new()
	border.color = Color(0.8, 0.1, 0.1, 0.85)
	border.size = Vector2(320, 4)
	border.position = Vector2(0, 0)
	_root_panel.add_child(border)

	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language
		
	var subheader_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")

	# Prompt label.
	_label_prompt = Label.new()
	_label_prompt.text = "สลัดเมาส์เพื่อหลุดพ้น" if lang == "th" else "SHAKE MOUSE TO BREAK FREE"
	_label_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_prompt.position = Vector2(0, 20)
	_label_prompt.size = Vector2(320, 30)
	_label_prompt.add_theme_font_size_override("font_size", 16)
	_label_prompt.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_label_prompt.add_theme_font_override("font", subheader_font)
	_root_panel.add_child(_label_prompt)

	# Shake-dot indicators (unfilled circles, filled as player shakes).
	_shake_dots = HBoxContainer.new()
	_shake_dots.position = Vector2(0, 68)
	_shake_dots.size = Vector2(320, 32)
	_shake_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_shake_dots.add_theme_constant_override("separation", 10)
	_root_panel.add_child(_shake_dots)
	for i in shakes_needed:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.color = Color(0.25, 0.25, 0.25)
		_shake_dots.add_child(dot)

	# Timer bar background.
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.2, 0.2, 0.2)
	_bar_bg.position = Vector2(20, 116)
	_bar_bg.size = Vector2(280, 14)
	_root_panel.add_child(_bar_bg)

	# Timer bar fill (starts full, drains red).
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.85, 0.15, 0.15)
	_bar_fill.position = Vector2(20, 116)
	_bar_fill.size = Vector2(280, 14)
	_root_panel.add_child(_bar_fill)

	# Result label (hidden until resolved).
	_label_result = Label.new()
	_label_result.text = ""
	_label_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_result.position = Vector2(0, 145)
	_label_result.size = Vector2(320, 28)
	_label_result.add_theme_font_size_override("font_size", 18)
	_label_result.add_theme_font_override("font", subheader_font)
	_label_result.visible = false
	_root_panel.add_child(_label_result)

# ---------- Per-frame logic ----------

func _process(delta: float) -> void:
	if _resolved:
		return

	# --- Mouse shake detection ---
	var mouse_vel: Vector2 = Input.get_last_mouse_velocity()
	var speed: float       = mouse_vel.length()
	# Count a shake when velocity crosses threshold and direction changed enough.
	var dir_changed: bool  = _last_mouse_vel.length() > 10.0 and \
		mouse_vel.normalized().dot(_last_mouse_vel.normalized()) < -0.3
	if speed > shake_threshold and dir_changed:
		_shake_count += 1
		_last_mouse_vel = mouse_vel
		_update_dots()
		_flash_dot(_shake_count - 1)
		if _shake_count >= shakes_needed:
			_resolve(true)
			return
	elif speed > shake_threshold * 0.4:
		_last_mouse_vel = mouse_vel

	# --- Timer ---
	_time_left -= delta
	var frac: float = clampf(_time_left / duration, 0.0, 1.0)
	_bar_fill.size.x = 280.0 * frac
	# Colour shifts from red toward dark as time runs out.
	_bar_fill.color = Color(0.85, 0.15 + frac * 0.35, 0.15)

	if _time_left <= 0.0:
		_resolve(false)

# ---------- Resolution ----------

func _resolve(player_escaped: bool) -> void:
	if _resolved:
		return
	_resolved = true
	_label_prompt.visible = false
	_bar_bg.visible       = false
	_bar_fill.visible     = false
	for dot in _shake_dots.get_children():
		dot.visible = false

	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	if player_escaped:
		_label_result.text = "หลุดพ้นสำเร็จ!" if lang == "th" else "ESCAPED!"
		_label_result.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		escaped.emit()
	else:
		_label_result.text = "โดนจับตัว!" if lang == "th" else "GRABBED!"
		_label_result.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		caught.emit()

	_label_result.visible = true
	# Auto-dismiss after a short pause so the player reads the result.
	await get_tree().create_timer(0.8).timeout
	queue_free()

# ---------- Visual helpers ----------

func _update_dots() -> void:
	var dots := _shake_dots.get_children()
	for i in dots.size():
		(dots[i] as ColorRect).color = \
			Color(0.2, 0.85, 0.3) if i < _shake_count else Color(0.25, 0.25, 0.25)

func _flash_dot(idx: int) -> void:
	var dots := _shake_dots.get_children()
	if idx >= dots.size():
		return
	var dot := dots[idx] as ColorRect
	dot.color = Color(1, 1, 1)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(dot):
		dot.color = Color(0.2, 0.85, 0.3)
