extends Control

# preloaded fonts
var font_bold = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
var font_regular = preload("res://scenes/font/iannnnn-DOG-Regular.ttf")
var font_lazy_dog = preload("res://scenes/font/lazy_dog.ttf")

# Ranks
var ranks = ["D-", "D", "D+", "C", "C+", "B", "B+", "A", "A+", "S", "S+"]

# UI Nodes created dynamically
var title_lbl: Label
var subtitle_lbl: Label
var stats_grid: GridContainer
var grade_lbl: Label
var badges_container: VBoxContainer
var buttons_container: HBoxContainer
var badge_list_parent: HBoxContainer

# Values retrieved from GameManager
var is_victory: bool = false
var time_remaining_val: float = 0.0
var kill_count_val: int = 0
var kill_percent_val: float = 0.0
var takedown_count_val: int = 0
var damage_taken_val: float = 0.0
var accuracy_val: float = 0.0
var highest_combo_val: int = 0
var total_enemies: int = 0
var water_consumed_val: float = 0.0
var anchalee_damage_val: float = 0.0

var lang: String = "en"
var final_score: float = 0.0
var final_grade: String = "D-"
var earned_badges: Array = []

func _ready() -> void:
	# Force mouse cursor visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SoundManager.stop_music()
	
	# Fetch values from GameManager
	if get_tree().root.has_node("GameManager"):
		var gm = get_tree().root.get_node("GameManager")
		lang = gm.selected_language
		is_victory = (gm.game_outcome == gm.Outcome.VICTORY)
		time_remaining_val = max(0.0, gm.SURVIVAL_LIMIT - gm.survival_time_elapsed)
		kill_count_val = gm.kill_count
		takedown_count_val = gm.takedown_count
		damage_taken_val = gm.player_damage_taken
		water_consumed_val = gm.water_consumed
		anchalee_damage_val = gm.anchalee_damage_taken
		highest_combo_val = gm.highest_combo
		total_enemies = gm.total_enemies_in_level
		
		if gm.shots_fired > 0:
			accuracy_val = float(gm.shots_hit) / float(gm.shots_fired)
		else:
			accuracy_val = 1.0
			
		if total_enemies > 0:
			kill_percent_val = float(kill_count_val) / float(total_enemies)
		else:
			kill_percent_val = 1.0
	else:
		# Sandbox/fallback values for debug
		is_victory = true
		time_remaining_val = 325.4
		kill_count_val = 12
		kill_percent_val = 0.8
		takedown_count_val = 4
		damage_taken_val = 20.0
		accuracy_val = 0.75
		highest_combo_val = 5
		total_enemies = 15
	
	# Calculate score, grade and badges
	_calculate_results()
	
	# Build the entire screen layout
	_build_ui()
	
	# Animate the grade reveal
	_animate_sequence()

func _calculate_results() -> void:
	# Calculate weighted score:
	# Mission Success: 35%
	# Time Remaining: 20%
	# Damage Taken: 15%
	# Kill Count/Percentage: 15%
	# Takedowns: 10%
	# Accuracy: 5%
	final_score = 0.0
	
	# 1. Mission Success (35 points)
	if is_victory:
		final_score += 35.0
		
	# 2. Time Remaining (20 points)
	# Max time remaining is SURVIVAL_LIMIT (600.0s). If Victory, scale points.
	if is_victory:
		final_score += 20.0 * (time_remaining_val / 600.0)
		
	# 3. Damage Taken (15 points)
	# Caps penalty at MaxHP (150)
	var damage_factor = max(0.0, 1.0 - (damage_taken_val / 150.0))
	final_score += 15.0 * damage_factor
	
	# 4. Kills (15 points)
	final_score += 15.0 * kill_percent_val
	
	# 5. Takedowns (10 points)
	# Target of 5 takedowns for full points
	var takedown_factor = min(1.0, float(takedown_count_val) / 5.0)
	final_score += 10.0 * takedown_factor
	
	# 6. Accuracy (5 points)
	final_score += 5.0 * accuracy_val
	
	# Convert score to grade
	if final_score >= 95.0:
		final_grade = "S+"
	elif final_score >= 90.0:
		final_grade = "S"
	elif final_score >= 85.0:
		final_grade = "A+"
	elif final_score >= 80.0:
		final_grade = "A"
	elif final_score >= 75.0:
		final_grade = "B+"
	elif final_score >= 70.0:
		final_grade = "B"
	elif final_score >= 65.0:
		final_grade = "C+"
	elif final_score >= 60.0:
		final_grade = "C"
	elif final_score >= 50.0:
		final_grade = "D+"
	elif final_score >= 40.0:
		final_grade = "D"
	else:
		final_grade = "D-"
		
	# Capping grade at C if the player lost
	if not is_victory:
		var higher_than_c = ["S+", "S", "A+", "A", "B+", "B", "C+"]
		if final_grade in higher_than_c:
			final_grade = "C"
			
	# Determine earned achievement badges
	# Speed Demon
	if is_victory and time_remaining_val > 300.0:
		earned_badges.append({
			"name_en": "Speed Demon",
			"name_th": "ความเร็วปีศาจ",
			"desc_en": "Finished with > 5 mins remaining",
			"desc_th": "ผ่านด่านโดยเหลือเวลามากกว่า 5 นาที"
		})
	
	# Water Saver
	if is_victory and water_consumed_val < 40.0:
		earned_badges.append({
			"name_en": "Water Saver",
			"name_th": "ประหยัดน้ำ",
			"desc_en": "Consumed less than 40 water",
			"desc_th": "ใช้น้ำไปน้อยกว่า 40 หน่วย"
		})
		
	# Sharpshooter
	if accuracy_val >= 0.80 and is_victory:
		earned_badges.append({
			"name_en": "Sharpshooter",
			"name_th": "มือปืนสุดแม่น",
			"desc_en": "Achieved >= 80% accuracy",
			"desc_th": "ยิงปืนแม่นยำมากกว่า 80%"
		})
		
	# Executioner
	if takedown_count_val >= 5:
		earned_badges.append({
			"name_en": "Executioner",
			"name_th": "เพชฌฆาต",
			"desc_en": "Performed 5 or more takedowns",
			"desc_th": "จัดการซอมบี้ด้วยท่าจู่โจมพิเศษ 5 ครั้งขึ้นไป"
		})
		
	# Untouchable
	if damage_taken_val == 0.0 and is_victory:
		earned_badges.append({
			"name_en": "Untouchable",
			"name_th": "ไร้รอยขีดข่วน",
			"desc_en": "Completed without taking damage",
			"desc_th": "ผ่านด่านโดยไม่ได้รับความเสียหายเลย"
		})
		
	# Guardian
	if anchalee_damage_val <= 10.0 and is_victory:
		earned_badges.append({
			"name_en": "Guardian",
			"name_th": "ผู้พิทักษ์",
			"desc_en": "Protected Anchalee with minimal damage",
			"desc_th": "ปกป้องอัญชลีโดยเธอแทบไม่ได้รับบาดเจ็บ"
		})
		
	# Crowd Cleaner
	if is_victory and kill_count_val >= total_enemies:
		earned_badges.append({
			"name_en": "Crowd Cleaner",
			"name_th": "นักกวาดล้าง",
			"desc_en": "Defeated every single zombie",
			"desc_th": "เอาชนะซอมบี้ทุกตัวในฉาก"
		})

func _build_ui() -> void:
	# 1. MainMenu BG as background (behind the control viewport canvas)
	var bg_scene = load("res://scenes/MainMenu_BG.tscn")
	if bg_scene:
		var bg_instance = bg_scene.instantiate()
		if bg_instance is CanvasLayer:
			bg_instance.layer = -1
		add_child(bg_instance)
		
	# 2. Blurred ColorRect overlay
	var blur_rect = ColorRect.new()
	blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var blur_shader = load("res://shaders/screen_blur.gdshader") as Shader
	if blur_shader:
		var mat = ShaderMaterial.new()
		mat.shader = blur_shader
		blur_rect.material = mat
	else:
		blur_rect.color = Color(0.02, 0.02, 0.03, 0.8)
	add_child(blur_rect)
	
	# Radial glow background (subtle gradient vibe)
	var panel_glow = Panel.new()
	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	glow_style.border_width_left = 0
	glow_style.border_width_top = 0
	glow_style.border_width_right = 0
	glow_style.border_width_bottom = 0
	glow_style.corner_radius_top_left = 500
	glow_style.corner_radius_top_right = 500
	glow_style.corner_radius_bottom_left = 500
	glow_style.corner_radius_bottom_right = 500
	panel_glow.add_theme_stylebox_override("panel", glow_style)
	panel_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_glow.modulate = Color(1.0, 1.0, 1.0, 0.15)
	add_child(panel_glow)
	
	# Main layout container
	var main_margin = MarginContainer.new()
	main_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 80)
	main_margin.add_theme_constant_override("margin_right", 80)
	main_margin.add_theme_constant_override("margin_top", 60)
	main_margin.add_theme_constant_override("margin_bottom", 60)
	add_child(main_margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 30)
	main_margin.add_child(main_vbox)
	
	# TITLE & SUBTITLE
	var title_vbox = VBoxContainer.new()
	title_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(title_vbox)
	
	title_lbl = Label.new()
	title_lbl.add_theme_font_override("font", font_lazy_dog)
	title_lbl.add_theme_font_size_override("font_size", 72)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Configure Title text and colors
	if is_victory:
		title_lbl.text = "VICTORY" if lang != "th" else "ชัยชนะ"
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # Golden glow
	else:
		title_lbl.text = "DEFEAT" if lang != "th" else "พ่ายแพ้"
		title_lbl.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25)) # Red glow
		
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 12)
	title_vbox.add_child(title_lbl)
	
	subtitle_lbl = Label.new()
	subtitle_lbl.add_theme_font_override("font", font_bold)
	subtitle_lbl.add_theme_font_size_override("font_size", 24)
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle_lbl.add_theme_constant_override("outline_size", 6)
	
	# Handle sub-description based on failure outcome
	if is_victory:
		subtitle_lbl.text = "Mission successfully cleared!" if lang != "th" else "ภารกิจเสร็จสิ้นเรียบร้อย!"
		subtitle_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	else:
		# Check failure condition
		var reason = "You were overwhelmed."
		if get_tree().root.has_node("GameManager"):
			var gm = get_tree().root.get_node("GameManager")
			if gm.game_outcome == gm.Outcome.DEFEAT_ANCHALEE:
				reason = "Mission Failed - You failed to protect Anchalee." if lang != "th" else "ภารกิจล้มเหลว - คุณไม่สามารถปกป้องอัญชลีได้"
			else:
				reason = "You were overwhelmed." if lang != "th" else "คุณถูกฝูงซอมบี้รุมล้อมจนพ่ายแพ้"
		subtitle_lbl.text = reason
		subtitle_lbl.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		
	title_vbox.add_child(subtitle_lbl)
	
	# CONTENT HBOX (Split Left/Right)
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 50)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)
	
	# LEFT PANEL: Statistics
	var left_panel = PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(left_panel)
	
	# Glassmorphism stylebox
	var glass_left = StyleBoxFlat.new()
	glass_left.bg_color = Color(0.06, 0.06, 0.08, 0.7)
	glass_left.border_width_left = 2
	glass_left.border_width_top = 2
	glass_left.border_width_right = 2
	glass_left.border_width_bottom = 2
	glass_left.border_color = Color(0.8, 0.8, 1.0, 0.15)
	glass_left.corner_radius_top_left = 16
	glass_left.corner_radius_top_right = 16
	glass_left.corner_radius_bottom_left = 16
	glass_left.corner_radius_bottom_right = 16
	glass_left.shadow_color = Color(0, 0, 0, 0.4)
	glass_left.shadow_size = 12
	left_panel.add_theme_stylebox_override("panel", glass_left)
	
	var left_margin = MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 30)
	left_margin.add_theme_constant_override("margin_right", 30)
	left_margin.add_theme_constant_override("margin_top", 30)
	left_margin.add_theme_constant_override("margin_bottom", 30)
	left_panel.add_child(left_margin)
	
	var left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 20)
	left_margin.add_child(left_vbox)
	
	var stats_title = Label.new()
	stats_title.text = "MISSION STATISTICS" if lang != "th" else "สถิติภารกิจ"
	stats_title.add_theme_font_override("font", font_bold)
	stats_title.add_theme_font_size_override("font_size", 24)
	stats_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	left_vbox.add_child(stats_title)
	
	# Horizontal separator line
	var sep = ColorRect.new()
	sep.color = Color(1.0, 1.0, 1.0, 0.1)
	sep.custom_minimum_size = Vector2(0, 2)
	left_vbox.add_child(sep)
	
	# Stats Grid Container
	stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 16)
	left_vbox.add_child(stats_grid)
	
	# Populate Stats List
	var time_formatted = "%02d:%02d" % [int(time_remaining_val) / 60, int(time_remaining_val) % 60]
	var kills_formatted = "%d / %d" % [kill_count_val, total_enemies]
	var kill_pct_formatted = "%d%%" % int(kill_percent_val * 100.0)
	var accuracy_formatted = "%d%%" % int(accuracy_val * 100.0)
	
	_add_stat_row("Time Remaining" if lang != "th" else "เวลาที่เหลือ", time_formatted)
	_add_stat_row("Songkarner Defeated" if lang != "th" else "ซอมบี้ที่ถูกปราบ", kills_formatted + " (" + kill_pct_formatted + ")")
	_add_stat_row("Takedowns Executed" if lang != "th" else "ท่าพิเศษที่ใช้ (Takedown)", str(takedown_count_val))
	_add_stat_row("Player Damage Taken" if lang != "th" else "ความเสียหายที่ผู้เล่นได้รับ", "%d HP" % int(damage_taken_val))
	_add_stat_row("Water Gun Accuracy" if lang != "th" else "ความแม่นยำปืนฉีดน้ำ", accuracy_formatted)
	_add_stat_row("Highest Defeat Combo" if lang != "th" else "การกำจัดคอมโบสูงสุด", str(highest_combo_val) + " Kills")
	
	# RIGHT PANEL: Grade and Badges
	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(right_panel)
	
	# Glassmorphism stylebox
	var glass_right = glass_left.duplicate()
	right_panel.add_theme_stylebox_override("panel", glass_right)
	
	var right_margin = MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 30)
	right_margin.add_theme_constant_override("margin_right", 30)
	right_margin.add_theme_constant_override("margin_top", 30)
	right_margin.add_theme_constant_override("margin_bottom", 30)
	right_panel.add_child(right_margin)
	
	var right_vbox = VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 24)
	right_margin.add_child(right_vbox)
	
	# Title for Grade
	var grade_title = Label.new()
	grade_title.text = "MISSION GRADE" if lang != "th" else "เกรดภารกิจ"
	grade_title.add_theme_font_override("font", font_bold)
	grade_title.add_theme_font_size_override("font_size", 24)
	grade_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	right_vbox.add_child(grade_title)
	
	var right_sep = ColorRect.new()
	right_sep.color = Color(1.0, 1.0, 1.0, 0.1)
	right_sep.custom_minimum_size = Vector2(0, 2)
	right_vbox.add_child(right_sep)
	
	# Grade display circle/shield holder
	var grade_holder = CenterContainer.new()
	grade_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(grade_holder)
	
	# Massive Grade Label
	grade_lbl = Label.new()
	grade_lbl.add_theme_font_override("font", font_lazy_dog)
	grade_lbl.add_theme_font_size_override("font_size", 144)
	grade_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grade_lbl.text = "-"
	grade_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	grade_lbl.add_theme_constant_override("outline_size", 20)
	
	# Connect resized signal to ensure scaling works from the exact center
	grade_lbl.resized.connect(func():
		grade_lbl.pivot_offset = grade_lbl.size / 2.0
	)
	grade_holder.add_child(grade_lbl)
	
	# BADGES SECTION
	badges_container = VBoxContainer.new()
	badges_container.add_theme_constant_override("separation", 10)
	right_vbox.add_child(badges_container)
	
	var badges_header = Label.new()
	badges_header.text = "ACHIEVEMENT BADGES" if lang != "th" else "ตราความสำเร็จ"
	badges_header.add_theme_font_override("font", font_bold)
	badges_header.add_theme_font_size_override("font_size", 18)
	badges_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	badges_container.add_child(badges_header)
	
	badge_list_parent = HBoxContainer.new()
	badge_list_parent.add_theme_constant_override("separation", 10)
	badge_list_parent.alignment = HBoxContainer.ALIGNMENT_CENTER
	badges_container.add_child(badge_list_parent)
	
	# Create placeholders for earned badges
	if earned_badges.is_empty():
		var no_badges_lbl = Label.new()
		no_badges_lbl.text = "None earned this run" if lang != "th" else "ไม่ได้รับตราความสำเร็จในการเล่นครั้งนี้"
		no_badges_lbl.add_theme_font_override("font", font_regular)
		no_badges_lbl.add_theme_font_size_override("font_size", 16)
		no_badges_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		badge_list_parent.add_child(no_badges_lbl)
	else:
		for b in earned_badges:
			var badge_panel = PanelContainer.new()
			badge_panel.modulate.a = 0.0 # initially hidden for sequental fade-in
			
			var badge_bg = StyleBoxFlat.new()
			badge_bg.bg_color = Color(0.12, 0.12, 0.18, 0.8)
			badge_bg.border_width_left = 1
			badge_bg.border_width_top = 1
			badge_bg.border_width_right = 1
			badge_bg.border_width_bottom = 1
			badge_bg.border_color = Color(1.0, 0.85, 0.3, 0.3)
			badge_bg.corner_radius_top_left = 8
			badge_bg.corner_radius_top_right = 8
			badge_bg.corner_radius_bottom_left = 8
			badge_bg.corner_radius_bottom_right = 8
			badge_panel.add_theme_stylebox_override("panel", badge_bg)
			
			var badge_margin = MarginContainer.new()
			badge_margin.add_theme_constant_override("margin_left", 12)
			badge_margin.add_theme_constant_override("margin_right", 12)
			badge_margin.add_theme_constant_override("margin_top", 8)
			badge_margin.add_theme_constant_override("margin_bottom", 8)
			badge_panel.add_child(badge_margin)
			
			var badge_vbox = VBoxContainer.new()
			badge_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
			badge_margin.add_child(badge_vbox)
			
			var b_title = Label.new()
			b_title.text = b.name_en if lang != "th" else b.name_th
			b_title.add_theme_font_override("font", font_bold)
			b_title.add_theme_font_size_override("font_size", 14)
			b_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # gold title
			b_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge_vbox.add_child(b_title)
			
			var b_desc = Label.new()
			b_desc.text = b.desc_en if lang != "th" else b.desc_th
			b_desc.add_theme_font_override("font", font_regular)
			b_desc.add_theme_font_size_override("font_size", 10)
			b_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
			b_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge_vbox.add_child(b_desc)
			
			badge_list_parent.add_child(badge_panel)
			
	# BOTTOM PANEL: Menu Options
	buttons_container = HBoxContainer.new()
	buttons_container.alignment = HBoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 30)
	main_vbox.add_child(buttons_container)
	
	# Retry button
	var retry_btn = Button.new()
	retry_btn.text = "Retry" if lang != "th" else "เริ่มเกมใหม่"
	_style_button(retry_btn)
	retry_btn.pressed.connect(_on_retry_pressed)
	buttons_container.add_child(retry_btn)
	
	# Main menu button
	var menu_btn = Button.new()
	menu_btn.text = "Main Menu" if lang != "th" else "เมนูหลัก"
	_style_button(menu_btn)
	menu_btn.pressed.connect(_on_menu_pressed)
	buttons_container.add_child(menu_btn)
	
	# Exit button
	var exit_btn = Button.new()
	exit_btn.text = "Exit to Desktop" if lang != "th" else "ออกจากเกม"
	_style_button(exit_btn)
	exit_btn.pressed.connect(_on_exit_pressed)
	buttons_container.add_child(exit_btn)

func _add_stat_row(label_text: String, value_text: String) -> void:
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_override("font", font_regular)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	stats_grid.add_child(label)
	
	var value = Label.new()
	value.text = value_text
	value.add_theme_font_override("font", font_bold)
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(value)

func _style_button(btn: Button) -> void:
	btn.add_theme_font_override("font", font_bold)
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(220, 50)
	
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.12, 0.12, 0.16, 0.8)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_left = 8
	btn_normal.corner_radius_bottom_right = 8
	btn_normal.border_width_left = 1
	btn_normal.border_width_top = 1
	btn_normal.border_width_right = 1
	btn_normal.border_width_bottom = 1
	btn_normal.border_color = Color(0.8, 0.8, 1.0, 0.15)
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.2, 0.2, 0.28, 0.9)
	btn_hover.border_color = Color(1.0, 0.85, 0.3, 0.8) # gold highlight on hover
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	
	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_stylebox_override("pressed", btn_pressed)
	
	# Add slight scale effect on hover using signals
	btn.mouse_entered.connect(func():
		SoundManager.play_2d("Hover_Ui")
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.1)
		# set pivot to center
		btn.pivot_offset = btn.size / 2.0
	)
	
	btn.mouse_exited.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2.ONE, 0.1)
		btn.pivot_offset = btn.size / 2.0
	)

func _animate_sequence() -> void:
	# Hide buttons initially
	buttons_container.modulate.a = 0.0
	
	# Start cycles of grade ticking
	var cycle_duration = 0.9 # secs
	var steps = 12
	var step_delay = cycle_duration / steps
	
	for i in range(steps):
		var temp_g = ranks[i % ranks.size()]
		grade_lbl.text = temp_g
		grade_lbl.scale = Vector2(0.8, 0.8)
		SoundManager.play_2d("Hover_Ui")
		await get_tree().create_timer(step_delay).timeout
		
	# Reveal Final Grade
	grade_lbl.text = final_grade
	
	var grade_color = Color(0.65, 0.65, 0.75) # Default gray
	if final_grade.begins_with("S"):
		grade_color = Color(1.0, 0.85, 0.3) # Gold
	elif final_grade.begins_with("A"):
		grade_color = Color(0.3, 0.7, 1.0) # Sky blue
	elif final_grade.begins_with("B"):
		grade_color = Color(0.3, 0.9, 0.5) # Green
	elif final_grade.begins_with("C"):
		grade_color = Color(0.95, 0.6, 0.3) # Orange
		
	grade_lbl.add_theme_color_override("font_color", grade_color)
	
	# Animate bounce
	grade_lbl.pivot_offset = grade_lbl.size / 2.0
	grade_lbl.scale = Vector2.ZERO
	var tween_grade = create_tween()
	tween_grade.tween_property(grade_lbl, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Play reveal chimes
	if final_grade.begins_with("S") or final_grade.begins_with("A"):
		SoundManager.play_2d("Reload_QTE_WIN")
	else:
		SoundManager.play_2d("Reload_QTE_FAIL")
		
	# Delay for badge reveal
	await get_tree().create_timer(0.4).timeout
	
	# Sequentially reveal earned badges
	for child in badge_list_parent.get_children():
		if child is PanelContainer:
			var tween_badge = create_tween()
			tween_badge.tween_property(child, "modulate:a", 1.0, 0.3)
			SoundManager.play_2d("Hover_Ui")
			await get_tree().create_timer(0.2).timeout
			
	# Fade in action buttons
	var tween_buttons = create_tween()
	tween_buttons.tween_property(buttons_container, "modulate:a", 1.0, 0.4)

func _on_retry_pressed() -> void:
	SoundManager.play_2d("Confirm_UI")
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").reset_game()
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")

func _on_menu_pressed() -> void:
	SoundManager.play_2d("Confirm_UI")
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").restart_game_to_disclaimer()
	else:
		get_tree().change_scene_to_file("res://scenes/startup.tscn")

func _on_exit_pressed() -> void:
	SoundManager.play_2d("Cancel_UI")
	get_tree().quit()
