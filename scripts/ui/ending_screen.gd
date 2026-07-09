extends Control

@onready var container: VBoxContainer = $CenterContainer/VBoxContainer

func _ready() -> void:
	# Keep mouse cursor visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SoundManager.stop_music()

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
