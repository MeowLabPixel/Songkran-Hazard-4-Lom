extends Control

@onready var play_btn := $MenuContainer/VBoxContainer/PlayButton
@onready var settings_btn := $MenuContainer/VBoxContainer/SettingsButton
@onready var quit_btn := $MenuContainer/VBoxContainer/QuitButton
@onready var title := $MenuContainer/VBoxContainer/Title
@onready var anim := $"MenuContainer/VBoxContainer/QuitButton/MainMenu/CutScene1/Cutscene1/AnimationPlayer - Cutscene1"

# Audio settings panel
@onready var audio_panel := $MenuContainer/AudioSettingsPanel
@onready var master_slider := $MenuContainer/AudioSettingsPanel/VBoxContainer/MasterSlider
@onready var sfx_slider := $MenuContainer/AudioSettingsPanel/VBoxContainer/SFXSlider
@onready var dialogue_slider := $MenuContainer/AudioSettingsPanel/VBoxContainer/DialogueSlider
@onready var music_slider := $MenuContainer/AudioSettingsPanel/VBoxContainer/MusicSlider
@onready var close_btn := $MenuContainer/AudioSettingsPanel/VBoxContainer/CloseButton
@onready var fade: AnimationPlayer = $"AnimationPlayer- Logo"

func _ready() -> void:
	# Load custom font
	var custom_font = load("res://Audio System and SFX/Ui/TypefaceMario64-ywA93.otf")
	
	# Set up ping-pong animation for main menu idle loop
	anim.play("Mainmenu start")
	print("[MainMenu] Playing Mainmenu start animation in ping-pong mode")
	
	# Apply liquid glass shader to all buttons
	_apply_glass_shader(play_btn)
	_apply_glass_shader(settings_btn)
	_apply_glass_shader(quit_btn)
	
	# Style title with custom font
	title.add_theme_font_override("font", custom_font)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	
	# Style button labels with custom font
	for button in [play_btn, settings_btn, quit_btn]:
		var label = button.get_node("Label")
		label.add_theme_font_override("font", custom_font)
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	
	# Style audio settings panel with custom font
	if audio_panel:
		var panel_title = audio_panel.get_node("VBoxContainer/TitleLabel")
		panel_title.add_theme_font_override("font", custom_font)
		panel_title.add_theme_font_size_override("font_size", 32)
		
		# Style all labels in audio panel
		for child in audio_panel.get_node("VBoxContainer").get_children():
			if child is Label:
				child.add_theme_font_override("font", custom_font)
				child.add_theme_font_size_override("font_size", 20)
			elif child is Button:
				child.add_theme_font_override("font", custom_font)
				child.add_theme_font_size_override("font_size", 24)
	
	# Connect button signals
	play_btn.gui_input.connect(_on_play_input)
	settings_btn.gui_input.connect(_on_settings_input)
	quit_btn.gui_input.connect(_on_quit_input)
	
	# Hover animations
	play_btn.mouse_entered.connect(func(): _on_button_hover(play_btn, true))
	play_btn.mouse_exited.connect(func(): _on_button_hover(play_btn, false))
	settings_btn.mouse_entered.connect(func(): _on_button_hover(settings_btn, true))
	settings_btn.mouse_exited.connect(func(): _on_button_hover(settings_btn, false))
	quit_btn.mouse_entered.connect(func(): _on_button_hover(quit_btn, true))
	quit_btn.mouse_exited.connect(func(): _on_button_hover(quit_btn, false))
	
	# Audio settings setup
	_setup_audio_settings()

func _apply_glass_shader(panel: Panel) -> void:
	var shader_material = ShaderMaterial.new()
	var shader = load("res://Audio System and SFX/Cutscene/liquid_glass.gdshader")
	shader_material.shader = shader
	
	# Customize shader parameters for nice glass effect
	shader_material.set_shader_parameter("blur", 3.5)
	shader_material.set_shader_parameter("warp_intensity", 0.35)
	shader_material.set_shader_parameter("corner_radius", 0.15)
	shader_material.set_shader_parameter("tint", Color(0.95, 0.97, 1.0, 0.15))
	shader_material.set_shader_parameter("edge_highlight", Color(1.0, 1.0, 1.0, 0.4))
	shader_material.set_shader_parameter("chromatic_strength", 3.0)
	
	panel.material = shader_material

func _on_button_hover(button: Panel, hovered: bool) -> void:
	var tween = create_tween().set_parallel(true)
	
	if hovered:
		# UI sound
		AudioManager.play_random_ui.emit("hover")
		
		# Apply rainbow shader to the glass panel
		var rainbow_shader_path = "res://Audio System and SFX/Ui/Rainbow hover.gdshader"
		if ResourceLoader.exists(rainbow_shader_path):
			var rainbow_shader = load(rainbow_shader_path)
			if rainbow_shader:
				var rainbow_material = ShaderMaterial.new()
				rainbow_material.shader = rainbow_shader
				button.material = rainbow_material
				print("[MainMenu] Rainbow shader applied to ", button.name)
			else:
				push_error("[MainMenu] Failed to load rainbow shader!")
		else:
			push_error("[MainMenu] Rainbow shader file not found at: ", rainbow_shader_path)
		
		# Scale up slightly
		tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		# Restore glass shader
		_apply_glass_shader(button)
		
		# Scale back
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func _on_play_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AudioManager.play_random_ui.emit("Title")
		print("[MainMenu] Play clicked - starting cutscene animation...")
		
		# Stop the menu loop animation
		if anim:
			anim.stop()
		
		# Hide menu UI

		fade.play('logo_out')
		await get_tree().create_timer(1.2).timeout
		# Start the cutscene animation
		if anim and anim.has_animation("FullCutscene"):
			anim.play("FullCutscene")
			print("[MainMenu] Playing FullCutscene animation")
		else:
			push_error("[MainMenu] FullCutscene animation not found!")

func _on_settings_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AudioManager.play_random_ui.emit("accept")
		print("[MainMenu] Settings clicked - showing audio panel")
		audio_panel.visible = true
		
		# Apply glass shader to settings panel
		var glass_shader = load("res://Audio System and SFX/Cutscene/liquid_glass.gdshader")
		var glass_material = ShaderMaterial.new()
		glass_material.shader = glass_shader
		glass_material.set_shader_parameter("u_roundness", 0.3)
		glass_material.set_shader_parameter("u_distortion_intensity", 0.8)
		glass_material.set_shader_parameter("u_blur_intensity", 1.5)
		audio_panel.material = glass_material

func _on_quit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AudioManager.play_random_ui.emit("cancel")
		print("[MainMenu] Quit clicked")
		get_tree().quit()

func _setup_audio_settings() -> void:
	# Load current volume values
	master_slider.value = AudioSettings.get_master_volume()
	sfx_slider.value = AudioSettings.get_sfx_volume()
	dialogue_slider.value = AudioSettings.get_dialogue_volume()
	music_slider.value = AudioSettings.get_music_volume()
	
	# Connect sliders to AudioSettings
	master_slider.value_changed.connect(AudioSettings.set_master_volume)
	sfx_slider.value_changed.connect(AudioSettings.set_sfx_volume)
	dialogue_slider.value_changed.connect(AudioSettings.set_dialogue_volume)
	music_slider.value_changed.connect(AudioSettings.set_music_volume)
	
	# Close button
	close_btn.pressed.connect(_on_audio_close)
	
	print("[MainMenu] Audio settings initialized")

func _on_audio_close() -> void:
	AudioManager.play_random_ui.emit("cancle")
	audio_panel.visible = false
