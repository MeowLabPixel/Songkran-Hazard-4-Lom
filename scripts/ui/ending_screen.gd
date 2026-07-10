extends Control

@onready var container: VBoxContainer = $CenterContainer/VBoxContainer

func _ready() -> void:
	# Keep mouse cursor visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SoundManager.play_main_theme()

	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = get_tree().root.get_node("GameManager").selected_language
		
	var header_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf") if lang == "th" else preload("res://scenes/font/lazy_dog.ttf")
	var subheader_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	
	var ending_text = get_node_or_null("CenterContainer/VBoxContainer/EndingText")
	if ending_text:
		ending_text.add_theme_font_override("font", header_font)
		if lang == "th":
			ending_text.text = "ขอบคุณที่ร่วมเล่นเกมเดโม!"
		else:
			ending_text.text = "Thank you for playing!"
			
	var prompt_lbl = get_node_or_null("CenterContainer/VBoxContainer/PromptLabel")
	if prompt_lbl:
		prompt_lbl.add_theme_font_override("font", subheader_font)
		if lang == "th":
			prompt_lbl.text = "กดปุ่ม Escape เพื่อออกจากเกม"
		else:
			prompt_lbl.text = "Press Escape to exit"

	# Set up initial state for pop-in animation
	container.scale = Vector2.ZERO
	container.modulate.a = 0.0
	
	# Set pivot to center so scaling is centered
	container.pivot_offset = container.size / 2.0
	container.resized.connect(func():
		container.pivot_offset = container.size / 2.0
	)
	
	# Wait one frame to ensure container size is computed correctly
	await get_tree().process_frame
	container.pivot_offset = container.size / 2.0
	
	# Start pop-in animation using back transition
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(container, "modulate:a", 1.0, 0.5)

func _unhandled_input(event: InputEvent) -> void:
	# Quit the game when Escape is pressed
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
