## ReloadQteHud: self-contained CanvasLayer that drives the reload QTE and Superpump hold minigames.
##
## Usage:
##   var hud = ReloadQteHud.new(current_air, max_air)
##   hud.qte_hit.connect(_on_qte_hit)
##   hud.finished.connect(_on_reload_finished)
##   add_child(hud)
##
class_name ReloadQteHud
extends CanvasLayer

signal qte_hit() # Emitted when a QTE prompt is successfully hit
signal finished(final_air: float, super_activated: bool) # Emitted when reload finishes
signal cancelled() # Emitted if interrupted (e.g. by aiming)

# ---- Settings & State ----
var start_air: float = 0.0
var max_air: float = 100.0
var mode: String = "qte" # "qte" or "superpump"

# QTE variables
var num_prompts: int = 4
var prompt_size: float = 0.05
var duration: float = 2.0
var time_left: float = 2.0
var current_progress: float = 0.0
var reload_progress: float = 0.0 # Conveyed by the progress line (0.0 to 1.0)
var prompts: Array = [] # Array of Dictionary: { center: float, hit: bool, missed: bool }
var resolved: bool = false

# Superpump hold variables
var superpump_hold_time: float = 0.0
var superpump_required_hold: float = 0.6

# ---- UI Nodes (Created procedurally) ----
var _background_dim: ColorRect
var _container: Control
var _gauge: Control
var _center_circle: Panel
var _center_label: Label
var _prompt_label: Label
var _instruction_label: Label

func _init(p_current_air: float, p_max_air: float) -> void:
	start_air = p_current_air
	max_air = p_max_air
	layer = 128 # Always draw on top of everything
	
	if start_air >= max_air:
		mode = "superpump"
	else:
		mode = "qte"
		_setup_qte_parameters()

func _ready() -> void:
	_build_ui()

func _setup_qte_parameters() -> void:
	# Keep QTE sweep duration fixed at 2.0 seconds for steady timing
	duration = 2.0
	time_left = duration
	
	var air_pct = clampf(start_air / max_air, 0.0, 1.0)
	# Reload progress starts at current air percentage
	reload_progress = air_pct
	
	# Determine number of QTE prompts based on remaining air
	if start_air >= 75.0:
		num_prompts = 1
	elif start_air >= 50.0:
		num_prompts = 2
	elif start_air >= 25.0:
		num_prompts = 3
	else:
		num_prompts = 4
		
	# Interpolate prompt size between 0.05 (hard at 0 air) and 0.14 (easy at 100 air)
	prompt_size = lerp(0.05, 0.14, air_pct)
	
	# Generate randomized non-overlapping prompt centers inside [0.12, 0.88]
	prompts.clear()
	var seg_start_pct = 0.12
	var seg_end_pct = 0.88
	var total_span = seg_end_pct - seg_start_pct
	var segment_size = total_span / num_prompts
	
	for i in range(num_prompts):
		var s_min = seg_start_pct + i * segment_size
		var s_max = s_min + segment_size
		# Pick a random center inside the middle portion of the segment
		var center = s_min + segment_size * randf_range(0.25, 0.75)
		prompts.append({
			"center": center,
			"hit": false,
			"missed": false
		})

func _build_ui() -> void:
	# 1. Background overlay
	_background_dim = ColorRect.new()
	_background_dim.color = Color(0, 0, 0, 0.15)
	_background_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background_dim)
	
	# 2. Main Center Container (slightly taller to accommodate progress line)
	_container = Control.new()
	_container.set_anchors_preset(Control.PRESET_CENTER)
	_container.custom_minimum_size = Vector2(250, 270)
	_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_container)
	
	# 3. Custom Procedural Drawing Gauge
	_gauge = Control.new()
	_gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauge.draw.connect(_draw_gauge)
	_container.add_child(_gauge)
	
	# 4. Central Button UI (A circle containing 'R')
	_center_circle = Panel.new()
	_center_circle.custom_minimum_size = Vector2(48, 48)
	_center_circle.position = Vector2(101, 101) # Centered on 250x250 circle
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	style.border_color = Color(0.3, 0.7, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	_center_circle.add_theme_stylebox_override("panel", style)
	_container.add_child(_center_circle)
	
	_center_label = Label.new()
	_center_label.text = "R"
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.add_theme_font_size_override("font_size", 22)
	_center_label.add_theme_color_override("font_color", Color.WHITE)
	_center_circle.add_child(_center_label)
	
	# 5. Text prompt below the gauge and progress line
	_prompt_label = Label.new()
	_prompt_label.text = "PRESS [R] IN ZONE" if mode == "qte" else "HOLD [R] TO SUPERPUMP"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(0, 235)
	_prompt_label.size = Vector2(250, 24)
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if mode == "qte" else Color(1.0, 0.5, 0.1))
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 5)
	_container.add_child(_prompt_label)
	
	# 6. Small helper text above the gauge
	_instruction_label = Label.new()
	_instruction_label.text = "RELOADING AIR..." if mode == "qte" else "PRESSURE STABLE"
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.position = Vector2(0, 30)
	_instruction_label.size = Vector2(250, 20)
	_instruction_label.add_theme_font_size_override("font_size", 11)
	_instruction_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.8))
	_instruction_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_instruction_label.add_theme_constant_override("outline_size", 3)
	_container.add_child(_instruction_label)

func _process(delta: float) -> void:
	if resolved:
		return
		
	if mode == "qte":
		_process_qte(delta)
	else:
		_process_superpump(delta)

func _process_qte(delta: float) -> void:
	# Tick down time
	time_left -= delta
	
	# Calculate needle progress (0.0 to 1.0)
	if duration > 0.0:
		current_progress = clampf((duration - time_left) / duration, 0.0, 1.0)
	else:
		current_progress = 1.0
		
	# Increase reload progress steadily based on elapsed time (reaches 1.0 at 2.0s)
	reload_progress = clampf(reload_progress + (delta / duration), 0.0, 1.0)
	
	# Check for missed prompts that the needle has passed
	for p in prompts:
		if not p.hit and not p.missed and current_progress > (p.center + prompt_size):
			p.missed = true
			
	# Redraw the UI
	_gauge.queue_redraw()
	
	# If reload progress reaches 100%, we are done!
	if reload_progress >= 1.0:
		_resolve(true)
	elif time_left <= 0.0:
		# Time ran out, resolve with whatever progress was made
		_resolve(reload_progress >= 1.0)

func _process_superpump(delta: float) -> void:
	if Input.is_action_pressed("Reload"):
		superpump_hold_time += delta
		
		var ratio = clampf(superpump_hold_time / superpump_required_hold, 0.0, 1.0)
		_center_circle.position = Vector2(101, 101) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * ratio * 3.0
		
		if superpump_hold_time >= superpump_required_hold:
			_resolve(true)
	else:
		superpump_hold_time = maxf(superpump_hold_time - delta * 2.0, 0.0)
		_center_circle.position = Vector2(101, 101)
		
	_gauge.queue_redraw()

func _input(event: InputEvent) -> void:
	if resolved:
		return
		
	if mode == "qte" and event.is_action_pressed("Reload"):
		_check_qte_input()

func _check_qte_input() -> void:
	var hit_any = false
	
	for p in prompts:
		if p.hit or p.missed:
			continue
			
		# Check if current needle progress falls inside the target range
		if current_progress >= (p.center - prompt_size) and current_progress <= (p.center + prompt_size):
			p.hit = true
			hit_any = true
			
			# Emit hit signal to trigger player quick reload animation
			qte_hit.emit()
			
			# Visual success flash
			_flash_center_success()
			
			# Add 25% (0.25) to reload progress immediately!
			reload_progress = minf(reload_progress + 0.25, 1.0)
			break
			
	if hit_any:
		if reload_progress >= 1.0:
			_resolve(true)
	else:
		# Miss penalty: flash red, play click
		_flash_center_failure()
		SoundManager.play_2d("watergun_pistol_reload")
		
	_gauge.queue_redraw()

# ---------- Drawing Procedural UI ----------

func _draw_gauge() -> void:
	var center = _gauge.size / 2.0
	# Circular gauge properties
	var radius = 72.0
	var thickness = 10.0
	
	# Draw background circle
	_gauge.draw_arc(center, radius, 0, 2*PI, 64, Color(0.1, 0.1, 0.12, 0.7), thickness, true)
	
	if mode == "qte":
		# Draw the prompt arcs
		for p in prompts:
			var start_ang = -PI/2 + (p.center - prompt_size) * 2*PI
			var end_ang = -PI/2 + (p.center + prompt_size) * 2*PI
			
			var color = Color(0.2, 0.7, 0.9, 0.8) # Cyan active zone
			if p.hit:
				color = Color(0.2, 0.9, 0.4, 0.9) # Green hit
			elif p.missed:
				color = Color(0.8, 0.2, 0.2, 0.45) # Red miss
				
			_gauge.draw_arc(center, radius, start_ang, end_ang, 24, color, thickness, true)
			
		# Draw the needle (Sweeps steadily without jumping)
		var needle_angle = -PI/2 + current_progress * 2*PI
		var dir = Vector2(cos(needle_angle), sin(needle_angle))
		var needle_start = center + dir * (radius - 12.0)
		var needle_end = center + dir * (radius + 12.0)
		
		_gauge.draw_line(needle_start, needle_end, Color.WHITE, 4.0, true)
		_gauge.draw_circle(needle_end, 5.0, Color.WHITE)
		
		# Draw horizontal reload progress line below the gauge
		var line_y = 212.0
		var line_width = 180.0
		var line_left = center.x - line_width / 2.0
		var line_right = center.x + line_width / 2.0
		
		# Line background (dark grey track)
		_gauge.draw_line(Vector2(line_left, line_y), Vector2(line_right, line_y), Color(0.12, 0.12, 0.15, 0.85), 6.0, true)
		
		# Line fill (cyan/blue reload fill)
		var fill_x = line_left + line_width * clampf(reload_progress, 0.0, 1.0)
		if fill_x > line_left:
			_gauge.draw_line(Vector2(line_left, line_y), Vector2(fill_x, line_y), Color(0.3, 0.75, 1.0, 0.95), 6.0, true)
			# Small glowing tip on progress line
			_gauge.draw_circle(Vector2(fill_x, line_y), 4.5, Color.WHITE)

	elif mode == "superpump":
		# Draw hold progress bar filling up the circle
		var hold_ratio = clampf(superpump_hold_time / superpump_required_hold, 0.0, 1.0)
		if hold_ratio > 0.0:
			var start_ang = -PI/2
			var end_ang = -PI/2 + hold_ratio * 2*PI
			var fill_color = Color(1.0, 0.55, 0.1, 0.9).lerp(Color(1.0, 0.9, 0.2, 1.0), hold_ratio)
			_gauge.draw_arc(center, radius, start_ang, end_ang, 48, fill_color, thickness, true)

# ---------- Visual Polish Effects ----------

func _flash_center_success() -> void:
	var style = _center_circle.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = Color(0.2, 0.9, 0.4, 1.0)
	style.bg_color = Color(0.05, 0.15, 0.08, 0.9)
	_center_circle.add_theme_stylebox_override("panel", style)
	
	var tween = create_tween()
	tween.tween_property(_center_circle, "scale", Vector2(1.2, 1.2), 0.05)
	tween.tween_property(_center_circle, "scale", Vector2.ONE, 0.15)
	
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(_center_circle):
		var orig_style = StyleBoxFlat.new()
		orig_style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
		orig_style.border_color = Color(0.3, 0.7, 1.0, 0.8)
		orig_style.set_border_width_all(2)
		orig_style.set_corner_radius_all(24)
		_center_circle.add_theme_stylebox_override("panel", orig_style)

func _flash_center_failure() -> void:
	var style = _center_circle.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = Color(0.9, 0.2, 0.2, 1.0)
	style.bg_color = Color(0.18, 0.05, 0.05, 0.9)
	_center_circle.add_theme_stylebox_override("panel", style)
	
	var tween = create_tween()
	for i in range(4):
		var offset = Vector2(randf_range(-4, 4), randf_range(-4, 4))
		tween.tween_property(_center_circle, "position", Vector2(101, 101) + offset, 0.03)
	tween.tween_property(_center_circle, "position", Vector2(101, 101), 0.03)
	
	await get_tree().create_timer(0.25).timeout
	if is_instance_valid(_center_circle):
		var orig_style = StyleBoxFlat.new()
		orig_style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
		orig_style.border_color = Color(0.3, 0.7, 1.0, 0.8)
		orig_style.set_border_width_all(2)
		orig_style.set_corner_radius_all(24)
		_center_circle.add_theme_stylebox_override("panel", orig_style)

# ---------- Resolution & Cleanup ----------

func _resolve(success: bool) -> void:
	if resolved:
		return
	resolved = true
	
	if mode == "qte":
		var final_air = start_air
		if success:
			final_air = max_air
			_prompt_label.text = "PERFECT RELOAD!"
			_prompt_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			SoundManager.play_2d("Superpump_Ready_FullAir")
		else:
			# Refills to 100% on standard completed reload timer
			final_air = max_air
			_prompt_label.text = "RELOAD COMPLETE"
			_prompt_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.5))
			SoundManager.play_2d("watergun_pistol_reload")
			
		_prompt_label.scale = Vector2.ZERO
		create_tween().tween_property(_prompt_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
		
		await get_tree().create_timer(0.3).timeout
		finished.emit(final_air, false)
		queue_free()
		
	elif mode == "superpump":
		if success:
			_prompt_label.text = "SUPERPUMP ACTIVATED!"
			_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			SoundManager.play_2d("watergun_pistol_reload_Superpump")
			
			_prompt_label.scale = Vector2.ZERO
			create_tween().tween_property(_prompt_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
			
			await get_tree().create_timer(0.3).timeout
			finished.emit(120.0, true) # 120.0 is the super_threshold
			queue_free()
		else:
			finished.emit(start_air, false)
			queue_free()

func cancel() -> void:
	if resolved:
		return
	resolved = true
	cancelled.emit()
	queue_free()
