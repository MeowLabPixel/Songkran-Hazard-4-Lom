@tool
## ReloadQteHud: Controls the reload QTE and Superpump hold minigame within player_stat_hud.
##
## Usage:
##   var hud = get_tree().get_first_node_in_group("reload_qte_hud") as ReloadQteHud
##   hud.qte_hit.connect(_on_qte_hit)
##   hud.finished.connect(_on_reload_finished)
##   hud.start(current_air, max_air)
##
## The node manages its own visibility and state without queue_free().
class_name ReloadQteHud
extends Control

signal qte_hit() # Emitted when a QTE prompt is successfully hit
signal superpump_started() # Emitted when dynamically transitioning to SuperPump
signal superpump_completed() # Emitted as soon as superpump gauge reaches full
signal finished(final_air: float, super_activated: bool) # Emitted when reload finishes
signal cancelled() # Emitted if interrupted (e.g. by aiming)

# ---- Settings & State ----
@export var start_air: float = 0.0
@export var max_air: float = 100.0
var mode: String = "qte" # "qte" or "superpump"
@export var show_progress_bar: bool = false
@export var fail_ends_reload: bool = true
@export var superpump_confirm_hold: float = 0.15
var _is_resolving_qte: bool = false
var _superpump_hold_confirm_timer: float = 0.0
var _has_released_since_qte: bool = false
var _superpump_gauge_completed: bool = false
var _last_qte_hit_time: float = -1.0
var _finish_tween: Tween = null

# QTE variables
@export var num_prompts: int = 4
@export var prompt_size: float = 0.05
@export var prompt_size_override: float = 0.0 # Configurable on the fly
@export var prompt_count_override: int = 0    # Configurable on the fly
@export var duration: float = 2.0
var actual_time: float = 0.0 # Actual time elapsed in reload (max 2.0s)
var successful_qtes: int = 0  # Number of QTE prompts successfully hit
var current_progress: float = 0.0 # Needle progress (0.0 to 1.0)
var reload_progress: float = 0.0 # Conveyed by the progress line (0.0 to 1.0)
var prompts: Array = [] # Array of Dictionary: { center: float, hit: bool, missed: bool }
var resolved: bool = false
var failed: bool = false
var progress_segments: Array = [] # Array of Dictionary: { start: float, end: float, is_skipped: bool }
var elapsed_time: float = 0.0

# Superpump hold variables
var superpump_hold_time: float = 0.0
@export var superpump_required_hold: float = 0.6

func get_superpump_progress() -> float:
	if mode == "superpump" and superpump_required_hold > 0.0:
		return clampf(superpump_hold_time / superpump_required_hold, 0.0, 1.0)
	return 0.0


# ---- Visual Customization: Gauge Geometry ----
@export_group("Gauge Geometry")
@export var gauge_radius: float = 72.0:
	set(v):
		if v == null:
			return
		gauge_radius = v
		_queue_gauge_redraw()
@export var gauge_thickness: float = 10.0:
	set(v):
		if v == null:
			return
		gauge_thickness = v
		_queue_gauge_redraw()
@export var needle_width: float = 4.0:
	set(v):
		if v == null:
			return
		needle_width = v
		_queue_gauge_redraw()
@export var needle_tip_size: float = 5.0:
	set(v):
		if v == null:
			return
		needle_tip_size = v
		_queue_gauge_redraw()
@export var needle_extension: float = 12.0:
	set(v):
		if v == null:
			return
		needle_extension = v
		_queue_gauge_redraw()

# ---- Visual Customization: Inner Fill Styling ----
@export_group("Inner Fill Styling")
@export var inner_fill_max_radius: float = 60.0:
	set(v):
		if v == null:
			return
		inner_fill_max_radius = v
		_queue_gauge_redraw()
@export var inner_fill_color: Color = Color(0.28955156, 0.97432137, 1, 0.2509804):
	set(v):
		if v == null or inner_fill_color == v:
			return
		inner_fill_color = v
		_queue_gauge_redraw()
@export var inner_fill_skipped_color: Color = Color(1.0, 1.0, 1.0, 0.22):
	set(v):
		if v == null or inner_fill_skipped_color == v:
			return
		inner_fill_skipped_color = v
		_queue_gauge_redraw()
@export var inner_fill_perfect_color: Color = Color(0.19999999, 0.8509804, 0.6162923, 0.2509804):
	set(v):
		if v == null or inner_fill_perfect_color == v:
			return
		inner_fill_perfect_color = v
		_queue_gauge_redraw()
@export var inner_fill_failed_color: Color = Color(0.8, 0.2, 0.2, 0.25):
	set(v):
		if v == null or inner_fill_failed_color == v:
			return
		inner_fill_failed_color = v
		_queue_gauge_redraw()

# Backward-compatibility property delegation (no separate backing or circular setters)
var fill_color_normal: Color:
	get:
		return inner_fill_color
	set(v):
		if v != null:
			inner_fill_color = v

var fill_color_perfect: Color:
	get:
		return inner_fill_perfect_color
	set(v):
		if v != null:
			inner_fill_perfect_color = v

var fill_color_failed: Color:
	get:
		return inner_fill_failed_color
	set(v):
		if v != null:
			inner_fill_failed_color = v

# ---- Visual Customization: Gauge Colors ----
@export_group("Gauge Colors")
@export var gauge_bg_color: Color = Color(0.1, 0.1, 0.12, 0.7):
	set(v):
		if v == null:
			return
		gauge_bg_color = v
		_queue_gauge_redraw()
@export var prompt_active_color: Color = Color(0.2, 0.7, 0.9, 0.8):
	set(v):
		if v == null:
			return
		prompt_active_color = v
		_queue_gauge_redraw()
@export var prompt_hit_color: Color = Color(0.2, 0.9, 0.4, 0.9):
	set(v):
		if v == null:
			return
		prompt_hit_color = v
		_queue_gauge_redraw()
@export var prompt_miss_color: Color = Color(0.8, 0.2, 0.2, 0.45):
	set(v):
		if v == null:
			return
		prompt_miss_color = v
		_queue_gauge_redraw()
@export var needle_color: Color = Color.WHITE:
	set(v):
		if v == null:
			return
		needle_color = v
		_queue_gauge_redraw()
@export var superpump_color_start: Color = Color(1.0, 0.55, 0.1, 0.9):
	set(v):
		if v == null:
			return
		superpump_color_start = v
		_queue_gauge_redraw()
@export var superpump_color_end: Color = Color(1.0, 0.9, 0.2, 1.0):
	set(v):
		if v == null:
			return
		superpump_color_end = v
		_queue_gauge_redraw()

# ---- Visual Customization: Center Circle Styling ----
@export_group("Center Circle Styling")
@export var center_bg_color: Color = Color(0.08, 0.08, 0.1, 0.85):
	set(v):
		center_bg_color = v
		_apply_center_circle_style()
@export var center_border_color: Color = Color(0.3, 0.7, 1.0, 0.8):
	set(v):
		center_border_color = v
		_apply_center_circle_style()
@export var center_border_width: int = 2:
	set(v):
		center_border_width = v
		_apply_center_circle_style()
@export var center_corner_radius: int = 24:
	set(v):
		center_corner_radius = v
		_apply_center_circle_style()
@export var center_success_border: Color = Color(0.2, 0.9, 0.4, 1.0)
@export var center_fail_border: Color = Color(0.9, 0.2, 0.2, 1.0)

# ---- Visual Customization: Progress Bar Styling ----
@export_group("Progress Bar Styling")
@export var progress_bar_y: float = 212.0:
	set(v):
		progress_bar_y = v
		_queue_gauge_redraw()
@export var progress_bar_width: float = 180.0:
	set(v):
		progress_bar_width = v
		_queue_gauge_redraw()
@export var progress_bar_thickness: float = 6.0:
	set(v):
		progress_bar_thickness = v
		_queue_gauge_redraw()
@export var progress_bar_bg_color: Color = Color(0.12, 0.12, 0.15, 0.85):
	set(v):
		progress_bar_bg_color = v
		_queue_gauge_redraw()
@export var progress_bar_fill_color: Color = Color(0.3, 0.75, 1.0, 0.95):
	set(v):
		progress_bar_fill_color = v
		_queue_gauge_redraw()

# ---- Visual Customization: Overlay ----
@export_group("Overlay")
@export var dim_color: Color = Color(0, 0, 0, 0.15):
	set(v):
		dim_color = v
		if is_inside_tree() and background_dim:
			background_dim.color = v

# ---- UI Node References (Customizable in Godot Editor) ----
@export_group("UI References")
@export var background_dim: ColorRect
@export var container: Control
@export var gauge: Control
@export var center_circle: Panel
@export var center_label: Label
@export var prompt_label: Label
@export var instruction_label: Label

func _queue_gauge_redraw() -> void:
	if is_inside_tree() and gauge:
		gauge.queue_redraw()

func _apply_center_circle_style() -> void:
	if not is_inside_tree() or not center_circle:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = center_bg_color
	style.border_color = center_border_color
	style.set_border_width_all(center_border_width)
	style.set_corner_radius_all(center_corner_radius)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	center_circle.add_theme_stylebox_override("panel", style)

func _init(p_current_air: float = 0.0, p_max_air: float = 100.0) -> void:
	start_air = p_current_air
	max_air = p_max_air

func _ready() -> void:
	add_to_group("qte_hud")
	add_to_group("reload_qte_hud")
	_wire_nodes()
	_apply_center_circle_style()
	if background_dim:
		background_dim.color = dim_color
	if gauge and not gauge.draw.is_connected(_draw_gauge):
		gauge.draw.connect(_draw_gauge)
	if Engine.is_editor_hint():
		_setup_editor_preview()
		return
	visible = false
	set_process(false)
	set_process_input(false)

func _wire_nodes() -> void:
	if not background_dim:
		background_dim = get_node_or_null("DimOverlay") as ColorRect
	if not container:
		container = get_node_or_null("Container") as Control
	if container:
		if not gauge:
			gauge = container.get_node_or_null("Gauge") as Control
		if not center_circle:
			center_circle = container.get_node_or_null("CenterCircle") as Panel
		if center_circle and not center_label:
			center_label = center_circle.get_node_or_null("CenterLabel") as Label
		if not prompt_label:
			prompt_label = container.get_node_or_null("PromptLabel") as Label
		if not instruction_label:
			instruction_label = container.get_node_or_null("InstructionLabel") as Label

func _setup_editor_preview(request_redraw: bool = true) -> void:
	_wire_nodes()
	mode = "qte"
	num_prompts = 3
	prompt_size = 0.08
	current_progress = 0.65
	reload_progress = 0.85
	resolved = false
	failed = false
	progress_segments = [
		{"start": 0.0, "end": 0.55, "is_skipped": false},
		{"start": 0.55, "end": 0.85, "is_skipped": true}
	]
	prompts = [
		{"center": 0.25, "hit": true, "missed": false},
		{"center": 0.55, "hit": false, "missed": false},
		{"center": 0.82, "hit": false, "missed": false}
	]
	if container:
		container.modulate = Color.WHITE
		container.scale = Vector2.ONE
	if background_dim:
		background_dim.color = dim_color
	_apply_center_circle_style()
	if prompt_label:
		prompt_label.scale = Vector2.ONE
		if prompt_label.text.is_empty() or prompt_label.text == "PERFECT QTE!":
			prompt_label.text = "PERFECT QTE!"
			prompt_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	if instruction_label and (instruction_label.text.is_empty() or instruction_label.text == "PRESS [R] | [SPACE] ON TARGET"):
		instruction_label.text = "PRESS [R] | [SPACE] ON TARGET"
		instruction_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1, 0.8))
	if request_redraw and gauge:
		gauge.queue_redraw()

func setup() -> void:
	if mode == "qte":
		_setup_qte_parameters()

# ---------- Activation & Lifecycle ----------

func start(p_current_air: float = 0.0, p_max_air: float = 100.0) -> void:
	if _finish_tween and _finish_tween.is_valid():
		_finish_tween.kill()
		_finish_tween = null
	_is_resolving_qte = false
	_superpump_hold_confirm_timer = 0.0
	_has_released_since_qte = false
	start_air = p_current_air
	max_air = p_max_air
	elapsed_time = 0.0
	actual_time = 0.0
	current_progress = 0.0
	reload_progress = 0.0
	prompts.clear()
	progress_segments.clear()
	superpump_hold_time = 0.0
	_superpump_gauge_completed = false
	_last_qte_hit_time = -1.0
	resolved = false
	failed = false

	_wire_nodes()

	if start_air >= max_air:
		mode = "superpump"
	else:
		mode = "qte"

	if mode == "qte":
		_setup_qte_parameters()

	# Reset visual elements
	if container:
		container.scale = Vector2.ONE
		container.modulate.a = 1.0
	if background_dim:
		background_dim.color = dim_color
	if center_circle:
		center_circle.position = Vector2(101, 101)
		_apply_center_circle_style()

	var lang = "en"
	if get_tree() and get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	if prompt_label:
		prompt_label.scale = Vector2.ONE
		if mode == "qte":
			prompt_label.text = ""
			prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			prompt_label.text = "" if lang == "th" else ""
			prompt_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1))

	if instruction_label:
		if mode == "qte":
			instruction_label.text = "กด [R] | [SPACE] ให้ตรงเป้า" if lang == "th" else "PRESS [R] | [SPACE] ON TARGET"
		else:
			instruction_label.text = "กด [R] ค้างเพื่อปั๊มน้ำเพิ่มแรงดัน" if lang == "th" else "HOLD [R] TO SUPERPUMP"

	if gauge:
		gauge.queue_redraw()

	var should_show := true
	if get_tree() and get_tree().root.has_node("GameManager"):
		should_show = GameManager.show_reload_qte and GameManager.show_gameplay_ui
	visible = should_show
	set_process(true)
	set_process_input(true)

func _setup_qte_parameters() -> void:
	duration = 2.0
	actual_time = 0.0
	successful_qtes = 0
	elapsed_time = 0.0
	
	var air_pct = clampf(start_air / max_air, 0.0, 1.0)
	reload_progress = 0.0
	progress_segments = [
		{"start": 0.0, "end": 0.0, "is_skipped": false}
	]
	
	# Determine number of QTE prompts based on remaining air
	if prompt_count_override > 0:
		num_prompts = prompt_count_override
	else:
		var air_ratio = start_air / max_air
		if air_ratio <= 0.0:
			num_prompts = 4
		elif air_ratio <= 0.30:
			num_prompts = 3
		elif air_ratio <= 0.50:
			num_prompts = 2
		else:
			num_prompts = 1
		
	# Interpolate prompt size between 0.05 (hard at 0 air) and 0.14 (easy at 100 air)
	if prompt_size_override > 0.0:
		prompt_size = prompt_size_override
	else:
		prompt_size = lerp(0.05, 0.14, air_pct) * 0.75
	
	# Generate prompts based on scaled phantom segment timing (starts earlier)
	prompts.clear()
	for i in range(num_prompts):
		var center = 0.05 + 0.70 * (float(i + 1) / float(num_prompts + 1))
		prompts.append({
			"center": center,
			"hit": false,
			"missed": false
		})

func cancel() -> void:
	if _finish_tween and _finish_tween.is_valid():
		_finish_tween.kill()
		_finish_tween = null
	_is_resolving_qte = false
	_superpump_hold_confirm_timer = 0.0
	_has_released_since_qte = false
	set_process(false)
	set_process_input(false)
	visible = false
	if container:
		container.modulate.a = 1.0
		container.scale = Vector2.ONE
	if background_dim:
		background_dim.color = dim_color

	if not resolved:
		resolved = true
		if not _superpump_gauge_completed:
			cancelled.emit()

func transition_to_superpump() -> void:
	if _finish_tween and _finish_tween.is_valid():
		_finish_tween.kill()
		_finish_tween = null
	_is_resolving_qte = false
	_superpump_hold_confirm_timer = 0.0
	_has_released_since_qte = false
	_superpump_gauge_completed = false
	if reload_progress > 0.0:
		start_air = clampf(start_air + (max_air - start_air) * reload_progress, 0.0, max_air)
	
	mode = "superpump"
	resolved = false
	failed = false
	elapsed_time = 0.0
	superpump_hold_time = 0.0
	set_process(true)
	set_process_input(true)
	visible = true
	
	if container:
		container.scale = Vector2.ONE
		container.modulate.a = 1.0
	if background_dim:
		background_dim.color = dim_color
	if center_circle:
		center_circle.position = Vector2(101, 101)
		_apply_center_circle_style()
		
	var lang = "en"
	if get_tree() and get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language
		
	if prompt_label:
		prompt_label.scale = Vector2.ONE
		prompt_label.text = "" if lang == "th" else ""
		prompt_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1))
	if instruction_label:
		instruction_label.text = "กด [R] ค้างเพื่อปั๊มน้ำเพิ่มแรงดัน" if lang == "th" else "HOLD [R] TO SUPERPUMP"
	if gauge:
		gauge.queue_redraw()
	
	superpump_started.emit()

# ---------- Per-frame logic ----------

func _process(delta: float) -> void:
	if _is_resolving_qte:
		_process_qte_resolution_hold(delta)
		return

	if resolved:
		return
		
	elapsed_time += delta
	
	if mode == "qte":
		_process_qte(delta)
	else:
		_process_superpump(delta)

func _process_qte_resolution_hold(delta: float) -> void:
	if not _has_released_since_qte:
		if not Input.is_action_pressed("Reload"):
			_has_released_since_qte = true
	else:
		if Input.is_action_pressed("Reload"):
			_superpump_hold_confirm_timer += delta
			if _superpump_hold_confirm_timer >= superpump_confirm_hold:
				transition_to_superpump()
		else:
			_superpump_hold_confirm_timer = 0.0

func _process_qte(delta: float) -> void:
	actual_time += delta
	
	# Clock hand (outer ring needle) sweeps steadily over base duration
	current_progress = clampf(actual_time / duration, 0.0, 1.0)
	
	# Count hits and check if all hit
	successful_qtes = 0
	var all_hit = true
	for p in prompts:
		if p.hit:
			successful_qtes += 1
		else:
			all_hit = false
			
	# Calculate reload progress based on effective duration
	var skip_time = (duration * 0.5) * (float(successful_qtes) / float(num_prompts))
	var effective_duration = duration - skip_time
	reload_progress = clampf(actual_time / effective_duration, 0.0, 1.0)
	
	# Update the current elapsed progress segment's end value
	if progress_segments.size() > 0:
		progress_segments[-1].end = reload_progress
	
	# Check for missed prompts that the needle has passed
	for p in prompts:
		if not p.hit and not p.missed and current_progress > (p.center + prompt_size):
			p.missed = true
			failed = true
			get_tree().call_group("player_ui", "on_qte_prompt_miss")
			if fail_ends_reload:
				_resolve(false)
				return
			
	if gauge:
		gauge.queue_redraw()
	
	# End condition checks
	if all_hit:
		_resolve(true)
	elif reload_progress >= 1.0:
		_resolve(true)

func _process_superpump(delta: float) -> void:
	if Input.is_action_pressed("Reload"):
		superpump_hold_time += delta
		
		var ratio = clampf(superpump_hold_time / superpump_required_hold, 0.0, 1.0)
		if center_circle:
			center_circle.position = Vector2(101, 101) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * ratio * 3.0
		
		if superpump_hold_time >= superpump_required_hold:
			if not _superpump_gauge_completed:
				_superpump_gauge_completed = true
				superpump_completed.emit()
			_resolve(true)
	else:
		# Immediately cancel super pump if player stops holding R key (after 0.3s guard)
		if not _superpump_gauge_completed and elapsed_time >= 0.3:
			cancel()
		
	if gauge:
		gauge.queue_redraw()

func _input(event: InputEvent) -> void:
	if resolved or _is_resolving_qte:
		return
		
	if mode == "qte" and _is_qte_trigger_event(event):
		get_viewport().set_input_as_handled()
		_check_qte_input()

func _is_qte_trigger_event(event: InputEvent) -> bool:
	if event.is_action_pressed("Reload"):
		return true
	if event.is_action_pressed("ui_select"):
		return true
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.physical_keycode == KEY_SPACE or event.keycode == KEY_SPACE:
			return true
	return false

func _check_qte_input() -> void:
	var hit_any = false
	var is_early = false
	
	for p in prompts:
		if p.hit or p.missed:
			continue
			
		# Check if current needle progress falls inside the target range
		if current_progress >= (p.center - prompt_size) and current_progress <= (p.center + prompt_size):
			p.hit = true
			hit_any = true
			
			qte_hit.emit()
			get_tree().call_group("player_ui", "on_qte_prompt_hit")
			
			_flash_center_success()
			
			if container:
				var pop_tween = create_tween()
				container.scale = Vector2(1.12, 1.12)
				pop_tween.tween_property(container, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			var hits = 0
			for other_p in prompts:
				if other_p.hit:
					hits += 1
					
			var val_before = reload_progress
			var skip_time = (duration * 0.5) * (float(hits) / float(num_prompts))
			var effective_dur = duration - skip_time
			var val_after = clampf(actual_time / effective_dur, 0.0, 1.0)
			
			if progress_segments.size() > 0:
				progress_segments[-1].end = val_before
				
			progress_segments.append({"start": val_before, "end": val_after, "is_skipped": true})
			progress_segments.append({"start": val_after, "end": val_after, "is_skipped": false})
			reload_progress = val_after
			break
		elif current_progress < (p.center - prompt_size):
			is_early = true
			
	if hit_any:
		_last_qte_hit_time = actual_time
		var all_hit = true
		for p in prompts:
			if not p.hit:
				all_hit = false
				break
				
		if all_hit:
			_resolve(true)
	else:
		# If an input arrives within 0.12s of a successful hit, treat it as a simultaneous press and ignore
		if _last_qte_hit_time >= 0.0 and (actual_time - _last_qte_hit_time) < 0.12:
			return
			
		_flash_center_failure()
		get_tree().call_group("player_ui", "on_qte_prompt_miss")
		
		if not is_early:
			failed = true
			if fail_ends_reload:
				_resolve(false)
		
	if gauge:
		gauge.queue_redraw()

# ---------- Drawing Procedural UI ----------

func _draw_gauge() -> void:
	if not gauge:
		return
	if Engine.is_editor_hint() and prompts.is_empty():
		_setup_editor_preview(false)
	var center = gauge.size / 2.0
	var radius = gauge_radius
	var thickness = gauge_thickness
	
	# Draw background circle
	gauge.draw_arc(center, radius, 0, 2*PI, 64, gauge_bg_color, thickness, true)
	
	if mode == "qte":
		# Draw the prompt arcs
		for p in prompts:
			var start_ang = -PI/2 + (p.center - prompt_size) * 2*PI
			var end_ang = -PI/2 + (p.center + prompt_size) * 2*PI
			
			var color = prompt_active_color
			if p.hit:
				color = prompt_hit_color
			elif p.missed:
				color = prompt_miss_color
			if color == null:
				color = Color(0.2, 0.7, 0.9, 0.8)
				
			gauge.draw_arc(center, radius, start_ang, end_ang, 24, color, thickness, true)
			
		# Draw the needle
		var needle_angle = -PI/2 + current_progress * 2*PI
		var dir = Vector2(cos(needle_angle), sin(needle_angle))
		var needle_start = center + dir * (radius - needle_extension)
		var needle_end = center + dir * (radius + needle_extension)
		
		gauge.draw_line(needle_start, needle_end, needle_color if needle_color != null else Color.WHITE, needle_width, true)
		gauge.draw_circle(needle_end, needle_tip_size, needle_color if needle_color != null else Color.WHITE)
		
		# Draw reload progress filling the inner circle
		if not show_progress_bar:
			var max_radius = inner_fill_max_radius
			
			if resolved:
				if failed:
					gauge.draw_circle(center, max_radius, inner_fill_failed_color if inner_fill_failed_color != null else Color.RED)
				elif successful_qtes == num_prompts and successful_qtes > 0:
					gauge.draw_circle(center, max_radius * reload_progress, inner_fill_perfect_color if inner_fill_perfect_color != null else Color.GREEN)
				else:
					gauge.draw_circle(center, max_radius * reload_progress, inner_fill_color if inner_fill_color != null else Color.CYAN)
			else:
				for segment in progress_segments:
					var r_start = segment.start * max_radius
					var r_end = segment.end * max_radius
					var seg_thickness = r_end - r_start
					var mid_radius = (r_start + r_end) / 2.0
					var color = inner_fill_skipped_color if segment.is_skipped else inner_fill_color
					if color == null:
						color = Color(1.0, 1.0, 1.0, 0.25)
					
					if seg_thickness > 0.05:
						gauge.draw_arc(center, mid_radius, 0, 2*PI, 64, color, seg_thickness, false)
		
		# Draw horizontal reload progress line below the gauge (optional)
		if show_progress_bar:
			var line_y = progress_bar_y
			var line_width = progress_bar_width
			var line_left = center.x - line_width / 2.0
			var line_right = center.x + line_width / 2.0
			
			gauge.draw_line(Vector2(line_left, line_y), Vector2(line_right, line_y), progress_bar_bg_color, progress_bar_thickness, true)
			
			var fill_x = line_left + line_width * clampf(reload_progress, 0.0, 1.0)
			if fill_x > line_left:
				var line_color = progress_bar_fill_color
				if resolved:
					if failed:
						line_color = Color(0.8, 0.2, 0.2, 0.95)
					elif successful_qtes == num_prompts and successful_qtes > 0:
						line_color = Color(0.2, 0.85, 0.4, 0.95)
				
				gauge.draw_line(Vector2(line_left, line_y), Vector2(fill_x, line_y), line_color, progress_bar_thickness, true)
				gauge.draw_circle(Vector2(fill_x, line_y), 4.5, needle_color)

	elif mode == "superpump":
		var hold_ratio = clampf(superpump_hold_time / superpump_required_hold, 0.0, 1.0)
		if hold_ratio > 0.0:
			var start_ang = -PI/2
			var end_ang = -PI/2 + hold_ratio * 2*PI
			var fill_color = superpump_color_start.lerp(superpump_color_end, hold_ratio)
			gauge.draw_arc(center, radius, start_ang, end_ang, 48, fill_color, thickness, true)

# ---------- Visual Polish Effects ----------

func _flash_center_success() -> void:
	if not center_circle:
		return
	var style = center_circle.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = center_success_border
	style.bg_color = Color(0.05, 0.15, 0.08, 0.9)
	center_circle.add_theme_stylebox_override("panel", style)
	
	var tween = create_tween()
	tween.tween_property(center_circle, "scale", Vector2(1.2, 1.2), 0.05)
	tween.tween_property(center_circle, "scale", Vector2.ONE, 0.15)
	
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(center_circle):
		_apply_center_circle_style()

func _flash_center_failure() -> void:
	if not center_circle:
		return
	var style = center_circle.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = center_fail_border
	style.bg_color = Color(0.18, 0.05, 0.05, 0.9)
	center_circle.add_theme_stylebox_override("panel", style)
	
	var tween = create_tween()
	for i in range(4):
		var offset = Vector2(randf_range(-4, 4), randf_range(-4, 4))
		tween.tween_property(center_circle, "position", Vector2(101, 101) + offset, 0.03)
	tween.tween_property(center_circle, "position", Vector2(101, 101), 0.03)
	
	await get_tree().create_timer(0.25).timeout
	if is_instance_valid(center_circle):
		_apply_center_circle_style()

# ---------- Resolution & Cleanup ----------

func _resolve(success: bool) -> void:
	if resolved:
		return
	resolved = true
	
	if mode == "qte":
		var current_air_at_resolve = clampf(start_air + (max_air - start_air) * reload_progress, 0.0, max_air)
		var final_air = start_air
		print("[ReloadQteHud debug] _resolve called. success: ", success, ", failed: ", failed, ", start_air: ", start_air, ", reload_progress: ", reload_progress, ", current_air_at_resolve: ", current_air_at_resolve)
		
		if not failed:
			reload_progress = 1.0
			if progress_segments.size() > 0:
				progress_segments[-1].end = 1.0
		if gauge:
			gauge.queue_redraw()
		
		var hit_count = 0
		for p in prompts:
			if p.hit:
				hit_count += 1
				
		var lang = "en"
		if get_tree() and get_tree().root.has_node("GameManager"):
			lang = GameManager.selected_language
			
		var is_perfect = (hit_count == prompts.size() and hit_count > 0 and not failed)
		
		if prompt_label:
			if failed:
				final_air = current_air_at_resolve
				prompt_label.text = "" if lang == "th" else ""
				prompt_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
				SoundManager.play_2d("watergun_pistol_reload")
			elif is_perfect:
				final_air = max_air
				prompt_label.text = "จังหวะสมบูรณ์แบบ!" if lang == "th" else "PERFECT QTE!"
				prompt_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
				SoundManager.play_2d("Superpump_Ready_FullAir")
			elif hit_count > 0:
				final_air = max_air
				prompt_label.text = "" if lang == "th" else ""
				prompt_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
				SoundManager.play_2d("watergun_pistol_reload")
			else:
				final_air = max_air
				prompt_label.text = "รีโหลดสำเร็จ" if lang == "th" else "RELOAD COMPLETE"
				prompt_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.5))
				SoundManager.play_2d("watergun_pistol_reload")
				
		get_tree().call_group("player_ui", "on_qte_reload_ended", is_perfect, final_air)
		
		# Allow hold confirmation into superpump (on success or fail)
		_is_resolving_qte = true
		_superpump_hold_confirm_timer = 0.0
		_has_released_since_qte = not Input.is_action_pressed("Reload")
		set_process(true)
		set_process_input(false)
		
		if prompt_label:
			prompt_label.scale = Vector2.ZERO
			create_tween().tween_property(prompt_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
		
		await get_tree().create_timer(0.3).timeout
		if not _is_resolving_qte or not visible:
			visible = false
			return
		
		if container and background_dim:
			_finish_tween = create_tween().set_parallel(true)
			_finish_tween.tween_property(container, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_finish_tween.tween_property(container, "modulate:a", 0.0, 0.25)
			_finish_tween.tween_property(background_dim, "color:a", 0.0, 0.25)
			await _finish_tween.finished
			if not _is_resolving_qte or not visible:
				visible = false
				return
		
		# If player is currently holding Reload to confirm superpump, wait for confirmation
		while _is_resolving_qte and Input.is_action_pressed("Reload") and _superpump_hold_confirm_timer < superpump_confirm_hold:
			await get_tree().process_frame
			if not _is_resolving_qte or not visible:
				visible = false
				return
		
		_is_resolving_qte = false
		set_process(false)
		set_process_input(false)
		visible = false
		finished.emit(final_air, false)
		
	elif mode == "superpump":
		set_process(false)
		set_process_input(false)
		if success:
			var lang = "en"
			if get_tree() and get_tree().root.has_node("GameManager"):
				lang = GameManager.selected_language
			if prompt_label:
				prompt_label.text = "ซูเปอร์ปั๊ม!" if lang == "th" else "SUPERPUMP!"
				prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			SoundManager.play_2d("watergun_pistol_reload_Superpump")
			
			if prompt_label:
				prompt_label.scale = Vector2.ZERO
				create_tween().tween_property(prompt_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
			
			await get_tree().create_timer(0.3).timeout
			if not visible or not is_inside_tree():
				return
			
			if container and background_dim:
				_finish_tween = create_tween().set_parallel(true)
				_finish_tween.tween_property(container, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_finish_tween.tween_property(container, "modulate:a", 0.0, 0.25)
				_finish_tween.tween_property(background_dim, "color:a", 0.0, 0.25)
				await _finish_tween.finished
				if not visible or not is_inside_tree():
					return
			
			visible = false
			finished.emit(120.0, true) # 120.0 is the super_threshold
		else:
			if container and background_dim:
				_finish_tween = create_tween().set_parallel(true)
				_finish_tween.tween_property(container, "scale", Vector2(1.15, 1.15), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_finish_tween.tween_property(container, "modulate:a", 0.0, 0.2)
				_finish_tween.tween_property(background_dim, "color:a", 0.0, 0.2)
				await _finish_tween.finished
				if not visible or not is_inside_tree():
					return
			
			visible = false
			finished.emit(start_air, false)
