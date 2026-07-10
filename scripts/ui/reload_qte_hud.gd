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
@export var show_progress_bar: bool = false

# QTE variables
var num_prompts: int = 4
var prompt_size: float = 0.05
var prompt_size_override: float = 0.0 # Configurable on the fly
var prompt_count_override: int = 0    # Configurable on the fly
var duration: float = 2.0
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
	elapsed_time = 0.0
	
	if start_air >= max_air:
		mode = "superpump"
	else:
		mode = "qte"

func setup() -> void:
	if mode == "qte":
		_setup_qte_parameters()

func _ready() -> void:
	_build_ui()

func _setup_qte_parameters() -> void:
	# Needle sweep duration is always exactly 2.0 seconds
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
	_container.pivot_offset = Vector2(125, 135)
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
	
	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language
		
	var subheader_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	var body_font = preload("res://scenes/font/iannnnnVCD 2007 Bold.ttf")

	_center_label = Label.new()
	_center_label.text = "R"
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.add_theme_font_size_override("font_size", 22)
	_center_label.add_theme_color_override("font_color", Color.WHITE)
	_center_label.add_theme_font_override("font", subheader_font)
	_center_circle.add_child(_center_label)
	
	# 5. Text prompt below the gauge and progress line
	_prompt_label = Label.new()
	if mode == "qte":
		_prompt_label.text = ""
	else:
		_prompt_label.text = "กด [R] ค้างเพื่อปั๊มน้ำเพิ่มแรงดัน" if lang == "th" else "HOLD [R] TO SUPERPUMP"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(0, 235)
	_prompt_label.size = Vector2(250, 24)
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if mode == "qte" else Color(1.0, 0.5, 0.1))
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 5)
	_prompt_label.add_theme_font_override("font", subheader_font)
	_container.add_child(_prompt_label)
	
	# 6. Small helper text above the gauge
	_instruction_label = Label.new()
	if mode == "qte":
		_instruction_label.text = ""
	else:
		_instruction_label.text = "แรงดันคงที่" if lang == "th" else "PRESSURE STABLE"
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.position = Vector2(0, 30)
	_instruction_label.size = Vector2(250, 20)
	_instruction_label.add_theme_font_size_override("font_size", 11)
	_instruction_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.8))
	_instruction_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_instruction_label.add_theme_font_override("font", body_font)
	_instruction_label.add_theme_constant_override("outline_size", 3)
	_container.add_child(_instruction_label)

func _process(delta: float) -> void:
	if resolved:
		return
		
	elapsed_time += delta
	
	if mode == "qte":
		_process_qte(delta)
	else:
		_process_superpump(delta)

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
			
	# Redraw the UI
	_gauge.queue_redraw()
	
	# End condition checks
	if all_hit:
		_resolve(true)
	elif reload_progress >= 1.0:
		_resolve(true)

func _process_superpump(delta: float) -> void:
	if Input.is_action_pressed("Reload"):
		superpump_hold_time += delta
		
		var ratio = clampf(superpump_hold_time / superpump_required_hold, 0.0, 1.0)
		_center_circle.position = Vector2(101, 101) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * ratio * 3.0
		
		if superpump_hold_time >= superpump_required_hold:
			_resolve(true)
	else:
		# Immediately cancel super pump if player stops holding R key (after 0.3s guard)
		if elapsed_time >= 0.3:
			cancel()
		
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
			# Register the hit
			p.hit = true
			hit_any = true
			
			# Emit hit signal to trigger player quick reload animation
			qte_hit.emit()
			
			# Visual success flash
			_flash_center_success()
			
			# Juicy scale pulse on correct timing
			var pop_tween = create_tween()
			_container.scale = Vector2(1.12, 1.12)
			pop_tween.tween_property(_container, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			# Count hit prompts including this one
			var hits = 0
			for other_p in prompts:
				if other_p.hit:
					hits += 1
					
			var val_before = reload_progress
			
			# Calculate reload progress based on effective duration
			var skip_time = (duration * 0.5) * (float(hits) / float(num_prompts))
			var effective_dur = duration - skip_time
			var val_after = clampf(actual_time / effective_dur, 0.0, 1.0)
			
			# Close the current elapsed segment at val_before
			if progress_segments.size() > 0:
				progress_segments[-1].end = val_before
				
			# Add skipped segment
			progress_segments.append({"start": val_before, "end": val_after, "is_skipped": true})
			# Add new elapsed segment
			progress_segments.append({"start": val_after, "end": val_after, "is_skipped": false})
			
			# Update reload_progress instantly to prevent any single-frame lag
			reload_progress = val_after
			break
			
	if hit_any:
		var all_hit = true
		for p in prompts:
			if not p.hit:
				all_hit = false
				break
				
		if all_hit:
			_resolve(true)
	else:
		# Miss penalty: flash red, play click, and trigger immediate QTE failure
		_flash_center_failure()
		failed = true
		_resolve(false)
		
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
		
		# Draw reload progress filling the inner circle (default option)
		if not show_progress_bar:
			var max_radius = 60.0
			
			if resolved:
				# Paint the entire progress circle based on QTE success level
				if failed:
					_gauge.draw_circle(center, max_radius * reload_progress, Color(0.8, 0.2, 0.2, 0.25)) # Red failure
				elif successful_qtes == num_prompts and successful_qtes > 0:
					_gauge.draw_circle(center, max_radius * reload_progress, Color(0.2, 0.85, 0.4, 0.25)) # Green perfect
				else:
					_gauge.draw_circle(center, max_radius * reload_progress, Color(0.2, 0.65, 0.95, 0.25)) # Blue/Cyan partial or missed
			else:
				for segment in progress_segments:
					var r_start = segment.start * max_radius
					var r_end = segment.end * max_radius
					
					var seg_thickness = r_end - r_start
					var mid_radius = (r_start + r_end) / 2.0
					var color = Color(1.0, 1.0, 1.0, 0.22) if segment.is_skipped else Color(0.2, 0.65, 0.95, 0.32)
					
					if seg_thickness > 0.05:
						# Draw all segments as exact concentric rings.
						# Set antialiased = false to prevent edge bleeding and stacked opacity lines.
						_gauge.draw_arc(center, mid_radius, 0, 2*PI, 64, color, seg_thickness, false)
		
		# Draw horizontal reload progress line below the gauge (optional)
		if show_progress_bar:
			var line_y = 212.0
			var line_width = 180.0
			var line_left = center.x - line_width / 2.0
			var line_right = center.x + line_width / 2.0
			
			# Line background (dark grey track)
			_gauge.draw_line(Vector2(line_left, line_y), Vector2(line_right, line_y), Color(0.12, 0.12, 0.15, 0.85), 6.0, true)
			
			# Line fill (reload fill)
			var fill_x = line_left + line_width * clampf(reload_progress, 0.0, 1.0)
			if fill_x > line_left:
				var line_color = Color(0.3, 0.75, 1.0, 0.95)
				if resolved:
					if failed:
						line_color = Color(0.8, 0.2, 0.2, 0.95) # Red failure
					elif successful_qtes == num_prompts and successful_qtes > 0:
						line_color = Color(0.2, 0.85, 0.4, 0.95) # Green perfect
				
				_gauge.draw_line(Vector2(line_left, line_y), Vector2(fill_x, line_y), line_color, 6.0, true)
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
		# Force full progress and redraw circle fill on resolution
		reload_progress = 1.0
		if progress_segments.size() > 0:
			progress_segments[-1].end = 1.0
		_gauge.queue_redraw()
		
		# Count successful QTE hits dynamically at resolution time
		var hit_count = 0
		for p in prompts:
			if p.hit:
				hit_count += 1
				
		var lang = "en"
		if get_tree().root.has_node("GameManager"):
			lang = GameManager.selected_language
			
		if failed:
			final_air = max_air
			_prompt_label.text = "การรีโหลดล้มเหลว" if lang == "th" else "RELOAD FAILED"
			_prompt_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2)) # Red
			SoundManager.play_2d("watergun_pistol_reload")
		elif hit_count == prompts.size() and hit_count > 0:
			final_air = max_air
			_prompt_label.text = "จังหวะสมบูรณ์แบบ!" if lang == "th" else "PERFECT QTE!"
			_prompt_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5)) # Green
			SoundManager.play_2d("Superpump_Ready_FullAir")
		elif hit_count > 0:
			final_air = max_air
			_prompt_label.text = "จังหวะดี!" if lang == "th" else "PARTIAL QTE!"
			_prompt_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0)) # Cyan
			SoundManager.play_2d("watergun_pistol_reload")
		else:
			# Refills to 100% on standard completed reload timer
			final_air = max_air
			_prompt_label.text = "รีโหลดสำเร็จ" if lang == "th" else "RELOAD COMPLETE"
			_prompt_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.5)) # Standard green/cyan
			SoundManager.play_2d("watergun_pistol_reload")
			
		_prompt_label.scale = Vector2.ZERO
		create_tween().tween_property(_prompt_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
		
		await get_tree().create_timer(0.3).timeout
		
		var fade_tween = create_tween().set_parallel(true)
		fade_tween.tween_property(_container, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_tween.tween_property(_container, "modulate:a", 0.0, 0.25)
		fade_tween.tween_property(_background_dim, "color:a", 0.0, 0.25)
		await fade_tween.finished
		
		finished.emit(final_air, false)
		queue_free()
		
	elif mode == "superpump":
		if success:
			var lang = "en"
			if get_tree().root.has_node("GameManager"):
				lang = GameManager.selected_language
			_prompt_label.text = "เปิดใช้งานซูเปอร์ปั๊มสำเร็จ!" if lang == "th" else "SUPERPUMP ACTIVATED!"
			_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			SoundManager.play_2d("watergun_pistol_reload_Superpump")
			
			_prompt_label.scale = Vector2.ZERO
			create_tween().tween_property(_prompt_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
			
			await get_tree().create_timer(0.3).timeout
			
			var fade_tween = create_tween().set_parallel(true)
			fade_tween.tween_property(_container, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			fade_tween.tween_property(_container, "modulate:a", 0.0, 0.25)
			fade_tween.tween_property(_background_dim, "color:a", 0.0, 0.25)
			await fade_tween.finished
			
			finished.emit(120.0, true) # 120.0 is the super_threshold
			queue_free()
		else:
			var fade_tween = create_tween().set_parallel(true)
			fade_tween.tween_property(_container, "scale", Vector2(1.15, 1.15), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			fade_tween.tween_property(_container, "modulate:a", 0.0, 0.2)
			fade_tween.tween_property(_background_dim, "color:a", 0.0, 0.2)
			await fade_tween.finished
			
			finished.emit(start_air, false)
			queue_free()

func cancel() -> void:
	if resolved:
		return
	resolved = true
	cancelled.emit()
	queue_free()
