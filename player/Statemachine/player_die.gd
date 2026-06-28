extends State

func _enter() -> void:
	print(name)
	stop_moving()
	owner.aim_bone_on(false)
	owner.anim.get("parameters/playback").travel("Die")
	if owner.has_method("force_die"):
		owner.force_die()

	# Disable all enemy attacks and force them back to hunt/idle
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.attack_blocked = true
			if enemy.state_machine:
				if enemy.state_machine.current_state and enemy.state_machine.current_state.name == "StateAttack":
					enemy.state_machine.transition_to("StateHunt")

	# Wait 1.0 second, then transition to defeated scene
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(func():
		var canvas_layer = CanvasLayer.new()
		canvas_layer.layer = 99
		var color_rect = ColorRect.new()
		color_rect.color = Color(0.02, 0.02, 0.03, 1.0)
		color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		color_rect.modulate.a = 0.0
		canvas_layer.add_child(color_rect)
		owner.add_child(canvas_layer)
		
		var tween = owner.create_tween()
		tween.tween_property(color_rect, "modulate:a", 1.0, 1.0)
		tween.finished.connect(func():
			get_tree().change_scene_to_file("res://scenes/defeated_scene.tscn")
		)
	)

func _exit() -> void:
	pass

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)
