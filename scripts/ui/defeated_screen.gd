extends Control

@onready var buttons_container: VBoxContainer = $ButtonsContainer

func _ready() -> void:
	# Keep mouse cursor visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Animate the buttons fade in
	buttons_container.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(buttons_container, "modulate:a", 1.0, 1.0).set_delay(0.5)

func _on_restart_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file("res://scenes/disclaimer.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
