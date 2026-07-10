extends Control

@onready var buttons_container: VBoxContainer = $ButtonsContainer

func _ready() -> void:
	# Keep mouse cursor visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SoundManager.stop_music()

	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = get_tree().root.get_node("GameManager").selected_language
		
	var subheader_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	
	var restart_btn = get_node_or_null("ButtonsContainer/RestartButton")
	if restart_btn:
		restart_btn.add_theme_font_override("font", subheader_font)
		if lang == "th":
			restart_btn.text = "เริ่มเกมใหม่"
		else:
			restart_btn.text = "Restart"
			
	var exit_btn = get_node_or_null("ButtonsContainer/ExitButton")
	if exit_btn:
		exit_btn.add_theme_font_override("font", subheader_font)
		if lang == "th":
			exit_btn.text = "ออกจากเกม"
		else:
			exit_btn.text = "Exit to Desktop"

	# Animate the buttons fade in
	buttons_container.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(buttons_container, "modulate:a", 1.0, 1.0).set_delay(0.5)

func _on_restart_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file("res://scenes/disclaimer.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
