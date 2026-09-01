extends CanvasLayer

enum Phase {
	INIT,
	PRESS_E,
	REVEAL,
	IDLE,
	TRANSITION
}

var current_phase: Phase = Phase.INIT
var bg_scene = preload("res://scenes/MainMenu_BG.tscn")
var bg_instance: Node = null

@export var enable_ui: bool = true:
	set(value):
		enable_ui = value
		_update_ui_visibility()
@export var auto_transition: bool = false
@export var fade_logo_after_press_e: bool = true
@export var logo_fade_delay: float = 10.0
@export var logo_fade_duration: float = 1.0
@export var disclaimer_prompt_en: String = "[ PRESS E TO ENTER ]"
@export var disclaimer_prompt_th: String = "[ กดปุ่ม E เพื่อดำเนินต่อ ]"

@onready var bg_container: Node2D = $BackgroundContainer
@onready var prompt_label: Label = $PromptLabel

var pulse_tween: Tween = null
var reveal_tween: Tween = null
var logo_fade_tween: Tween = null
var sway_time: float = 0.0
var sway_weight: float = 0.0
var sway_configs: Dictionary = {}
var original_positions: Dictionary = {}
var original_scales: Dictionary = {}
var can_transition: bool = false

# Startup language changer state
var selected_lang: String = "en"
var lang_changer_container: HBoxContainer
var btn_en: TextureButton
var btn_th: TextureButton
var img_thai_btn = preload("res://scenes/Thai.png")
var img_english_btn = preload("res://scenes/English.png")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Reset game manager state and get language
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").reset_game()
		selected_lang = get_tree().root.get_node("GameManager").selected_language
	else:
		selected_lang = "en"
	
	if not SoundManager.is_playing_main_theme():
		SoundManager.stop_music()
	
	# Setup UI prompt font and color override to fix scene layout alpha bug
	var font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	if font:
		prompt_label.add_theme_font_override("font", font)
	prompt_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1.0))
	prompt_label.text = _get_continue_text()
	prompt_label.modulate.a = 0.0
	prompt_label.visible = enable_ui
	
	_create_language_changer()
	
	# Instantiate background
	bg_instance = bg_scene.instantiate()
	bg_container.add_child(bg_instance)
	
	# Hide all layers except 23_BG (first child at index 0) and cache original layout positions/scales
	var children = bg_instance.get_children()
	for i in range(children.size()):
		var child = children[i] as Sprite2D
		if child:
			original_positions[child.name] = child.position
			original_scales[child.name] = child.scale
			
			# Apply shader to the logo
			if "logo" in child.name.to_lower():
				var shader = load("res://shaders/logo_shine.gdshader") as Shader
				if shader:
					var mat = ShaderMaterial.new()
					mat.shader = shader
					mat.set_shader_parameter("surface", child.texture)
					child.material = mat
			
			if i == 0:
				child.visible = true
				child.modulate.a = 0.0
			else:
				child.visible = false
				
	# Fade in the background layer 23_BG
	var base_layer = children[0] as Sprite2D
	var fade_in = create_tween()
	fade_in.tween_property(base_layer, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_in.finished.connect(func():
		_change_phase(Phase.PRESS_E)
	)

func _process(delta: float) -> void:
	if current_phase == Phase.IDLE or current_phase == Phase.TRANSITION:
		sway_time += delta
		_apply_sway_idle()

func _unhandled_input(event: InputEvent) -> void:
	var is_e_pressed = event.is_action_pressed("takedown") or (
		event is InputEventKey and event.pressed and event.keycode == KEY_E
	)
	var is_backspace_pressed = event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE
	
	if is_e_pressed:
		if current_phase == Phase.PRESS_E:
			_start_reveal()
		elif current_phase == Phase.IDLE and can_transition:
			_start_transition()
	elif is_backspace_pressed:
		if current_phase == Phase.IDLE or current_phase == Phase.REVEAL:
			_reset_to_press_e()

func _change_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	
	match current_phase:
		Phase.PRESS_E:
			prompt_label.text = _get_continue_text()
			_start_prompt_pulse()
		Phase.IDLE:
			pass

func _get_continue_text() -> String:
	var selected_lang = "en"
	if get_tree().root.has_node("GameManager"):
		selected_lang = get_tree().root.get_node("GameManager").selected_language
	return "[ กดปุ่ม E เพื่อดำเนินต่อ ]" if selected_lang == "th" else "[ PRESS E TO CONTINUE ]"

func _get_disclaimer_prompt() -> String:
	var selected_lang = "en"
	if get_tree().root.has_node("GameManager"):
		selected_lang = get_tree().root.get_node("GameManager").selected_language
	return disclaimer_prompt_th if selected_lang == "th" else disclaimer_prompt_en

func _start_prompt_pulse() -> void:
	if pulse_tween:
		pulse_tween.kill()
		pulse_tween = null
	
	if not enable_ui:
		prompt_label.hide()
		prompt_label.modulate.a = 0.0
		return
	
	prompt_label.show()
	prompt_label.modulate.a = 0.0
	pulse_tween = create_tween().set_loops()
	pulse_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse_tween.tween_property(prompt_label, "modulate:a", 0.2, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_prompt_pulse(fade_out_duration: float = 0.2) -> void:
	if pulse_tween:
		pulse_tween.kill()
		pulse_tween = null
	
	var fade = create_tween()
	fade.tween_property(prompt_label, "modulate:a", 0.0, fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.finished.connect(func():
		prompt_label.hide()
	)

func _start_logo_fade_timer() -> void:
	_cancel_logo_fade()
	if not fade_logo_after_press_e:
		return
	
	logo_fade_tween = create_tween()
	logo_fade_tween.tween_interval(logo_fade_delay)
	logo_fade_tween.tween_callback(func():
		if current_phase == Phase.IDLE or current_phase == Phase.REVEAL:
			_fade_out_logo()
	)

func _cancel_logo_fade() -> void:
	if logo_fade_tween and logo_fade_tween.is_valid():
		logo_fade_tween.kill()
	logo_fade_tween = null

func _fade_out_logo() -> void:
	if not bg_instance:
		return
	var logo_node = bg_instance.find_child("3_logo", true, false)
	if logo_node and logo_node.material and logo_node.material is ShaderMaterial:
		var mat = logo_node.material as ShaderMaterial
		var current_alpha = mat.get_shader_parameter("Alpha")
		if current_alpha == null:
			current_alpha = 1.0
		var fade = create_tween()
		fade.tween_method(
			func(val: float): mat.set_shader_parameter("Alpha", val),
			current_alpha,
			0.0,
			logo_fade_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func set_fade_logo_enabled(enabled: bool) -> void:
	fade_logo_after_press_e = enabled
	if not enabled:
		_cancel_logo_fade()
		if bg_instance:
			var logo_node = bg_instance.find_child("3_logo", true, false)
			if logo_node and logo_node.material and logo_node.material is ShaderMaterial:
				var mat = logo_node.material as ShaderMaterial
				mat.set_shader_parameter("Alpha", 1.0)
	else:
		if current_phase == Phase.IDLE:
			_start_logo_fade_timer()


func _start_reveal() -> void:
	_change_phase(Phase.REVEAL)
	_stop_prompt_pulse(0.2)
	SoundManager.play_main_theme()
	_start_logo_fade_timer()
	
	if lang_changer_container and enable_ui:
		var fade_out_lang = create_tween()
		fade_out_lang.tween_property(lang_changer_container, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	var children = bg_instance.get_children()
	reveal_tween = create_tween().set_parallel(true)
	reveal_tween.set_speed_scale(1.15)
	
	var mc_index = -1
	for j in range(children.size()):
		if "mc" in children[j].name.to_lower():
			mc_index = j
			break
			
	# Stagger anim starting from index 1 (the layer after the base background)
	for i in range(1, children.size()):
		var child = children[i] as Sprite2D
		if not child:
			continue
			
		var name = child.name.to_lower()
		var delay = (i - 1) * 0.12
		
		# Cloud layer appears after all bomb layers have finished (around 2.7s delay)
		if "cloud" in name:
			delay = 2.7
		# dust4 appears right before cloud (at 2.5s delay)
		elif "dust4" in name:
			delay = 2.5
		# bomb splashes start slightly before zombie layers (which start at 0.96s)
		elif "splash" in name:
			delay = 0.6
		# merchantWater starts with zombies47 (which has delay of index 8 = 0.84)
		elif "merchant" in name:
			var zombies_idx = -1
			for j in range(children.size()):
				if "zombies47" in children[j].name.to_lower():
					zombies_idx = j
					break
			if zombies_idx != -1:
				delay = (zombies_idx - 1) * 0.12
			else:
				delay = 0.84
		elif mc_index != -1 and i > mc_index:
			var mc_delay = (mc_index - 1) * 0.12
			delay = mc_delay + (i - mc_index) * 0.04
			
		var target_pos = original_positions[child.name] as Vector2
		var original_scale = original_scales[child.name] as Vector2
		
		child.visible = true
		
		# Apply custom stylish entrance based on name/type, relative to their original offsets/scales
		if "overlay" in name or "colorcorrection" in name:
			child.modulate.a = 0.0
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.8).set_delay(delay)
			
		elif "splash" in name or "dust" in name:
			# Pop up from below right under its own position
			child.position = target_pos + Vector2(0, 150)
			child.scale = Vector2.ZERO
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.0).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "scale", original_scale, 1.0).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.8).set_delay(delay)
			
		elif "bomb" in name:
			# Always pop/slide from the bottom-right corner of the screen
			child.position = Vector2(1920, 1080)
			child.scale = original_scale * 1.25
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.2).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "scale", original_scale, 1.2).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.6).set_delay(delay)
			
		elif "zombie" in name:
			# Pop up from the bottom-rightish
			child.position = target_pos + Vector2(150, 150)
			child.scale = Vector2.ZERO
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.0).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "scale", original_scale, 1.0).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.8).set_delay(delay)
			
		elif "cloud" in name:
			# Pan and fade in from the left
			child.position = target_pos + Vector2(-300, 0)
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.2).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 1.0).set_delay(delay)
			
		elif "sunlight" in name or "sunray" in name:
			# Pan and fade in from the right
			child.position = target_pos + Vector2(300, 0)
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.2).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 1.0).set_delay(delay)
			
		elif "mc" in name:
			# Unique heroic slide up from bottom-left with scale bounce
			child.position = target_pos + Vector2(-200, 400)
			child.scale = original_scale * 0.4
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.8).set_delay(delay)
			
			var scale_tween = create_tween()
			scale_tween.tween_property(child, "scale", original_scale * 1.15, 0.8).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			scale_tween.tween_property(child, "scale", original_scale, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			
			# Play the title drop voiceline when the MC animation starts
			reveal_tween.tween_callback(func(): SoundManager.play_2d("Title Drop")).set_delay(delay)
			
		elif "logo" in name:
			# Falling drop with elastic overshoot and slight spin
			child.position = target_pos + Vector2(0, -400)
			child.scale = Vector2.ZERO
			child.rotation = deg_to_rad(-25.0)
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.4).set_delay(delay).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "scale", original_scale, 1.2).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "rotation", 0.0, 1.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.7).set_delay(delay)
			
		elif "sparkle" in name:
			child.position = target_pos
			child.scale = Vector2.ZERO
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "scale", original_scale, 1.0).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.8).set_delay(delay)
			
		else:
			child.position = target_pos + Vector2(0, 200)
			child.modulate.a = 0.0
			
			reveal_tween.tween_property(child, "position", target_pos, 1.0).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_tween.tween_property(child, "modulate:a", 1.0, 0.8).set_delay(delay)

	reveal_tween.finished.connect(_on_reveal_finished)

func _on_reveal_finished() -> void:
	_init_sway_configs()
	_change_phase(Phase.IDLE)
	
	# Smoothly blend from final reveal positions into the sway idle state
	sway_weight = 0.0
	var blend = create_tween()
	blend.tween_property(self, "sway_weight", 1.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Auto-trigger disclaimer page transition after 1.5s in sway mode
	get_tree().create_timer(1.5).timeout.connect(func():
		if current_phase == Phase.IDLE:
			if auto_transition:
				_start_transition()
			else:
				can_transition = true
				prompt_label.text = _get_disclaimer_prompt()
				_start_prompt_pulse()
	)

func _init_sway_configs() -> void:
	var children = bg_instance.get_children()
	for child in children:
		var sprite = child as Sprite2D
		if not sprite:
			continue
			
		var name = sprite.name.to_lower()
		var amp = Vector2.ZERO
		var freq = Vector2.ZERO
		
		# Assign custom sway parameters based on layer types
		if "overlay" in name or "colorcorrection" in name or "layer33" in name or "23_bg" in name:
			amp = Vector2.ZERO
			freq = Vector2.ZERO
		elif "logo" in name:
			amp = Vector2(4, 10)
			freq = Vector2(0.8, 1.1)
		elif "cloud" in name:
			amp = Vector2(15, 3)
			freq = Vector2(0.2, 0.15)
		elif "sunlight" in name or "sunray" in name:
			amp = Vector2(5, 5)
			freq = Vector2(0.3, 0.3)
		elif "dust" in name or "sparkle" in name:
			amp = Vector2(20, 18)
			freq = Vector2(1.1, 0.9)
		elif "bomb" in name or "splash" in name:
			amp = Vector2(10, 8)
			freq = Vector2(0.6, 0.7)
		elif "zombie" in name:
			amp = Vector2(12, 6)
			freq = Vector2(0.7, 0.5)
		elif "mc" in name:
			amp = Vector2(7, 5)
			freq = Vector2(0.5, 0.4)
		elif "merchant" in name:
			amp = Vector2(9, 7)
			freq = Vector2(0.6, 0.45)
		else:
			amp = Vector2(6, 6)
			freq = Vector2(0.5, 0.5)
			
		sway_configs[sprite.name] = {
			"base_pos": original_positions[sprite.name],
			"amp": amp,
			"freq": freq,
			"phase_x": randf() * TAU,
			"phase_y": randf() * TAU
		}

func _apply_sway_idle() -> void:
	var children = bg_instance.get_children()
	for child in children:
		var sprite = child as Sprite2D
		if not sprite or not sway_configs.has(sprite.name):
			continue
			
		var cfg = sway_configs[sprite.name]
		var amp = cfg["amp"] as Vector2
		var freq = cfg["freq"] as Vector2
		
		if amp == Vector2.ZERO:
			continue
			
		var offset = Vector2(
			sin(sway_time * freq.x + cfg["phase_x"]) * amp.x,
			cos(sway_time * freq.y + cfg["phase_y"]) * amp.y
		)
		sprite.position = cfg["base_pos"] + offset * sway_weight

func _start_transition() -> void:
	_cancel_logo_fade()
	_change_phase(Phase.TRANSITION)
	_stop_prompt_pulse(0.5)
	
	# Fade out prompt label and the logo shader parameter in parallel
	var fade_out = create_tween().set_parallel(true)
	fade_out.tween_property(prompt_label, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	if bg_instance:
		var logo_node = bg_instance.find_child("3_logo", true, false)
		if logo_node and logo_node.material and logo_node.material is ShaderMaterial:
			var mat = logo_node.material as ShaderMaterial
			fade_out.tween_method(
				func(val: float): mat.set_shader_parameter("Alpha", val),
				1.0,
				0.0,
				0.6
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	fade_out.finished.connect(func():
		var disclaimer_scene = load("res://scenes/disclaimer.tscn")
		if disclaimer_scene:
			var disclaimer_instance = disclaimer_scene.instantiate()
			add_child(disclaimer_instance)
	)

func _reset_to_press_e() -> void:
	_cancel_logo_fade()
	can_transition = false
	if lang_changer_container:
		lang_changer_container.modulate.a = 1.0
		lang_changer_container.visible = enable_ui
	SoundManager.stop_music()
	if reveal_tween:
		reveal_tween.kill()
		reveal_tween = null
		
	sway_weight = 0.0
	sway_time = 0.0
	
	if bg_instance:
		var children = bg_instance.get_children()
		for i in range(children.size()):
			var child = children[i] as Sprite2D
			if child:
				# Reset transformations & visibilities
				child.rotation = 0.0
				child.scale = original_scales[child.name]
				child.position = original_positions[child.name]
				
				# Reset shader Alpha parameter if it has a ShaderMaterial
				if child.material and child.material is ShaderMaterial:
					child.material.set_shader_parameter("Alpha", 1.0)
				
				if i == 0:
					child.visible = true
					child.modulate.a = 1.0
				else:
					child.visible = false
					child.modulate.a = 1.0
					
	_change_phase(Phase.PRESS_E)

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
	lang_changer_container.visible = enable_ui
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

func _update_ui_visibility() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	if lang_changer_container:
		lang_changer_container.visible = enable_ui
	if not enable_ui:
		if pulse_tween:
			pulse_tween.kill()
			pulse_tween = null
		if prompt_label:
			prompt_label.hide()
			prompt_label.modulate.a = 0.0
	else:
		if prompt_label:
			if current_phase == Phase.PRESS_E or (current_phase == Phase.IDLE and can_transition):
				_start_prompt_pulse()

func _update_language_buttons_style() -> void:
	if btn_en and btn_th:
		if selected_lang == "en":
			btn_en.modulate = Color(1.0, 1.0, 1.0, 1.0)
			btn_th.modulate = Color(0.5, 0.5, 0.5, 0.7)
		else:
			btn_en.modulate = Color(0.5, 0.5, 0.5, 0.7)
			btn_th.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _switch_language(lang: String) -> void:
	if lang == selected_lang:
		return
		
	selected_lang = lang
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").selected_language = lang
		get_tree().root.get_node("GameManager").save_settings()
		
	_update_language_buttons_style()
	
	# Instantly update prompt label text depending on active phase
	if current_phase == Phase.PRESS_E:
		prompt_label.text = _get_continue_text()
	elif current_phase == Phase.IDLE and can_transition:
		prompt_label.text = _get_disclaimer_prompt()

func return_to_swaymode() -> void:
	_change_phase(Phase.IDLE)
	can_transition = true
	
	# Reset prompt text and pulse animation
	prompt_label.text = _get_disclaimer_prompt()
	_start_prompt_pulse()
	
	# Fade back in the logo's shader Alpha parameter
	if bg_instance:
		var logo_node = bg_instance.find_child("3_logo", true, false)
		if logo_node and logo_node.material and logo_node.material is ShaderMaterial:
			var mat = logo_node.material as ShaderMaterial
			var fade_in = create_tween()
			fade_in.tween_method(
				func(val: float): mat.set_shader_parameter("Alpha", val),
				0.0,
				1.0,
				0.6
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			fade_in.finished.connect(func():
				_start_logo_fade_timer()
			)
