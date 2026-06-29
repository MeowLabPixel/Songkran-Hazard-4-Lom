extends Control

@export var pages: Array[Texture2D] = [
	preload("res://scenes/1_Disclaimer.png"),
	preload("res://scenes/2_Controls.png"),
	preload("res://scenes/3_Reload.png"),
	preload("res://scenes/4_Weakpoints.png"),
	preload("res://scenes/5_Objective.png")
]

@onready var container: Control = $ContentContainer
@onready var texture_rect: TextureRect = $ContentContainer/VBox/TextureRect
@onready var prompt_label: Label = $ContentContainer/VBox/Prompt

var is_transitioning := false
var current_step := 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").reset_game()

	# Initialize pages
	if pages.size() > 0:
		texture_rect.texture = pages[current_step]
	update_prompt()

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

func update_prompt() -> void:
	if prompt_label == null:
		return
	if current_step < pages.size() - 1:
		prompt_label.text = "[ Press E Next | Q for Back ]"
		prompt_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
	else:
		prompt_label.text = "[ Press E to START THE GAME | Q for Back ]"
		prompt_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1)) # Gold color for emphasis

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
		
	var is_forward = event.is_action_pressed("takedown") or (
		event is InputEventKey and event.pressed and (
			event.keycode == KEY_E or 
			event.keycode == KEY_D or 
			event.keycode == KEY_RIGHT
		)
	)
	
	var is_backward = event is InputEventKey and event.pressed and (
		event.keycode == KEY_Q or 
		event.keycode == KEY_A or 
		event.keycode == KEY_LEFT
	)
	
	if is_forward:
		if current_step == pages.size() - 1:
			transition_to_game()
		else:
			transition_to_page(current_step + 1)
	elif is_backward:
		if current_step > 0:
			transition_to_page(current_step - 1)

func transition_to_page(next_page_index: int) -> void:
	is_transitioning = true
	
	# Start pop-out animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(container, "modulate:a", 0.0, 0.2)
	
	tween.finished.connect(func():
		current_step = next_page_index
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
	
	# Start pop-out animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(container, "modulate:a", 0.0, 0.3)
	
	tween.finished.connect(func():
		get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
	)
