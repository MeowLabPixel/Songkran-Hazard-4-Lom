extends Control

@onready var container: Control = $ContentContainer
@onready var texture_rect: TextureRect = $ContentContainer/VBox/TextureRect

var is_transitioning := false
var current_step := 1

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").reset_game()

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
	
	# Start pop-in animation using back transition for bounce effect
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(container, "modulate:a", 1.0, 0.4)

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
		
	if event.is_action_pressed("takedown") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		is_transitioning = true
		
		# Start pop-out animation
		var tween = create_tween().set_parallel(true)
		tween.tween_property(container, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(container, "modulate:a", 0.0, 0.3)
		
		tween.finished.connect(func():
			if current_step == 1:
				current_step = 2
				texture_rect.texture = load("res://scenes/Instruction.png")
				
				# Start pop-in animation for instruction screen
				var tween_in = create_tween().set_parallel(true)
				tween_in.tween_property(container, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tween_in.tween_property(container, "modulate:a", 1.0, 0.4)
				
				tween_in.finished.connect(func():
					is_transitioning = false
				)
			else:
				# Transition to the loading screen upon completion
				get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
		)

