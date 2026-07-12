extends Control

var pages_th: Array[Texture2D] = [
	preload("res://scenes/1_Disclaimer.png"),
	preload("res://scenes/2_Controls.png"),
	preload("res://scenes/3_Reload.png"),
	preload("res://scenes/4_Weakpoints.png"),
	preload("res://scenes/5_Objective.png")
]

var pages_en: Array[Texture2D] = [
	preload("res://scenes/1_Disclaimer_ENG.png"),
	preload("res://scenes/2_Controls_ENG.png"),
	preload("res://scenes/3_Reload_ENG.png"),
	preload("res://scenes/4_Weakpoints_ENG.png"),
	preload("res://scenes/5_Objective_ENG.png")
]

var pages: Array[Texture2D] = []

# Preload language switcher buttons
var img_thai_btn = preload("res://scenes/Thai.png")
var img_english_btn = preload("res://scenes/English.png")

# Preload control selection buttons
var img_type_a_en = preload("res://scenes/Type_A.png")
var img_type_b_en = preload("res://scenes/Type_B.png")
var img_type_c_en = preload("res://scenes/Type_C.png")

var img_type_a_th = preload("res://scenes/Type_A_Thai.png")
var img_type_b_th = preload("res://scenes/Type_B_Thai.png")
var img_type_c_th = preload("res://scenes/Type_C_Thai.png")

# Preload difficulty selection buttons
var img_expert_en = preload("res://scenes/Expert.png")
var img_casual_en = preload("res://scenes/Casual.png")
var img_expert_th = preload("res://scenes/Expert_Thai.png")
var img_casual_th = preload("res://scenes/Casual_Thai.png")

@onready var container: Control = $ContentContainer
@onready var texture_rect: TextureRect = $ContentContainer/VBox/TextureRect
@onready var prompt_label: Label = $ContentContainer/VBox/Prompt

var is_transitioning := false
var current_step := 0
var language_selected := true
var selected_lang := "en"
var lang_changer_container: HBoxContainer
var move_selection_container: Control
var difficulty_selection_container: Control
var btn_en: TextureButton
var btn_th: TextureButton

# Hold skip tutorial state
var is_holding_e := false
var e_hold_time := 0.0
const E_HOLD_REQUIRED := 1.2 # seconds to hold

var skip_container: HBoxContainer
var skip_lbl: Label
var skip_bar: ProgressBar

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not SoundManager.is_playing_main_theme():
		SoundManager.stop_music()
	
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").reset_game()
		selected_lang = get_tree().root.get_node("GameManager").selected_language
	else:
		selected_lang = "en"

	if selected_lang == "th":
		pages = pages_th
	else:
		pages = pages_en
		
	language_selected = true
	
	# Apply screen blur shader to Background ColorRect
	var blur_shader = load("res://shaders/screen_blur.gdshader") as Shader
	if blur_shader and has_node("Background"):
		var mat = ShaderMaterial.new()
		mat.shader = blur_shader
		$Background.material = mat
	
	# Override prompt label font
	prompt_label.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Bold.ttf"))
	
	# Show the tutorial content container immediately
	container.show()
	current_step = 0
	if pages.size() > 0:
		texture_rect.texture = pages[current_step]
	
	_create_language_changer()
	_create_skip_button()
	update_prompt()
	_update_skip_indicator()
	
	# Set pivot to center so scaling is centered
	container.resized.connect(func():
		container.pivot_offset = container.size / 2.0
	)
	
	# Initial modulate alpha set to 0 to prevent snap/pop, then fade in smoothly
	modulate.a = 0.0
	var fade_in = create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _create_skip_button() -> void:
	skip_container = HBoxContainer.new()
	skip_container.alignment = BoxContainer.ALIGNMENT_CENTER
	skip_container.add_theme_constant_override("separation", 10)
	add_child(skip_container)
	
	skip_lbl = Label.new()
	skip_lbl.text = "Hold [E] to skip tutorials" if selected_lang == "en" else "กด [E] ค้างเพื่อข้ามคำแนะนำ"
	skip_lbl.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Regular.ttf"))
	skip_lbl.add_theme_font_size_override("font_size", 18)
	skip_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.8))
	skip_container.add_child(skip_lbl)
	
	skip_bar = ProgressBar.new()
	skip_bar.custom_minimum_size = Vector2(120, 10)
	skip_bar.show_percentage = false
	
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.12, 0.6)
	sb_bg.corner_radius_top_left = 6
	sb_bg.corner_radius_top_right = 6
	sb_bg.corner_radius_bottom_left = 6
	sb_bg.corner_radius_bottom_right = 6
	
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = Color(1.0, 0.85, 0.3, 0.9)
	sb_fg.corner_radius_top_left = 6
	sb_fg.corner_radius_top_right = 6
	sb_fg.corner_radius_bottom_left = 6
	sb_fg.corner_radius_bottom_right = 6
	
	skip_bar.add_theme_stylebox_override("background", sb_bg)
	skip_bar.add_theme_stylebox_override("fill", sb_fg)
	skip_bar.max_value = E_HOLD_REQUIRED
	skip_bar.value = 0.0
	skip_container.add_child(skip_bar)
	
	# Position anchors at bottom right
	skip_container.anchor_left = 1.0
	skip_container.anchor_top = 1.0
	skip_container.anchor_right = 1.0
	skip_container.anchor_bottom = 1.0
	
	skip_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	skip_container.offset_left = -380
	skip_container.offset_right = -40
	skip_container.offset_top = -60
	skip_container.offset_bottom = -20

func _update_skip_indicator() -> void:
	if not skip_container or not is_instance_valid(skip_container):
		return
	
	var should_be_visible = current_step < pages.size()
	skip_container.visible = should_be_visible
	
	if should_be_visible and skip_bar and skip_lbl:
		skip_bar.value = e_hold_time
		skip_lbl.text = "Hold [E] to skip tutorials" if selected_lang == "en" else "กด [E] ค้างเพื่อข้ามคำแนะนำ"

func _process(delta: float) -> void:
	if is_holding_e and current_step < pages.size():
		e_hold_time += delta
		_update_skip_indicator()
		if e_hold_time >= E_HOLD_REQUIRED:
			is_holding_e = false
			e_hold_time = 0.0
			_update_skip_indicator()
			_skip_to_controls()
	else:
		if e_hold_time > 0.0:
			e_hold_time = max(0.0, e_hold_time - delta * 3.0)
			_update_skip_indicator()

func _skip_to_controls() -> void:
	if is_transitioning:
		return
	print("[Disclaimer] Skipping tutorials directly to movement control selection.")
	if current_step == 0:
		SoundManager.play_main_theme()
	transition_to_page(pages.size())

func _create_language_changer() -> void:
	lang_changer_container = HBoxContainer.new()
	lang_changer_container.alignment = BoxContainer.ALIGNMENT_END
	lang_changer_container.add_theme_constant_override("separation", 15)
	
	# English button
	btn_en = TextureButton.new()
	btn_en.texture_normal = img_english_btn
	btn_en.ignore_texture_size = true
	btn_en.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn_en.custom_minimum_size = Vector2(160, 100)
	btn_en.pressed.connect(func(): _switch_language("en"))
	
	# Thai button
	btn_th = TextureButton.new()
	btn_th.texture_normal = img_thai_btn
	btn_th.ignore_texture_size = true
	btn_th.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn_th.custom_minimum_size = Vector2(160, 100)
	btn_th.pressed.connect(func(): _switch_language("th"))
	
	lang_changer_container.add_child(btn_en)
	lang_changer_container.add_child(btn_th)
	
	# Set up hover and exited effects
	btn_en.mouse_entered.connect(func():
		if selected_lang != "en":
			btn_en.modulate = Color(0.8, 0.8, 0.8, 0.9)
	)
	btn_en.mouse_exited.connect(func():
		_update_language_buttons_style()
	)
	btn_th.mouse_entered.connect(func():
		if selected_lang != "th":
			btn_th.modulate = Color(0.8, 0.8, 0.8, 0.9)
	)
	btn_th.mouse_exited.connect(func():
		_update_language_buttons_style()
	)
	
	# Position at top right
	add_child(lang_changer_container)
	lang_changer_container.anchor_left = 1.0
	lang_changer_container.anchor_right = 1.0
	lang_changer_container.anchor_top = 0.0
	lang_changer_container.anchor_bottom = 0.0
	
	# Adjust top right offset
	lang_changer_container.offset_left = -370
	lang_changer_container.offset_right = -35
	lang_changer_container.offset_top = 35
	lang_changer_container.offset_bottom = 135
	
	_update_language_buttons_style()

func _update_language_buttons_style() -> void:
	if btn_en and btn_th:
		if selected_lang == "en":
			btn_en.modulate = Color(1.0, 1.0, 1.0, 1.0)
			btn_th.modulate = Color(0.5, 0.5, 0.5, 0.7)
		else:
			btn_en.modulate = Color(0.5, 0.5, 0.5, 0.7)
			btn_th.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _switch_language(lang: String) -> void:
	if lang == selected_lang or is_transitioning:
		return
	is_transitioning = true
	
	var current_container: Control
	if difficulty_selection_container:
		current_container = difficulty_selection_container
	elif move_selection_container:
		current_container = move_selection_container
	else:
		current_container = container
	
	# Start pop-out animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(current_container, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(current_container, "modulate:a", 0.0, 0.2)
	
	tween.finished.connect(func():
		selected_lang = lang
		if get_tree().root.has_node("GameManager"):
			get_tree().root.get_node("GameManager").selected_language = lang
		if lang == "th":
			pages = pages_th
		else:
			pages = pages_en
			
		_update_language_buttons_style()
		_update_skip_indicator()
		
		# Update current UI state
		if current_step == pages.size():
			_show_movement_selection()
			
			move_selection_container.scale = Vector2.ZERO
			move_selection_container.modulate.a = 0.0
			move_selection_container.resized.connect(func():
				move_selection_container.pivot_offset = move_selection_container.size / 2.0
			)
			
			var tween_in = create_tween().set_parallel(true)
			tween_in.tween_property(move_selection_container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween_in.tween_property(move_selection_container, "modulate:a", 1.0, 0.3)
			
			tween_in.finished.connect(func():
				is_transitioning = false
			)
		elif current_step == pages.size() + 1:
			_show_difficulty_selection()
			
			difficulty_selection_container.scale = Vector2.ZERO
			difficulty_selection_container.modulate.a = 0.0
			difficulty_selection_container.resized.connect(func():
				difficulty_selection_container.pivot_offset = difficulty_selection_container.size / 2.0
			)
			
			var tween_in = create_tween().set_parallel(true)
			tween_in.tween_property(difficulty_selection_container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween_in.tween_property(difficulty_selection_container, "modulate:a", 1.0, 0.3)
			
			tween_in.finished.connect(func():
				is_transitioning = false
			)
		else:
			container.show()
			if current_step >= 0 and current_step < pages.size():
				texture_rect.texture = pages[current_step]
			update_prompt()
			
			# Start pop-in animation
			var tween_in = create_tween().set_parallel(true)
			tween_in.tween_property(container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween_in.tween_property(container, "modulate:a", 1.0, 0.3)
			
			tween_in.finished.connect(func():
				is_transitioning = false
			)
	)

func update_prompt() -> void:
	if prompt_label == null:
		return
	if current_step < pages.size() - 1:
		prompt_label.text = "[ Press E Next | Q for Back ]" if selected_lang == "en" else "[ กดปุ่ม E ถัดไป | Q เพื่อย้อนกลับ ]"
		prompt_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
	else:
		prompt_label.text = "[ Press E to CHOOSE CONTROLS | Q for Back ]" if selected_lang == "en" else "[ กดปุ่ม E เพื่อเลือกการควบคุม | Q เพื่อย้อนกลับ ]"
		prompt_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1))

func _unhandled_input(event: InputEvent) -> void:
	if not language_selected or is_transitioning:
		return
		
	# Handle hold E skipping
	if event is InputEventKey and event.keycode == KEY_E and current_step < pages.size():
		if event.pressed and not event.is_echo():
			is_holding_e = true
			e_hold_time = 0.0
		elif not event.pressed:
			if is_holding_e:
				is_holding_e = false
				if e_hold_time < E_HOLD_REQUIRED:
					if current_step == 0:
						SoundManager.play_main_theme()
					transition_to_page(current_step + 1)
				e_hold_time = 0.0
				_update_skip_indicator()
		return

	# Instant forward keys (not E)
	var is_forward_instant = event.is_action_pressed("takedown") or (
		event is InputEventKey and event.pressed and (
			event.keycode == KEY_D or 
			event.keycode == KEY_RIGHT
		)
	)
	
	# Instant backward keys
	var is_backward = event is InputEventKey and event.pressed and (
		event.keycode == KEY_Q or 
		event.keycode == KEY_A or 
		event.keycode == KEY_LEFT
	)
	
	if is_forward_instant:
		if current_step < pages.size():
			if current_step == 0:
				SoundManager.play_main_theme()
			transition_to_page(current_step + 1)
	elif is_backward:
		if current_step > 0:
			transition_to_page(current_step - 1)
		elif current_step == 0:
			_transition_back_to_intro()

func _transition_back_to_intro() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	
	# Play pop-out/down animations for container
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(container, "modulate:a", 0.0, 0.3)
	
	# Turn off/fade out screen blur on Background ColorRect
	if has_node("Background"):
		var bg_node = get_node("Background") as ColorRect
		if bg_node.material and bg_node.material is ShaderMaterial:
			# Fade screen blur LOD to 0 to unblur smoothly
			tween.tween_method(
				func(val: float): bg_node.material.set_shader_parameter("lod", val),
				2.0,
				0.0,
				0.4
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(bg_node, "modulate:a", 0.0, 0.4)
		
	# Fade out the language changer if it exists
	if lang_changer_container:
		tween.tween_property(lang_changer_container, "modulate:a", 0.0, 0.3)

	# Fade out the skip button container if it exists
	if skip_container:
		tween.tween_property(skip_container, "modulate:a", 0.0, 0.3)

	tween.finished.connect(func():
		var parent_node = get_parent()
		if parent_node and parent_node.has_method("return_to_swaymode"):
			parent_node.return_to_swaymode()
		queue_free()
	)

func transition_to_page(next_page_index: int) -> void:
	is_transitioning = true
	
	var current_container: Control
	if difficulty_selection_container:
		current_container = difficulty_selection_container
	elif move_selection_container:
		current_container = move_selection_container
	else:
		current_container = container
	
	# Start pop-out animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(current_container, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(current_container, "modulate:a", 0.0, 0.2)
	
	tween.finished.connect(func():
		current_step = next_page_index
		_update_skip_indicator()
		
		# Clean up UI containers if transitioning
		if difficulty_selection_container and current_step != pages.size() + 1:
			difficulty_selection_container.queue_free()
			difficulty_selection_container = null
		if move_selection_container and current_step < pages.size():
			move_selection_container.queue_free()
			move_selection_container = null
			
		if current_step == pages.size():
			_show_movement_selection()
			
			move_selection_container.scale = Vector2.ZERO
			move_selection_container.modulate.a = 0.0
			move_selection_container.resized.connect(func():
				move_selection_container.pivot_offset = move_selection_container.size / 2.0
			)
			
			var tween_in = create_tween().set_parallel(true)
			tween_in.tween_property(move_selection_container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween_in.tween_property(move_selection_container, "modulate:a", 1.0, 0.3)
			
			tween_in.finished.connect(func():
				is_transitioning = false
			)
		elif current_step == pages.size() + 1:
			_show_difficulty_selection()
			
			difficulty_selection_container.scale = Vector2.ZERO
			difficulty_selection_container.modulate.a = 0.0
			difficulty_selection_container.resized.connect(func():
				difficulty_selection_container.pivot_offset = difficulty_selection_container.size / 2.0
			)
			
			var tween_in = create_tween().set_parallel(true)
			tween_in.tween_property(difficulty_selection_container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween_in.tween_property(difficulty_selection_container, "modulate:a", 1.0, 0.3)
			
			tween_in.finished.connect(func():
				is_transitioning = false
			)
		else:
			container.show()
			if current_step >= 0 and current_step < pages.size():
				texture_rect.texture = pages[current_step]
			update_prompt()
			
			# Start pop-in animation
			var tween_in = create_tween().set_parallel(true)
			tween_in.tween_property(container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween_in.tween_property(container, "modulate:a", 1.0, 0.3)
			
			tween_in.finished.connect(func():
				is_transitioning = false
			)
	)

func transition_to_game() -> void:
	is_transitioning = true
	SoundManager.fade_out_music(0.8)
	var active_container: Control
	if difficulty_selection_container:
		active_container = difficulty_selection_container
	elif move_selection_container:
		active_container = move_selection_container
	else:
		active_container = container
	
	# Start pop-out animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(active_container, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(active_container, "modulate:a", 0.0, 0.3)
	
	tween.finished.connect(func():
		get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
	)

var movement_texts = {
	"title": {
		"en": "CHOOSE MOVEMENT CONTROL TYPE",
		"th": "เลือกรูปแบบการควบคุมการเคลื่อนไหว"
	}
}

func _show_movement_selection() -> void:
	if move_selection_container:
		move_selection_container.queue_free()
		move_selection_container = null
		
	container.hide()
	
	move_selection_container = Control.new()
	move_selection_container.name = "MovementSelectionUI"
	add_child(move_selection_container)
	if lang_changer_container:
		move_child(lang_changer_container, -1)
	move_selection_container.anchor_right = 1.0
	move_selection_container.anchor_bottom = 1.0
	
	# Background style matching disclaimer (with blur shader)
	var bg = ColorRect.new()
	var blur_shader = load("res://shaders/screen_blur.gdshader") as Shader
	if blur_shader:
		var mat = ShaderMaterial.new()
		mat.shader = blur_shader
		bg.material = mat
	else:
		bg.color = Color(0.02, 0.02, 0.03, 0.8)
	move_selection_container.add_child(bg)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	move_selection_container.add_child(vbox)
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_top = 40
	vbox.offset_bottom = -40
	
	# Title
	var title_lbl = Label.new()
	title_lbl.text = movement_texts["title"][selected_lang]
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 42)
	
	# Header font: lazy_dog for Eng, iannnnn-DOG-Bold for Thai
	var title_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf") if selected_lang == "th" else preload("res://scenes/font/lazy_dog.ttf")
	title_lbl.add_theme_font_override("font", title_font)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # Golden text
	vbox.add_child(title_lbl)
	
	# Buttons horizontal layout
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	
	# Create the 3 custom image buttons
	_create_movement_button(hbox, GameManager.MovementType.HYBRID_RETRO)
	_create_movement_button(hbox, GameManager.MovementType.MODERN)
	_create_movement_button(hbox, GameManager.MovementType.TANK)
	
	# Back prompt
	var back_prompt = Label.new()
	back_prompt.text = "[ Press Q to go back ]" if selected_lang == "en" else "[ กดปุ่ม Q เพื่อย้อนกลับ ]"
	back_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_prompt.add_theme_font_size_override("font_size", 24)
	back_prompt.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Bold.ttf"))
	back_prompt.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
	vbox.add_child(back_prompt)

func _create_movement_button(parent: Control, type_val: GameManager.MovementType) -> void:
	var btn = TextureButton.new()
	
	var normal_tex: Texture2D
	match type_val:
		GameManager.MovementType.HYBRID_RETRO:
			normal_tex = img_type_a_th if selected_lang == "th" else img_type_a_en
		GameManager.MovementType.MODERN:
			normal_tex = img_type_b_th if selected_lang == "th" else img_type_b_en
		GameManager.MovementType.TANK:
			normal_tex = img_type_c_th if selected_lang == "th" else img_type_c_en
			
	btn.texture_normal = normal_tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	
	# Make them a nice size
	btn.custom_minimum_size = Vector2(230, 350)
	parent.add_child(btn)
	
	btn.resized.connect(func():
		btn.pivot_offset = btn.size / 2.0
	)
	
	# Add keyboard/controller support
	btn.focus_mode = Control.FOCUS_ALL
	
	btn.mouse_entered.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.15, 1.15, 1.15, 1.0)
	)
	btn.mouse_exited.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	)
	
	btn.focus_entered.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.15, 1.15, 1.15, 1.0)
	)
	btn.focus_exited.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	)
	
	btn.pressed.connect(func():
		_select_movement_type(type_val)
	)

func _select_movement_type(type: GameManager.MovementType) -> void:
	GameManager.movement_type = type
	GameManager.movement_type_selected = true
	print("[Disclaimer] Selected movement control: ", GameManager.MovementType.keys()[type])
	transition_to_page(pages.size() + 1)

var difficulty_texts = {
	"title": {
		"en": "CHOOSE DIFFICULTY MODE",
		"th": "เลือกโหมดระดับความยาก"
	}
}

func _show_difficulty_selection() -> void:
	if difficulty_selection_container:
		difficulty_selection_container.queue_free()
		difficulty_selection_container = null
		
	container.hide()
	if move_selection_container:
		move_selection_container.hide()
	
	difficulty_selection_container = Control.new()
	difficulty_selection_container.name = "DifficultySelectionUI"
	add_child(difficulty_selection_container)
	if lang_changer_container:
		move_child(lang_changer_container, -1)
	difficulty_selection_container.anchor_right = 1.0
	difficulty_selection_container.anchor_bottom = 1.0
	
	# Background style matching disclaimer (with blur shader)
	var bg = ColorRect.new()
	var blur_shader = load("res://shaders/screen_blur.gdshader") as Shader
	if blur_shader:
		var mat = ShaderMaterial.new()
		mat.shader = blur_shader
		bg.material = mat
	else:
		bg.color = Color(0.02, 0.02, 0.03, 0.8)
	difficulty_selection_container.add_child(bg)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 35)
	difficulty_selection_container.add_child(vbox)
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_top = 40
	vbox.offset_bottom = -40
	
	# Title
	var title_lbl = Label.new()
	title_lbl.text = difficulty_texts["title"][selected_lang]
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 42)
	
	# Header font: lazy_dog for Eng, iannnnn-DOG-Bold for Thai
	var title_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf") if selected_lang == "th" else preload("res://scenes/font/lazy_dog.ttf")
	title_lbl.add_theme_font_override("font", title_font)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # Golden text
	vbox.add_child(title_lbl)
	
	# Buttons horizontal layout
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 50)
	vbox.add_child(hbox)
	
	# Create the 2 custom image buttons (Casual and Expert)
	if GameManager.expert_mode_played:
		_create_difficulty_button(hbox, GameManager.Difficulty.CASUAL)
	_create_difficulty_button(hbox, GameManager.Difficulty.EXPERT)
	
	# Back prompt
	var back_prompt = Label.new()
	back_prompt.text = "[ Press Q to go back ]" if selected_lang == "en" else "[ กดปุ่ม Q เพื่อย้อนกลับ ]"
	back_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_prompt.add_theme_font_size_override("font_size", 24)
	back_prompt.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Bold.ttf"))
	back_prompt.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
	vbox.add_child(back_prompt)

func _create_difficulty_button(parent: Control, diff_val: GameManager.Difficulty) -> void:
	var btn = TextureButton.new()
	
	var normal_tex: Texture2D
	match diff_val:
		GameManager.Difficulty.CASUAL:
			normal_tex = img_casual_th if selected_lang == "th" else img_casual_en
		GameManager.Difficulty.EXPERT:
			normal_tex = img_expert_th if selected_lang == "th" else img_expert_en
			
	btn.texture_normal = normal_tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	
	# Make them a nice size
	btn.custom_minimum_size = Vector2(340, 520)
	parent.add_child(btn)
	
	if diff_val == GameManager.Difficulty.CASUAL and get_tree().root.has_node("GameManager") and get_tree().root.get_node("GameManager").casual_mode_new:
		var new_lbl = Label.new()
		new_lbl.text = "NEW!" if selected_lang == "en" else "ใหม่!"
		new_lbl.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Bold.ttf"))
		new_lbl.add_theme_font_size_override("font_size", 28)
		new_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2)) # Red text
		
		# Overlay styling (dark background, red border)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.08, 0.1, 0.85)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(1.0, 0.2, 0.2)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		new_lbl.add_theme_stylebox_override("normal", sb)
		
		new_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		new_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		btn.add_child(new_lbl)
		new_lbl.anchor_left = 0.5
		new_lbl.anchor_right = 0.5
		new_lbl.anchor_top = 0.0
		new_lbl.anchor_bottom = 0.0
		new_lbl.offset_left = -60
		new_lbl.offset_right = 60
		new_lbl.offset_top = 20
		new_lbl.offset_bottom = 60
		new_lbl.pivot_offset = Vector2(60, 20)
		
		# Pulse animation
		var tween_new = new_lbl.create_tween().set_loops()
		tween_new.tween_property(new_lbl, "scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween_new.tween_property(new_lbl, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	btn.resized.connect(func():
		btn.pivot_offset = btn.size / 2.0
	)
	
	btn.focus_mode = Control.FOCUS_ALL
	
	btn.mouse_entered.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.15, 1.15, 1.15, 1.0)
	)
	btn.mouse_exited.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	)
	
	btn.focus_entered.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.15, 1.15, 1.15, 1.0)
	)
	btn.focus_exited.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	)
	
	btn.pressed.connect(func():
		_select_difficulty(diff_val)
	)

func _select_difficulty(diff: GameManager.Difficulty) -> void:
	GameManager.difficulty = diff
	if diff == GameManager.Difficulty.CASUAL:
		GameManager.casual_mode_new = false
		GameManager.save_settings()
	print("[Disclaimer] Selected difficulty: ", GameManager.Difficulty.keys()[diff])
	transition_to_game()
